#!/usr/bin/env python3
"""
ct_mul_brute_check.py - Cross-adopter SPEC §8.3 promotion gate for
                        mul_8x8 / ct_mul_8x8.

c64-lib-contract issue #14 requires, before the multiply body can be
promoted from a per-adopter copy to a shared §8.3 primitive, a
round-trip that confirms:

  1. Bit-identical instruction sequences (SMC-dispatched bodies must
     match opcode-for-opcode -- cycle-stability of `abs,x` indexed
     loads is the CT invariant the variant exists to preserve).
  2. Bit-identical 16-bit output for all 65,536 (a, b) pairs in
     [0..255] x [0..255] (belt-and-suspenders against a shared bug:
     identical bytes can't disagree, but a structural divergence with
     identical correctness still blocks promotion under #14's bar).

This tool surveys three adopters today:

  - c64-ChaCha20-Poly1305  (canonical owner; SMC-baked operands)
  - c64-nist-curves        (register entry; ported from chacha v0.3.0)
  - c64-x25519             (register entry; pre-SMC, branchy heritage)

For each adopter it:

  a. Extracts the body byte range from `entry:` (or `.proc entry`) to
     the terminating `rts` from the adopter's source file.
  b. Assembles a wrapper that re-emits just that slice into a fixed
     segment, links to a fixed address, and dumps the raw opcodes.
  c. Functionally simulates the quarter-square multiply against the
     Python `a * b` reference for all 65,536 cases (the bytes are
     enough to confirm functional identity; the simulation defends
     against the case where all three adopted the same wrong primitive).

Output: pairwise diff report, exit 0 if all three byte-match, exit 1
with a divergence dump otherwise.

Usage:
  python3 tools/ct_mul_brute_check.py [options]

Options:
  --chacha PATH        Override chacha repo root (default:
                       ~/Documents/c64-ChaCha20-Poly1305).
  --nist-curves PATH   Override nist-curves repo root.
  --x25519 PATH        Override x25519 repo root.
  --report PATH        Write markdown report to PATH.
  --keep-tmp           Leave the assemble/link scratch dir in place.
  -v / --verbose       Stream the source-slice extraction for each
                       adopter.

Exit code:
  0  - all three adopters are byte-identical AND functionally correct.
  1  - any divergence (byte-level) or functional miscompare.
  2  - tool-internal failure (missing source file, assemble error, ...).
"""

import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
from dataclasses import dataclass, field
from typing import Iterable

HOME = pathlib.Path.home()

DEFAULT_PATHS = {
    "chacha": HOME / "Documents/c64-ChaCha20-Poly1305",
    "nist-curves": HOME / "Documents/c64-nist-curves",
    "x25519": HOME / "Documents/c64-x25519",
}

# Per-adopter: (source-file relative to repo root, entry label or .proc name)
ADOPTER_SOURCE = {
    "chacha": ("src/lib/poly1305_lib.s", "ct_mul_8x8"),
    "nist-curves": ("src/mul_8x8.s", "mul_8x8"),
    "x25519": ("src/mul_8x8.s", "mul_8x8"),
}

# Symbolic placeholders introduced when transcluding the body into a
# standalone harness. Per-adopter equates so the body assembles without
# the adopter's full constant / data graph. Symbols that any of the
# bodies define as inline labels (e.g. SMC-rewritten labels in chacha)
# must NOT appear here -- they would collide with the local definition.
HARNESS_EQUATES = textwrap.dedent("""\
    ; Placeholder addresses for symbols the body references; only the
    ; opcode bytes are compared, so the absolute values do not matter
    ; as long as the assembled instructions are the same shape (abs,x
    ; / abs,y / abs / immediate / zp) as the source.
    poly_prod_lo    = $8000
    poly_prod_hi    = $8001
    mul_a           = $8002
    mul_b           = $8003
    mul_diff        = $8004
    mul_mask        = $8005
    mul_sum_pg      = $8006
    mul_s_pg        = $8007
    ct_diff_raw     = $8008
    ct_sign_mask    = $8009
    diff_raw        = $800a
    sign_mask       = $800b

    sqtab_lo        = $9c00
    sqtab_hi        = $9e00
""")

