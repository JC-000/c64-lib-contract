# `ct_mul_8x8` cross-adopter divergence report

**Date:** 2026-05-23
**Tool:** `tools/ct_mul_brute_check.py` (this branch)
**Mechanical report:** [`ct_mul_brute_check_2026_05_23.md`](ct_mul_brute_check_2026_05_23.md)
**Gates:** c64-lib-contract issue [#14](https://github.com/JC-000/c64-lib-contract/issues/14)
**Status:** SPEC §8.3 promotion **BLOCKED** by structural divergence; reconciliation deferred.

## Summary

All three adopters' `mul_8x8` / `ct_mul_8x8` bodies are functionally
correct (each passes the 65 536 brute-force `(a, b) ∈ [0..255]²` check
against the Python `a * b` reference, via the quarter-square identity
`a*b = sqtab[a+b] - sqtab[|a-b|]`). None of the three bodies are
bit-identical to either of the other two:

| Adopter | Source | Entry | Body bytes | SHA-256 (first 16 hex) |
|---|---|---|---:|---|
| `c64-ChaCha20-Poly1305` | `src/lib/poly1305_lib.s` | `ct_mul_8x8` | 59 | `c9fe8fdc6937e256` |
| `c64-nist-curves` | `src/mul_8x8.s` | `mul_8x8` | 63 | `913bd104417508bc` |
| `c64-x25519` | `src/mul_8x8.s` | `mul_8x8` | 84 | `62cdab9d62592d83` |

Issue #14's evidence gate requires bit-identical instruction sequences
("SMC-dispatched bodies must match opcode-for-opcode, since
cycle-stability of `abs,x` indexed loads is the CT invariant the variant
exists to preserve"). The structural differences below mean we cannot
proceed with §8.3 promotion under the current source shapes.

## Divergence classification

The three bodies diverge along **three independent axes**. Any
reconciliation will need to pick a single point in this product space
and have the other two adopters move to it.

### Axis A — calling convention (entry contract)

| Adopter | Entry | Scratch on entry | Notes |
|---|---|---|---|
| chacha | **SMC-baked** `a` operand: `smc_sum_a_imm+1` and `smc_diff_a_imm+1` hold `a`; `Y = b` at entry | none on entry (caller pre-baked) | Pays 6 cy at caller for two `sta` per outer-`j` iter; saves 5 cy per inner-`i` call. Profitable only for tight inner loops with N inner iters per outer (Poly1305: 16 i per j). |
| nist-curves | **Register entry**: `A = a`, `X = b`; preamble does `tay / stx mul_b` (saves an `lda mul_a` in the diff block by keeping `a` live in Y) | 1 zp byte (`mul_b`) | Pays 5 cy at entry, saves 2 cy mid-body by reading `a` from Y instead of zp. Pure win vs the obvious `sta mul_a / stx mul_b` shape. |
| x25519 | **Register entry**: `A = a`, `X = b`; preamble does `sta mul_a / stx mul_b` (the textbook shape) | 2 zp bytes (`mul_a`, `mul_b`) | The "obvious" register entry; uses both zp slots. Pays 2 cy more in body than the nist-curves shape; 5 cy more than chacha (which avoids both stash slots and the body re-load). |

### Axis B — block ordering (sum-first vs diff-first)

| Adopter | First block | Second block |
|---|---|---|
| chacha | **sum + SMC patch** | `\|a-b\|` |
| nist-curves | **sum + SMC patch** | `\|a-b\|` |
| x25519 | **`\|a-b\|`** | **sum + SMC patch** |

This is the most consequential algorithmic divergence. nist-curves
matches chacha's sum-first ordering (since nist-curves was ported from
chacha v0.3.0 per its CLAUDE.md "Origin" note). x25519 keeps the
historical diff-first ordering of the pre-S12 `mul_8x8` ancestor (see
the audit table in chacha's [`docs/design/ct_mul_8x8.md`](../../c64-ChaCha20-Poly1305/docs/design/ct_mul_8x8.md)
§2.3: "Identical CT bug" branchy ancestor). The opcode bytes therefore
disagree from offset 0 onward.

Either ordering is correct (the two blocks are independent), but they
produce different opcode bytes and hence different SMC layouts.

### Axis C — sign-mask scratch placement

| Adopter | Sign-mask byte location | Diff-raw stash location |
|---|---|---|
| chacha | `ct_sign_mask` (zp / data) | `ct_diff_raw` (zp / data) |
| nist-curves | `ct_sign_mask` (zp / data) | **Y register** (kept live across the `lda #0 / sbc #0`) |
| x25519 | `mul_mask` (zp / data) | `mul_diff` (zp / data) |

nist-curves' `tay` after the raw sbc and `tya` before the eor (the
"Y-shuttle" form) saves one `sta diff_raw` / `lda diff_raw` round-trip
vs both chacha and x25519. The chacha and x25519 shapes are
otherwise structurally similar in this block but the scratch slot
*names* differ (`ct_sign_mask` vs `mul_mask`), and x25519 also
introduces a `mul_sum_pg` byte that chacha and nist-curves fold
directly into the carry path. The x25519 body therefore has more `sta`
instructions in absolute count, hence its 84-byte size.