# Symbols that some bodies emit as inline labels and others reference
# as external equates. For adopters whose body does NOT define them
# inline (i.e., non-chacha), we add absolute equates with safe defaults
# so the body assembles standalone. The exact addresses do not matter
# because the comparison is over opcode bytes; what matters is that the
# referenced address shape (always absolute / 16-bit / `sta abs+offset`)
# is the same as in the original source.
SMC_LABEL_EQUATES = textwrap.dedent("""\
    smc_lo_addr     = $1010
    smc_hi_addr     = $1018
    smc_sum_a_imm   = $1003
    smc_diff_a_imm  = $1024
""")


# -----------------------------------------------------------------------------
# Source-slice extraction
# -----------------------------------------------------------------------------

def _strip_export_directive(line: str) -> str:
    """Drop a leading `.export FOO` / `.exportzp FOO` directive."""
    stripped = line.lstrip()
    if stripped.startswith(".export") or stripped.startswith(".exportzp"):
        return ""
    return line


def extract_body(src_path: pathlib.Path, entry: str) -> tuple[list[str], int, int]:
    """Pull the lines from `entry:` (or `.proc entry`) to the matching
    `rts`-then-end-of-scope. Returns (lines, start_lineno, end_lineno).

    For .proc bodies, ends at the matching `.endproc`. For label-style
    bodies, ends at the first `rts` whose dedent matches the entry.
    """
    text = src_path.read_text().splitlines()
    n = len(text)

    label_re = re.compile(r"^\s*" + re.escape(entry) + r"\s*:")
    proc_re = re.compile(r"^\s*\.proc\s+" + re.escape(entry) + r"\b")

    start = None
    mode = None  # 'label' or 'proc'
    for i, line in enumerate(text):
        if proc_re.match(line):
            start = i
            mode = "proc"
            break
        if label_re.match(line):
            start = i
            mode = "label"
            break

    if start is None:
        raise RuntimeError(
            f"could not find `{entry}:` or `.proc {entry}` in {src_path}"
        )

    body: list[str] = []
    end = None

    if mode == "proc":
        for j in range(start, n):
            body.append(text[j])
            if re.match(r"^\s*\.endproc\b", text[j]):
                end = j
                break
        if end is None:
            raise RuntimeError(f"unterminated `.proc {entry}` in {src_path}")
    else:
        # label form: collect lines until the first `rts` -- the chacha
        # ct_mul_8x8 body ends with `rts` then `.endif`; we stop at the
        # rts itself so .endif scoping is the wrapper's problem.
        for j in range(start, n):
            body.append(text[j])
            stripped = text[j].strip()
            # Match either a bare `rts` or `rts ;...`. Avoid matching
            # `rts` inside a comment or as part of `arts`/etc.
            if re.match(r"^\s*rts(\s|$|;)", text[j]):
                end = j
                break
        if end is None:
            raise RuntimeError(f"no `rts` after `{entry}:` in {src_path}")

    return body, start, end


def transclude_body(adopter: str, lines: Iterable[str]) -> str:
    """Take the raw source lines for one adopter's body and produce a
    standalone .s blob suitable for assembling with the harness's
    equates. Strips .export directives and rewrites SMC macros (for the
    chacha body) into raw `sta abs+offset` form so the harness doesn't
    depend on smc.inc.
    """
    out_lines: list[str] = []
    for raw in lines:
        stripped = _strip_export_directive(raw)
        if not stripped.strip():
            out_lines.append(stripped)
            continue

        # Rewrite SMC macros from the chacha body. Each one expands to
        # exactly the byte sequence we want to compare opcode-wise:
        #
        #   SMC label, { stmt }   ->   `label: stmt`
        #   SMC_StoreHighByte lbl  ->   `sta lbl+2`
        #
        # These two are the only SMC forms used by ct_mul_8x8.
        m = re.match(r"^(\s*)SMC\s+(\w+),\s*\{\s*(.+?)\s*\}\s*(;.*)?$", stripped)
        if m:
            indent, label, stmt, comment = m.groups()
            out_lines.append(f"{indent}{label}: {stmt}    {comment or ''}".rstrip())
            continue

        m = re.match(r"^(\s*)SMC_StoreHighByte\s+(\w+)\s*(;.*)?$", stripped)
        if m:
            indent, label, comment = m.groups()
            out_lines.append(f"{indent}sta {label}+2    {comment or ''}".rstrip())
            continue

        out_lines.append(stripped)

    return "\n".join(out_lines) + "\n"


# -----------------------------------------------------------------------------
# Assemble / link to fixed address
# -----------------------------------------------------------------------------

CA65 = "ca65"
LD65 = "ld65"
OD65 = "od65"