## Per-adopter opcode dump (verbatim from tool)

### `c64-ChaCha20-Poly1305` (canonical SMC variant, 59 B)

```
+0000: 98 18 69 00 aa a9 9c 69 00 8d 29 10 69 02 8d 33
+0010: 10 98 38 e9 00 8d 08 80 a9 00 e9 00 8d 09 80 4d
+0020: 08 80 38 ed 09 80 a8 bd 00 80 38 f9 00 9c 8d 00
+0030: 80 bd 00 82 f9 00 9e 8d 01 80 60
```

Decoded prefix: `tya / clc / adc #$00 / tax / lda #$9c / adc #$00 / sta
$1029 / adc #$02 / sta $1033` — confirms the sum-first + SMC patch
shape with `Y` already holding `b` at entry.

### `c64-nist-curves` (ported from chacha; register entry, 63 B)

```
+0000: a8 8e 03 80 18 6d 03 80 aa a9 9c 69 00 8d 2d 10
+0010: 69 02 8d 37 10 98 38 ed 03 80 a8 a9 00 e9 00 8d
+0020: 09 80 98 4d 09 80 38 ed 09 80 a8 bd 00 9c 38 f9
+0030: 00 9c 8d 00 80 bd 00 9e f9 00 9e 8d 01 80 60
```

Decoded prefix: `tay / stx $8003 / clc / adc $8003 / tax / lda #$9c /
adc #$00 / sta $102d / adc #$02 / sta $1037` — register-entry preamble
then the chacha-shape sum-first block; +4 bytes vs chacha is the
two-instruction entry preamble (`tay` / `stx mul_b`).

### `c64-x25519` (pre-SMC heritage; register entry, diff-first, 84 B)

```
+0000: 8d 02 80 8e 03 80 ad 02 80 38 ed 03 80 8d 04 80
+0010: a9 00 e9 00 8d 05 80 4d 04 80 38 ed 05 80 a8 ad
+0020: 02 80 18 6d 03 80 aa a9 00 69 00 8d 06 80 a9 9c
+0030: 18 6d 06 80 8d 42 10 a9 9e 18 6d 06 80 8d 4c 10
+0040: bd 00 9c 38 f9 00 9c 8d 00 80 bd 00 9e f9 00 9e
+0050: 8d 01 80 60
```

Decoded prefix: `sta $8002 / stx $8003 / lda $8002 / sec / sbc $8003 /
sta $8004 / lda #$00 / sbc #$00 / sta $8005 / eor $8004 / sec / sbc
$8005 / tay / lda $8002 / clc / adc $8003 / tax / lda #$00 / adc #$00 /
sta $8006 / lda #$9c / clc / adc $8006 / sta $1042 / lda #$9e / clc /
adc $8006 / sta $104c` — diff-first; then the sum block computes
`mul_sum_pg` as a separate byte and uses two `clc / adc mul_sum_pg`
sequences (one per SMC patch site) instead of folding the page bit
into the running carry as chacha and nist-curves do. The folded-carry
shape saves 7 bytes per SMC patch site (14 bytes total) vs the
explicit `mul_sum_pg`-staged shape — the bulk of the 21-byte size
delta vs nist-curves.