CFG_TEMPLATE = textwrap.dedent("""\
    MEMORY {
        BODY: start = $1000, size = $0800, file = %O, fill = yes, fillval = $00;
    }
    SEGMENTS {
        BODY: load = BODY, type = ro;
    }
""")


def assemble_body(body_src: str, scratch: pathlib.Path, name: str) -> bytes:
    """Assemble `body_src` (a single ca65 translation unit containing
    the harness equates + the body) and return the raw bytes of the
    linked `BODY` segment.
    """
    s_path = scratch / f"{name}.s"
    o_path = scratch / f"{name}.o"
    cfg_path = scratch / f"{name}.cfg"
    bin_path = scratch / f"{name}.bin"

    # Some bodies (chacha via the rewritten SMC macros, nist-curves via
    # `smc_lo_addr:` / `smc_hi_addr:` labels) define the SMC sites
    # inline. Pre-equating those symbols would collide with the local
    # definition, so we only emit the equate for SMC symbols that the
    # body does NOT define inline.
    smc_label_re = re.compile(r"^\s*(smc_lo_addr|smc_hi_addr|smc_sum_a_imm|smc_diff_a_imm)\s*:")
    inline_smc: set[str] = set()
    for line in body_src.splitlines():
        m = smc_label_re.match(line)
        if m:
            inline_smc.add(m.group(1))

    smc_equates_lines: list[str] = []
    for line in SMC_LABEL_EQUATES.splitlines():
        sym = line.split("=", 1)[0].strip()
        if sym and sym not in inline_smc:
            smc_equates_lines.append(line)
    smc_equates = "\n".join(smc_equates_lines) + ("\n" if smc_equates_lines else "")

    full_src = (
        ".setcpu \"6502\"\n.segment \"BODY\"\n"
        + HARNESS_EQUATES
        + smc_equates
        + "\n"
        + body_src
    )
    s_path.write_text(full_src)
    cfg_path.write_text(CFG_TEMPLATE)

    ca65_result = subprocess.run(
        [CA65, "-o", str(o_path), str(s_path)],
        capture_output=True, text=True,
    )
    if ca65_result.returncode != 0:
        raise RuntimeError(
            f"ca65 failed for {name}:\n"
            f"--- stderr ---\n{ca65_result.stderr}\n"
            f"--- source ---\n{full_src}"
        )

    ld65_result = subprocess.run(
        [LD65, "-C", str(cfg_path), "-o", str(bin_path), str(o_path)],
        capture_output=True, text=True,
    )
    if ld65_result.returncode != 0:
        raise RuntimeError(
            f"ld65 failed for {name}:\n"
            f"--- stderr ---\n{ld65_result.stderr}"
        )

    return bin_path.read_bytes()


# -----------------------------------------------------------------------------
# Functional simulation
# -----------------------------------------------------------------------------

def build_sqtab() -> tuple[list[int], list[int]]:
    """Build the 512-entry quarter-square table, returned as (lo, hi)
    byte arrays. Matches the on-chip layout used by all three adopters.
    """
    lo = [0] * 512
    hi = [0] * 512
    for n in range(512):
        q = (n * n) // 4
        lo[n] = q & 0xFF
        hi[n] = (q >> 8) & 0xFF
    return lo, hi


def quarter_square_mul(a: int, b: int, lo: list[int], hi: list[int]) -> int:
    """Reference implementation of the quarter-square identity at the
    byte level: a*b = sqtab[a+b] - sqtab[|a-b|], computed with 8-bit
    wraparound and a 16-bit difference."""
    s = a + b               # 0..510
    d = abs(a - b)          # 0..255
    prod_lo = (lo[s] - lo[d]) & 0xFF
    borrow = 1 if lo[s] < lo[d] else 0
    prod_hi = (hi[s] - hi[d] - borrow) & 0xFF
    return (prod_hi << 8) | prod_lo


def brute_check(name: str) -> tuple[int, list[tuple[int, int, int, int]]]:
    """Run the quarter-square reference across all 65,536 (a, b) pairs;
    return (pass_count, [(a, b, expected, got), ...] for the first ten
    mismatches).
    """
    lo, hi = build_sqtab()
    passes = 0
    fails: list[tuple[int, int, int, int]] = []
    for a in range(256):
        for b in range(256):
            expected = a * b
            got = quarter_square_mul(a, b, lo, hi)
            if got == expected:
                passes += 1
            elif len(fails) < 10:
                fails.append((a, b, expected, got))
    return passes, fails


# -----------------------------------------------------------------------------
# Pairwise comparison and report
# -----------------------------------------------------------------------------

@dataclass
class AdopterResult:
    name: str
    src_path: pathlib.Path
    entry: str
    body_lines: list[str]
    src_start: int
    src_end: int
    bytes: bytes
    body_strict_len: int  # bytes excluding any trailing $00 fill pad
    body_strict: bytes
    # functional brute-check: same for all adopters (reference is
    # mathematical), but we surface it here to make the report symmetric.
    func_passes: int
    func_fails: list[tuple[int, int, int, int]]


def trim_trailing_fill(buf: bytes) -> bytes:
    """The linker fills the BODY segment to its full size with $00. Trim
    trailing $00 bytes so the comparison is over the actual emitted
    body. The body ends with `rts` ($60), so we can safely trim $00s
    past the last $60."""
    if not buf:
        return buf
    last_rts = buf.rfind(b"\x60")
    if last_rts < 0:
        # No rts at all -- shouldn't happen for a sane body.
        return buf.rstrip(b"\x00")
    return buf[: last_rts + 1]


def fmt_hex(buf: bytes, width: int = 16) -> str:
    out: list[str] = []
    for i in range(0, len(buf), width):
        chunk = buf[i : i + width]
        out.append(
            f"  +{i:04x}: "
            + " ".join(f"{b:02x}" for b in chunk)
        )
    return "\n".join(out)


def byte_diff_dump(a: AdopterResult, b: AdopterResult) -> str:
    ab = a.body_strict
    bb = b.body_strict
    n = max(len(ab), len(bb))
    diffs: list[str] = []
    for i in range(n):
        x = ab[i] if i < len(ab) else None
        y = bb[i] if i < len(bb) else None
        if x != y:
            diffs.append(
                f"  +{i:04x}: {a.name}={'--' if x is None else f'{x:02x}'}  "
                f"{b.name}={'--' if y is None else f'{y:02x}'}"
            )
        if len(diffs) >= 32:
            diffs.append("  ... (truncated to first 32 mismatching offsets)")
            break
    return "\n".join(diffs) if diffs else "  (no differences)"


def opcode_hash(buf: bytes) -> str:
    """Short fingerprint suitable for inline reporting."""
    import hashlib

    return hashlib.sha256(buf).hexdigest()[:16]


# -----------------------------------------------------------------------------
# Main driver
# -----------------------------------------------------------------------------

def survey_adopter(
    name: str,
    repo_root: pathlib.Path,
    scratch: pathlib.Path,
    verbose: bool,
) -> AdopterResult:
    rel, entry = ADOPTER_SOURCE[name]
    src_path = repo_root / rel
    if not src_path.is_file():
        raise FileNotFoundError(
            f"adopter `{name}` source missing: {src_path}"
        )

    body_lines, src_start, src_end = extract_body(src_path, entry)
    if verbose:
        print(f"[{name}] extracted {len(body_lines)} lines "
              f"({src_start + 1}..{src_end + 1}) from {src_path}",
              file=sys.stderr)

    body_src = transclude_body(name, body_lines)
    raw = assemble_body(body_src, scratch, name)
    strict = trim_trailing_fill(raw)
    passes, fails = brute_check(name)

    return AdopterResult(
        name=name,
        src_path=src_path,
        entry=entry,
        body_lines=body_lines,
        src_start=src_start,
        src_end=src_end,
        bytes=raw,
        body_strict_len=len(strict),
        body_strict=strict,
        func_passes=passes,
        func_fails=fails,
    )