## CT-cycle equivalence vs byte-identity

Even though all three bodies pass the brute-check (functional
correctness), only chacha and nist-curves are within the "small local
rewrite" distance of each other. x25519 is a meaningfully different
algorithm decomposition:

- **chacha vs nist-curves:** the bodies differ by ~4 bytes (the two
  entry preamble bytes plus a one-byte tya/lda re-route in the diff
  block). Both end identically (final `bd 00 9c 38 f9 00 9c 8d 00 80 bd
  00 9e f9 00 9e 8d 01 80 60`). They are "the same algorithm with two
  different calling conventions".
- **x25519 vs either:** the diff-first block ordering AND the explicit
  `mul_sum_pg` staging are independent structural choices. The body is
  >40% larger and has no shared prefix with either other adopter.

Per issue #14's wording, **all three** of these distinctions block
promotion. The CT invariant (`abs,x` cycle-stability under SMC dispatch)
is preserved in each body — none of them re-introduces the pre-S12
`bcs :+` or `beq @s0` branches — but the bar is byte-identity, not
"CT-equivalent".

## Recommended reconciliation order (NOT applied here — for maintainer)

The user explicitly instructed: "If divergence found, do NOT attempt to
reconcile." This section is forward-looking only; no source patches are
proposed in this branch.

The minimum-effort reconciliation:

1. **Adopt the chacha SMC body verbatim as canonical**. It is the
   smallest of the three (59 B), the existing §8.1 forward-look already
   names chacha as the canonical owner, and chacha's macro pack
   (`src/include/smc.inc`) is the only one that emits the `SMC label, {
   stmt }` form cleanly.
2. **Port nist-curves to the SMC-baked calling convention** (drop the
   `tay / stx mul_b` preamble; teach `reu_mul_init` to bake `a` into
   the two SMC immediates per outer iteration). The nist-curves single
   caller is `reu_mul_init` (boot-time only), so the perf cost of the
   bake at each outer iter is irrelevant (~2 s of boot-time noise per
   CLAUDE.md). Conversion delta: ~4 byte body delta to chacha + a
   3-instruction preamble at the single caller.
3. **Port x25519 to the same SMC shape**. Higher effort — x25519 has
   multiple `mul_8x8` callers (every `fe25519_*` op), so the
   per-caller SMC bake cost has to be measured. The diff-first vs
   sum-first reorder is mechanical; the `mul_sum_pg` elimination
   requires folding the page bit into the carry chain (a 7-byte
   shrink per SMC site).

After all three converge on the chacha body, re-run
`ct_mul_brute_check.py`; expected outcome is three matching 59-byte
SHA-256 fingerprints and exit 0. At that point the §8.3 SPEC clause
text can be drafted (the user requested the draft be deferred until the
gate clears).

## Open questions for the maintainer

1. **Is reconciliation in-scope for the §8.3 milestone**, or does §8.3
   ship with a "canonical = chacha SMC body, adopters MAY ship local
   ports until LIB_ABI_VERSION ≥ 2" allowance the way §8.1 does for
   `SHARED_SQTAB_INIT`? The latter avoids cross-repo coordination but
   weakens the CT-equivalence story across adopters.
2. **Does nist-curves' single-caller register-entry adaptation get a
   carve-out?** Per nist-curves' CLAUDE.md, the `mul_8x8` body is on
   a boot-only path; pushing it to the SMC-baked form means
   `reu_mul_init` has to re-emit the SMC bake per `a` value, which
   complicates the boot path without any runtime benefit. This may be
   the right place to allow a §8.3 "register-entry profile" carve-out
   alongside the canonical SMC profile, gated by a build-time switch
   analogous to `SHARED_SQTAB_INIT`.
3. **Does x25519's diff-first ordering have a documented reason** (e.g.
   register pressure on the older fe25519 callsite) or is it just
   historical? If it's historical, the reconciliation cost on x25519 is
   the highest-value of the three to recover and the chacha shape is a
   clean win.