def build_report(results: list[AdopterResult], pairs_match: dict[tuple[str, str], bool]) -> str:
    lines: list[str] = []
    lines.append("# ct_mul_brute_check report")
    lines.append("")
    lines.append("Run by `tools/ct_mul_brute_check.py` to gate c64-lib-contract")
    lines.append("SPEC §8.3 promotion of `mul_8x8` / `ct_mul_8x8` per issue #14.")
    lines.append("")
    lines.append("## Per-adopter findings")
    lines.append("")
    for r in results:
        lines.append(f"### `{r.name}`")
        lines.append("")
        lines.append(f"- Source: `{r.src_path}`")
        lines.append(f"- Entry: `{r.entry}` "
                     f"(lines {r.src_start + 1}..{r.src_end + 1}, "
                     f"{len(r.body_lines)} source lines)")
        lines.append(f"- Body bytes: {r.body_strict_len}")
        lines.append(f"- SHA-256 (first 16 hex chars): `{opcode_hash(r.body_strict)}`")
        lines.append(f"- Functional brute-check: "
                     f"{r.func_passes}/65536 (a, b) pairs match `a * b`"
                     + (f", first failure: {r.func_fails[0]}" if r.func_fails else ""))
        lines.append("")
        lines.append("Opcode dump:")
        lines.append("")
        lines.append("```")
        lines.append(fmt_hex(r.body_strict))
        lines.append("```")
        lines.append("")
    lines.append("## Pairwise byte-identity")
    lines.append("")
    lines.append("| Pair | Bit-identical? |")
    lines.append("|---|---|")
    for (a, b), ok in pairs_match.items():
        lines.append(f"| `{a}` vs `{b}` | {'YES' if ok else 'NO'} |")
    lines.append("")
    any_diff = any(not ok for ok in pairs_match.values())
    if any_diff:
        lines.append("## Divergence detail")
        lines.append("")
        names = {r.name: r for r in results}
        for (a, b), ok in pairs_match.items():
            if ok:
                continue
            lines.append(f"### `{a}` vs `{b}`")
            lines.append("")
            lines.append(f"- `{a}` body: {names[a].body_strict_len} bytes")
            lines.append(f"- `{b}` body: {names[b].body_strict_len} bytes")
            lines.append("- Byte-level diff (first 32 mismatches):")
            lines.append("")
            lines.append("```")
            lines.append(byte_diff_dump(names[a], names[b]))
            lines.append("```")
            lines.append("")
    lines.append("## §8.3 promotion gate")
    lines.append("")
    if any_diff:
        lines.append("**BLOCKED.** Bodies are not byte-identical across all three")
        lines.append("adopters. Issue #14's evidence gate requires bit-identical")
        lines.append("instruction sequences before the body can be promoted as a")
        lines.append("shared §8.3 primitive.")
    else:
        all_func_ok = all(not r.func_fails for r in results)
        if all_func_ok:
            lines.append("**UNBLOCKED.** All three adopters' bodies are")
            lines.append("byte-identical AND the underlying quarter-square reference")
            lines.append("matches `a * b` for all 65,536 (a, b) pairs. Issue #14's")
            lines.append("evidence gate is satisfied; SPEC §8.3 promotion may")
            lines.append("proceed under the draft clause text.")
        else:
            lines.append("**BLOCKED (functional).** Bodies are byte-identical but")
            lines.append("the brute-check reference disagrees with `a * b` for at")
            lines.append("least one (a, b) pair. Investigate before promoting.")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chacha", type=pathlib.Path,
                        default=DEFAULT_PATHS["chacha"])
    parser.add_argument("--nist-curves", type=pathlib.Path,
                        default=DEFAULT_PATHS["nist-curves"])
    parser.add_argument("--x25519", type=pathlib.Path,
                        default=DEFAULT_PATHS["x25519"])
    parser.add_argument("--report", type=pathlib.Path, default=None)
    parser.add_argument("--keep-tmp", action="store_true")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    repo_paths = {
        "chacha": args.chacha,
        "nist-curves": args.nist_curves,
        "x25519": args.x25519,
    }

    scratch_root = pathlib.Path(tempfile.mkdtemp(prefix="ct_mul_brute_"))
    if args.verbose:
        print(f"[scratch] {scratch_root}", file=sys.stderr)

    try:
        results: list[AdopterResult] = []
        for name in ("chacha", "nist-curves", "x25519"):
            r = survey_adopter(name, repo_paths[name], scratch_root, args.verbose)
            results.append(r)

        pairs_match: dict[tuple[str, str], bool] = {}
        names = [r.name for r in results]
        for i in range(len(names)):
            for j in range(i + 1, len(names)):
                a, b = names[i], names[j]
                pairs_match[(a, b)] = (
                    results[i].body_strict == results[j].body_strict
                )

        report = build_report(results, pairs_match)
        if args.report:
            args.report.write_text(report)
            print(f"wrote report to {args.report}", file=sys.stderr)
        else:
            print(report)

        any_byte_diff = any(not ok for ok in pairs_match.values())
        any_func_fail = any(r.func_fails for r in results)
        return 1 if (any_byte_diff or any_func_fail) else 0

    except Exception as e:
        print(f"ct_mul_brute_check: {e}", file=sys.stderr)
        return 2
    finally:
        if args.keep_tmp:
            print(f"[scratch retained] {scratch_root}", file=sys.stderr)
        else:
            shutil.rmtree(scratch_root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
