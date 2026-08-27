# C64 Library ABI Contract

**Version:** 0.12.1 (2026-08-27)
**Status:** Draft — under joint review by adopters and consumers.

**Referencing a version.** Every version in §12 is tagged `v<version>` in this repository, so a consumer or adopter can pin, diff or cite a specific contract revision rather than tracking `main`. A tag's `SPEC.md` states its own version on the line above — check it rather than assuming, since a recent tag does not imply recent content.

## 0. Scope and audience

This contract defines the symbols, segment names, and build conventions that a C64 cryptographic library should expose so that *multiple downstream consumers* can integrate it without patching the library's source files.

- A **library** is a self-contained C64 implementation of a cryptographic primitive (ECC scalar mult, ECDSA verify, X25519, ChaCha20-Poly1305, SHA, etc.) shipped as a git repository, typically with a standalone test PRG and a `make lib` archive target.
- A **consumer** is a downstream project (TLS client, IPsec/VPN, signature verifier, ...) that vendors one or more libraries as git submodules and links their archives into its own PRG.
- The contract exists because, without it, each consumer mid-build sed-patches each library's sources to rename segments, relocate ZP slots, and strip unwanted code paths. That tightly couples consumer cfgs to library source layout — every library tag bump risks breaking the consumer's integration shell scripts. With the contract, the library publishes everything the consumer needs as code (equates, segment names, build targets), and the consumer's cfg picks up the library by name with zero source patches.

The contract is deliberately minimal. It governs symbols and conventions, not implementation choices.

**How to read this document (v0.10.1).** The chapters fall into three kinds, and a new adopter reads the first kind plus whichever of the second apply:

| Kind | Sections | Who reads it |
|---|---|---|
| **Core** — every library, every consumer | §1 versioning · §2 zero page · §3 REU layout · §4 segments · §5 manifests · §6 build-and-consume · §7 semver | everyone |
| **Domain** — only if the library implements that domain | §8 shared crypto primitives · §13 network backend ABI | crypto libraries: §8; network backends: §13 |
| **Meta** — project state | §9 compatibility timeline · §10 adopters · §11 consumers · §12 changelog | reference as needed |

Section numbers are stable identifiers and never change; the reading order above is also the physical order of this document (the changelog closes it). An ip65-shaped network library reads the core and §13 and can ignore §8 entirely; the four crypto adopters read the core and §8 and ignore §13.

## 1. Version identification

Every library MUST export the following integer equates, where `<X>` is the library's own UPPER_SNAKE_CASE prefix — the same `<X>` used by its §5 manifest equates (`X25519`, `NISTCURVES`, `CHACHA20_POLY1305`, `POLYVAL`):

| Symbol | Type | Semantics |
|---|---|---|
| `LIB_<X>_VERSION_MAJOR` | integer equate | Semantic-version major. Bumped on breaking ABI change. |
| `LIB_<X>_VERSION_MINOR` | integer equate | Semantic-version minor. Bumped on additive ABI change (new symbol, new build target). |
| `LIB_<X>_VERSION_PATCH` | integer equate | Bug-fix release. No ABI change. |
| `LIB_<X>_ABI_VERSION` | integer equate | Monotonic generation counter for the exported surface, **starting at 1**. Incremented on any breaking export change. Deliberately independent of MAJOR — see the note below. |

The symbols live in a dedicated file, conventionally `src/lib_version.s`, and are exported via `.export ... : abs`. The `: abs` hint is required, not decorative: these are small integers, so ca65 infers **zeropage** for them without it, while a consumer's `.import` defaults to absolute — producing `ld65: Warning: Address size mismatch` at every import site. Same defect as the §8.4 macro exports fixed in v0.7.4 ([#58](https://github.com/JC-000/c64-lib-contract/issues/58)).

**Deprecated bare forms (v0.7.0).** Through v0.x every library MUST *also* export the unprefixed `LIB_VERSION_MAJOR` / `LIB_VERSION_MINOR` / `LIB_VERSION_PATCH` / `LIB_ABI_VERSION`, so existing single-library consumers keep working unchanged. These names are **deprecated and scheduled for removal at contract v1.0**: they are identical across every library, so a consumer that links two of them and imports both manifests gets `ld65: Error: Duplicate external identifier` ([#43](https://github.com/JC-000/c64-lib-contract/issues/43)). The bare exports MUST be gated on `LIB_NO_BARE_EXPORTS` so a composing consumer can suppress them build-wide with `ca65 -D LIB_NO_BARE_EXPORTS=1`.

**Zero-consumer carve-out (v0.11.0).** A library onboarding with **no released consumers** SHOULD NOT export the bare forms at all. The MUST above is written for *existing* single-library consumers — it exists so they keep working unchanged. A library nobody has linked yet has none, so the export protects no one while adding a further claimant to the exact four names that produce [#43](https://github.com/JC-000/c64-lib-contract/issues/43)'s `Duplicate external identifier`. Such a library is simply born in the state every other library reaches at contract v1.0, and it never needs the removal.

Scope is the same test §6.5 uses: "no released consumers" means no tagged release that any consumer pins, checkable from the library's own tags and `consumers.md` rather than asserted. A library that has cut a release someone links keeps the MUST.

This is a `SHOULD NOT` rather than a `MUST NOT` because the bare forms remain harmless in a single-library link, and a library that prefers uniformity with the incumbents may keep them. What it MUST NOT do is ship them ungated — the `LIB_NO_BARE_EXPORTS` requirement above is unaffected by this carve-out.

**`LIB_<X>_ABI_VERSION` is independent of MAJOR (normative, v0.7.5).** It is a generation counter for the exported surface, not a mirror of the semantic version. It starts at **1** and increments on any breaking export change — a removed or renamed symbol, a changed calling convention, a changed memory model.

It cannot track MAJOR, because §7 permits breaking changes on MINOR bumps while a library is pre-1.0, so MAJOR stays `0` across breakage and carries no signal. A consumer gating on `LIB_<X>_ABI_VERSION` would then never fire for exactly the changes the gate exists to catch. This is not hypothetical: `c64-nist-curves` v0.9.0 removed 17 exported symbols on a MINOR bump ([#90](https://github.com/JC-000/c64-nist-curves/issues/90), [#91](https://github.com/JC-000/c64-nist-curves/issues/91)) with `LIB_NISTCURVES_ABI_VERSION` left at `0` per the previous "matches MAJOR" wording, and consumer guards stayed silent.

Consumers gate on this equate rather than on MINOR being "safe":

```asm
.import LIB_X25519_ABI_VERSION
.assert LIB_X25519_ABI_VERSION = 1, lderror, "c64-x25519 exported-surface generation changed; re-check the integration"
```

**TU isolation (required).** The bare exports MUST live in a translation unit that exports nothing else — no §5 manifest equates, no §8.4 table equates, no code. §8.4 requires the `LIB_PRECALC_TABLE` macro to be included from a single TU, and ld65 pulls in whole object members: if the bare names share a member with anything a consumer legitimately imports, they enter the link uninvited and collide even when the consumer never referenced them. `src/lib_version.s` holding only the block below satisfies this; §5's aggregate equates move to `src/lib_manifest.s`.

**Pattern:**

```asm
; src/lib_version.s — exports nothing but these
.export LIB_X25519_VERSION_MAJOR: abs
.export LIB_X25519_VERSION_MINOR: abs
.export LIB_X25519_VERSION_PATCH: abs
.export LIB_X25519_ABI_VERSION: abs

LIB_X25519_VERSION_MAJOR = 0
LIB_X25519_VERSION_MINOR = 8
LIB_X25519_VERSION_PATCH = 0
LIB_X25519_ABI_VERSION   = 1

.ifndef LIB_NO_BARE_EXPORTS
    ; Deprecated, removed at contract v1.0. Suppress with
    ; ca65 -D LIB_NO_BARE_EXPORTS=1 when composing two or more libraries.
    .export LIB_VERSION_MAJOR: abs
    .export LIB_VERSION_MINOR: abs
    .export LIB_VERSION_PATCH: abs
    .export LIB_ABI_VERSION: abs

    LIB_VERSION_MAJOR = LIB_X25519_VERSION_MAJOR
    LIB_VERSION_MINOR = LIB_X25519_VERSION_MINOR
    LIB_VERSION_PATCH = LIB_X25519_VERSION_PATCH
    LIB_ABI_VERSION   = LIB_X25519_ABI_VERSION
.endif
```

Aliasing the bare names to the prefixed ones rather than restating the literals means a release bump touches four lines, not eight, and the two forms cannot drift.

**Consumer-side usage:**

```asm
.import LIB_X25519_VERSION_MAJOR
.import LIB_X25519_VERSION_MINOR

.assert (LIB_X25519_VERSION_MAJOR > 0) .or (LIB_X25519_VERSION_MINOR >= 8), lderror, "this consumer needs c64-x25519 v0.8 or later"
```

**Why `.assert` / `lderror` rather than `.if` / `.error`.** `.if` needs an assembly-time constant, and an `.import`ed symbol has no value until link — ca65 rejects the guard outright with `Constant expression expected`, so an `.if`-based version gate never assembles at all rather than silently passing. `.assert` with the `lderror` action defers evaluation to ld65, which is the only stage that knows the imported value. The trade is that the guard fires at link rather than assemble time; it still fires before anything runs.

A consumer linking two or more libraries builds them all with `-D LIB_NO_BARE_EXPORTS=1` and imports the prefixed forms only; the guard above then names which library is out of date instead of reporting one anonymous version.

Where a consumer pins to a specific library version via git submodule SHA, the `LIB_VERSION_*` guard is a defense-in-depth assert that fires at assemble time before any 30-minute link/test cycle.

## 2. Zero-page contract

Every library that claims any ZP slots MUST publish them as `.exportzp`-ed equates in a dedicated `src/zp_config.s` (or `.inc`) file. Each equate MUST be `.ifndef`-guarded so a consumer can override the slot via `ca65 -D <slot>=$<addr>`.

**Naming convention:** `<lib_prefix>_<role>`, lower-case (e.g., `fp_src1`, `cc20_state`, `x25519_w_lo`). The prefix keeps slots from colliding across libraries when a consumer links several.

**ZP prefix registry (v0.9.0).** Every exported slot name MUST begin with a prefix registered here to exactly one library; intake of a new adopter checks its ZP surface against this table exactly as §8.0 checks bit claims. Same-named slots across two libraries are always a defect unless the name is a §8.x canonical contract item — deliberate cross-library sharing is expressed only through §8.x clauses, never through incidental name equality (the [#83](https://github.com/JC-000/c64-lib-contract/issues/83) failure class: three adopters independently converged on bare `zp_tmp1`/`zp_ptr1`, two shipped them, and the resulting duplicate-identifier error was the only thing preventing a measured 12-byte silent address overlap between actively-used scratch).

| Prefixes | Registered to |
|---|---|
| `fp_` `ec_` `sha_` `nistcurves_` | `c64-nist-curves` |
| `fe25519_` `fe_` `x25_` `mul_` `sqr_` `x25519_` | `c64-x25519` |
| `polyval_` `pv_` | `c64-polyval` |
| `cc20_` `poly_` `w32_` `ct_` `chacha_` `chacha20poly1305_` | `c64-ChaCha20-Poly1305` |
| `mlkem_` | `c64-mlkem` |

Every library's §6.1 `<shortname>_` is registered to it by construction (v0.9.2 — the general-scratch rule below implied this; the table now states it, closing the gap the first `chacha20poly1305_zp_*` migration exposed in [chacha#78](https://github.com/JC-000/c64-ChaCha20-Poly1305/pull/78)). General-purpose scratch takes `<shortname>_zp_<role>` (e.g., `nistcurves_zp_tmp1`). Known migration items, riding the §6.5 rename window **with its suppression gate** (deprecated bare slot names sit behind `LIB_NO_BARE_EXPORTS`, per §6.5/#88 — an ungated bare alias would preserve the #83 collision for the window's whole duration): `c64-nist-curves`' live bare `zp_tmp1`/`zp_tmp2`/`zp_ptr1`/`zp_ptr2`; `c64-x25519`'s `poly_carry` (a `mul_8x8` carry byte, colliding with the `poly_` registration) renames into its `mul_` family; `c64-ChaCha20-Poly1305`'s bare `.importzp` names move in the same window.

**Pattern:**

```asm
; src/zp_config.s
.ifndef fp_src1
    fp_src1 = $22
.endif
.ifndef fp_src2
    fp_src2 = $26
.endif
.exportzp fp_src1, fp_src2
```

**Consumer override:**

```sh
ca65 -D 'fp_src1=$40' -D 'fp_src2=$44' ...
```

The library's own standalone tests assemble with the defaults; the consumer relocates as needed via `-D`.

> **Flag spelling (normative for every snippet in this document).** The ca65 symbol-define flag is **`-D name[=value]`**. It is *not* `--asm-define` — that is `cl65`'s spelling for the same thing, which `cl65` forwards to ca65. Invoking `ca65 --asm-define ...` fails outright with `ca65: Unknown option: --asm-define` (measured, ca65 V2.18). Consumers driving the build through `cl65` may use either form; every `ca65` command line in §2, §3, §8.x and §13 uses `-D`.
>
> **`$`-hex quoting (normative for every `-D` value, v0.8.6).** A `-D` value containing ca65's `$` hex prefix MUST be single-quoted on any shell command line: unquoted, the shell expands `$40` as positional parameter `$4` followed by `0`, so `-D fp_src1=$40` silently becomes `-D fp_src1=0` — the assemble succeeds, the guard `.ifndef` is satisfied, and the slot lands at address `$00` with no diagnostic at any stage (measured, sh and zsh). Inside a **make** variable or recipe the failure is worse: make's own `$`-expansion consumes the sigil first, and each added escape layer fails differently — `$40` and `$$40` both measured to produce **0**, and `$$$$40` produces **the shell's PID**: a plausible-looking address that changes between invocations, with no diagnostic from make, the shell, ca65 or ld65 (a consumer would see intermittent ZP corruption with no reason to suspect the flag). Make-mediated interfaces MUST therefore pass `$`-free values: ca65 accepts **`0x`-prefixed hex natively** — `-D fp_src1=0x40` survives make and the shell unquoted and unescaped (measured, ca65 V2.18) — with plain decimal as the alternative. `\$$40` also survives but earns nothing over `0x40`. Adopter docs that copied the previously-unquoted forms should re-check their own snippets.

## 3. REU layout contract

If a library uses any 17xx-series RAM Expansion Unit (REU) banks for precompute tables or scratch, every base bank/offset MUST be a `.ifndef`-guarded integer equate in `src/reu_config.s` (or equivalent), `.export`-ed so the consumer can `.import` it.

**Naming convention:** `<LIB>_REU_BANK` for the primary bank, `<LIB>_REU_OFFSET` for the within-bank base offset; per-table offsets where needed (`<LIB>_TABLE1_OFFSET`, etc.).

**Pattern:**

```asm
; src/reu_config.s
.ifndef X25519_REU_BANK
    X25519_REU_BANK = $00
.endif
.ifndef X25519_REU_OFFSET
    X25519_REU_OFFSET = $0000
.endif
.export X25519_REU_BANK, X25519_REU_OFFSET
```

**Consumer override:**

```sh
ca65 -D 'X25519_REU_BANK=$03' ...
```

**Aggregate bitmask:** the library MUST also export a `LIB_<X>_REU_BANKS_USED` bitmask equate listing every REU bank the library claims. Consumers compose these per-library masks at assemble time:

```asm
.import LIB_NISTCURVES_REU_BANKS_USED
.import LIB_X25519_REU_BANKS_USED
.assert (LIB_NISTCURVES_REU_BANKS_USED & LIB_X25519_REU_BANKS_USED) = 0, error, "REU bank collision"
```

Consumers MAY relocate any library's REU base via `-D` to resolve a collision. The aggregate mask makes collisions visible at assemble time rather than runtime.

## 4. Segment naming

Library code, rodata, and BSS MUST live in segments prefixed with `LIB_<X>_` (uppercase). The default ld65 segment names (`CODE`, `RODATA`, `DATA`, `BSS`) MUST NOT appear in library sources. **`ZEROPAGE` is exempt**: zero-page allocation is governed by §2, which requires `.exportzp`-ed, `.ifndef`-guarded slot equates rather than a prefixed segment name. A misplaced ZP segment fails loudly with a range error, so it needs no silent-failure protection here.

**Why:** Consumer projects use their own `CODE` / `RODATA` for `main.s` and helpers. Without prefixed segments, the consumer must mid-build `sed -i ''` the library's `.segment "CODE"` directives to rename them before assembly. Prefixed segments let the consumer's cfg `SEGMENTS{}` block place library bytes by name — zero source patches.

**Pattern:**

```asm
; libfoo/src/something.s
.segment "LIB_FOO_CODE"

my_helper:
    rts
```

**Multi-variant libraries** (e.g., per-curve) MUST split per-variant segments: `LIB_NISTCURVES_P256_CODE`, `LIB_NISTCURVES_P384_CODE`. This lets a consumer link only the variants it uses.

**Load-bearing cfg attributes (normative).** Segment *names* are only half of what a consumer must get right. A library whose correctness or constant-time behaviour depends on how its segments are placed MUST declare those dependencies, and a consumer placing library segments MUST preserve them.

Declare them as comments on the segment lines of the example cfg this clause already requires, so they travel with the thing consumers copy:

```
SEGMENTS {
    # REQUIRED align = $100 — CT invariant. Secret-indexed `.align 256` LUTs
    # are aligned relative to this segment; without page alignment here an
    # indexed read crosses a page for some indices and takes an extra cycle,
    # making execution time depend on a secret. ld65 only *warns*.
    LIB_FOO_CODE: load = MAIN, type = ro, align = $100;

    # REQUIRED type = rw in a file-emitting area — holds initialised data
    # (`foo_ready` idempotence flag). Under `type = bss` the bytes are not
    # emitted and read as power-on garbage. ld65 says nothing at all.
    LIB_FOO_DATA: load = MAIN, type = rw;
}
```

Each declaration states the attribute, its required value, and what breaks if it is wrong. State the consequence, not just the requirement — a consumer who knows only *that* `align` matters will still drop it when reorganising a memory map under pressure.

**"The link was clean" is not evidence.** Measured on ld65 V2.18 — and both diagnostics are **conditional on the library's own shape**, not on the violation:

| Violation | ld65 warns | …only when | Silent when | Result |
|---|---|---|---|---|
| `align = $100` omitted | sometimes | the segment contains a source-level `.align`, which gives ld65 an explicit request to check the cfg against | alignment is expressed **only in the cfg** — no `.align` in any source file | the table lands off its page boundary either way |
| `type = rw` → `type = bss` | sometimes | the segment's content is **non-zero** | content is zero-filled — `.res n, 0`, the ordinary library-scratch shape | see below |

Neither is ever an error, and neither condition is one a consumer can evaluate: both depend on library source the consumer does not read. A library expressing page alignment in its cfg alone — a normal and correct thing to do — gets **no diagnostic at all** when a consumer drops the attribute, and the same holds for any zero-filled buffer flipped to `bss`. The loud cases are the exception, not the rule.

**The `bss` consequence is worse than a stale byte.** If the affected segment is last in a file-emitting area, its bytes are simply absent and read as power-on garbage. **Mid-area, ld65 emits a shorter image and everything after the hole loads at the wrong address** — measured at 9,154 bytes of displacement for one mid-image code segment, every subsequent byte landing that far below its link address. Such a build can appear to work by coincidence: it does, if the missing content happens to be zeros and every affected buffer happens to be written before it is read.

That is why declaring is the library's obligation rather than something a careful consumer could infer — the consumer cannot see the conditions that decide whether they get a warning at all.

This is the §2 / §3 pattern applied to placement: those clauses already make ZP slots and REU banks declared, overridable, and checkable rather than leaving a consumer to discover them. §8.1 likewise `.assert`s that `LIB_SHARED_SQTAB_BASE` is page-aligned — but nothing today protects the *segment* that alignment is measured from, which is the gap this closes.

**Library's own standalone build:** the library's example cfg (`cfg/<libname>.cfg` or similar) MUST add a `SEGMENTS{}` block that maps the prefixed names back to MAIN/RODATA/DATA for the standalone PRG. That way, the library's own tests and bench harness build unchanged.

## 5. Aggregate manifest equates

Every library MUST export the following four integer equates. As of v0.7.0 they live in `src/lib_manifest.s`, **not** `src/lib_version.s` — §1 requires that file to carry the deprecated bare version exports and nothing else, so that importing a manifest equate cannot drag them into the link:

| Symbol | Semantics |
|---|---|
| `LIB_<X>_ZP_USAGE_BYTES` | Total bytes of ZP slots claimed (sum of all `.exportzp` slots). |
| `LIB_<X>_REU_BANKS_USED` | Bitmask of REU banks claimed (see §3). Zero if no REU. |
| `LIB_<X>_RESIDENT_BYTES` | Approximate code+rodata footprint that must remain CPU-resident in any consumer. Refreshed per release. |
| `LIB_<X>_COLD_BYTES` | Approximate code+rodata footprint that a consumer MAY overlay-page (load on demand from REU, kernal-banked RAM, or external storage). Refreshed per release. |

Libraries that consume one or more shared primitives defined in §8 MUST additionally export a `LIB_<X>_SHARED_PRIMITIVES` bitmask equate, ORed from the per-primitive bit constants declared in each §8.x sub-clause, and its companion `LIB_<X>_SHARED_CONSUMES` bitmask (v0.5.0). The ownership bitmask lets consumers detect duplicate ownership of any shared primitive at assemble time; the consumes bitmask lets them verify every consumed primitive has an owner in the link. See §8.0 for the bit allocation table, the normative build-config state definitions, and both masks' required construction forms.

These let a consumer's cfg do assemble-time fit checks:

```asm
.import LIB_NISTCURVES_RESIDENT_BYTES
.import __CRYPTO_HOT_SIZE__   ; ld65-published region size
.assert LIB_NISTCURVES_RESIDENT_BYTES + ... < __CRYPTO_HOT_SIZE__, error, "no room"
```

And let a CI bot decide whether to even attempt a build against a new library version before kicking off a long compile + test cycle.

The numbers MAY be approximate — within 5% is fine. The library author refreshes them when a release substantively changes any one of them.

## 6. Build and consume

Obligations in this chapter attach to **archives** — the artifacts a consumer links — not to "the library" in the abstract. A library shipping nine variant archives satisfies each clause nine times or not at all. This is the noun correction motivating the v0.9.0 restructuring: per-library phrasing let per-variant truth fall through the gap (§6.4).

### 6.1 Targets and artifact names

The library's Makefile MUST provide:

- `make` (no args) — build the standalone test PRG. Library author's primary integration target; what `make test` and `make bench` depend on.
- `make lib` — the full archive `build/lib/<shortname>.a`, containing every exported symbol the library ships.
- `make lib-<variant>` — minimal-subset archives for primary consumer use cases, at `build/lib/<shortname>-<variant>.a`. Variants are library-specific.
- `make lib-app-owned` — §6.3, required of §8.x-consuming libraries.

`<shortname>` is the library's §1 prefix, lowercased (`nistcurves`, `x25519`, `polyval`, `chacha20poly1305`). Archive basenames that differ today (`libx25519.a`, `c64-chacha20-poly1305.a`) are deprecated dialects: ship the canonical basename alongside the old one from the library's next MINOR release, drop the old form at its next MAJOR (§6.5 window).

The `lib` / `lib-*` make-target namespace is reserved for targets that produce archives. Check and verification targets MUST NOT use it; existing `lib-verify`-style names are grandfathered until each repo's next MAJOR, new ones take `check-*` / `verify-*`.

Consumers fetch `build/lib/<shortname>[-<variant>].a` and link directly. No mid-build `sed`, no copying intermediates around, and **no `ar65` member surgery** — an archive whose member set a consumer has edited is outside every §5/§8.0 manifest claim it ships. §6.2 and §6.3 exist so surgery is never the only route to a configuration.

### 6.2 Consumer defines reach the build

Every §6.1 target MUST accept consumer-supplied ca65 defines without the consumer editing the Makefile or replacing a flag variable wholesale. A hard-assigned `CA65FLAGS` a consumer must clobber to inject one `-D` is non-conformant — the clobber silently drops `-t c64` and include paths (measured: `Error: Cannot open include file` at best, a mis-targeted assemble at worst).

Two contract-normative make variables, both defaulting empty. The split is load-bearing, not stylistic:

| Variable | Reaches | Carries |
|---|---|---|
| `CONTRACT_DEFINES` | **every** archive-member recipe | variant/profile selectors, §8.x deferral switches, `LIB_SHARED_SQTAB_BASE`, `LIB_SHARED_REU_MUL_*` placement, `LIB_NO_BARE_EXPORTS` |
| `CONTRACT_ZP_DEFINES` | **only** the ZP-defining TU(s) | §2 slot overrides |

A §2 slot override delivered globally collides with every `.importzp` site — `Error: Symbol '<slot>' is already defined` (measured). The failure shape is silent until the first consumer override, because the library's own build defines nothing; a single-variable implementation passes its own CI and breaks in the consumer's hands. If the ZP-defining TU is built by a generic pattern rule, it needs an explicit rule to receive the scoped variable at all (measured in the first adopter implementation, [c64-nist-curves#104](https://github.com/JC-000/c64-nist-curves/pull/104)).

**The scoping rule, stated once (v0.9.1):** a §2 slot define MUST reach **every TU that defines the slot** and MUST NOT reach **any TU that `.importzp`s it**. Everything else follows per-model: import-based libraries (one defining TU — nist-curves) scope `CONTRACT_ZP_DEFINES` to it; include/bake-everywhere libraries (every TU defines via `.ifndef`-guarded includes — polyval, x25519) deliver it globally, where narrowing to one object silently diverges slot addresses between that object and the rest — the mirror image of the `Symbol already defined` failure, measured from both directions in [c64-polyval#34](https://github.com/JC-000/c64-polyval/pull/34) and [c64-x25519#95](https://github.com/JC-000/c64-x25519/pull/95); consumer-assembled libraries (zero archive TUs define — chacha) need no scoped variable at all.

Values MUST be `$`-free — `0x` hex or decimal, per §2's `$`-hex quoting note:

```sh
make lib CONTRACT_ZP_DEFINES='-D fp_src1=0x50'
```

All members of one archive MUST be assembled under the same `CONTRACT_DEFINES` — one configuration per artifact; §6.4 makes the manifest attest to it.

A library MAY instead ship its ZP-defining TU as **consumer-assembled source** rather than an archive member (the `c64-ChaCha20-Poly1305` model): archive TUs `.importzp` every slot, and the consumer assembles the library's `zp_config.s` into their own build, applying slot overrides there. Such a library needs no `CONTRACT_ZP_DEFINES`; its integration doc MUST state where overrides go instead. This model is the recommended shape for new libraries — it is the only one where a slot override requires no library rebuild at all.

### 6.3 Every contemplated configuration is reachable

Every configuration this contract contemplates — each §8.0 ownership state, each deferral combination, each documented variant/profile axis — MUST be reachable through §6.1 targets plus §6.2 defines, with no library edits.

One named convenience target is REQUIRED of every library that consumes any §8.x primitive: `make lib-app-owned`, building `build/lib/<shortname>-app-owned.a` — the `lib` member set assembled with **all** of the library's applicable §8.x deferral switches defined. Which switches a library can defer is library-specific knowledge; the target encapsulates it so a consumer can request §8.0's `APP_OWNED` shape without knowing the switch list. Per §8.0's conditional-mask rule the resulting manifest attests the deferral (`LIB_<X>_SHARED_PRIMITIVES` drops the deferred bits; `LIB_<X>_SHARED_CONSUMES` keeps them).

No further target matrix is required or wanted — finer combinations ride `CONTRACT_DEFINES` on existing targets, and every additional target name enlarges the §6.5 surface #70 must then freeze.

**Scope of that posture (v0.10.4).** It governs *define-reachable* combinations. An axis that changes an archive's **member set** — a profile whose objects differ, not merely their assembly configuration — cannot ride §6.2 defines (a `-D` reconfigures TUs; it cannot add an object to an archive), and member surgery is banned outright (§6.1). So when a *documented* axis is member-set-shaped, this clause's MUST decides it: the axis takes a §6.1 target, carrying its own §6.4 manifest TUs assembled under that configuration and gated on its switches. The frozen §6.5 name is the accepted cost of reachability, not a reason to leave the axis surgery-only. Motivating case: [nist#117](https://github.com/JC-000/c64-nist-curves/issues/117) — the P-256 comb verify set existed only inside the full `lib-onchip` archive, so the library's fastest documented verify configuration was reachable only through staged `rm`-of-members rebuilds consumer-side, and the retained full-set manifest (legitimately describing the pre-surgery archive) forced the consumer to exempt that profile from its §6.6 assert — the clause chain §6.1→§6.4→§6.6 breaking at the first link.

**The looks-reachable failure of the same shape (v0.10.5).** The §6.1 surgery ban catches a consumer editing members; it does not catch a library offering the axis in a form that silently ignores it. Measured ([polyval#40](https://github.com/JC-000/c64-polyval/issues/40)): `POLYVAL_PROFILE` reached every TU's assembly flags while the AEAD archive's member list pinned the LONG multiply object — `make lib POLYVAL_PROFILE=short` exited 0 and shipped an archive simultaneously unlinkable (the pinned member's imports had no exporter among its SHORT-assembled peers) and in violation of §6.4's title rule (its manifest, correctly gated and SHORT-valued, described an archive carrying LONG code — half 1 and half 2 both satisfied per-TU, defeated by member *selection*). Therefore, stated at the archive level: a §6.1 target MUST either honor an axis in **both member selection and assembly configuration**, or reject the combination loudly at build time; an exit-0 build whose member set and assembly configuration disagree about an axis value is non-conformant *even though no target for that combination exists*. A parse-time rejection ([polyval#41](https://github.com/JC-000/c64-polyval/pull/41)'s `$(error)` guard) satisfies this paragraph while leaving ¶1's reachability obligation standing — a guard is the stopgap, the target is the fix. This failure is harder for an adopter to notice than the surgery shape precisely because nothing banned appears anywhere: every command is documented, every exit code is zero, and the artifact is wrong.

There are three shapes on this ladder, and the rule below covers all of them ([contract#117](https://github.com/JC-000/c64-lib-contract/issues/117) discussion): **(1) surgery-only** — the axis is unreachable without editing members; banned by §6.1, adjudicated by the v0.10.4 paragraph (nist#117). **(2) incoherent artifact** — the axis looks reachable, builds clean, ships an archive whose manifest misdescribes it (polyval#40, above). **(3) silent no-op** — the axis looks reachable, builds clean, and ships a *correct* artifact that is not the one requested; the least visible, because nothing downstream is wrong enough to trip an assert (measured in c64-x25519 v0.11.1: `X25519_PROFILE=onchip` is accepted without diagnostic on `make lib` yet reaches only the `lib-verify` expectation machinery — the archive built is the default one). **The rule: a build knob the library itself defines whose name or values denote a variant/profile axis MUST, on every §6.1 target that accepts it, either select that axis — in member selection and assembly configuration both — or reject the invocation loudly. Exit-0 emission of any artifact other than the one the knob requested is non-conformant, whether the artifact is incoherent (2) or merely wrong (3).** Checkability note: verify by comparing **linked output**, never archive bytes and never extracted members — `ca65` stamps a wall-clock `OPT_DATETIME` (seconds granularity) into every object regardless of `-g`, and embeds source paths and mtimes in the object's `Files:` section, so objects and archives differ across time-separated builds and across build paths while being byte-stable within a single second (`ar65` itself concatenates and adds nothing — measured: `touch` every `.o` and re-archive reproduces the archive byte-for-byte). A raw-bytes diff therefore reports a difference on every knob, no-op or not — except when two builds land in the same second, where it reports an identity that "refutes" the rule — and an up-to-date no-rebuild run reports an identity that is really make staleness. Where only archives exist, compare `od65` structural dumps (segments/exports/imports) or the member name list, both timestamp-free. The same applies to the fleet's worktree-rebuild attestation practice: `.o`/`.a` comparisons are unreliable across build paths by construction; linked PRGs carry no toolchain metadata and remain the valid comparand.

**Which consequence the rule carries (v0.11.1).** "Select the axis or reject loudly" leaves the adopter to work out which of the two it owes, and the answer is decided by the distinction the v0.10.4 paragraph above already draws — so this routes an existing taxonomy to a second consequence rather than adding one. **A §6.2 knob value the target cannot honor MUST be rejected at parse time; one it can honor MUST invalidate whatever it reconfigures.** The two branches are not interchangeable and neither subsumes the other:

- **Member-set axis routed through `CONTRACT_DEFINES` → reject.** No `-D` reaches member selection, so the request is unsatisfiable by construction and invalidating the cache would only rebuild the same wrong member set more expensively. Shipped shape: [polyval#56](https://github.com/JC-000/c64-polyval/pull/56)'s parse-time `$(error)` on `POLYVAL_PROFILE` / `POLYVAL_NO_AES`, whose comment names the reason exactly — *a half-built tree is itself the input to the stale shape*.
- **Configuration axis routed through `CONTRACT_DEFINES` → invalidate.** Here the request *is* satisfiable, and is in fact already satisfied from a clean tree, so rejecting it would be wrong. The exposure is that the knobs reach every TU's assembly flags and **no make prerequisite**, so the object cache — keyed on source mtimes — silently survives a knob change and the target ships the previous configuration under a zero exit code. This is not a new obligation: it is the shape-3 rule applied to a warm tree, and it is the same fact the checkability note above records from the auditor's side ("an up-to-date no-rebuild run reports an identity that is really make staleness"), stated here as the adopter's duty. Shipped shape: a stamp of the flattened knob string recorded at parse time, invalidating objects and archives when it changes — `c64-nist-curves` (`CONTRACT_STAMP`, pinned by `tools/check_archives.py`), `c64-ChaCha20-Poly1305` ([chacha#87](https://github.com/JC-000/c64-ChaCha20-Poly1305/pull/87), pinned by `make verify-knob-staleness`), `c64-x25519` ([x25519#110](https://github.com/JC-000/c64-x25519/pull/110), stamped from the **composed** assemble-flag set rather than `CONTRACT_DEFINES` alone, so any deprecated alias the repo still forwards is covered).

Two properties of the invalidation branch are load-bearing, because a guard missing either is worse than none: **unchanged knobs MUST NOT rebuild** — otherwise the guard is an unconditional rebuild wearing a stamp, and same-knob incremental builds are gone — and whatever pins it MUST assert **the artifact flipped**, not merely that something rebuilt. A check with only the first two legs passes on a guard that has quietly become `rm -rf build`.

Worth recording for the next adopter: the knob whose name denotes an axis is not the dangerous one. `c64-ChaCha20-Poly1305` has no `<LIB>_PROFILE` make variable at all — its profile axis rides `CONTRACT_DEFINES` directly — so it satisfied the knob-naming half vacuously and carried shape 3 anyway ([chacha#86](https://github.com/JC-000/c64-ChaCha20-Poly1305/issues/86)); the fleet's parse-time `$(error)` guards on `<LIB>_PROFILE`, which are the right fix for what they cover, would not have touched it. And the knobs whose staleness is *invisible in the artifact* carry more risk than a wrong profile, which is at least loud at link: a stale `LIB_NO_BARE_EXPORTS` is a suppression that silently did not happen, which is exactly the [#43](https://github.com/JC-000/c64-lib-contract/issues/43) collision the mitigation exists to prevent, and a stale `LIB_SHARED_SQTAB_BASE` is a wrong *address* for the §8.1 window.

### 6.4 The manifest describes the archive it ships in

The per-variant rule ([#62](https://github.com/JC-000/c64-lib-contract/issues/62)), stated per-TU with both halves required: every TU contributing §5 or §8.0 manifest equates MUST be

1. **assembled under the same configuration** (defines, profile, variant) as the archive it ships in, and
2. **gated on the same switches** that gate the code and exports it describes.

Half 1 without half 2 is the measured chacha shape — per-variant object directories dutifully assembling byte-identical manifests from an ungated source, the trimmed archive claiming the full build's 16 896 B against a measured 16 513. Half 2 without half 1 is the measured nist shape — one manifest TU per-variant and another not, one archive half-right.

Manifest equate *names* stay per-library (`LIB_<X>_RESIDENT_BYTES`); variant identity lives in which archive the TU ships in, never in the name. Variant-mangled equate names (`LIB_<X>_<VARIANT>_RESIDENT_BYTES`) are deprecated: any existing ones stay exported until that library's next MAJOR, valued equal to the canonical equate inside the variant's own archives.

### 6.5 The consumer-facing name surface

The following are contract surface, subject to §7 semver and the rename window below: exported symbols and their `LIB_<X>_` families; §2 ZP slot names (registry in §2); §4 segment names; archive basenames (§6.1); **archive member basenames**; make target names (§6.1); the §6.2 variables and every define family they forward.

Archive member basenames are a flat namespace under `ar65` composition and extraction tooling — today `lib_version.o` and `lib_manifest.o` ship unprefixed in four adopters, `zp_config.o` in three. At each library's next MAJOR, member basenames MUST take the `<shortname>_` prefix (`x25519_lib_version.o`). Members cannot carry two names at once, which is why this rides MAJOR rather than a window.

**A library onboarding with no released consumers SHOULD be born prefixed (v0.11.0).** The MAJOR deferral above is a concession to installed base, not a judgement that unprefixed members are acceptable: an established library cannot rename a member without breaking whoever extracts it, so it waits. A library that nobody has linked yet pays none of that cost, and there is no reason for it to join a namespace pile-up it would immediately begin waiting to leave. The window exists to be escaped; a new adopter should simply start on the far side of it.

Scope: "no released consumers" means no tagged release that any consumer pins, which is checkable from the library's own tags and this repo's `consumers.md` rather than being a matter of assertion. A library that has cut a release someone links falls back to the MAJOR rule. `c64-mlkem` is the first library to take this path — it ships `mlkem_lib_version.o` / `mlkem_lib_manifest.o` from its first archive — which is why the count above is four rather than five.

**Rename window (the [#70](https://github.com/JC-000/c64-lib-contract/issues/70) rule).** Any rename of a surface element MUST ship both names for at least one MINOR release, the old form documented as deprecated, before removal at the next MAJOR (or v1.0, whichever comes first). Elements that cannot dual-name (archive members) change only at MAJOR.

**Deprecated-spelling override behavior (v0.10.0).** Two alias shapes shipped in the ZP wave, and **both are window-conformant because both fail loudly**; the trade is recorded so the next rename picks deliberately. *Compatible shape* (`c64-ChaCha20-Poly1305`): the bare name keeps an `.ifndef` guard, so a legacy `-D zp_tmp1=…` still works and moves the canonical slot — but both spellings are independently definable, so a build that defines them divergently could split one slot across two addresses; safe only while nothing does. *Loud-break shape* (`c64-nist-curves`): the bare name is an unguarded alias of the canonical (`zp_tmp1 = nistcurves_zp_tmp1`), so a legacy `-D` of the bare spelling dies at assemble time with `Symbol already defined` — the old override interface breaks, but divergence is structurally impossible. What is **not** conformant is any shape whose failure mode is silent: one slot at two addresses with no diagnostic is the forbidden outcome, in either direction. Consumer-facing rule of thumb from the wave: consumers that assemble the library's own ZP TU are untouched by either shape; consumers that supply slots from their own source must move to canonical spellings (the [c64-wireguard#52](https://github.com/JC-000/c64-wireguard/issues/52) case).

**Suppression gate for colliding old forms ([#88](https://github.com/JC-000/c64-lib-contract/issues/88), v0.9.1).** When the old form is itself a cross-library collision — the #83 ZP names being the motivating case — an ungated dual-name preserves the defect for the whole window: a composed link is no better off the day the window opens than the day before, and §2's registry migration would be blocked by the very rule that schedules it. Therefore: **a dual-named old form that collides across libraries MUST sit behind a consumer-settable suppression define, and the canonical gate for bare-name cases is the existing `LIB_NO_BARE_EXPORTS`** (the §1 precedent — composing consumers already build every library with it, so composed links are collision-free from the day the window opens, while single-library consumers keep the old names untouched).

### 6.6 Consumer footprint asserts (v0.10.0)

**Failure mode this prevents.** A MINOR library bump grows resident code or rodata and the consumer's memory region overflows at link time, with no advance signal that the bump was a spatial event ([#69](https://github.com/JC-000/c64-lib-contract/issues/69), measured twice in `c64-https`: a +512 B validation gate against ~1 byte of region slack, bisected across three tags to find). The ld65 error is loud but late; this clause makes spatial safety checkable *before* a bump, from the manifest alone.

**Why this clause could not exist before v0.9.0.** The assert binds a consumer budget to `LIB_<X>_RESIDENT_BYTES`/`LIB_<X>_COLD_BYTES` — and until §6.4, those described the *library*, not the linked archive. The measured consequence of skipping that gate: `LIB_NISTCURVES_RESIDENT_BYTES` reported 27–28 KB against a 16 KB region for a minimal-variant link that in fact builds and passes its full KAT suite — the assert would have refused a working configuration. §6.4 is now verified in every adopter's shipped archives, so the numbers describe what is linked, and the gate (#62-before-#69, held from both sides) is discharged.

**Library obligations.**
1. Footprint equates are per-archive (§6.4) and **safe-direction**: each value MUST be ≥ the measured segment sum for that archive, rounded UP (the fleet convention is the next 256-byte boundary — headroom under one page, so incidental growth is absorbed without forcing consumer `.assert` rewrites, and the equate moving is itself the signal that a re-look is due).
2. `RESIDENT_BYTES` and `COLD_BYTES` are a **pair**: `COLD` is reclaimable-after-init and may legitimately live in a different consumer budget. Release notes MUST state footprint deltas **per (profile × variant)** — a single per-version delta is meaningless when one tag carries several footprint pairs (measured: `c64-x25519` v0.8.0 defined three, selected by profile).

**Consumer pattern** (RECOMMENDED for every linked archive; `lderror` because the operands are imports, §1's guard rule; the area publishes its extent via `define = yes`):

```asm
; consumer side — one per linked archive, in the consumer's own build
.import LIB_NISTCURVES_RESIDENT_BYTES
.import LIB_NISTCURVES_COLD_BYTES
.import __MAIN_SIZE__                  ; cfg: MAIN: ... define = yes;
.assert LIB_NISTCURVES_RESIDENT_BYTES + LIB_NISTCURVES_COLD_BYTES <= __MAIN_SIZE__, lderror, "nistcurves declared footprint exceeds the MAIN budget"
```

Consumers with split budgets assert the pair separately against the regions that hold them. Because the declared value is safe-direction, `declared ≤ budget` implies `actual ≤ budget`; a bump that moves the declared number past the budget fails the link with a named cause instead of an opaque segment-overflow discovered mid-bisect.

### 6.7 Declared non-segment reservations (v0.10.0)

**Failure mode this prevents.** A placement *equate* (not a segment) reserves address space — §8.1's `sqtab` window, §8.2's staging buffers — and **ld65 does not know the region exists**: a memory area spanning the window will happily place growing segments across it, link clean, and corrupt the table at runtime with no diagnostic at any stage ([#78](https://github.com/JC-000/c64-lib-contract/issues/78) item 2; it happened at the previous sqtab base and cost a debugging session). This is the inverse of §6.6's failure: there, the region is declared and the error late-but-loud; here the region is undeclared and there is no error at all. The equate form is *forced* by §8.x — it exists so independently-built adopters agree on one address via `-D` — so the seam between the clause that creates the invisible region and the clause that governs placement is closed here.

**Rule 1 — prefer a segment when nothing forces the equate.** If a single build owns the table (no cross-library placement agreement in play), place it as a segment-resident `.res` buffer: ld65 then enforces non-overlap natively and no guard is needed. The equate form, the declaration, and the assert below exist for the §8.x shared case only.

**Rule 2 — the library guards its own image.** Every library placing an equate-reserved region MUST carry, in a TU that ships in **no** archive (its standalone test/bench driver is the natural home), the three-line guard:

```
# cfg — the memory area publishes its extent
MAIN: file = %O, start = %S, size = $D000 - %S, define = yes;
```

```asm
; a TU no archive contains
.import __MAIN_LAST__
.assert __MAIN_LAST__ <= LIB_SHARED_SQTAB_BASE, lderror, "image overruns the sqtab window (LIB_SHARED_SQTAB_BASE)"
```

**Where the guard gets the base (v0.10.2, correcting v0.10.0):** the equate is obtained **source-level** — the guard TU includes the same `.ifndef`-guarded header the placing TU uses — **never by `.import`**, which §8.1's export discipline forecloses (measured: `.import LIB_SHARED_SQTAB_BASE` fails as an unresolved external, exactly as §8.1 implies; the v0.10.0 prose here said "imported equate", a contradiction carried from before the v0.9.1 canonical-≠-exported ruling — [#105](https://github.com/JC-000/c64-lib-contract/issues/105)). The `.ifndef` is what preserves relocation: `-D` defines the symbol for the whole assembly, so the placing TU and the guard see the same override and move together (re-measured for this correction: a relocated base inside the image fires the guard; outside, it passes). **The default MUST live in exactly one shared include** — two independent copies of the `.ifndef` default can silently disagree, and the guard then checks a different window than the table occupies: trustworthy, not merely present, requires single-source.

Measured properties (ld65 V2.18, from the [#78 item-2 verification](https://github.com/JC-000/c64-lib-contract/issues/78) and re-verified for this clause): `__MAIN_LAST__` is the first address past the last byte actually *placed*, including the `rw`/`bss` tail — not the area end (the name suggests otherwise; it was checked, not assumed). The boundary is exact to the byte where the primitive's own rules allow it to be observed — a primitive whose base must be page-aligned (§8.1) bounds the observable granularity to the page, since a non-aligned probe fails the alignment assert first ([chacha's §6.7 adoption](https://github.com/JC-000/c64-ChaCha20-Poly1305/pull/81) measured page-exact: last byte `$4D27`, base `$4E00` passes, `$4D00` fires). The guard is free: `define = yes` only publishes symbols, `.assert` emits no code, and the PRG is byte-identical with and without it.

**Two constraints that are part of the rule, not advice:**
1. **The guard TU MUST NOT ship in any archive** — an `.import __MAIN_LAST__` inside an archive member would force every consumer to name a memory area `MAIN` with `define = yes` or eat an unresolved external. The guard therefore protects the *library's own image only*; a consumer authors their own memory map, so consumers SHOULD mirror the same assert against their own `__<AREA>_LAST__` for every equate-placed reservation of every library they link.
2. **The import MUST NOT be weak or optional.** An `lderror` assert whose operand is missing degrades to `Warning: Cannot evaluate assertion` — a silent no-op. The pattern is safe only because the unresolved external is itself a hard link error; weaken the import and the guard silently stops guarding.
3. **Prove the guard fires in the configuration that actually places the table (v0.10.2).** A profile-gated guard in a build whose profile emits no table is *correctly skipped* — a firing test against that build passes and has verified nothing. Second silent-no-op mode, different mechanism from constraint 2, same outcome; measured during [chacha's adoption](https://github.com/JC-000/c64-lib-contract/issues/105), whose first firing test "passed" against the profile that places nothing. The acceptance test for adopting this clause is a deliberate overrun that *fires*, in the placing configuration.

**Verified scope.** The `__*_LAST__` behavior above is measured on ld65 V2.18 with a single file-emitting memory area whose top segment is `bss`. Load/run splits, multiple areas, and overlays are unverified — an adopter with those shapes MUST re-measure before relying on the guard, and should report the result to this clause.

## 7. Semver expectations

- **MAJOR** — bumped on any breaking change to the exported surface (removed/renamed symbols, changed calling conventions, changed memory model, changed semver of a manifest equate).
- **MINOR** — bumped on additive changes (new symbols, new build targets, new manifest equates, new variants).
- **PATCH** — bug fix only, no ABI surface change.
- **`LIB_<X>_ABI_VERSION`** is **not** derived from MAJOR. It is an independent generation counter for the exported surface, starting at 1 and incremented on any breaking export change (§1). The consumer-side gate `.assert LIB_<X>_ABI_VERSION = <expected>, lderror, "..."` is the load-bearing breakage check — `.assert`/`lderror`, never `.if`/`.error`, for the reason §1's guard rule states: the operand is an import with no value until link, and `.if` on it fails with `Constant expression expected` (this bullet carried the broken `.if` form from v0.7.5 until [#107](https://github.com/JC-000/c64-lib-contract/issues/107); v0.8.1 fixed §1's snippets and missed this restatement). It is load-bearing *because* of the next paragraph: pre-1.0 breakage rides MINOR bumps, so MAJOR cannot carry the signal.

While the contract is in v0.x (pre-1.0), breaking changes happen freely with MINOR bumps. Once v1.0 ships, breaking changes go through a one-MINOR-release deprecation cycle.

## 8. Shared primitives

Some primitives are reimplemented identically across multiple sibling libraries. When a consumer links several of those libraries into the same PRG, each one defines its own copy of the table at its own address, wasting resident RAM and boot cycles, and — more importantly — making the placement decision per-library rather than per-consumer. This section names primitives where the duplication has been confirmed across at least two adopters, fixes the *shape* every implementation must agree on, and leaves the *address* to the consumer via the `-D` override mechanism already established in §2 and §3.

A primitive listed here is opt-in per library: an adopter MAY continue to ship its own private copy until it migrates. Once migrated, the library reflects ownership of the primitive in its `LIB_<X>_SHARED_PRIMITIVES` bitmask manifest equate (§5) — *conditionally*, so a build that defers the primitive to a canonical provider drops the bit (§8.0) — letting consumers detect double-ownership at assemble time.

### 8.0 Bit allocation for `LIB_<X>_SHARED_PRIMITIVES`

Each §8.x sub-clause declares one bit constant of the form `LIB_SHARED_PRIMITIVES_<NAME>`. Bits are append-only and never reused: a primitive that is later deprecated keeps its bit reserved so old consumer cfgs that `.assert` on the bit continue to parse against newer SPEC revisions. New §8.x sub-clauses allocate the next free bit and update the table below.

| Bit | Constant | Primitive | Defined in |
|---|---|---|---|
| `$0001` | `LIB_SHARED_PRIMITIVES_SQTAB` | 8×8 quarter-square multiply table | §8.1 |
| `$0002` | `LIB_SHARED_PRIMITIVES_REU_MUL` | 8×8→16 REU multiplication table (128 KB bank pair) | §8.2 |
| `$0004` | `LIB_SHARED_PRIMITIVES_CT_MUL_8X8` | constant-time 8×8→16 multiply body | §8.3 |

**Definition site (normative).** The bit constants above are plain assemble-time equates and **MUST NOT** be `.export`ed. Each adopter copies the block verbatim into its own source — exactly as §13.0's `NET_FAMILY_*` constants are copied — and `.ifndef`-guards them so a consumer may define them globally without a redefinition error:

```asm
.ifndef LIB_SHARED_PRIMITIVES_SQTAB
  LIB_SHARED_PRIMITIVES_SQTAB      = $0001
.endif
.ifndef LIB_SHARED_PRIMITIVES_REU_MUL
  LIB_SHARED_PRIMITIVES_REU_MUL    = $0002
.endif
.ifndef LIB_SHARED_PRIMITIVES_CT_MUL_8X8
  LIB_SHARED_PRIMITIVES_CT_MUL_8X8 = $0004
.endif
```

Both sides of the link carry the values, and only exported symbols can collide. The per-library `LIB_<X>_SHARED_PRIMITIVES` and `LIB_<X>_SHARED_CONSUMES` masks are this clause's **sole** exports; they carry the library prefix and therefore cannot collide.

An adopter that exports the bit constants reintroduces the [#43](https://github.com/JC-000/c64-lib-contract/issues/43) collision on a family the v0.7.0 prefixed forms do not cover — two libraries exporting `LIB_SHARED_PRIMITIVES_SQTAB` at the same value still fail the link:

```
ld65: Error: Duplicate external identifier: 'LIB_SHARED_PRIMITIVES_SQTAB'
```

ld65 rejects duplicate externals regardless of whether the values agree, and it halts at the first one, so a consumer sees a single name rather than the full set. This is stated against its opposite because the failure is invisible to the adopter — a library exporting these builds and tests cleanly standalone, and only a *composed consumer* ever sees the error.

**Consumer-side composition.** Each adopter's `LIB_<X>_SHARED_PRIMITIVES` mask reflects the primitives it **owns in this build configuration**: a primitive's bit is included **iff this build does NOT defer that primitive** via its per-primitive migration switch (the `SHARED_*` / `SHARED_*_INIT` define from the primitive's §8.x clause). A library that defers a shared primitive to a canonical provider (built with that switch defined) drops the corresponding bit, so two libraries linked into the same PRG that share a primitive end up with **disjoint** masks — exactly one keeps the bit. A consumer then asserts disjointness:

```asm
.import LIB_NISTCURVES_SHARED_PRIMITIVES
.import LIB_CHACHA20_POLY1305_SHARED_PRIMITIVES
.assert (LIB_NISTCURVES_SHARED_PRIMITIVES & LIB_CHACHA20_POLY1305_SHARED_PRIMITIVES) = 0, error, "shared-primitive double-ownership — exactly one provider must own each shared primitive; the other(s) must build with that primitive's SHARED_* switch defined"
```

**Per-primitive deferral-switch mapping** (the define that, when present, zeroes the bit):

| Bit | Constant | Deferral switch |
|---|---|---|
| `$0001` | `LIB_SHARED_PRIMITIVES_SQTAB` | `SHARED_SQTAB_INIT` |
| `$0002` | `LIB_SHARED_PRIMITIVES_REU_MUL` | `SHARED_REU_MUL_INIT` |
| `$0004` | `LIB_SHARED_PRIMITIVES_CT_MUL_8X8` | `SHARED_CT_MUL_8X8` |

**Mask construction (required form).** Each adopter MUST build its mask so a defined switch drops the bit — do **not** OR the bit constants unconditionally. An unconditional mask makes the disjointness assert above unsatisfiable for any legitimately-shared primitive (two sharers both keep the bit), the defect fixed in v0.4.0 (see [#21](https://github.com/JC-000/c64-lib-contract/issues/21)):

```asm
.ifdef SHARED_SQTAB_INIT
  _OWN_SQTAB   = 0
.else
  _OWN_SQTAB   = LIB_SHARED_PRIMITIVES_SQTAB
.endif
.ifdef SHARED_CT_MUL_8X8
  _OWN_CT_MUL  = 0
.else
  _OWN_CT_MUL  = LIB_SHARED_PRIMITIVES_CT_MUL_8X8
.endif
; ... one .ifdef/.else block per primitive THIS library consumes ...
LIB_<X>_SHARED_PRIMITIVES = _OWN_SQTAB | _OWN_CT_MUL    ; OR only the primitives this lib uses
```

The bit therefore means "owned in this build config": a standalone build (no switches defined) claims every primitive it consumes; an integrated build defers the shared ones it does not provide, and its bits drop out so the consumer disjointness assert holds.

**Build-config states (normative, v0.5.0).** For each §8.x primitive, a given build configuration of an adopter is in exactly one of three states. A clear ownership bit alone does not distinguish the last two — and they impose opposite obligations on the composed consumer (see [#44](https://github.com/JC-000/c64-lib-contract/issues/44); the demonstrator is c64-x25519 v0.8.0, whose `SHARED_REU_MUL_INIT` deferral build and `X25519_ONCHIP_MUL` profile build both export `LIB_X25519_SHARED_PRIMITIVES = $0005` while requiring a §8.2 provider in the link and no provider at all, respectively):

| State | `SHARED_PRIMITIVES` bit | `SHARED_CONSUMES` bit | Obligations |
|---|---|---|---|
| **owner** | set | set | Exports the primitive's init/body per its §8.x clause. |
| **deferring consumer** | clear | set | The primitive's deferral switch is defined. The build still reads the primitive at runtime: it retains the primitive's consumption surface (placement equates, aggregate claims such as §3 REU banks), the composed link MUST contain exactly one owner, and boot MUST initialize the primitive before first use. |
| **non-consumer** (profile-gated or permanent) | clear | clear | The primitive's placement/precalc export surface is absent, no aggregate claim is made, and there is no provider obligation. |

**Companion mask `LIB_<X>_SHARED_CONSUMES` (required, v0.5.0).** Each adopter that consumes any §8 primitive MUST also export `LIB_<X>_SHARED_CONSUMES`: bit set **iff this build configuration consumes the primitive at all** — a deferral switch does NOT clear it; only profile-gated or permanent non-consumption does. Invariant: ownership bits are a subset of consumes bits, which each adopter pins at assemble time:

```asm
.assert (LIB_<X>_SHARED_PRIMITIVES & ~LIB_<X>_SHARED_CONSUMES) = 0, error, "a build cannot own a primitive it does not consume"
```

For the purposes of both masks, **exporting a primitive's canonical body or init per its §8.x clause counts as consuming it, even when no runtime path in that build config invokes it**: the body is present, callable, and available for a co-linked sibling to defer to, so the ownership bit stays set and the consumes bit follows from the subset invariant. (Concrete case: a `FP_ONCHIP_MUL` build of c64-nist-curves ships the §8.3 `ct_mul_8x8` body and claims `$0004` although its onchip row generator never calls it at runtime — that build declares ct_mul_8x8 consumed. Do NOT resolve this case by dropping the ownership bit; a sibling's deferral may depend on it.)

The consumes mask is derived from the same switches that already drive the conditional ownership mask — the profile/config gates drop bits from both masks, while the `SHARED_*` deferral switches drop bits from the ownership mask only:

```asm
.ifdef X25519_ONCHIP_MUL         ; profile gate: drops the bit from BOTH masks
  _USE_REU_MUL = 0
.else
  _USE_REU_MUL = LIB_SHARED_PRIMITIVES_REU_MUL
.endif
; ... one gate per primitive whose consumption is build-config-conditional ...
LIB_<X>_SHARED_CONSUMES = LIB_SHARED_PRIMITIVES_SQTAB | _USE_REU_MUL | LIB_SHARED_PRIMITIVES_CT_MUL_8X8
```

The consumer-side composition story then completes with a coverage assert alongside the existing disjointness assert — every consumed primitive has exactly one owner somewhere in the link:

```asm
; existing (v0.4.0): no double ownership
.assert (LIB_A_SHARED_PRIMITIVES & LIB_B_SHARED_PRIMITIVES) = 0, error, "shared-primitive double-ownership"
; new (v0.5.0): no consumed primitive without an owner
.assert ((LIB_A_SHARED_CONSUMES | LIB_B_SHARED_CONSUMES) & ~(LIB_A_SHARED_PRIMITIVES | LIB_B_SHARED_PRIMITIVES)) = 0, error, "consumed shared primitive with no owner in the link — exactly one library must be built without that primitive's SHARED_* switch"
```

A consumer application MAY itself provide a shared primitive from its own modules — the original design intent of the `SHARED_*` deferral switches (§8.1: "a future consumer can replace it with the canonical `mul_tables_init` from a shared-primitives module"). In that configuration every linked library legitimately defers; the consumer then ORs its own contribution into the owner union so the coverage assert composes:

```asm
APP_OWNED = LIB_SHARED_PRIMITIVES_SQTAB   ; primitives provided by the consumer's own modules
.assert ((LIB_A_SHARED_CONSUMES | LIB_B_SHARED_CONSUMES) & ~(LIB_A_SHARED_PRIMITIVES | LIB_B_SHARED_PRIMITIVES | APP_OWNED)) = 0, error, "consumed shared primitive with no owner in the link"
```

Without the coverage assert, the missing-provider failure mode is an ld65 unresolved external at best (when the deferring library imports the canonical entry point) and a silent wrong-result at worst (table read with no init); with it, the failure is a named assemble-time error. *Link-time note (v0.7.0):* importing manifest equates from two libraries used to collide on the unprefixed §1/§8.4 symbols ([#43](https://github.com/JC-000/c64-lib-contract/issues/43)). Adopters that have shipped the v0.7.0 prefixed forms compose directly: build every library with `ca65 -D LIB_NO_BARE_EXPORTS=1` and import the `LIB_<X>_*` equates from each. Against a library still on the bare-only forms, the §8.4 `od65 --dump-exports` out-of-band pattern remains the fallback for that library — noting that `od65` reads objects, not archives, so a consumer holding only that library's shipped `.a` extracts its members first (§8.0, "Auditing a shipped archive").

### 8.4 Precalc-table enumeration — the catch loop (heading added v0.10.3)

> Numbering and provenance note: the fleet has cited this clause as **§8.4** since v0.7.0 (13 references in this document, 70+ per adopter repo, and one inside the canonical macro source itself) — but the heading never existed: the clause lived as an unnumbered block inside §8.0, which every citation survived on faith. [#109](https://github.com/JC-000/c64-lib-contract/issues/109) caught it. This heading makes the fleet's number real; it sits here, inside the §8.0 flow it grew out of, because numbers are stable identifiers, not positions (§0). Older prose and the canonical `precalc_table.inc` header comment say "§8.0 catch-loop" — same clause, historical spelling.

A primitive becomes a §8.x candidate only after duplication is confirmed across two or more adopters. The first two §8.x clauses (`sqtab`, `reu_mul`) were both found by ad-hoc audit after the duplication had been in place for one or more releases. To make detection systematic rather than reactive, every adopter MUST enumerate its precalculated tables in a consumer-readable form at intake (per [adopters.md](adopters.md) "How to add your library" step 6).

**Floor.** Enumeration is mandatory for any precalculated table that meets *both* of the following:

- size **≥ 256 B**, AND
- one of: REU-resident, hot-loop-read (touched in a per-byte or per-row inner loop), or page-aligned for fetch-alignment reasons.

Tables below this floor (ChaCha20 quarter-round constants, mod-n reduction one-off scratch, small rotation lookup tables, etc.) are exempt — they are correctly never §8.x-eligible and listing them dilutes the catalog.

**Two-form enumeration.** Each enumerated table is recorded in *both* of the following forms:

1. **Doc-level** in `docs/precalc-tables.md` (or equivalent path linked from the adopter's `adopters.md` row): name, size, region, source file, classification (curve-/algorithm-specific *or* potentially shareable), and the rationale for the classification. The rationale is the load-bearing field — writing it down forces the maintainer to think through whether a sibling library might converge on the same shape.
2. **Assembler-level** via the `LIB_PRECALC_TABLE` macro (canonical source below). The macro emits three exported equates per invocation that survive doc rot and make build-time audits mechanical: `grep -r '_PRECALC_' src/` adopter-local, `od65 --dump-exports build/lib.o | grep _PRECALC_` post-build. (Audit on `_PRECALC_`, not `LIB_PRECALC_`: as of v0.7.0 the macro also emits the library-prefixed `LIB_<X>_PRECALC_<name>_*` form, which the older pattern would miss.) (cc65 toolchain; `od65` is the cc65 object-file inspector. It reads single ca65 `.o` files **only** — pointed at an `.a` archive it prints `<name>: (no xo65 object file)` and exits `0`, so a script that greps its output sees no symbols and silently reports a false negative rather than an error. To audit an archive, extract its members first — see "Auditing a shipped archive" below.)

Both forms are required. The doc captures shape and rationale; the macro captures size, region, and sharing as build-time data. An asymmetry between the two (a `LIB_PRECALC_*` export with no `docs/precalc-tables.md` row, or vice versa) blocks the adopter PR per the intake-reviewer-MUST rule in `adopters.md`.

**Canonical `precalc_table.inc`.** The byte-for-byte canonical source lives at [`precalc_table.inc`](precalc_table.inc) in this repo's root and is smoke-tested under [`examples/precalc_table_smoke.s`](examples/precalc_table_smoke.s) via `make verify`. Adopters copy that file verbatim into one `src/precalc_table.inc` file and `.include` it from a single translation unit. Updates land via coordinated cross-repo PR; do not edit local copies. The fenced block below is shown for reading; do not retype from it — copy the file.

```ca65
; precalc_table.inc — canonical per c64-lib-contract SPEC §8.0 catch-loop.
;
; CANONICAL SOURCE. The fenced code block in SPEC.md §8.0 is shown for
; readability; this file is the byte-for-byte source adopters copy into
; their own src/precalc_table.inc. Updates land via coordinated cross-repo
; PR; do not edit your local copy.
;
; Smoke-tested in examples/precalc_table_smoke.s and exercised by `make verify`
; at this repo's root.

.ifndef PRECALC_TABLE_INC_INCLUDED
PRECALC_TABLE_INC_INCLUDED = 1

PRECALC_REGION_RAM     = $01
PRECALC_REGION_REU     = $02
PRECALC_REGION_RODATA  = $03

PRECALC_SHARED_NO      = $00
PRECALC_SHARED_YES     = $01

; LIB_PRECALC_TABLE "name", size_bytes, region, shared [, "LIB"]
;
;   "name":       quoted string literal (becomes the symbol suffix;
;                 use lower_snake_case, no leading digit)
;   size_bytes:   total bytes claimed by the table
;   region:       PRECALC_REGION_RAM | _REU | _RODATA
;   shared:       PRECALC_SHARED_YES | PRECALC_SHARED_NO
;   "LIB":        quoted library prefix, UPPER_SNAKE_CASE, matching the
;                 <X> in this library's §5 LIB_<X>_* manifest equates
;                 (e.g. "X25519", "CHACHA20_POLY1305"). Required as of
;                 SPEC v0.7.0; omitted only by pre-v0.7.0 adopters that
;                 have not yet migrated.
;
; Emits, per invocation:
;
;   LIB_<LIB>_PRECALC_<name>_{SIZE,REGION,SHARED}   (when "LIB" is given)
;   LIB_PRECALC_<name>_{SIZE,REGION,SHARED}         (unless suppressed)
;
; The prefixed form is collision-free across libraries, so a consumer
; linking two libraries can .import both manifests and cross-check that
; they agree on a shared table's shape (SPEC #43). The bare form is
; DEPRECATED — it is the form that collides — and is scheduled for
; removal at contract v1.0.
;
; Define LIB_NO_BARE_EXPORTS (ca65 -D LIB_NO_BARE_EXPORTS=1) to suppress
; the deprecated bare form. A consumer composing two or more libraries
; that describe the same shared table MUST build them all with this
; define; otherwise ld65 rejects the link with
;   Duplicate external identifier: 'LIB_PRECALC_<name>_SHARED'
; Single-library consumers need not define it, and adopters assembling
; standalone keep the bare exports by default.
;
; The macro preserves the case of the `name` argument verbatim (ca65 has
; no built-in toupper), so `LIB_PRECALC_TABLE "sqtab", ...` emits the
; symbols in their lower-case form. The normative §8.x canonical names
; use lower_snake_case throughout, so cross-adopter audits grep on a
; single case convention — and on `_PRECALC_`, which matches both the
; prefixed and bare forms.
;
; SIZE is exported without an address-size hint so values > 16 bits
; (e.g. the 131072-byte REU mul table) export cleanly as 'far'
; without a "far but exported absolute" warning — its address size is
; value-dependent by design (absolute at 1024, far at 131072).
;
; REGION and SHARED are pinned ': abs' instead. They can never exceed a
; byte, so ca65 would infer 'zeropage' for them in every adopter, while
; a consumer's .import defaults to absolute — which makes the §8.4
; cross-check snippet emit an "Address size mismatch" warning on every
; composed build. The link succeeds and the asserts evaluate correctly,
; but the natural consumer reaction is to write '.import ... : zeropage',
; pinning a manifest constant to an address size that is an artifact of
; its current value rather than a property of the symbol.

.macro LIB_PRECALC_TABLE name, size_bytes, region, shared, lib
    .ifndef LIB_NO_BARE_EXPORTS
        .ident (.sprintf("LIB_PRECALC_%s_SIZE",   name)) = size_bytes
        .ident (.sprintf("LIB_PRECALC_%s_REGION", name)) = region
        .ident (.sprintf("LIB_PRECALC_%s_SHARED", name)) = shared

        .export .ident (.sprintf("LIB_PRECALC_%s_SIZE",   name))
        .export .ident (.sprintf("LIB_PRECALC_%s_REGION", name)): abs
        .export .ident (.sprintf("LIB_PRECALC_%s_SHARED", name)): abs
    .endif

    .if .not .blank (lib)
        .ident (.sprintf("LIB_%s_PRECALC_%s_SIZE",   lib, name)) = size_bytes
        .ident (.sprintf("LIB_%s_PRECALC_%s_REGION", lib, name)) = region
        .ident (.sprintf("LIB_%s_PRECALC_%s_SHARED", lib, name)) = shared

        .export .ident (.sprintf("LIB_%s_PRECALC_%s_SIZE",   lib, name))
        .export .ident (.sprintf("LIB_%s_PRECALC_%s_REGION", lib, name)): abs
        .export .ident (.sprintf("LIB_%s_PRECALC_%s_SHARED", lib, name)): abs
    .else
        .ifdef LIB_NO_BARE_EXPORTS
            .error "LIB_PRECALC_TABLE: LIB_NO_BARE_EXPORTS suppresses the bare exports, so the lib-prefix argument is required — this invocation would emit nothing"
        .endif
    .endif
.endmacro

.endif ; PRECALC_TABLE_INC_INCLUDED
```

**Example invocation** (illustrative — a curve library that consumes both §8.1 and §8.2 plus two library-private tables):

```ca65
.include "precalc_table.inc"

LIB_PRECALC_TABLE "sqtab",        1024,   PRECALC_REGION_RAM,    PRECALC_SHARED_YES, "NISTCURVES"
LIB_PRECALC_TABLE "reu_mul",      131072, PRECALC_REGION_REU,    PRECALC_SHARED_YES, "NISTCURVES"
LIB_PRECALC_TABLE "lim_lee_comb", 24576,  PRECALC_REGION_REU,    PRECALC_SHARED_NO,  "NISTCURVES"
LIB_PRECALC_TABLE "sha384_k",     640,    PRECALC_REGION_RODATA, PRECALC_SHARED_NO,  "NISTCURVES"
```

The fifth argument is the library prefix (§1/§5 `<X>`), **required as of v0.7.0**. It is what makes the emitted equates collision-free: the same `"sqtab"` invocation in two libraries yields `LIB_NISTCURVES_PRECALC_sqtab_SIZE` and `LIB_X25519_PRECALC_sqtab_SIZE`, which a consumer can import together. The table *name* stays unprefixed and normative (see the §8.1/§8.2 back-links below) — the prefix distinguishes the *declaring library*, never the table.

**Consumer-side composition** (optional, for the consumer that wants to cross-check a composed library's shape). The canonical cross-check reads the exported equates out of the post-build object via `od65 --dump-exports` — the same tool §8.0 already uses for the adopter-intake audit above — and greps for the `_PRECALC_<name>_*` symbol family:

```sh
od65 --dump-exports build/*.o | grep _PRECALC_reu_mul
```

This reports `LIB_<X>_PRECALC_reu_mul_SIZE`, `_REGION`, and `_SHARED` — plus the deprecated bare `LIB_PRECALC_reu_mul_*` triple while it is still emitted — with their exported values for any table size, including the 128 KB `reu_mul` and the 192 KB `reu_mul_doubled`. A consumer build script asserts the values it expects (`_SHARED = 1`, `_SIZE = 131072`) against this dump.

Note the glob: **objects, not archives.** `build/*.o` is normative here — `od65` cannot read a `.a`, and against one it produces empty output with exit `0`, which a grep-based check cannot distinguish from "this library declares no such table."

**Auditing a shipped archive.** A consumer holding only a distributed `.a` — the §6 minimal-archive build target, and exactly the case the out-of-band fallback in the §8.0 coverage-assert note points at — must resolve it to object files first. `ar65` enumerates and extracts members, so this needs no knowledge of the library's build layout:

```sh
mkdir -p /tmp/audit && cd /tmp/audit
for m in $(ar65 t /path/to/lib.a); do ar65 x /path/to/lib.a "$m"; done
od65 --dump-exports *.o | grep _PRECALC_
```

`ar65 t` lists the member names; `ar65 x` takes them explicitly (it extracts nothing when given an archive alone). An audit script SHOULD assert that the extraction produced at least one `.o`, so an empty or unreadable archive fails loudly instead of dropping through to a silent zero-match.

> **Address-size limit (normative).** On the ca65 6502 target an *assemble-time* cross-check that `.import`s `LIB_PRECALC_<name>_SIZE` into a second translation unit and `.assert`s on it only works for tables **≤ 65 535 B**. ca65's `.import` accepts only the `: zp` (8-bit) and `: abs` (16-bit) address-size hints — there is no `: far` (24-bit) form — so importing the `_SIZE` of a larger table (e.g. `reu_mul` = 131072 B) raises `Range error (131072 not in [-32768..65535])` at the consumer. The producer-side `.export LIB_PRECALC_<name>_SIZE` equate is unaffected (ca65 `.export` accepts an absolute value of any width up to 32 bits — see the macro note in `precalc_table.inc`); only the *consuming* `.import` is constrained. For tables that fit, the assemble-time form is available:
>
> ```asm
> ; Assemble-time cross-check — VALID ONLY for tables ≤ 65 535 B.
> ; For larger tables (reu_mul, reu_mul_doubled) use the od65 dump above.
> .import LIB_X25519_PRECALC_sqtab_SHARED
> .import LIB_X25519_PRECALC_sqtab_SIZE
> .assert LIB_X25519_PRECALC_sqtab_SHARED = PRECALC_SHARED_YES, error, "if this lib reports sqtab, it MUST claim sharing"
> .assert LIB_X25519_PRECALC_sqtab_SIZE   = 1024,               error, "sqtab size mismatch — bit-identical shape required for §8.1"
> 
> ; Two-library agreement check — the cross-check the bare form could never
> ; express, because both libraries emitted the same symbol name (#43).
> .import LIB_CHACHA20_POLY1305_PRECALC_sqtab_SIZE
> .assert LIB_X25519_PRECALC_sqtab_SIZE = LIB_CHACHA20_POLY1305_PRECALC_sqtab_SIZE, error, "linked libraries disagree on the shared sqtab size"
> ```

Note the symbol case: `LIB_<X>_PRECALC_reu_mul_*` / `LIB_<X>_PRECALC_sqtab_*` — UPPER_SNAKE_CASE library prefix, lower-case table name. The macro preserves the literal case of the `name` argument since ca65 has no built-in toupper; the normative §8.x canonical names use lower_snake_case so adopters and consumers grep on a single case convention.

**Audit triggers.** A precalc table flagged `PRECALC_SHARED_YES` by two or more adopters at byte-identical size + region is a §8.x promotion candidate. The audit step runs:

- whenever a new adopter is added,
- whenever an existing adopter publishes a new minor version that adds a precalc table, AND
- **whenever an adopter generalises a previously curve-/algorithm-specific table** — e.g., a size-class jump, or a shape that was lib-private now applying to a sibling lib. Example: `c64-x25519`'s pre-doubled 8f+8g tables are correctly x25519-private today, but if `c448` / `Ed448` ever land in this stack and use the same pre-doubling trick, the audit must re-classify them. The pure-additive trigger would miss this case.

The catch loop is process, not contract — there is no `.assert` that enforces "two adopters with matching shape ⇒ a §8.x clause was filed." But the doc-level rationale field plus the build-time macro exports together give a future audit run something it can grep and reason about mechanically.

### 8.1 Shared 8×8 quarter-square multiply table (`sqtab`)

**Failure mode this prevents.** On 2026-05-17 the `c64-nist-curves` repo had to relocate its multiply table from `$7800` to `$9c00` because code growth pushed neighbouring data into the previous sqtab base and silently corrupted the table at boot. The same primitive is independently defined in five sibling libraries at four different addresses today (see issue [JC-000/c64-lib-contract#5](https://github.com/JC-000/c64-lib-contract/issues/5) for the audit). This clause exists to give the consumer a single placement point so the next "silent overwrite at boot" incident becomes a link-time error instead.

**Semantics.** Two byte tables `sqtab_lo` and `sqtab_hi`, each 512 bytes, such that

```
(sqtab_hi[n] << 8) | sqtab_lo[n] = floor(n² / 4)   for n ∈ 0..510
```

Used to implement `a*b = t(a+b) - t(a-b)` where `t(k) = floor(k²/4)`. Index 511 is unused; the 512-byte size is forced by the page-alignment / page-delta constraints below.

**Placement contract.** The consumer chooses the base address via the equate `LIB_SHARED_SQTAB_BASE`. Each adopting library's canonical header MUST follow this shape:

```asm
.ifndef LIB_SHARED_SQTAB_BASE
    LIB_SHARED_SQTAB_BASE = $...          ; per-lib default for standalone builds
.endif
sqtab_lo = LIB_SHARED_SQTAB_BASE
sqtab_hi = LIB_SHARED_SQTAB_BASE + $0200

.assert (LIB_SHARED_SQTAB_BASE & $00ff) = 0, error, "sqtab base must be page-aligned"
.assert sqtab_hi = sqtab_lo + $0200,        error, "sqtab_hi must follow sqtab_lo by $0200"
```

The `.ifndef` guard lets the library assemble standalone with its existing default; the consumer overrides via `ca65 -D 'LIB_SHARED_SQTAB_BASE=$<addr>'` (single-quoted — §2's `$`-hex quoting note). The two `.assert`s catch misconfigurations at assemble time:

- `LIB_SHARED_SQTAB_BASE & $00ff == 0` — CT-strict `abs,x` indexing requires a page-aligned base for cycle-stable loads.
- `sqtab_hi - sqtab_lo == $0200` — adopters that dispatch via self-modifying code on the lo→hi delta fold this constant into the opcode hi-byte patching; alternative deltas silently miscompute.

The contract pins *shape*, not *placement*. A consumer linking multiple sqtab-using libraries supplies one `-D 'LIB_SHARED_SQTAB_BASE=$<addr>'` and the libraries agree.

**Export discipline (v0.8.5).** `LIB_SHARED_SQTAB_BASE` is consumer *input*. Libraries MUST NOT `.export` it: two libraries exporting the same unprefixed name is a guaranteed `ld65: Duplicate external identifier` in any composed link (the [#82](https://github.com/JC-000/c64-lib-contract/issues/82)-class failure, which hit §8.2's analogous equates). Fleet practice was already unanimous — no adopter exports it; this sentence makes the practice normative.

**Init.** The canonical init entry point is `mul_tables_init`. It populates both tables from the quarter-square recurrence and MUST be idempotent — calling it twice produces the same table state and has no side effects beyond the table bytes.

**Migration shape.** Each adopting library MAY keep its existing per-lib `sqtab_init` exported for backwards compatibility. Under `.ifdef SHARED_SQTAB_INIT`, the library's own init body is gated out and the canonical `mul_tables_init` takes over. This lets a consumer flip libraries to the shared init one at a time without an atomic cross-repo cutover.

**Deferral means import, never stub (v0.9.0).** A build that defines `SHARED_SQTAB_INIT` MUST `.import` the provider's `mul_tables_init`; exporting a stub body (`rts`) under the deferred name is non-conformant — it puts two same-named canonical inits into every composed link, which is the duplicate-identifier failure the switch exists to remove (measured in the [#82](https://github.com/JC-000/c64-lib-contract/issues/82)/[#83](https://github.com/JC-000/c64-lib-contract/issues/83) composed-link audit: twelve residual duplicates, this class among them).

**Table names (v0.9.1, correcting v0.9.0).** `sqtab_lo` / `sqtab_hi` are the canonical names, **ratifying what every adopter already does** — the v0.9.0 text claimed `c64-x25519` used a `sqr_lo`/`sqr_hi` dialect and scheduled a deprecation; that was a misreading (x25519's `sqr_lo`/`sqr_hi` is a *different table*, the 512-byte a² diagonal-squaring lookup read by `fe25519_sqr`, and its quarter-square table has been `sqtab_lo`/`sqtab_hi` since before §8.1 adoption). No rename obligation exists.

**Canonical does not mean exported (v0.9.1).** `sqtab_lo`/`sqtab_hi` derive from the consumer-input `LIB_SHARED_SQTAB_BASE`, so the v0.8.5 export discipline applies: they are *source-level* names each consuming TU derives via the header pattern above, and libraries MUST NOT `.export` them — an SMC-dispatching consumer needs the base at assemble time anyway, the linker never needs the symbol, and two exporters collide in any composed link. (`c64-x25519` already conforms; `c64-nist-curves`' current bare export of both is a §6.5-window migration item, gated per #88.)

**Bit allocation.** This primitive owns bit `$0001`:

```asm
LIB_SHARED_PRIMITIVES_SQTAB = $0001
```

Adopters OR this bit into their `LIB_<X>_SHARED_PRIMITIVES` manifest equate (§5). For a lib that consumes only `sqtab` today:

```asm
LIB_<X>_SHARED_PRIMITIVES = LIB_SHARED_PRIMITIVES_SQTAB
```

**§8.4 catch-loop registry.** Adopters consuming this primitive MUST emit, in addition to the manifest-equate bit above, one §8.4 catch-loop macro invocation:

```ca65
LIB_PRECALC_TABLE "sqtab", 1024, PRECALC_REGION_RAM, PRECALC_SHARED_YES, "<X>"
```

The string `"sqtab"` is **normative**; adopters MUST NOT substitute a library-prefixed variant (e.g., `"nistcurves_sqtab"` or `"chacha_sqtab"`). The cross-adopter audit `od65 --dump-exports build/*.o | grep _PRECALC_sqtab_SIZE` depends on every adopter exporting the same `_PRECALC_sqtab_*` symbol family. The v0.7.0 library prefix goes in the fifth macro argument, never into the table name: `LIB_X25519_PRECALC_sqtab_SIZE` keeps the audit signal-rich, `LIB_PRECALC_x25519_sqtab_SIZE` would destroy it. Size (`1024`) and region (`PRECALC_REGION_RAM`) are also normative — they are invariants of the shared shape — only placement (the `LIB_SHARED_SQTAB_BASE` equate above) is consumer-chosen.

**Related future promotion.** The multiply body that consumes the table (`mul_8x8` / `ct_mul_8x8`) is duplicated across the same set of libraries. The CT-strict `ct_mul_8x8` variant (introduced by `c64-ChaCha20-Poly1305` v0.3.0, already ported by `c64-nist-curves`) is the right candidate to promote alongside `sqtab` once two or more adopters confirm bit-identical bodies. This clause does not pre-commit to that promotion; it is named here so adopters know which variant to align on if they touch the multiply body during the sqtab migration. **(Resolved in v0.4.0:** `ct_mul_8x8` was promoted to §8.3, bit `$0004`, once all three adopters confirmed byte-identical bodies via the cross-adopter `ct_mul_brute_check` gate.**)**

### 8.2 Shared 8×8→16 REU multiplication table (`reu_mul`)

**Failure mode this prevents.** The 128 KB 8×8→16 multiplication table at the heart of every multi-precision field-arithmetic loop is currently built and stashed in REU by both `c64-nist-curves` and `c64-x25519`. At each library's default `-D` setting both lay it down at REU banks `$00`/`$01` with byte-identical row layout (see [JC-000/c64-lib-contract#10](https://github.com/JC-000/c64-lib-contract/issues/10) for the audit). A consumer that links both libraries into a single PRG either silently collides on the same 128 KB or — after `-D`-relocating one of them — wastes 128 KB of REU plus ~3-6 s of cold-boot init on a redundant build of the same table. This clause gives the consumer one placement point so the duplication becomes recoverable from the consumer's cfg.

**Semantics.** 256 rows × 512 bytes occupying two contiguous REU banks (128 KB) starting at the chosen base. Each row is laid out as:

- bytes `[a * 512 .. a * 512 + 256)` — the 256 low bytes of `a × b` for `b ∈ [0..255]`
- bytes `[a * 512 + 256 .. a * 512 + 512)` — the 256 high bytes of `a × b` for `b ∈ [0..255]`

Rows are addressed `[a * 512]` where `a ∈ [0..255]`. Rows `0..127` live in the first bank (`LIB_SHARED_REU_MUL_BANK`); rows `128..255` live in the second bank (`LIB_SHARED_REU_MUL_BANK + 1`). No row crosses the bank boundary. The implementation MAY generate this from any source — quarter-square recurrence (the common path today), schoolbook `a × b`, or table image — as long as the resulting 128 KB is bitwise identical.

**Placement contract.** The consumer chooses the base bank via the equates below. Each adopting library's canonical header MUST follow this shape:

```asm
.ifndef LIB_SHARED_REU_MUL_BANK
    LIB_SHARED_REU_MUL_BANK = $00          ; per-lib default for standalone builds
.endif
.ifndef LIB_SHARED_REU_MUL_OFFSET
    LIB_SHARED_REU_MUL_OFFSET = $0000
.endif
LIB_SHARED_REU_MUL_BANKS_USED = (1 .shl LIB_SHARED_REU_MUL_BANK) | (1 .shl (LIB_SHARED_REU_MUL_BANK + 1))

.assert LIB_SHARED_REU_MUL_OFFSET = $0000, error, "reu_mul must start at offset 0 within its bank pair (v0.x.0 constraint)"
.assert LIB_SHARED_REU_MUL_BANK < $FE,     error, "reu_mul base bank must leave room for the hi-half bank at base+1"
```

The `.ifndef` guards let each library assemble standalone with its existing default; the consumer overrides via `ca65 -D 'LIB_SHARED_REU_MUL_BANK=$<bank>'` once and all consuming libraries agree. The `.assert`s catch misconfigurations at assemble time:

- `LIB_SHARED_REU_MUL_OFFSET = $0000` — current adopters require start-of-bank for row-stride math. Annotated as a v0.x.0 constraint; loosen only on a justified non-zero need from a future adopter.
- `LIB_SHARED_REU_MUL_BANK < $FE` — the table claims two contiguous banks (`base` and `base + 1`), so `base = $FF` has no successor.

`LIB_SHARED_REU_MUL_BANKS_USED` is a derived equate that names both claimed banks as a single mask. Consumers compose it into their REU-region `.assert` budget instead of writing `(1 .shl bank) | (1 .shl (bank + 1))` at every callsite; libraries OR it into their own `LIB_<X>_REU_BANKS_USED` (§5) when they consume the canonical primitive.

**ZP and staging-buffer surface.** The canonical init and per-row fetch share two ZP scratch slots and a page-aligned main-RAM staging buffer pair. Both follow the §2 / §3 `.ifndef` pattern so consumers compose without collision:

```asm
.ifndef LIB_SHARED_REU_MUL_ZP_INIT_A
    LIB_SHARED_REU_MUL_ZP_INIT_A = $..    ; one byte of ZP scratch (per-lib default)
.endif
.ifndef LIB_SHARED_REU_MUL_ZP_INIT_B
    LIB_SHARED_REU_MUL_ZP_INIT_B = $..    ; one byte of ZP scratch (per-lib default)
.endif
.ifndef LIB_SHARED_REU_MUL_STAGE_LO
    LIB_SHARED_REU_MUL_STAGE_LO = $....   ; 256 B page-aligned, lo half of fetched row
.endif
.ifndef LIB_SHARED_REU_MUL_STAGE_HI
    LIB_SHARED_REU_MUL_STAGE_HI = $....   ; 256 B page-aligned, hi half of fetched row
.endif

.assert (LIB_SHARED_REU_MUL_STAGE_LO & $00ff) = 0,                              error, "reu_mul stage_lo must be page-aligned"
.assert (LIB_SHARED_REU_MUL_STAGE_HI & $00ff) = 0,                              error, "reu_mul stage_hi must be page-aligned"
.assert LIB_SHARED_REU_MUL_STAGE_HI = LIB_SHARED_REU_MUL_STAGE_LO + $0100,      error, "reu_mul stage_hi must follow stage_lo by $0100"
```

Page alignment and adjacent placement of the two stage buffers are required by the fetch primitive's 4×-unrolled `abs,y` accumulator loop. Each adopter's existing `mul_dma_lo` / `mul_dma_hi` labels remain exported for backwards compatibility; the canonical names alias them.

**Export discipline (v0.8.5).** Every `LIB_SHARED_REU_MUL_*` equate above is consumer *input* (or derived directly from one). Libraries MUST NOT `.export` any of them. Both REU adopters did, producing a live `Duplicate external identifier: 'LIB_SHARED_REU_MUL_BANKS_USED'` in the exact pair `c64-https` ships — see [#82](https://github.com/JC-000/c64-lib-contract/issues/82); fixed adopter-side in [c64-x25519#92](https://github.com/JC-000/c64-x25519/pull/92) and [c64-nist-curves#103](https://github.com/JC-000/c64-nist-curves/pull/103).

What a §8.2-consuming library MUST export instead is its library-prefixed *output* counterparts of the three placement equates, so a consumer can verify that co-linked libraries agree on placement:

```asm
; library side — in the TU that consumes the §8.2 knobs.
; Alias the symbol the REU access paths actually READ. If the code reads the
; knob directly, that is the knob; if it reads a §3 alias of the knob
; (e.g. LIB_<X>_REU_BANK_MUL), alias THAT — aliasing the knob would publish a
; stale value whenever a consumer overrides the §3 alias directly, the exact
; decorative-export defect this clause bans (both override spellings must
; track: measured in c64-nist-curves#105).
LIB_<X>_SHARED_REU_MUL_BANK       = <the bank symbol the code reads>
LIB_<X>_SHARED_REU_MUL_OFFSET     = <the offset symbol the code reads>
LIB_<X>_SHARED_REU_MUL_BANKS_USED = (1 .shl LIB_<X>_SHARED_REU_MUL_BANK) | (1 .shl (LIB_<X>_SHARED_REU_MUL_BANK + 1))
.export LIB_<X>_SHARED_REU_MUL_BANK:       abs
.export LIB_<X>_SHARED_REU_MUL_OFFSET:     abs
.export LIB_<X>_SHARED_REU_MUL_BANKS_USED: abs
```

Libraries that honor the ZP/staging knobs SHOULD additionally export prefixed counterparts of those (`LIB_<X>_SHARED_REU_MUL_ZP_INIT_A`, …, `LIB_<X>_SHARED_REU_MUL_STAGE_HI`), same shape.

**The exported value MUST be the value the code reads.** An export whose value the library's REU access paths do not actually consume certifies nothing — `c64-x25519`'s pre-#92 export was exactly this: code read `X25519_REU_BANK` at every access site while the §8.2 knob published a number nothing consumed, so `-D 'LIB_SHARED_REU_MUL_BANK=$04'` succeeded silently, published 4, and read bank 0. Adopter review MUST grep the access paths for the knob, not just the export list.

Consumer cross-check:

```asm
; consumer side — placement agreement across co-linked §8.2 consumers
.import LIB_NISTCURVES_SHARED_REU_MUL_BANK
.import LIB_X25519_SHARED_REU_MUL_BANK
.assert LIB_NISTCURVES_SHARED_REU_MUL_BANK = LIB_X25519_SHARED_REU_MUL_BANK, lderror, "co-linked libraries disagree on reu_mul placement"
```

(`lderror`, not `error`: the operands are imports, unknown at assemble time — §1's guard rule applies. Both snippets assemble-tested, and the assert verified to fire on a deliberate one-bank disagreement, ca65/ld65 V2.18.)

**Init.** The canonical init entry point is `reu_mul_tables_init`. It populates banks `LIB_SHARED_REU_MUL_BANK` and `LIB_SHARED_REU_MUL_BANK + 1` and nothing else. The contract is **safe to call twice**: a second call produces the same final REU state with the same observable side effects (the full ~3 s of init work runs twice). The contract does NOT promise no-op on re-call — adding an init-done flag would be an additive change deferred to a future minor bump if a consumer needs it. "Safe to call twice" is the load-bearing reading; do not infer "idempotent" in the no-op sense from this clause.

Libraries that ship adjacent caches keyed off the canonical table — e.g., `c64-x25519`'s pre-doubled 8f+8g rows in banks `+3..+5`, generated only under the build-time `SQR_DMA_K > 0` profile — generate those caches in a library-private init invoked *after* `reu_mul_tables_init` returns. The canonical init MUST NOT touch those banks, and the library-private init MUST stay gated on its existing build-time profile flag. This preserves the lean-profile reclamation those flags exist to provide (e.g., `lib-x25519-1764` with `SQR_DMA_K = 0` reclaims ~600 ms init and 3 REU banks).

**Fetch.** The canonical per-row fetch entry point is `reu_fetch_mul_row`. Calling convention: register `A = a` (row index); on return, the 512 bytes of row `a` are written to `LIB_SHARED_REU_MUL_STAGE_LO` / `LIB_SHARED_REU_MUL_STAGE_HI`. Per-call REU register touches: hi address byte (`$DF05`), bank (`$DF06`), command (`$DF01`) — three writes, ~20 cycles. The fetch MUST re-establish `reu_reu_lo` (`$DF04`) and `reu_addr_ctrl` (`$DF0A`) to `$00` defensively on entry to defend against caller residue (issue [JC-000/c64-x25519#33](https://github.com/JC-000/c64-x25519/issues/33)-class).

**Migration shape.** Each adopting library MAY keep its existing per-lib `reu_mul_init` exported for backwards compatibility. Under `.ifdef SHARED_REU_MUL_INIT`, the library's own un-doubled-banks init body is gated out and the canonical `reu_mul_tables_init` takes over. Library-private init for adjacent caches (above) stays under its own build-time gate and is invoked alongside the canonical init from the library's existing entry. A consumer flips libraries to the shared init one at a time without an atomic cross-repo cutover.

**Fetch deferral (v0.9.1, correcting v0.9.0; conditional surface refined v0.9.2).** `SHARED_REU_MUL_INIT` gates init only; the per-row fetch was exported unconditionally by both REU adopters, so every composed link carried two canonical fetches regardless of init deferral. A second switch, **`SHARED_REU_MUL_FETCH`**, gates the fetch surface: **`reu_fetch_mul_row`** always, and the SMC bank-patch label **`reu_fetch_mul_row_bank_patch`** *conditionally* (promoted from the #15 delegation mechanism). The patch label is required of a provider **iff its fetch body carries the SMC bank-patch site**; a provider whose fetch computes the bank inline (`c64-nist-curves`' shape — no SMC site, no callers) exports nothing and MUST NOT synthesize one. A deferring build MUST `.import` the patch label **iff its own adjacent-cache paths delegate through it** (`c64-x25519`'s `SQR_DMA_K > 0` shape). The unsupported pairing — a patch-needing deferrer composed against an inline-computing provider — fails as an unresolved external at link; that is the intended, loud outcome, and this sentence is its documentation.

**Import-never-stub, stated precisely (v0.9.2).** The load-bearing half of the rule is that a deferring build MUST NOT export a body under a canonical name — no second canonical definition, ever. The `.import` half applies only where the deferring build itself *references* the symbol; an import ca65 drops as unreferenced is conformant (measured in [nist#106](https://github.com/JC-000/c64-nist-curves/pull/106): a deferring build whose own code never calls the fetch has nothing observable to import, and the rule is satisfied by the absent stub alone).

The v0.9.0 text also gated `mul_dma_lo`/`mul_dma_hi`, `mul_cached_a` and `mul_src2_buf`; that was an overreach — those are adopter-private buffers (in `c64-x25519`, `mul_src2_buf` is the fe25519 operand-copy buffer the fetch never touches, and `mul_cached_a` is dual-purpose scratch), and deferring them would point a library's own field arithmetic at another library's memory. Staging *placement* is already the job of the unexported `LIB_SHARED_REU_MUL_STAGE_LO`/`_HI` input equates. The four bare labels instead move to the **rename track**: `mul_` is registered to `c64-x25519` in the §2 registry, so `c64-nist-curves`' `mul_dma_*`/`mul_cached_a`/`mul_src2_buf` take its own prefix under the §6.5 window (suppression-gated per #88), and x25519's remain under its registration.

**The two switches move together (v0.9.1).** A build MUST define `SHARED_REU_MUL_INIT` and `SHARED_REU_MUL_FETCH` both or neither; partial deferral is non-conformant. Bit `$0002` (`LIB_SHARED_PRIMITIVES_REU_MUL`) drops from the §8.0 mask exactly when both are defined. Rationale: the bit asserts ownership of *the primitive*, and a build that defers init while still exporting the canonical fetch is an owner of the fetch that is not an owner of the primitive — a state the §8.0 three-state table has no row for. If a future consumer demonstrates a need for split ownership, that is a §8.0 fourth-state proposal, not a silent partial deferral.

**Bit allocation.** This primitive owns bit `$0002`:

```asm
LIB_SHARED_PRIMITIVES_REU_MUL = $0002
```

Adopters OR it into their `LIB_<X>_SHARED_PRIMITIVES` manifest equate (§5) and the existing §8.0 `.assert` catches accidental cross-library double-ownership.

**§8.4 catch-loop registry.** Adopters consuming this primitive MUST emit, in addition to the manifest-equate bit above, one §8.4 catch-loop macro invocation:

```ca65
LIB_PRECALC_TABLE "reu_mul", 131072, PRECALC_REGION_REU, PRECALC_SHARED_YES, "<X>"
```

The string `"reu_mul"` is **normative**; adopters MUST NOT substitute a library-prefixed variant (e.g., `"nistcurves_reu_mul"` or `"x25519_reu_mul"`). The cross-adopter audit `od65 --dump-exports build/*.o | grep _PRECALC_reu_mul_SIZE` depends on every adopter exporting the same `_PRECALC_reu_mul_*` symbol family (the v0.7.0 library prefix goes in the fifth macro argument, never into the table name — see §8.1). (`od65` is the cc65 object-file inspector; ca65 `.o` files are not in ELF/Mach-O format so standard `nm` cannot read them. It reads objects only — for a shipped `.a`, extract members first per §8.0. Symbol case is preserved from the macro argument — see §8.0.) Size (`131072`) and region (`PRECALC_REGION_REU`) are also normative — they are invariants of the shared shape — only placement (the `LIB_SHARED_REU_MUL_BANK` equate above) is consumer-chosen.

**Worked consumer layout (TLS 1.3 stack).** A consumer that links `c64-nist-curves` (consumes §8.2 plus its own Lim-Lee comb at a private REU bank), `c64-x25519` (consumes §8.2 plus its own pre-doubled tables at private REU banks under `SQR_DMA_K > 0`), and `c64-ChaCha20-Poly1305` (consumes §8.1 sqtab only, no §8.2) might cfg as follows:

```asm
LIB_SHARED_REU_MUL_BANK         = $00       ; banks $00 + $01 — shared by nist-curves and x25519
LIB_NISTCURVES_REU_BANK_COMB    = $02       ; bank $02 — Lim-Lee comb (nist-curves private)
X25519_REU_BANK_DOUBLED         = $03       ; banks $03..$05 — x25519 pre-doubled (private, K>0)
LIB_SHARED_SQTAB_BASE           = $C000     ; main-RAM sqtab (chacha + nist-curves + x25519 all consume)
```

Under that cfg the three adopters' `LIB_<X>_REU_BANKS_USED` manifest equates resolve without overlap; the §8.0 `LIB_<X>_SHARED_PRIMITIVES` `.assert` catches any accidental double-ownership of bit `$0001` or `$0002`. Banks `$06` and `$07` remain free for the next §8.x candidate (e.g., a shared SHA message schedule cache) or for consumer-private use.

**Related future promotions.** Two follow-ups carry across from this clause:

- `mul_8x8` / `ct_mul_8x8` — the multiply body that consumes the table. **Resolved in v0.4.0: promoted to §8.3 (bit `$0004`)** after the cross-adopter `ct_mul_brute_check` round-trip confirmed byte-identical bodies across all three adopters. Was tracked in [JC-000/c64-lib-contract#14](https://github.com/JC-000/c64-lib-contract/issues/14).
- `c64-x25519`'s `reu_fetch_doubled_row` — structurally identical to `reu_fetch_mul_row` in its first DMA with a different bank base. **Resolved 2026-05-24:** the SMC-patch refactor shipped in [c64-x25519#59](https://github.com/JC-000/c64-x25519/pull/59) (patch-label export) + [c64-x25519#60](https://github.com/JC-000/c64-x25519/pull/60) (DMA #1 delegated to the canonical fetch via `reu_fetch_mul_row_bank_patch`; DMA #2 kept inline; autoload-latch invariant documented + regression-guarded). Was tracked in [JC-000/c64-lib-contract#15](https://github.com/JC-000/c64-lib-contract/issues/15), closed.

Both follow-ups from this clause are resolved: #14's evidence gate (cross-adopter brute-check round-trip) was satisfied and `ct_mul_8x8` promoted in §8.3 (v0.4.0); #15's SMC-patch refactor landed adopter-side without any §8.2 contract change.

### 8.3 Shared constant-time 8×8→16 multiply body (`ct_mul_8x8`)

**Failure mode this prevents.** The branchless, SMC-dispatched quarter-square multiply body that reads the §8.1 `sqtab` is reimplemented in every library that does field arithmetic. A pre-S12 ancestor of this body carried two secret-dependent branches; the constant-time rewrite (`c64-ChaCha20-Poly1305` v0.3.0 `ct_mul_8x8`) was then ported divergently into siblings (different calling conventions, block orderings, and scratch placement), so a CT-relevant edit to one copy could silently leave the others on a timing-variable shape. This clause pins one canonical body so the constant-time property is defined once and verified mechanically across adopters.

**Semantics.** A constant-time 8-bit × 8-bit → 16-bit multiply computing `a*b = t(a+b) - t(|a-b|)` over the §8.1 `sqtab` tables, with no secret-dependent branches and cycle-stable `abs,x` indexed loads (the invariant the variant exists to preserve). Entry: `Y = b`; the multiplier `a` is baked into the two `adc #imm` SMC immediate sites by the caller before the inner loop. The 16-bit product is returned in the library's product scratch (`poly_prod_lo` / `poly_prod_hi`). This clause **depends on §8.1** — the body reads `sqtab_lo` / `sqtab_hi` and inherits their page-alignment `.assert`s.

**Shape contract (pinned by gate, not by `.assert`).** Unlike §8.1 / §8.2 there is no placement equate — this is a code body, not a placed table. The canonical shape is the 59-byte `ct_mul_8x8` body in `c64-ChaCha20-Poly1305/src/lib/poly1305_lib.s`. Adopters MUST be **byte-identical** to it. This is enforced by the cross-adopter `tools/ct_mul_brute_check.py` ratchet — opcode-byte equality across all adopters plus a 65 536-case functional brute-check — which MUST return exit 0 before any body change lands. As of v0.4.0 all three adopters (`c64-ChaCha20-Poly1305`, `c64-nist-curves`, `c64-x25519`) are byte-identical (59 B, SHA-256 `3ed9025b…`, 65536/65536 functional).

**Canonical entry.** `ct_mul_8x8`. Adopters whose historical name is `mul_8x8` keep it exported as a back-compat alias of `ct_mul_8x8` (same address).

**Provider surface (v0.10.6).** The names above describe the calling convention; this paragraph makes them an obligation, because the convention is unusable across TUs without them. A §8.3 provider MUST export, and a deferring adopter MUST `.import` where referenced (§8.2's import-never-stub discipline): `ct_mul_8x8` itself, the two SMC operand sites `smc_sum_a_imm` / `smc_diff_a_imm` (the caller bakes `a` into their `+1` immediates — they are load-bearing entry state, not internals), and the product scratch `poly_prod_lo` / `poly_prod_hi`. Both current providers already export all five by convergent necessity (`c64-ChaCha20-Poly1305` `poly1305_lib.s`, `c64-x25519` `mul_8x8.s`), and `c64-x25519`'s own field layer consumes the SMC pair by import — but nothing required it, so a future provider exporting only the entry point would satisfy this clause as previously written and strand every deferring consumer at link ([nist#123](https://github.com/JC-000/c64-nist-curves/issues/123), where the deferring side of the same gap — a `SHARED_CT_MUL_8X8` gate that removed definitions without adding the imports — made APP_OWNED × on-chip unreachable and failed only in the combination CI never built). The gating corollary is explicit: a deferral switch MUST leave behind `.import`s for every name in this list that the TU's remaining code references — gating out a definition without importing its replacement is the assemble-time sibling of §6.3's looks-reachable failure.

**Migration shape.** Each adopting library gates its own copy under `.ifdef SHARED_CT_MUL_8X8`. When a consumer defines that switch, the library's private body is gated out and the canonical `ct_mul_8x8` provided by the designated owner takes over. This mirrors the §8.1 `SHARED_SQTAB_INIT` switch and lets a consumer flip libraries one at a time without an atomic cross-repo cutover. The §8.1 import-never-stub rule (v0.9.0) applies: a deferring build MUST `.import` the provider's `ct_mul_8x8`, never export a stub under the canonical name.

**Bit allocation.** This primitive owns bit `$0004`:

```asm
LIB_SHARED_PRIMITIVES_CT_MUL_8X8 = $0004
```

Adopters include this bit in their `LIB_<X>_SHARED_PRIMITIVES` manifest equate using the **conditional** mask construction of §8.0 — the bit is dropped when this build defines `SHARED_CT_MUL_8X8` (i.e. defers the body to a provider). The `$0004` → `SHARED_CT_MUL_8X8` mapping is registered in the §8.0 deferral-switch table.

**No §8.4 catch-loop registry entry.** §8.0's `LIB_PRECALC_TABLE` enumeration covers precalculated *tables*; `ct_mul_8x8` is a code body, not a table, so it takes **no** `LIB_PRECALC_TABLE` invocation. Its data dependency — the §8.1 `sqtab` table — is already enumerated under §8.1.

## 13. Network backend ABI

> Numbering note (v0.10.1): section numbers are **stable identifiers, not positions** — §2/§3/§4/§8.x are referenced by name from adopter and consumer cfgs, docs, and commit messages (measured at the v0.9.x wave tags: 900+ §8.x references fleet-wide), so no section is ever renumbered. §13 was historically appended after the §12 changelog to preserve that invariant; as of v0.10.1 the *text* is ordered for reading — core, then domain chapters, then meta — while every number stays fixed. New chapters continue from §14, placed with their kind.

This chapter is the contract's first non-cryptographic chapter. It standardizes the symbol surface and device-timing semantics of **network backends** — the adapter layers that put a C64 on a network — so that a consumer can switch backends at link time and so that hard-won device-timing fixes propagate across consumers instead of rotting in forks.

- A **network backend** is an adapter (`src/net/<backend>/`) plus the driver it fronts: today, `ip65` (RR-Net / cs8900a, driven via a position-linked binary blob) and `uci` (Ultimate 64 / U64E / C64 Ultimate command interface at `$DF1B-$DF1F`).
- The consumer-facing surface is a single `net_abi.inc` of `.import`ed symbols. Swapping backends is a link-line + cfg choice; higher layers (TLS, HTTP, WireGuard handshake/transport) do not change.

**Why this chapter exists.** Both current consumers confirmed the duplication the hard way: `c64-wireguard` copied `c64-https`'s `net_abi.inc` pattern and the two surfaces then drifted — divergent names for the same operation (`net_dhcp` vs `net_dhcp_acquire`), divergent data-passing conventions, adapter internals leaking into one public surface but not the other, and — most costly — **robustness divergence**: `c64-wireguard`'s UCI adapter is a snapshot that predates `c64-https`'s bounded-wait conversion, phantom-socket detection, and widened inter-access fence, so wedge classes already fixed in one consumer remain live in the other (its `uci_errors.inc` is an older copy missing `UCI_ERR_NO_SOCKET` and `UCI_ERR_WAIT_TIMEOUT`). This chapter pins the union surface and the semantics that were previously folklore.

**Scope (level 1 vs level 2).** v0.6.0 governs the *symbol surface and semantics* of adapters that live in-consumer (level 1). Packaging backends as relocatable `LIB_NET_<B>_*` archives per §4/§6 (level 2) is a future promotion, gated on the adapters stabilizing; §13.7 already defines the declaration pattern for the part that can never be §4-relocatable (the position-linked ip65 blob).

### 13.0 Families and capability declaration

Backend functionality is organized in **families**. A backend implements the core family plus any subset of the others, and declares what it implements via an exported manifest equate:

| Bit | Constant | Family | Surface |
|---|---|---|---|
| `$0001` | `NET_FAMILY_CORE` | lifecycle + addressing | `net_init`, `net_dhcp_acquire`, `net_poll`, `net_local_ip`, `net_last_error` |
| `$0002` | `NET_FAMILY_TCP` | TCP client | `net_tcp_connect`, `net_tcp_send`, `net_tcp_close`, `net_tcp_state`, TCP rx ring (§13.3) |
| `$0004` | `NET_FAMILY_UDP` | UDP sockets | `net_udp_listen`, `net_udp_send`, UDP rx buffer (§13.3) |
| `$0008` | `NET_FAMILY_DNS` | name resolution | `net_dns_resolve`, `net_resolved_ip` |

**Definition site.** The four `NET_FAMILY_*` constants are plain assemble-time equates — never `.export`ed — and live in one header that both the backend manifest and every family-asserting consumer `.include`:

```asm
; src/net/net_families.inc — included by the backend manifest and by consumers
NET_FAMILY_CORE = $0001
NET_FAMILY_TCP  = $0002
NET_FAMILY_UDP  = $0004
NET_FAMILY_DNS  = $0008
```

Keeping them unexported is deliberate: both sides of the link carry the header, and only exported symbols can collide at link time. The byte-for-byte source adopters copy is [`net_families.inc`](net_families.inc) at this repo's root (the fenced block above is shown for readability), exactly as [`precalc_table.inc`](precalc_table.inc) is for §8.0. `NET_BACKEND_FAMILIES` is the sole exported symbol in §13.0 and is per-backend, so a consumer linking two backends is a configuration error the linker will name rather than a naming defect in this clause (contrast the unprefixed §1/§8.4 manifest exports in [#43](https://github.com/JC-000/c64-lib-contract/issues/43)). Adopters copy the block verbatim rather than deriving the values, exactly as the §8.x bit constants are copied.

```asm
; src/net/<backend>/net_manifest.s
.include "net_families.inc"
.export NET_BACKEND_FAMILIES : absolute
NET_BACKEND_FAMILIES = NET_FAMILY_CORE | NET_FAMILY_TCP | NET_FAMILY_DNS
```

The `: absolute` hint is required, not stylistic: the mask fits in a byte, so an unhinted export makes ca65 infer `zeropage` while the consumer's `.import` defaults to absolute, and ld65 warns `Address size mismatch` on every link (the §8.4 defect of [#58](https://github.com/JC-000/c64-lib-contract/issues/58) recurring here; measured with these two snippets unmodified in [#140](https://github.com/JC-000/c64-lib-contract/issues/140)).

Bits are append-only and never reused, per the §8.0 discipline. `NET_FAMILY_CORE` is mandatory: a backend that cannot init, acquire an address, and be pumped is not a backend. A consumer asserts its needs against the linked backend:

```asm
.include "net_families.inc"
.import NET_BACKEND_FAMILIES
.assert (NET_BACKEND_FAMILIES & (NET_FAMILY_CORE | NET_FAMILY_UDP)) = (NET_FAMILY_CORE | NET_FAMILY_UDP), lderror, "this consumer needs a UDP-capable backend"
```

**DNS family note.** A backend MAY implement `NET_FAMILY_DNS` by deferral: the UCI firmware resolves hostnames inside `TCP_CONNECT`, so its `net_dns_resolve` stages the hostname and performs no I/O (§13.1). Deferral still sets the `$0008` bit — the consumer-visible behavior ("I can pass a hostname and connect to it") is what the bit declares, not the wire mechanism.

**Poll-pump model (normative).** Consumers drive the backend by calling `net_poll` from their main loop. A backend MUST NOT require interrupt service to make progress, and MUST tolerate arbitrarily long gaps between pumps: packets that arrive while the consumer is not pumping MAY be dropped (TCP recovery is the peer's retransmission; UDP recovery is the protocol's own loss tolerance). This is load-bearing for cryptographic consumers whose compute stalls reach minutes at stock clock — a TLS CertificateVerify at 1 MHz can leave the network unpumped for 20+ minutes, and the contract's answer is "drops are legal; the transport recovers," not "the adapter must buffer everything."

### 13.1 Symbol surface

Union surface across both consumers. Where the two existing surfaces conflicted, `c64-https` naming wins (it is the older and more hardened adapter pair); the per-consumer renames are tracked as §13.8 intake items. All flag/error semantics follow §13.2.

**Core family** (required):

| Symbol | Kind | Convention |
|---|---|---|
| `net_init` | entry | No arguments. Detect + initialize the device/driver. C=0 ok; C=1 fail with `net_last_error` set. |
| `net_dhcp_acquire` | entry | No arguments. Acquire a lease; populates `net_local_ip`. C flag per §13.2. Backends on multi-interface devices SHOULD probe all interfaces and take the first lease (cf. the C64 Ultimate WiFi/Ethernet fallback). |
| `net_poll` | entry | No arguments. Pump one unit of driver work (process ≤ 1 inbound packet / drain ≤ 1 firmware read chunk). C=1 only on backend error; **C=0 carries no "data arrived" meaning** — data availability is observed through the §13.3 buffers. Clobbers A/X/Y. |
| `net_local_ip` | data, 4 B | Local IPv4 address after `net_dhcp_acquire` succeeds. Zero before. |
| `net_last_error` | data, 1 B | Last error code (§13.2). `$00` = no error. |

**TCP family** (`NET_FAMILY_TCP`):

| Symbol | Kind | Convention |
|---|---|---|
| `net_tcp_connect` | entry | A = port low byte, X = port high byte. The destination host was staged by a prior `net_dns_resolve` call. C flag per §13.2; on failure `net_tcp_state` reflects it. |
| `net_tcp_send` | entry | A = data pointer low, X = high; `net_send_len` (2 B, exported data) = length. 16-bit lengths MUST be honored in full (§13.3). Short writes are best-effort: the backend records `NET_ERR`-class detail in `net_last_error` but returns C=0. |
| `net_tcp_close` | entry | No arguments. Always leaves `net_tcp_state` = closed. |
| `net_tcp_state` | data, 1 B | `$00` `NET_TCP_CLOSED`, `$01` `NET_TCP_CONNECTED`, `$02` `NET_TCP_ERROR`, `$03` `NET_TCP_CONNECT_FAIL`. Values are normative (they are the existing `UCI_TCP_*` values, name-promoted). |
| rx ring | data | See §13.3. |

**DNS family** (`NET_FAMILY_DNS`):

| Symbol | Kind | Convention |
|---|---|---|
| `net_dns_resolve` | entry | A/X = pointer to NUL-terminated hostname (dotted-quad literals MUST pass through). Resolution MAY be lazy: a deferring backend stages the name for `net_tcp_connect` and cannot fail here; an eager backend resolves immediately. C flag per §13.2. |
| `net_resolved_ip` | data, 4 B | All-zero = not resolved; `$FF,$FF,$FF,$FF` = resolved internally by the device (deferral marker); anything else = the resolved address. Consumers MUST NOT treat the deferral marker as an address. |

**UDP family** (`NET_FAMILY_UDP`) — standardized from the `c64-wireguard` surface with adapter-internal and consumer-specific leaks removed:

| Symbol | Kind | Convention |
|---|---|---|
| `net_udp_listen` | entry | A = local port low, X = high. Binds and arms inbound delivery into the §13.3 UDP rx buffer. C flag per §13.2. |
| `net_udp_send` | entry | `net_udp_send_ptr` (2 B) = payload pointer, `net_udp_send_len` (2 B) = length, `net_udp_dest_ip` (4 B) + `net_udp_dest_port` (2 B) = destination — all exported ABI data, set by the caller before the call. C flag per §13.2. |
| rx buffer | data | See §13.3. |

**Deliberately not in the contract:**

- `net_tcp_set_recv_cb` — an RTS stub with zero in-tree callers in `c64-https`; the drain model (§13.3) is the contract. Retired rather than standardized.
- `net_udp_recv_cb` — adapter-internal wiring (it is the function the *driver* calls); exporting it invites consumers to call it. Internal.
- `net_save_zp` / `net_restore_zp` — see §13.5.
- `net_print_ip` — a consumer UI helper, not backend functionality.
- `wg_peer_ip` / `wg_peer_port` as send destinations — consumer state read by an adapter is a layering inversion; replaced by `net_udp_dest_ip` / `net_udp_dest_port` owned by the ABI.

### 13.2 Error and state convention

Every entry point returns C=0 on success and C=1 on failure with `net_last_error` holding a nonzero code. Two normative refinements:

- **"No data" is not an error.** `net_poll` with nothing to do, an empty rx ring, an unset ready flag — all are C=0 conditions observed through data, not flags. (This retires `c64-wireguard`'s "C=0 = packet processed" `net_poll` meaning, the one place the two consumers' flag semantics genuinely conflicted.)
- **Callers MUST propagate.** Adapter-internal helpers that can time out (§13.4) return C=1; every call site either handles or `bcs`-propagates. An adapter that swallows a timeout wedges the machine one layer up.
- **Advisory codes.** A backend MAY record a nonzero `net_last_error` while returning C=0 where the operation completed but something worth a post-mortem was observed (§13.1's best-effort short write; `$8B`). A consumer MUST NOT infer failure from a nonzero `net_last_error` alone — C is the success/failure signal, and the code is detail. Codes usable this way are marked **advisory** in the allocation table; every other code is terminal (C=1).

**`net_last_error` namespace.** `$00` = OK. The range is carved so codes identify their origin at a glance and existing values stay valid verbatim:

| Range | Owner |
|---|---|
| `$01-$3F` | Contract-generic codes (none allocated yet; future §13 revisions allocate here) |
| `$40-$7F` | ip65-family backends |
| `$80-$BF` | UCI-family backends — the pre-existing `UCI_ERR_*` values (`$81-$89`) are grandfathered unchanged; `$8A` was allocated to resolve the collision below; `$8B` is the first code allocated under the table rule; `$8C` the second, and the first with an observable trigger |
| `$C0-$FF` | Consumer-private experiments; never allocated by this contract |

A backend MUST emit only `$00` or codes from its own family range.

**Allocation table (v0.12.0).** A family range is ONE namespace shared by every backend of that family across all consumers — the two UCI adapters in the fleet (`c64-https`, `c64-wireguard`) emit into the same `$80-$BF`, and a consumer reading a `net_last_error` from either must be able to name it. Codes are therefore allocated **here first**, then in the adapter; a value in this table is never reassigned. The `$88` row is the case that motivated the table: `c64-wireguard` allocated `$88` for `UCI_ERR_LONG_READ` (PR #62, merged 2026-08-20) while c64-https had long emitted `$88` as `UCI_ERR_NO_SOCKET` — a head-on collision on the one device family where both arise, unnoticed for four days, in which **neither side violated §13.2 as written**. The clause reserved the range and published no name→value table, so both adapters were conformant while disagreeing about a byte. The registry, not the range, is what makes a code mean one thing.

| Code | Name | Meaning | C flag | Allocated by |
|---|---|---|---|---|
| `$41` | `NET_ERR_IP65_INIT` | `ip65_init` failed (no RR-Net / cs8900a) | terminal (C=1) | c64-https |
| `$42` | `NET_ERR_IP65_DHCP` | `ip65_dhcp_init` failed (no lease) | terminal (C=1) | c64-https |
| `$43` | `NET_ERR_IP65_DNS` | `ip65_dns_resolve` failed | terminal (C=1) | c64-https |
| `$44` | `NET_ERR_IP65_CONNECT` | `ip65_tcp_connect` failed | terminal (C=1) | c64-https |
| `$45` | `NET_ERR_IP65_SEND` | `ip65_tcp_send` failed | terminal (C=1) | c64-https |
| `$81` | `UCI_ERR_NOT_PRESENT` | `$DF1D` did not read back the UCI ID byte `$C9` | terminal (C=1) | c64-https (grandfathered) |
| `$82` | `UCI_ERR_CMD_FAILED` | error bit set after PUSH_CMD | terminal (C=1) | c64-https (grandfathered) |
| `$83` | `UCI_ERR_NO_IP` | GET_IPADDR returned all-zero on every probed interface | terminal (C=1) | c64-https (grandfathered) |
| `$84` | `UCI_ERR_CONNECT_FAIL` | TCP_CONNECT returned an error bit | terminal (C=1) | c64-https (grandfathered) |
| `$85` | `UCI_ERR_SEND_FAIL` | SOCKET_WRITE returned an error bit | terminal (C=1) | c64-https (grandfathered) |
| `$86` | `UCI_ERR_READ_FAIL` | SOCKET_READ returned an error bit | terminal (C=1) | c64-https (grandfathered) |
| `$87` | `UCI_ERR_SHORT_WRITE` | SOCKET_WRITE wrote fewer bytes than requested | **advisory** (C=0) | c64-https (grandfathered) |
| `$88` | `UCI_ERR_NO_SOCKET` | socket-open response yielded no socket id (phantom socket) | terminal (C=1) | c64-https (grandfathered) |
| `$89` | `UCI_ERR_WAIT_TIMEOUT` | a §13.4 bounded wait exceeded its wall-clock budget | terminal (C=1) | c64-https (grandfathered) |
| `$8A` | `UCI_ERR_LONG_READ` | The SOCKET_READ response header claimed more bytes than were requested and was not the `$FFFF` no-data sentinel. **On fw 3.14d this condition has no observable trigger on either transport, so no conformant adapter emits it today; the code is allocated and reserved** (the value must not be reused, and another firmware or UCI-family device may surface it). Measured: on TCP the header is `$FFFF` on idle polls and otherwise has not been seen above the request; on UDP a datagram that fits the request arrives whole in one poll with the header reporting its **true length** (512-893 B measured), while a datagram larger than the request is truncated to the request with the header reporting the **delivered** count (600-1280 B against 512: `rx_len` 512, header `$0200`) — never the true size, never above the request (c64-wireguard, fresh power cycle, each row repeated; the earlier "never the true length" reading was an artifact of only ever requesting 512). **The two transports are not uniform**: the same register is a no-data sentinel on TCP and a length on UDP; each adapter generalised from its own transport to the other and was wrong in the opposite direction. `$FFFF` MUST be excluded before any length arithmetic, and a device-supplied count MUST never be the only bound on a store loop (the founding `$D000` overrun, c64-wireguard PR #62, was 65535 from an idle poll used as a copy count). If a device does surface an over-claim, the datagram disposition is drop, and that is what this code means; the stream disposition is cap-and-continue, recorded as `$8B`. **On fw 3.14d oversized-datagram truncation is silent and undetectable at this ABI**, and the defence is the consumer's MTU pin (§13.3), not this code; a firmware that reports truncation (`04,DATAGRAM TRUNCATED`, GideonZ/1541ultimate#806, present from 3.15) makes the condition detectable, and an adapter that detects it drops the datagram and emits this code — the meaning does not change, only its reachability. | terminal (C=1) | c64-wireguard — **published**: `master` emitted this as `$88` from PR #62 (2026-08-20) until [c64-wireguard#67](https://github.com/JC-000/c64-wireguard/pull/67) moved it to `$8A` and vacated `$88` (merged 2026-08-27, `8088c43`). Builds before the `$FFFF` exclusion emitted it on idle polls, meaning "nothing pending". |
| `$8B` | `UCI_ERR_BAD_READ_HDR` | Stream-family counterpart of `$8A`, likewise **unobserved and reserved defensively**: a non-sentinel header above the request on a byte stream — the adapter caps its copy at the request (the remainder stays queued; nothing is lost), returns C=0, and leaves this code as a breadcrumb so a post-mortem can tell an undocumented header from a normal read. Same observation as `$8A`, different disposition: a stream adapter never emits `$8A`, a datagram adapter never emits `$8B`. Cheap insurance against a device that has already returned a sentinel where a count was expected. | **advisory** (C=0) | c64-https — **in flight** ([c64-https#143](https://github.com/JC-000/c64-https/pull/143)) |
| `$8C` | `UCI_ERR_SEND_TOO_LONG` | `net_udp_send_len` exceeds `NET_UDP_SEND_MAX` (§13.3): the datagram is larger than one `SOCKET_WRITE` can carry. The adapter refuses **before writing anything** rather than splitting, because on a connected UDP socket each write emits its own datagram — a split is several malformed packets, not one long one. Send-side mirror of `$8A`, and unlike `$8A` it has an observable trigger: measured on U64E fw 3.15 (2026-08-27), an adapter chunking at 800 B put `[800]`, `[800, 200]`, `[800, 652]` on the wire for 900/1000/1452 B sends, C=0, `net_last_error = $00`, peer dropped every fragment. Ceiling on that firmware is 892 (`command_length` saturates at 895 in `command_protocol.vhd`, minus 3 header bytes). | terminal (C=1) | c64-wireguard ([#141](https://github.com/JC-000/c64-lib-contract/issues/141), filed before use — the second allocation under the rule, the first with an observable trigger) |

`$FFFF` is called out in the `$8A` row because it is the trap both adapters fell into independently: an empty read, reported as a framing violation — and, once, used as a copy count. The portable lesson is not "the firmware over-claims" (nothing measured shows that it does) but **exclude the sentinel before any length arithmetic, and never let a device-supplied count be the only bound on a store loop**. The `$8A` row is worded by disposition rather than by transport on purpose: the same device event is recoverable on a stream and terminal on a datagram, and a table that said only "claimed more than requested" was about to give the byte two operational meanings in two UCI-family adapters — the `$88` failure one row down, caught by the cross-repo view a second time inside one release cycle. The table earns its keep by forcing that question before a byte is emitted. The ip65 codes name the adapter entry point that failed rather than a driver cause, because the ip65 driver reports only a carry. Not every backend emits every code in its family's table (`c64-https`'s UCI adapter reserves `$8A` without emitting it yet); a consumer decoding the byte uses the table, not the emitting adapter's header.

### 13.3 Buffer ownership and 16-bit-safe lengths

Rx buffers are **consumer-owned**: the consumer's cfg places them; the backend imports the symbols. This keeps placement decisions per-consumer (the same reason §8.1 pins shape, not address).

**TCP rx ring** (`NET_FAMILY_TCP`):

| Symbol | Kind | Semantics |
|---|---|---|
| `tcp_recv_buf` | equate | Ring base address. |
| `TCP_RECV_MASK` | equate | Ring size − 1. MUST be a power-of-two minus one: `.assert (TCP_RECV_MASK & (TCP_RECV_MASK + 1)) = 0`. |
| `tcp_recv_head` | data, 2 B | Consumer read position (16-bit, masked). |
| `tcp_recv_tail` | data, 2 B | Backend write position (16-bit, masked). |
| `tcp_recv_overflow` | data, 1 B | Set to 1 by the backend when the ring fills; the backend then drops. Consumers SHOULD surface it in diagnostics. |

The backend appends at tail; the consumer drains at head; empty iff head = tail (16-bit compare).

**UDP rx buffer** (`NET_FAMILY_UDP`): `udp_recv_buf` (consumer-sized), `udp_recv_len` (2 B), `udp_recv_ready` (1 B flag). The backend copies one datagram and sets `udp_recv_ready`; the consumer clears it after draining. Delivery while `udp_recv_ready` is still set is backend-defined in v0.6.0 (the current adapter overwrites); a future revision may tighten this to drop-while-ready — flagged as an open point rather than silently divergent.

**Datagram ceilings are published by the backend (v0.12.0, normative).** A UDP backend ships a header, `net_caps.inc`, alongside `net_abi.inc`, carrying two assemble-time equates (a header, never `.export`ed, for the same reason as §13.0's `NET_FAMILY_*`: `.res` sizing and `.assert`s need the values at assembly time):

```asm
; src/net/<backend>/net_caps.inc — the backend's published ceilings.
NET_UDP_SEND_MAX = 892    ; largest net_udp_send_len the backend accepts; larger fails C=1.  Floor: U64E fw 3.15 (895-byte command saturation)
NET_UDP_RECV_MAX = 893    ; largest datagram net_poll delivers whole into udp_recv_buf.  Floor: U64E fw 3.14d (894 hangs); 1472 if 3.15+ only
```

The two values are **adapter guarantees, not firmware facts**: each is the bound the backend holds on *every* device and firmware the build claims to support, so a backend that supports several firmware revisions publishes the minimum across them, and a build that drops an older firmware from its support matrix may raise a value. The header SHOULD state which firmware floor each value assumes. Backend obligations: a `net_udp_send` with `net_udp_send_len > NET_UDP_SEND_MAX` MUST fail C=1 with a family code (UCI: `$8C`) **before any byte reaches the device** — a backend MUST NOT split one datagram across several device writes (on a connected UDP socket each write is its own datagram, so a split is several malformed packets, not one long one) and MUST NOT truncate a send; and the backend MUST size its own read request so that a datagram of at most `NET_UDP_RECV_MAX` bytes is never truncated on any supported firmware. The two ceilings are independent and MAY differ — on the UCI family they do, in both directions across firmware revisions — so the contract names two numbers, never "the UDP ceiling". Consumer obligations: derive any protocol MTU as **`min(NET_UDP_SEND_MAX, NET_UDP_RECV_MAX) − own framing`** for a symmetric protocol (or from the matching side alone for a one-directional one), and `.assert` at assembly time that the largest datagram it builds (MTU plus its framing) is ≤ `NET_UDP_SEND_MAX` and that the equate it sizes `udp_recv_buf` from is ≥ `NET_UDP_RECV_MAX` — the asserts are against the consumer's own size equates, since a `.res` in another translation unit has no size ca65 can see; a consumer MUST NOT derive these from adapter-internal equates (the layering inversion §13.1 retired for `wg_peer_ip`). A consumer MAY pin its MTU **below** what the backend's ceilings allow — for RAM, protocol, or policy reasons — by folding its own cap into the minimum (`min(NET_UDP_SEND_MAX, NET_UDP_RECV_MAX, <consumer cap>) − framing`); the §13.8 asserts remain the *upper* bounds. A lower MTU does **not** relax the receive-buffer obligation: the backend still delivers any datagram up to `NET_UDP_RECV_MAX` whole, and a peer is not bound by this consumer's MTU, so `udp_recv_buf` MUST still hold `NET_UDP_RECV_MAX` bytes. §13.8 makes both equates mandatory. Future ceilings (a stream window, a socket count) join the same header under the same `NET_<TRANSPORT>_<THING>_MAX` pattern rather than a second file.

**Oversized datagrams are truncated silently (measured, scoped by firmware).** The measurement record behind the mechanism above. Every number below is a property of the named firmware on the named device, recorded as evidence; none is a contract constant — the contract constant is whatever the backend publishes in `net_caps.inc`.

- *Receive, U64E fw 3.14d.* A datagram larger than the `SOCKET_READ` request is delivered as exactly the requested length and the remainder discarded, the header reporting the delivered count (600-1280 B datagrams against a 512 B request: `rx_len` 512, header `$0200`, no flag, no error); a datagram that fits arrives whole with the header reporting its true length. **The request ceiling is a firmware constant, not 512**: `CMD_MAX_REPLY_LEN` = 896 minus the 2-byte header gives 894 (root-caused on GideonZ/1541ultimate#802; 512-893 B datagrams arrive whole in one poll). The 512 that both consumers carried was c64-wireguard's own Phase 3 MVP constant, measured back as a hardware limit because nothing larger had been asked for; a 1024 B request is rejected with `82,PARAMETER(S) OUT OF RANGE` on the STATUS channel, which an adapter that drains STATUS without reading never sees. **Never request exactly 894 on 3.14d**: the 896-byte reply exactly fills the response queue, the FPGA holds the pointer at the last byte with DATA_AV asserted, and the queue repeats forever — so a backend whose support matrix includes 3.14d can publish no more than 893 without violating the never-truncated obligation above. A truncated 1280 B datagram and a complete 512 B one are byte-identical in every register the adapter can read, so on this firmware **no read-time check can detect truncation**; a truncated datagram reaches the consumer looking intact and fails its AEAD, presenting as an authentication failure indistinguishable from corruption or an attack, with the cause three layers down. The MTU pin is the only defence on 3.14d.
- *Receive, U64E fw 3.15* (`update_v3.15-74-g6b5ffc21`, measured 2026-08-27 by c64-wireguard, [#142](https://github.com/JC-000/c64-lib-contract/issues/142)). Replies are multi-block (`Data More`, GideonZ/1541ultimate#806) and a datagram of up to **1472** B is delivered whole across blocks. Upstream's guard now refuses a 894 B request instead of hanging. #806's `04,DATAGRAM TRUNCATED: <true length>` status line is the right design for reporting truncation — a status, not a repurposed header field that existing clients parse; a backend on a firmware that reports it MAY detect truncation and then the disposition is drop, §13.2 `$8A`. Whether a given build publishes 893 or 1472 is a support-matrix decision, not a measurement one.
- *Send, U64E fw 3.15* (same measurement, [#141](https://github.com/JC-000/c64-lib-contract/issues/141)). One `SOCKET_WRITE` is one `lwip_send` on a `SOCK_DGRAM` socket — one datagram — and there is no command-direction multi-block, so the outbound ceiling is hard: the command buffer is 896 B but `command_protocol.vhd` saturates `command_length` at 895, and 895 − 3 (target, command, socket id) = **892** (`860 → [860]`, `892 → [892]`, `893` splits). An adapter that chunked at 800 B put `[800]`, `[800, 200]`, `[800, 652]` on the wire for 900/1000/1452 B sends with C=0 and `net_last_error = $00` — silent in every case, which is why `$8C` exists and why the refuse-before-write rule is a MUST. `WRITE_SOCKET_MORE` (GideonZ/1541ultimate#802) would raise this to ~1440 on a later firmware; a backend adopting it raises `NET_UDP_SEND_MAX` in its header and every consumer's `.assert` re-checks.
- *Reference consumer values.* c64-wireguard pins `WG_MTU = 860` = 892 − 32, send-bound under either receive ceiling (it was 480 while the cap was believed to be 512, and 861 while 893 was believed to bound both directions).

Two traps for anyone touching a length cap, both measured: (1) a guard of the shape `cmp #>CAP` / `bcc ok` / `bne bad` / `lda lo` / `beq ok` accepts the equal-high-byte case only when the low byte is zero — correct for `$0200`, silently wrong for `$037D` (it dropped legal 800-893 B datagrams and reported `$8A`, which reads exactly like firmware misbehaviour); use a full 16-bit subtract. (2) A conformance test around a cap SHOULD find the accepted length by bisection rather than hard-coding it, which is what would have caught (1) and the 512 misreading alike — and, measured the other way, a send-side test SHOULD count datagrams on the wire, not bytes accepted by the adapter. §13.2's `$8A` names the disposition if a device reports an over-claim or truncation; it is not a substitute for the pin.

**16-bit-safe lengths (normative).** Every rx copy path and every send path MUST handle 16-bit lengths in full. **Failure mode this prevents:** the original `c64-https` ip65 rx callback truncated `cb_remaining` to 255 when the high byte was nonzero while the driver ACKed the full length — every TLS record over 255 B was silently partially delivered, and record reassembly glued a prefix of record N onto bytes of record N+1 (fixed in c64-https PR #27). The bug class is a one-byte-register habit on a two-byte quantity; the contract makes the 16-bit obligation explicit so review catches it.

### 13.4 Bounded waits (wall-clock, never cycle-counted)

Any adapter loop that waits on device state (status registers, response drains, data-available flags) MUST bound the wait using a **wall-clock time source** — CIA TOD or timer — and MUST NOT use cycle-counted iteration budgets. On expiry: C=1, `net_last_error` = the backend's timeout code (UCI-family: `UCI_ERR_WAIT_TIMEOUT`).

**Failure mode this prevents.** Per-iteration cost scales with CPU clock while device-side operation durations do not. A cycle-counted budget tuned at 1 MHz collapses at 48-64 MHz turbo: `c64-https`'s abandoned `feat/net-drain-abi` branch split waits into fast/long tiers with cycle budgets and broke DHCP at turbo for exactly this reason. The unbounded alternative is worse — a wedged device converts to a wedged C64 (a real UCI FPGA wedge during CertificateVerify recv turned into a 1843 s test-sentinel timeout before the bounded conversion).

The reference implementation is `c64-https`'s `uci_wait_idle`: sample CIA1 TOD at entry (read order HOUR→MIN→SEC→TENTHS to latch/unlatch), re-read TENTHS per spin pass, bail after a fixed number of transitions (~5 s default), state in SMC bytes where the adapter's no-ZP convention requires it. Consumers running at non-standard clocks get the same wall-clock bound for free.

### 13.5 Zero-page discipline

ZP save/restore around driver calls (e.g., preserving crypto ZP `$02-$1B` across ip65 calls whose callback fires mid-`ip65_process`) is **adapter-internal**. A backend MUST NOT export save/restore helpers as public surface — a consumer calling them out of order corrupts either the driver's or its own ZP state in ways that surface layers away from the cause. (`c64-wireguard`'s exported `net_save_zp` / `net_restore_zp` predate this rule; retiring them is a §13.8 intake item.) Backends declare their ZP claims per §2 like any other library.

### 13.6 Device timing fences (UCI family)

The UCI FPGA requires a minimum interval between consecutive register accesses regardless of CPU clock. At stock 1 MHz the bus cycle time satisfies it naturally; at turbo (4-64 MHz) the CPU outruns the FPGA, producing double-latched writes and stale reads that corrupt the command protocol — the signature is *silent* command loss (command accepted, no error bit, nothing on the wire; typically surfacing as `UCI_ERR_NO_SOCKET` on the first `TCP_CONNECT`).

Conformance requirement for UCI-family backends: every register access is fenced, and the fence duration MUST meet the **empirically-bracketed floor across all supported devices**, not a single device's datasheet-ish number. The measured record, normative until a backend re-brackets it: the U64E needs ~38 µs; the C64 Ultimate ("Starlight", firmware 1.1.0/core 1.49) needs more, and its floor only bites under sustained `CMD_DATA` bursts — bracketed at 64 MHz as **51.6 µs FAIL / 62.9 µs PASS**. The reference parameters (`UCI_FENCE_OUTER = 5`, `UCI_FENCE_INNER = 217`, ≈85 µs at 64 MHz, ~35 % margin) are safe on both devices at every supported speed. The floor has a cost that scales with read size: every data byte read carries a fence, so at stock 1 MHz `INNER = 217` is ~5.45 ms per byte and an 893-byte read is seconds of wall clock (negligible at turbo). That is a real tension between §13.6 conformance and any stock-speed configuration; the resolution is to size reads for the clock, never to shrink the fence. Fence parameters are adapter-internal — consumers never see them — but shipping a fence below the bracketed floor is a conformance failure even if it happens to pass on one device: that is precisely how the U64E-era `INNER = 100` fence survived until the C64 Ultimate arrived.

### 13.7 Fixed-address blob backends

Some backends front a **position-linked driver blob** rather than relocatable code: the ip65 stack is prelinked to load at a fixed base (`$2000`, ~6.95 KB) with a fixed BSS span (`$4000-$4F8B`) and its own ZP claim (`$02-$1B`). This is the one part of a network backend that can never satisfy §4's segment-relocation model — ld65 places the blob as an opaque `.incbin`, not by segment name.

A blob-backed backend MUST declare its fixed footprint as exported equates so consumer cfgs can compose around it at assemble time:

```asm
; src/net/<backend>/net_manifest.s (continued)
.export LIB_NET_IP65_BLOB_BASE, LIB_NET_IP65_BLOB_SIZE
.export LIB_NET_IP65_BLOB_BSS_BASE, LIB_NET_IP65_BLOB_BSS_SIZE
LIB_NET_IP65_BLOB_BASE     = $2000
LIB_NET_IP65_BLOB_SIZE     = $1B27          ; refreshed per blob rebuild
LIB_NET_IP65_BLOB_BSS_BASE = $4000
LIB_NET_IP65_BLOB_BSS_SIZE = $0F8C
```

**Relocation is a relink, not a cfg edit.** The blob is produced by a scripted ld65 relink of the driver's object libraries against a stub + cfg (`c64-https`'s `make ip65-blob` is the reference). A consumer whose memory map cannot host the default base regenerates the blob at its own base by parameterizing that build; the declaration equates above then change with it, and every consumer-side fit `.assert` re-checks automatically. Contrast with §4 libraries, where the consumer moves bytes by editing its own `SEGMENTS{}` block — for a blob backend the consumer moves bytes by rebuilding the blob.

### 13.8 Conformance asserts and consumer intake

Each consumer ships a `net_abi_asserts` translation unit (mirroring the §3/§8.0 checks in `c64-wireguard`'s `src/contract_asserts.s`) asserting at least:

```asm
.include "net_families.inc"
.import NET_BACKEND_FAMILIES
.assert (NET_BACKEND_FAMILIES & NET_FAMILY_CORE) = NET_FAMILY_CORE, lderror, "backend missing core family"
.assert (NET_BACKEND_FAMILIES & NET_REQUIRED_FAMILIES) = NET_REQUIRED_FAMILIES, lderror, "backend missing a family this consumer needs"
.assert (TCP_RECV_MASK & (TCP_RECV_MASK + 1)) = 0, error, "TCP ring mask must be 2^n - 1"   ; TCP consumers only
; UDP consumers only (§13.3): the backend's net_caps.inc is mandatory, and buffers are sized from it, never
; from adapter internals. UDP_RECV_BUF_SIZE / MY_MTU / MY_FRAMING stand for the consumer's own equates
; (c64-wireguard: WG_MTU, WG_DATA_OVERHEAD = 32, and the .res size of udp_recv_buf; the asserts must target the equate, not the label).
.include "net_caps.inc"
.assert NET_UDP_SEND_MAX >= 1, error, "backend must publish NET_UDP_SEND_MAX (SPEC 13.3)"   ; guards a header that defines but never sets
.assert NET_UDP_RECV_MAX >= 1, error, "backend must publish NET_UDP_RECV_MAX (SPEC 13.3)"
.assert UDP_RECV_BUF_SIZE >= NET_UDP_RECV_MAX, error, "udp_recv_buf smaller than the backend's receive ceiling"
.assert (MY_MTU + MY_FRAMING) <= NET_UDP_SEND_MAX, error, "outbound datagrams would be refused ($8C) or, on a non-conformant backend, silently fragmented"
.assert (MY_MTU + MY_FRAMING) <= NET_UDP_RECV_MAX, error, "inbound datagrams at MTU would be silently truncated"
```

`net_caps.inc` is per-backend (`src/net/<backend>/`), unlike the shared `net_families.inc`, so backend selection MUST also select the include path (`-I src/net/<backend>`) — the consumer's `.include "net_caps.inc"` must resolve to the *linked* backend's header, never another backend's. A UDP-family backend that ships no `net_caps.inc` is non-conformant from v0.12.0: the `.include` fails the consumer's build, which is the intended failure — loud at assembly, not a stale local constant that fails as an AEAD error on hardware.

**Intake status (updated v0.12.0)** — known non-conformances, tracked as per-consumer alignment issues:

| Consumer | Items |
|---|---|
| `c64-https` ([#70](https://github.com/JC-000/c64-https/issues/70)) | **Aligned in [c64-https#142](https://github.com/JC-000/c64-https/pull/142)** (merged 2026-08-27, `95daa69`, closing c64-https#70; verifiable on `master`, not yet at a tag): `net_abi.inc` is `.include`d by every network-touching TU and imports the full core/TCP/DNS surface; ip65 grew `net_dhcp_acquire`, `net_local_ip`, `net_resolved_ip`, `net_last_error` (codes `$41-$45`, table above) and `net_tcp_state`; `net_tcp_set_recv_cb` deleted, `NET_TCP_*` names adopted, `net_print_ip` moved consumer-side; both backends ship `net_manifest.s` (ip65 with §13.7 blob equates link-asserted against the `.incbin` size) and the consumer ships `net_abi_asserts.s`. UCI now sets `tcp_recv_overflow` (§13.3). |
| `c64-wireguard` ([#48](https://github.com/JC-000/c64-wireguard/issues/48)) | **Largely landed in [c64-wireguard#67](https://github.com/JC-000/c64-wireguard/pull/67)** (merged 2026-08-27, `8088c43`; device-verified on U64E fw 3.14d and 3.15): the rename, carry semantics, un-export, `net_udp_dest_*`, the `$8A` move, bounded waits, the fence floor, the phantom-socket guard, `net_udp_close`. Deliberately deferred by that PR: `net_manifest.s` + `net_abi_asserts` (ip65 backend exports neither `net_local_ip` nor `net_last_error`, so a core-family assert would link green over an absent error channel — fix the backend first), and the §13.3 `net_caps.inc` header (follow-up, baseline fw 3.15+: `NET_UDP_RECV_MAX = 1472`, `NET_UDP_SEND_MAX = 892`, `WG_MTU = 860`). Original item list, kept for the record: rename `net_dhcp` → `net_dhcp_acquire`; retire `net_poll`'s "C=0 = packet" meaning (§13.2); un-export `net_save_zp`/`net_restore_zp` (§13.5); replace `wg_peer_ip`/`wg_peer_port` reads in the adapter with `net_udp_dest_ip`/`net_udp_dest_port` — **not a mechanical rename outside the adapter**: any host-side tool or test that calls `net_udp_send` directly becomes responsible for staging those cells, and one that stages only `wg_peer_*` **fails silently**: it sends to `0.0.0.0` with carry clear and `net_last_error` zero, i.e. it looks exactly like a working send (measured; it got past a 22-suite gate and four live tools at once and cost two device runs on hardware with ~5 good cycles per power-up — the dangerous failures are the ones that present as success, as with §13.3's silent truncation); rename send globals to `net_udp_send_ptr`/`net_udp_send_len`; **resync the UCI adapter with `c64-https`'s hardened one** (bounded waits §13.4, fence floor §13.6, phantom-socket detection — its `uci_errors.inc` predates `$88`/`$89`); ship `net_manifest.s` + `net_abi_asserts`. |

The resync item is the payoff case for this chapter: those fixes exist because real hardware wedged, and the contract's job is to make them travel.

## 9. Compatibility timeline

- **2026-05-20 — v0.1.0.** Contract published with the six core sections (§1–§6); adopters land iteratively. Tracking issues filed against each adopter library.
- **2026-05-20 → 2026-06-20 — v0.2.0–v0.4.0.** Additive growth: §7 semver expectations and §8 shared primitives (§8.0 precalc-table enumeration, §8.1 `sqtab`, §8.2 `reu_mul`, §8.3 `ct_mul_8x8`). See §12 for the per-release detail.
- **2026-07-28 — v0.5.0.** Additive: §8.0/§5 three-state build-config semantics for shared primitives (owner / deferring consumer / non-consumer) plus the companion `LIB_<X>_SHARED_CONSUMES` mask and its consumer-side coverage assert.
- **2026-08-12 — v0.6.0.** Additive: §13 network backend ABI — the first non-cryptographic chapter, standardizing the symbol surface and device-timing semantics both consumers had independently forked for their ip65/UCI networking adapters.
- **2026-08-12 — v0.7.0.** Additive: library-prefixed §1 version exports and §8.4 precalc-table equates, resolving the two-library manifest-import collision ([#43](https://github.com/JC-000/c64-lib-contract/issues/43)). The unprefixed forms stay required and gated behind `LIB_NO_BARE_EXPORTS` until v1.0 removes them.
- **v1.0 — target: when all current adopters (see [adopters.md](adopters.md)) have landed every applicable section, core and shared-primitive.** Contract is then stable; breaking changes go through a deprecation cycle.

The v1.0 cutover triggers a coordinated tag bump (every adopter to `LIB_ABI_VERSION = 1`) so consumers can pin against `LIB_ABI_VERSION >= 1` and know the full contract surface is present.

## 10. Adopters

See [adopters.md](adopters.md) for the status table and tracking issues per library.

## 11. Consumers

See [consumers.md](consumers.md) for the list of consumer projects relying on this contract.

## 12. Changelog

### 0.12.1 — 2026-08-27

Clarifying (PATCH): **§13.3 says a consumer MAY pin its MTU below the backend's ceilings, and that doing so does not shrink the receive buffer.** Raised by the first §13.3 implementation (c64-wireguard#68): the ip65 backend honestly publishes 1472/1472, and a consumer deriving MTU purely from the backend's pair would size buffers it cannot afford. The consumer folds its own cap into the minimum; the §13.8 asserts stay as upper bounds; `udp_recv_buf` still holds `NET_UDP_RECV_MAX` because the backend delivers up to that whole and the peer is not bound by this consumer's MTU. No wording in §13.8 changes.

### 0.12.0 — 2026-08-27

Normative (MINOR): **§13.2 gains an error-code allocation table and an allocate-here-first rule.** The v0.6.0 text carved `net_last_error` into family ranges and grandfathered `$81-$89`, but a family range is one namespace across every consumer's adapter of that family, and nothing said who allocates the next value. The gap was not a near-miss; it was a collision that had already happened: `c64-wireguard` PR #62 (merged 2026-08-20, the unbounded-read fix) allocated **`$88`** for `UCI_ERR_LONG_READ`, while c64-https had emitted `$88` as `UCI_ERR_NO_SOCKET` since issue #36 — one byte, two meanings, on the one device family where both conditions arise, unnoticed across two repos for four days. **Neither side violated §13.2 as written**: both are UCI-family backends emitting from the UCI range. Taking c64-https's table verbatim would have redefined a code `c64-wireguard` emits during healthy fw 3.14d operation into a phantom-socket report; `c64-wireguard` instead moved to `$8A` on 2026-08-24 ([c64-wireguard#67](https://github.com/JC-000/c64-wireguard/pull/67), merged 2026-08-27) and the c64-https §13 alignment ([c64-https#142](https://github.com/JC-000/c64-https/pull/142)) is where the cross-repo comparison finally surfaced it ([#137](https://github.com/JC-000/c64-lib-contract/issues/137)). "Both conformant, still colliding" is the argument for a registry: the clause now carries the table — ip65 `$41-$45` (c64-https), UCI `$81-$8C` — and the rule that codes are allocated in the table first, then in the adapter, and never reassigned. The `$8A` row was marked in flight until c64-wireguard#67 published the move; it merged the day this release was finalised, ending the collision on `master`. Its **meaning** went through a second correction before this entry was final: c64-https ported c64-wireguard's drop-on-over-claim check to its TCP `net_poll` and it aborted every real handshake at the first read — fw 3.14d's `$FFFF` header is its no-data sentinel on both transports, and both adapters had misfiled it as an over-claim (c64-https#140; c64-wireguard's own "fires routinely during healthy sessions" runbook line) — so the rows now name the sentinel, require excluding it before any length arithmetic, state the disposition per transport, and mark the over-claim condition itself as unobserved and reserved defensively: after the exclusion there is no measured non-sentinel over-claim on either transport, and the founding `$D000` overrun is explained in full by 65535 used as a copy count from an idle poll. The oversized-datagram UDP header was then measured (delivered count, `$0200`, never the true size), which retired the row's "the adapter drops it" clause: truncation is silent and undetectable at the ABI, the consumer's MTU pin is the sole defence, and §13.3 now says so. A second correction from the same lane then moved the ground: the 512 B read cap was c64-wireguard's own constant, not the firmware's — the real ceiling is 894 (`CMD_MAX_REPLY_LEN` − 2, never request exactly 894 on 3.14d), a fitting datagram's header is its true length, and only genuinely oversized datagrams are silently truncated; §13.3 recorded the cap, the 894 hang, an MTU pin at 861, and two cap-testing traps, and §13.6 records the fence-cost tension at stock speed — and the next paragraph records why those numbers were then demoted from rule to evidence. The two transports are not uniform — sentinel on TCP, count on UDP — and each adapter had generalised from its own to the other. The lesson that travels is *exclude the sentinel before any length arithmetic, and never let a device-supplied count be the only bound on a store loop* (stream: cap, recoverable, no code; datagram: drop, this code). Two adapters were about to give one byte two operational meanings, in the same release cycle as the `$88` collision; the registry caught it before either merged, which is the strongest evidence in this entry that it is the right mechanism.

Three classes of code are named because the release is the reason they differ: `$81-$89` predate the clause and are grandfathered unchanged; `$8A` was allocated to resolve the collision (published in c64-wireguard#67); `$8B` is the first allocated through the rule before emission. §13.2 also gains a third refinement — **advisory codes**: a nonzero `net_last_error` with C=0 is legal for observations (`$87`, `$8B`), C is the success signal, and the table marks which codes are advisory so a decoder can tell. Classified MINOR because the table and the advisory refinement are new normative content rather than a restatement; the range carve-up, bit values and every previously allocated code are unchanged, so no conformant adapter is affected.

Also in this release: **§13.0's manifest snippet exports `NET_BACKEND_FAMILIES : absolute`** — required, since the byte-sized mask otherwise infers `zeropage` and ld65 warns on every composed link (#140, the #58 defect recurring one chapter over; measured on V2.18 with the two snippets unmodified). **§13.0 names a canonical copy source** — [`net_families.inc`](net_families.inc) at the repo root, the byte-for-byte file adopters copy, mirroring `precalc_table.inc` for §8.0; `make verify` now assembles it standalone, asserts the four values, and fails if the fenced block's values drift from the file (`verify-net-families`), so the polyval#18 transcribed-from-the-block defect cannot recur here. **§13.8's intake table records c64-https as aligned in c64-https#142** (merged 2026-08-27, `95daa69`).

**§13.3 becomes firmware-agnostic: backends publish their datagram ceilings.** The draft of this release carried the UCI read ceiling (894, request at most 893), a consumer MTU (861), and the sentence "upstream's guard refuses 894 only from firmware 3.15, which is not downloadable" as normative text. Three days later fw 3.15 was on a fleet device and every one of those numbers was wrong for it: 3.15 receives 1472 B via multi-block replies and refuses 894 cleanly, while its send ceiling is 892 — lower than the read ceiling, and hard, because one `SOCKET_WRITE` is one datagram ([#141](https://github.com/JC-000/c64-lib-contract/issues/141), [#142](https://github.com/JC-000/c64-lib-contract/issues/142)). The numbers were the UCI adapter's ceilings on one firmware, generalised into contract constants by the same shape of error as `$FFFF` and 512 above: a measurement written into the same sentence as the rule it justified. The fix is structural, not a re-measure. §13.3 now requires a UDP backend to ship `net_caps.inc` with `NET_UDP_SEND_MAX` / `NET_UDP_RECV_MAX` as **adapter guarantees** (the minimum across the firmware the build supports, stated in the header), obliges the backend to refuse an over-size send before touching the device and never to split or truncate one, obliges the consumer to derive MTU as `min(send, recv) − framing` and `.assert` both buffers against the header, and §13.8 makes the header mandatory. The measurement record — 894 hang, 512 misreading, `$0200` header, 892 saturation, the two cap-testing traps — is kept in full as evidence, every number scoped to the firmware it was measured on, and the contract no longer asserts anything about which firmware exists. `$8C UCI_ERR_SEND_TOO_LONG` joins the table (c64-wireguard, filed before use — the second allocation under the new rule and the first with an observable trigger), and the `$8A` row records that a firmware reporting `04,DATAGRAM TRUNCATED` makes its condition reachable without changing its meaning. Consumer reference values as of this release: c64-wireguard `WG_MTU = 860` (send-bound under either receive ceiling). A firmware move that changes a ceiling now changes one header line in one backend and re-fires every consumer's assert; it does not require a contract release.

### 0.11.1 — 2026-08-23

Doc/clarification (PATCH): **§6.3 states which consequence its select-or-reject rule carries in which case.** The v0.10.5 rule ends at "select that axis ... or reject the invocation loudly" and leaves the adopter to derive which of the two it owes. Four libraries have now answered it in code, and the answers split cleanly along the member-set/configuration line the v0.10.4 paragraph already draws: a knob value the target *cannot* honor is rejected at parse time (polyval), and one it *can* honor invalidates whatever it reconfigures (nist-curves, chacha, x25519). The clause now says so, adding no new axis taxonomy — it routes the existing one to a second consequence.

Classified PATCH: an adopter conformant with the v0.10.5 rule was already forbidden from exit-0 emission of an artifact the knob did not request, and staleness is that rule applied to a warm tree rather than a clean one. Every conformant library already owed one of these two behaviours; what was missing was any statement of which, so this is the "zero normative change" v0.10.1 sets as the PATCH line. The contrary reading is recorded rather than hidden: the paragraph contains RFC-2119 `MUST`s, and a reader who takes the invalidation duty as newly imposed rather than newly *named* would classify it MINOR, as v0.11.0 did for its two `SHOULD`s.

The prompting measurement ([chacha#86](https://github.com/JC-000/c64-ChaCha20-Poly1305/issues/86), [#127](https://github.com/JC-000/c64-lib-contract/issues/127)) is worth keeping because it refutes the natural reading of v0.10.5: `c64-ChaCha20-Poly1305` has **no** `<LIB>_PROFILE` make variable — its profile axis rides `CONTRACT_DEFINES` directly — so it satisfied the knob-*naming* half vacuously and carried shape 3 regardless. `make lib CONTRACT_DEFINES="-D POLY1305_PROFILE_LONG=1"` over a warm tree answered "Nothing to be done", exited 0, and shipped the Profile B archive (18 `_PRECALC_` exports against Profile A's 24); the identical command against a clean tree built Profile A correctly, so §6.3 ¶1 reachability was never at issue. Both remediations the fleet had at the time were parse-time `$(error)` guards on a `<LIB>_PROFILE` variable, and neither would have touched it.

Two properties of the invalidation branch are stated because a guard missing either is worse than none — unchanged knobs must not rebuild, and the pinning check must assert the artifact flipped rather than that something rebuilt. A check with only the change-rebuilds legs passes on a guard that has quietly degraded to an unconditional rebuild.

**No adopter row changes.** `c64-nist-curves` and `c64-ChaCha20-Poly1305` are on the invalidation branch on `main`; `c64-x25519` is in flight ([#110](https://github.com/JC-000/c64-x25519/pull/110)); `c64-polyval` is on the rejection branch for its member-set axes and has the configuration-axis branch outstanding for the defines it correctly still accepts (`LIB_NO_BARE_EXPORTS`, `ZP_CONFIG_NO_EXPORTS`). `c64-mlkem` is unassessed against this paragraph.

### 0.11.0 — 2026-08-22

Normative (MINOR): **§6.5 gains a zero-consumer carve-out for archive member basenames.** The clause defers the `<shortname>_` prefix to each library's next MAJOR, and the reasoning is entirely about installed base — a member cannot carry two names at once, so a library someone already extracts from has to wait for a breaking release to rename. That reasoning does not reach a library nobody has linked yet, and the clause previously had no rule for one: it would have joined the unprefixed pile-up on day one and immediately started waiting for its own MAJOR to leave it. §6.5 now says such a library SHOULD be born prefixed instead.

Classified MINOR rather than PATCH because this is new normative text — an RFC-2119 `SHOULD` in a clause that previously carried only the MAJOR-deferral `MUST`, governing a class of libraries that had no rule at all. It is not the "zero normative change" that v0.10.1 sets as the PATCH line, even though it is additive and relaxes nothing for any existing adopter. Surfaced during the [#123](https://github.com/JC-000/c64-lib-contract/pull/123) intake review, where it was initially folded into that registry PATCH and split out for exactly this reason.

The scope test is deliberately checkable rather than asserted: "no released consumers" means no tagged release that any consumer pins, verifiable from the library's own tags and `consumers.md`. A library that has cut a release someone links falls back to the MAJOR rule.

**No existing adopter is affected.** All four incumbents have released consumers and stay on the MAJOR path; the four unprefixed `lib_version.o` / `lib_manifest.o` claimants are unchanged. The first library on the new path is `c64-mlkem`, registered in v0.10.7, which had already shipped prefixed members before this clause existed — the clause generalises a decision made under review rather than inventing a practice with no adopter.

Normative (MINOR): **§1 gains a zero-consumer carve-out for the deprecated bare version exports.** The `MUST also export` is justified in its own sentence as protecting *existing* single-library consumers; a library nobody has linked yet has none, so the export buys no compatibility and adds a further claimant to the four names behind [#43](https://github.com/JC-000/c64-lib-contract/issues/43). Such a library SHOULD NOT export them, and is thereby born in the state every other library reaches at v1.0. `SHOULD NOT` rather than `MUST NOT`: the forms stay harmless in a single-library link and uniformity with the incumbents is a legitimate preference. The ungated-export prohibition is untouched.

Two measurements motivated this rather than the argument alone. **No consumer in the fleet imports the bare forms** — `c64-https`, `c64-wireguard` and `c64-e2ee-chat` between them make zero bare `.import`s against five prefixed ones, so the compatibility the MUST protects is already unexercised. And **the suppression it relies on is not uniformly applied**: one of `c64-https`' thirteen integration scripts passes `-D LIB_NO_BARE_EXPORTS=1`. That second number is why each additional claimant is a real rather than theoretical risk — the mitigation §1 points at is available everywhere and used in one place. (Whether any current composed link is latently colliding is a consumer-side question this clause does not answer.)

Same scope test as §6.5's member-basename carve-out, and the same reasoning: the deprecation window exists to protect installed base, and a library without one should start on the far side of it rather than joining and immediately waiting to leave.

### 0.10.7 — 2026-08-22

Registry (PATCH): **`mlkem_` is registered to `c64-mlkem`**, the first new adopter since the §2 ZP prefix registry existed (it was created in v0.9.0 already populated with the four incumbents, so the intake path it describes had never actually been walked). Additive and collision-free: the library's entire ZP surface is `mlkem_zp_src` / `mlkem_zp_dst` / `mlkem_zp_len` / `mlkem_zp_tmp` — 8 bytes, all under the registered prefix, checked against every existing entry per the clause's intake requirement. No obligation changes for any existing adopter. Classification follows the v0.9.2 precedent, which added `chacha20poly1305_` to this same table as a PATCH.

One consequential wording fix rides along, non-normative: §6.5's flat-namespace sentence said `lib_version.o` and `lib_manifest.o` "ship in all four adopters", which goes ambiguous the moment a fifth row exists. It now reads "ship **unprefixed** in four adopters" — still four, because `c64-mlkem` ships `mlkem_lib_version.o` / `mlkem_lib_manifest.o` from its first archive and never joins the unprefixed set. (Whether §6.5 should *recommend* that for zero-consumer libraries generally is new normative text and rides its own MINOR; it is deliberately not in this release.)

Two observations from the intake worth recording, since both concern clauses whose behaviour had only been described from the incumbent side:

**The §6.2 consumer-assembled ZP model works as advertised for a library built on it from scratch.** §6.2 calls it "the recommended shape for new libraries" on the strength of `c64-ChaCha20-Poly1305`, which arrived at it by migration; `c64-mlkem` is the first to adopt it at birth. `zp_config.s` ships in no archive, archive TUs `.importzp`, and a consumer slot override needs no library rebuild — confirmed end to end (`make CONTRACT_ZP_DEFINES="-D mlkem_zp_src=0x40"` relocates the slot, verified in the linked build's labels), and the library enforces rather than merely intends it: its `check-archives` target fails the build if the ZP-defining TU or any driver object reaches an archive. The adopter-side cost is one real constraint worth naming for the next library: the ZP-defining TU must be excluded from `LIB_OBJS` *and* included in the standalone PRG's link set, which is easy to get backwards and fails only at a consumer's link, not the library's own.

**The intake's step-6 "no tables above the floor" path had also never been exercised.** `adopters.md` requires `docs/precalc-tables.md` even from a library with nothing clearing the §8.0 floor, and `c64-mlkem` is that case: its largest table is the 192 B FIPS 202 round-constant sequence, which is hot-loop-read but 64 bytes short of the 256 B threshold, and everything else is 16–25 B. It therefore files the enumeration with rationale and emits **zero** `LIB_PRECALC_*` exports — consistent in both directions, which is what the merge gate checks. The rule read unambiguously and needed no change; noted only because the reviewer-facing half of it ("a row without the export blocks merge") is symmetric and a zero-table library sits exactly on that symmetry.

### 0.10.6 — 2026-08-15

Doc/clarification (PATCH): **§8.3 gains the provider-surface enumeration** ([nist#123](https://github.com/JC-000/c64-nist-curves/issues/123)). The clause pinned the body byte-identically and named the canonical entry, but the five names the calling convention actually needs cross-TU — `ct_mul_8x8`, the `smc_sum_a_imm`/`smc_diff_a_imm` SMC operand sites, `poly_prod_lo`/`poly_prod_hi` — were described semantically and never required as exports. Both providers export all five today by convergent necessity, not obligation; the deferring side of the same gap was measured live: `c64-nist-curves`' `SHARED_CT_MUL_8X8` gate removed the definitions without adding imports, so `-D SHARED_CT_MUL_8X8` failed to assemble against the on-chip TU and APP_OWNED × on-chip was unreachable (§6.3) — caught by the first consumer to build that combination, not by CI, which never does. The gating corollary is stated: a deferral switch MUST leave `.import`s behind for every referenced name it un-defines — the assemble-time sibling of v0.10.5's looks-reachable rule.

### 0.10.5 — 2026-08-15

Doc/clarification (PATCH), two items from [#117](https://github.com/JC-000/c64-lib-contract/issues/117). **§6.3 gains the looks-reachable clause**: the v0.10.4 paragraph adjudicated the surgery shape (consumer edits members); [polyval#40](https://github.com/JC-000/c64-polyval/issues/40) is the adjacent one the surgery ban cannot see — the axis rides a make variable that reaches every TU's flags while the target's member list ignores it, so the build *looks* reachable, exits 0, and ships an archive that is unlinkable and §6.4-incoherent through member selection alone (both §6.4 halves held per-TU; the archive was still wrong). Stated at the archive level: honor the axis in both member selection and assembly, or reject loudly at build time; silent exit-0 disagreement is non-conformant with or without a target for the combination. The stopgap/fix split is recorded ([polyval#41](https://github.com/JC-000/c64-polyval/pull/41)'s parse-time guard discharges this paragraph, not ¶1's reachability). The clause is stated as a three-shape ladder (surgery-only / incoherent artifact / **silent no-op**) with one rule covering all three — a knob naming an axis MUST select it or fail loudly — after the x25519 adopter check surfaced shape 3 live (`X25519_PROFILE=onchip` silently accepted as a no-op on `make lib` at v0.11.1) and proposed the generalization. The checkability note went through two rounds of correction, recorded so nobody re-derives it wrong: the shape-3 evidence of byte-identical archives came from make staleness (the knob reaches no prerequisite, so nothing rebuilt); the non-determinism was first attributed to `ar65` member timestamps with "compare extracted members" as the remedy — both wrong ([polyval's trace](https://github.com/JC-000/c64-lib-contract/pull/118#issuecomment-5304220047)): the stamp is `ca65`'s `OPT_DATETIME` inside every object (plus source paths/mtimes in `Files:`), unconditional on `-g`, so extraction gives no immunity, same-second rebuilds are byte-identical, and the sound comparands are linked output or `od65` structural dumps. **Correcting the v0.10.4 record**: that entry closed with "the four adopters' current target sets are untouched," which overstated — no existing archive's *claims* changed, but the clarification created a live target obligation for any library with an unreached documented member-set axis, and two adopters had one: nist ([nist#117](https://github.com/JC-000/c64-nist-curves/issues/117), since discharged in v0.11.0's comb pair) and polyval (polyval#40, open). The imprecision was flagged on [PR #115](https://github.com/JC-000/c64-lib-contract/pull/115#issuecomment-5303846693) before the merge and shipped anyway; per the tags-are-immutable convention the v0.10.4 entry stays as written and this entry is the correction, the changelog self-correcting in sequence.

### 0.10.4 — 2026-08-15

Doc/clarification (PATCH): **§6.3's no-further-matrix posture is scoped to define-reachable combinations.** [nist#117](https://github.com/JC-000/c64-nist-curves/issues/117) (filed from the c64-https side, [c64-https#119](https://github.com/JC-000/c64-https/issues/119)) surfaced an axis shape the sentence did not adjudicate: the P-256 comb verify set differs from the shipped `lib-p256-verify-onchip` by *member set* (`ecdsa256.o` without `-D ECDSA_NO_COMB`, plus `points256_comb.o`/`data_p256_limlee.o`), which no §6.2 define can produce — so the sentence discouraging new targets and the ¶1 MUST requiring reachability pulled in opposite directions, and the measured consumer resolution was the worst one: staged member surgery (§6.1-banned) whose retained full-set manifest forced a §6.6 assert exemption. The clarification states the precedence that was already derivable: documented member-set axes take a §6.1 target with per-configuration §6.4 manifest TUs; the enlarged §6.5 freeze surface is the accepted cost. No obligation changes for any existing archive — the four adopters' current target sets are untouched.

### 0.10.3 — 2026-08-15

Doc (PATCH): **§8.4 exists now.** [#109](https://github.com/JC-000/c64-lib-contract/issues/109) reported 13 dangling `§8.4` references as a v0.10.1 reorder casualty; ref-verification showed the truth is older and stranger — **the heading never existed at any tag** (structure byte-identical at v0.8.4/v0.10.0/main), while the fleet has cited "§8.4" since v0.7.0: 13 times in this document, 70+ times per adopter repo, and once inside the canonical `precalc_table.inc` itself. The catch-loop clause simply lived unnumbered inside §8.0 and every citation survived on faith. Fix: the block is promoted in place to `### 8.4 Precalc-table enumeration — the catch loop`, making every existing citation correct retroactively; the two in-body "§8.0 catch-loop registry" phrasings in §8.1/§8.2/§8.3 are swept to §8.4; the canonical `precalc_table.inc` is deliberately **unchanged** (its own §8.4 reference self-heals, its "§8.0 catch-loop" header comment is recorded as the historical spelling — zero adopter byte-identity churn). Changelog entries citing §8.0's catch loop stay as written, per the historical-record convention.

### 0.10.2 — 2026-08-15

Doc (PATCH): **§6.7's prose contradicted §8.1's export discipline** — it said the guard compares "against the imported equate," but `LIB_SHARED_SQTAB_BASE` is one §8.1 forbids anyone from exporting (measured: the import fails as an unresolved external; the wording was carried from before the v0.9.1 canonical-≠-exported ruling). Found in [#105](https://github.com/JC-000/c64-lib-contract/issues/105) by the first §6.7 adoption ([chacha#81](https://github.com/JC-000/c64-ChaCha20-Poly1305/pull/81)) — the copy-paste-facing kind, since the code block was correct but the prose sent an adopter reconciling the two to `.import`. Corrected: the base is obtained **source-level** via the same `.ifndef`-guarded header the placing TU uses, with the **single-shared-include** rule (two copies of the default can silently disagree, leaving the guard checking a different window than the table occupies) and the relocation mechanism restated (`-D` reaches placing TU and guard together — re-measured both directions). Two adoption measurements folded in: boundary exactness is bounded by the primitive's own alignment rule (page-aligned base ⇒ page-granular observation), and constraint 3 added — **prove the guard fires in the configuration that actually places the table**, since a profile-gated guard skipped by the non-placing profile passes a firing test while verifying nothing. Eighth member of the copy-paste defect class — and members nine and ten ride along from [#107](https://github.com/JC-000/c64-lib-contract/issues/107), both found by the c64-https v0.10.0 alignment, both in clauses predating the run-every-snippet practice: **§7's ABI-gate bullet restated the `.if`-on-import form** that v0.8.1 had fixed in §1 (fixed to `.assert`/`lderror` with the §1 cross-reference), and **§8.0's consumes-mask snippet used `.if ::` on an unset `-D` selector**, which fails to assemble in the adopter's own default build (fixed to `.ifdef`, matching the adjacent ownership-mask snippet — the asymmetry read as deliberate and was not). Both replacements reproduced and both-directions-tested (ca65 V2.18). The #107 suggestion of a full fenced-block assembly sweep wired into `make verify` is accepted as follow-up tooling.

### 0.10.1 — 2026-08-15

Doc-only (PATCH — structure, zero normative change): **phase 4 of [#76](https://github.com/JC-000/c64-lib-contract/issues/76), the section reordering, resolved as a stable-numbers physical reorder.** The fleet survey that decided the shape: 900+ `§8.x` references across the four adopters at their wave tags (sources, cfgs, docs, tooling) versus ≤5 `§13`/`§12` references total — so renumbering anything was never on the table. The document now reads core (§1–§7) → domain chapters (§8 crypto, §13 network) → meta (§9–§12, changelog last), with **every section number unchanged**; §0 gains the how-to-read table making the three-kinds structure explicit, and the §13 numbering note is updated to state the invariant outright: numbers are stable identifiers, not positions — new chapters take the next free number and are placed with their kind. This completes item D, the last work item of the #76 restructuring.

### 0.10.0 — 2026-08-15

Normative (MINOR — the [#76](https://github.com/JC-000/c64-lib-contract/issues/76) restructuring, phase 2). **§6.6 lands** ([#69](https://github.com/JC-000/c64-lib-contract/issues/69)): consumer footprint asserts against the per-archive §6.4 manifest — library obligations (safe-direction round-up values; RESIDENT/COLD as a pair; release-note deltas per profile × variant, since one tag carries several footprint pairs) plus the consumer pattern against `__<AREA>_SIZE__` under `define = yes`. The #62-before-#69 gate is discharged: §6.4 is verified in all four adopters' shipped archives, so the assert binds to the linked artifact — the 27 KB-declared-vs-16 KB-region false-refusal that blocked this clause pre-#62 is impossible by construction. **§6.7 added** ([#78](https://github.com/JC-000/c64-lib-contract/issues/78) item 2): declared non-segment reservations — prefer segment-resident buffers where nothing forces the equate; where §8.x placement equates reserve address space invisible to ld65, the library MUST carry the three-line `__MAIN_LAST__` guard in a never-archived TU, with the two hard constraints (guard TU in no archive; import never weak — a missing operand degrades `lderror` to a silent warning) and the verified-scope statement (ld65 V2.18, single area, `bss`-top; other shapes MUST re-measure). Consumers mirror both patterns against their own maps. **§6.5 gains the deprecated-spelling override note**: both wave alias shapes (chacha compatible-with-divergence-risk, nist loud-break) are window-conformant because both fail loudly; silent slot-splitting is the forbidden outcome; the supplies-own-slots vs assembles-library-TU consumer split recorded. All snippets assemble/link-tested both directions this session (clean link passes both guards; a BSS pad trips §6.7's; an oversized declared footprint trips §6.6's; ca65/ld65 V2.18). Sources: #69's measured c64-https evidence + the profile-pairs refinement, #78 item 2's proven remedy with its measured properties, x25519's wave-measured per-switch deltas, chacha's round-up precedent, nist#107/chacha#78's alias shapes.

### 0.9.2 — 2026-08-15

Doc/clarification (PATCH), three items from wave implementations. **§2**: every library's §6.1 `<shortname>_` prefix is registered by construction — the table now lists `chacha20poly1305_` explicitly (gap exposed by the first `<shortname>_zp_*` migration, [chacha#78](https://github.com/JC-000/c64-ChaCha20-Poly1305/pull/78)). **§8.2**: `reu_fetch_mul_row_bank_patch` is *conditionally* required — providers export it iff their fetch carries the SMC site (inline-computing providers MUST NOT synthesize one); deferrers import it iff their adjacent caches delegate through it; the unsupported pairing fails loudly as an unresolved external, documented as intended ([nist#106](https://github.com/JC-000/c64-nist-curves/pull/106)'s question). **§8.2**: import-never-stub stated precisely — the load-bearing half is no-second-canonical-definition; imports only where referenced, and an import dropped as unreferenced is conformant. Also recorded from nist#106 for the fleet: a `$(subst)`-built member list defeated `check_archives.py`'s assignment parser, so the ratchet silently inspected the wrong object set until value pins caught it — archive-inspection tooling MUST read explicit member lists or the built archive itself, never make-expressions it cannot expand.

### 0.9.1 — 2026-08-15

Two things in one PATCH, both correction-shaped. **First, recovery:** three review amendments intended for 0.9.0 were pushed to the PR branch after the merge click and silently missed main *and* the `v0.9.0` tag (the merge-event-vs-merged-content variant of the fleet's stacked-PR lesson — verify the merged tree, not the merge notification). Re-landed here: §6.5's suppression gate for colliding old forms ([#88](https://github.com/JC-000/c64-lib-contract/issues/88), `LIB_NO_BARE_EXPORTS` canonical), the §2 registry's gate note, and the §8.2 export example aliasing the code-read symbol ([nist#105](https://github.com/JC-000/c64-nist-curves/pull/105)). **Second, the four defects from the [c64-x25519 adoption report](https://github.com/JC-000/c64-lib-contract/issues/76):** (A) §8.1 "Table names" was factually wrong — x25519's `sqr_lo`/`sqr_hi` is its a² diagonal-squaring table, not a sqtab dialect; the clause now ratifies `sqtab_lo`/`sqtab_hi` as what every adopter already does, and rules that **canonical does not mean exported** (they derive from consumer input; nist's bare export becomes a gated window item). (B) §8.2's fetch-deferral surface narrowed to `reu_fetch_mul_row` + the promoted `reu_fetch_mul_row_bank_patch` SMC label (#15); the four bare buffer labels were adopter-private overreach and move to the rename track under the §2 registry. (C) `SHARED_REU_MUL_INIT`/`SHARED_REU_MUL_FETCH` MUST move together — partial deferral created a §8.0 ownership state with no table row; split ownership, if ever needed, is a fourth-state proposal. (D) §6.2's ZP scoping restated as the model-independent rule: slot defines reach every TU that *defines* the slot and never a TU that `.importzp`s it — measured failures exist in both directions (polyval#34, x25519#95). Also recorded: x25519's §6.4 half-2 evidence (pre-migration COLD over-claimed up to +164 % in deferral builds; per-switch deltas now encoded and locked adopter-side).

### 0.9.0 — 2026-08-14

Normative (MINOR — the [#76](https://github.com/JC-000/c64-lib-contract/issues/76) restructuring, phase 1). **§6 becomes the build-and-consume chapter**, growing from 11 lines to six clauses; obligations now attach to *archives*, not "the library". New: §6.2 defines-forwarding with the contract-normative `CONTRACT_DEFINES` (global) / `CONTRACT_ZP_DEFINES` (ZP-defining-TU-scoped) pair — the split is measured, not stylistic: a globally-delivered slot override collides with every `.importzp` site, and a single-variable implementation passes the library's own CI while breaking the first consumer override ([nist#104](https://github.com/JC-000/c64-nist-curves/pull/104)). §6.3 reachability + required `lib-app-owned` target (encapsulating library-specific deferral-switch knowledge). §6.4 per-variant manifest rule from #62, both halves stated per-TU with the two measured single-half failures. §6.5 the name-surface enumeration incl. archive member basenames (`<shortname>_` prefix at next MAJOR) and the #70 rename window. §6.6 reserved for #69 per the #62-before-#69 gate. **§2 gains the ZP prefix registry** (#83): per-library prefix table checked at intake, same-name-across-libraries always a defect unless §8.x-canonical, general scratch takes `<shortname>_zp_<role>`. **§8.1/§8.2/§8.3 deferral completion**: import-never-stub rule; `SHARED_REU_MUL_FETCH` switch closing the both-adopters-always-own-the-fetch gap; `sqtab_lo`/`sqtab_hi` canonical over `sqr_*`. Archive basenames standardize on `<shortname>[-<variant>].a` under the window. Consolidates #62/#70/#72 (spec side) and the #82/#83 structural remainders; #69 explicitly deferred. Adopter-verified inputs: nist#104 (A.1 two-variable + pattern-rule caveat), chacha#75 (`lib-app-owned` precedent), the four R2 ZP audits, and the item-B surface table + addenda on #76.

### 0.8.6 — 2026-08-14

Doc-only (PATCH, the 0.7.1 precedent): **every `$`-hex `-D` shell snippet was silently broken as pasted.** Unquoted `$40` is expanded by the shell as positional parameter `$4` + literal `0`, so `ca65 -D fp_src1=$40` assembles cleanly with the slot at address **`$00`** — no diagnostic at any stage (measured on sh and zsh, ca65 V2.18; found while testing the §6-restructuring defines-forwarding pattern for [#76](https://github.com/JC-000/c64-lib-contract/issues/76)). All pasteable `-D` command lines in §2/§3/§8.1 now single-quote the value; a normative `$`-hex quoting note joins §2's flag-spelling note, including the make-interface corollary: make variables/recipes MUST pass `$`-free values, preferring ca65's natively-accepted `0x` hex (`-D fp_src1=0x40`, measured surviving make+shell) — `$40`/`$$40` measured to produce 0, and `$$$$40` produces the **shell's PID**, an address that changes per invocation with no diagnostic (both escape-ladder rows measured independently by the c64-nist-curves A.1 implementation, [nist#104](https://github.com/JC-000/c64-nist-curves/pull/104), and confirmed here). Seventh member of the copy-paste defect class (#41 `.and`, #50 `--asm-define`, #58/#74 `: abs`, #73 `.if`-on-import, #82 decorative export). Adopter repos copied the unquoted form into their own docs (e.g. x25519 `zp_config.s` comments, polyval `API.md`) and should re-check.

### 0.8.5 — 2026-08-14

Normative (PATCH, following the 0.7.3/0.7.4 precedent for export-surface rulings): §8.1 and §8.2 gain **export discipline** paragraphs. §8.1: `LIB_SHARED_SQTAB_BASE` MUST NOT be exported — ratifies unanimous fleet practice. §8.2: the `LIB_SHARED_REU_MUL_*` consumer-input equates MUST NOT be exported — both REU adopters exported them, yielding a live `Duplicate external identifier: 'LIB_SHARED_REU_MUL_BANKS_USED'` in the pair `c64-https` ships ([#82](https://github.com/JC-000/c64-lib-contract/issues/82); fixed adopter-side in c64-x25519#92 and c64-nist-curves#103) — and each §8.2-consuming library MUST export library-prefixed `LIB_<X>_SHARED_REU_MUL_{BANK,OFFSET,BANKS_USED}` output counterparts **whose values are the values the code reads** (the pre-#92 x25519 export was decorative: code read `X25519_REU_BANK` while the knob published an unread number, so a consumer `-D` override succeeded silently and relocated nothing). Adds the consumer placement-agreement `.assert` (`lderror` — imported operands per §1's guard rule). Both snippets assemble-tested; the assert verified to fire on a deliberate disagreement (ca65/ld65 V2.18). Routed standalone rather than into [#76](https://github.com/JC-000/c64-lib-contract/issues/76)'s §6 restructuring so the ruling is citable at a tag now; the §6 chapter absorbs it editorially. `c64-x25519` main already conforms fully; `c64-nist-curves` main conforms on the MUST-NOT half, prefixed outputs to follow.

### 0.8.4 — 2026-08-14

Doc-only (§4): stated that `ZEROPAGE` is exempt from the prefixed-segment rule and that §2 owns zero-page allocation. §4 forbids the default ld65 segment names in library sources and enumerates `CODE` / `RODATA` / `DATA` / `BSS`; `ZEROPAGE` is also a default name but absent from that list, leaving two readings — deliberately exempt because §2 governs ZP, or an oversight. Every adopter uses `.segment "ZEROPAGE"` in `zp_config.s`, so the question is live rather than theoretical. No consequence either way, since a misplaced ZP segment fails loudly with a range error rather than silently, which the clause now says. Resolves item 5 of [#78](https://github.com/JC-000/c64-lib-contract/issues/78).

Recording a measurement that answers the reporter's own calibration question on item 1, since it decides whether the v0.8.3 rewrite was the right shape of fix. They asked whether cfg-only alignment is the unusual case, in which case a caveat would have sufficed instead of a rewritten table. Counting source-level `.align` directives across all four adopters at their current tags: `c64-x25519` 6, `c64-ChaCha20-Poly1305` 3, `c64-nist-curves` 0, `c64-polyval` 0. **The fleet is split exactly two and two** — neither shape is unusual, so a clause stating unconditional behaviour is wrong for half the adopters however it is worded, and the conditional table is the correct fix rather than an over-correction.

### 0.8.3 — 2026-08-14

Doc-only (§4): corrected the v0.8.0 clause's own risk assessment, which was wrong in a way that would mislead exactly the adopter following it. Reported from `c64-nist-curves` after adopting v0.8.0, re-measured here on ld65 V2.18.

**Both diagnostics are conditional on the library's shape, not on the violation.** The clause presented the dropped-`align` case as loud and the `bss` case as uniquely silent. In fact the alignment warning fires only when the segment contains a source-level `.align` directive — it is that directive ld65 checks the cfg against, not the absence of the attribute. A library expressing page alignment **only in its cfg**, which `c64-nist-curves` does with no `.align` anywhere in its sources, gets no diagnostic whatsoever and the table lands off-page identically. Symmetrically, the `bss` warning keys on the segment's **byte values**: `.byte 1` warns, `.byte 0` does not, and a `.res n, 0` buffer — the ordinary library-scratch shape — disappears silently. Verified both directions here: 256 zero bytes vanished from an image with no diagnostic at all.

So the two shapes most likely to occur in practice are the two that produce no signal, and neither condition is one a **consumer** can evaluate, because both depend on library source the consumer never reads. That strengthens the clause's conclusion — declaring is the library's obligation — while invalidating the evidence table it rested on.

**The `bss` consequence was also understated.** "Reads return power-on garbage" holds only when the segment is last in a file-emitting area. Mid-area, ld65 emits a shorter image and everything past the hole loads at the wrong address — measured at 9,154 bytes of displacement for a single mid-image code segment. Such a build can appear to work by coincidence, if the absent content is zeros and every affected buffer is written before it is read.

PATCH per §7 — corrects measured claims and severity in prose; no normative requirement changes. Resolves items 1, 3 and 4 of [JC-000/c64-lib-contract#78](https://github.com/JC-000/c64-lib-contract/issues/78). Item 2 (no way to declare a non-segment address reservation) is routed to the [#76](https://github.com/JC-000/c64-lib-contract/issues/76) §6 restructuring; item 5 (`ZEROPAGE` ownership between §2 and §4) remains open as editorial.

### 0.8.2 — 2026-08-14

Doc-only: every version in §12 is now tagged `v<version>` in this repository, and the header says so. Previously the newest tag was **v0.4.0** against a `main` at v0.8.1 — twelve untagged versions — so a consumer pinning or reading by tag, which is the natural thing to do with a document defining a contract, got normative text four minor versions stale. A `c64-https` alignment audit was scoped against v0.4.0 on exactly that basis and missed §13, the v0.5.0 `SHARED_CONSUMES` mask and the whole [#43](https://github.com/JC-000/c64-lib-contract/issues/43) prefixed-export migration. Thirteen tags were created retroactively at each version's tip commit, and every tag from `v0.3.2` onward now has a `SPEC.md` header matching its own name — verified tag by tag.

Two older tags do not, and are documented rather than moved: `v0.3.0` and `v0.3.1` both point at commits whose header reads 0.2.0, and no commit in this repository ever carried a 0.3.0 or 0.3.1 header — those releases were tagged before the header line was being stamped. A caveat note now sits above the 0.3.1 entry. They were left in place because relocating a published tag silently changes what anything pinned to it resolves to, which is a worse failure than a documented inconsistency.

The header note also tells readers to check a tag's stated version rather than infer it from tag recency — the same mistake that produced a false "tagged" claim in `adopters.md` during the v0.7.0 migration, corrected in PR #61. Resolves [JC-000/c64-lib-contract#71](https://github.com/JC-000/c64-lib-contract/issues/71).

### 0.8.1 — 2026-08-14

Doc-only (§1): fixed both consumer-side version-guard snippets, neither of which assembled, and added the missing `: abs` export hint to the §1 pattern.

**The guards could not work.** Both used `.if` on an `.import`ed symbol — the ABI generation gate added in 0.7.5 and the `LIB_<X>_VERSION_*` gate added in 0.7.0. `.if` requires an assembly-time constant and an imported symbol has no value until link, so ca65 rejects the guard with `Constant expression expected`. A consumer pasting either got a build failure, not a working check. Both now use `.assert <expr>, lderror, "..."`, which defers evaluation to ld65 — the only stage that knows the value. Verified in both directions: the corrected form assembles, links clean against a satisfying version, and fails with the intended message against a too-old one. The clause now states why `.if` cannot be used here, since the reason is not obvious and the wrong form looks natural.

**The `: abs` hint was missing.** §1's pattern exported the version equates unhinted. They are small integers, so ca65 infers zeropage while a consumer's `.import` defaults to absolute, producing `ld65: Warning: Address size mismatch` at every import site — the same defect fixed for the §8.4 macro in 0.7.4 ([#58](https://github.com/JC-000/c64-lib-contract/issues/58)), recurring in a clause written before that fix landed. All four adopters already ship `: abs` here, so the spec was behind its own implementations.

Fourth and fifth instances of the copy-paste-facing-snippet class after [#41](https://github.com/JC-000/c64-lib-contract/issues/41) (`.and` vs `&`), [#50](https://github.com/JC-000/c64-lib-contract/issues/50) (`--asm-define` vs `-D`) and [#58](https://github.com/JC-000/c64-lib-contract/issues/58) — and the most severe of them, since a guard that cannot assemble is worse than one that merely warns. PATCH per §7 — no symbol, macro, section or build-target semantics change. Resolves [#73](https://github.com/JC-000/c64-lib-contract/issues/73) and [#74](https://github.com/JC-000/c64-lib-contract/issues/74).

### 0.8.0 — 2026-08-14

Additive (§4): libraries whose correctness or constant-time behaviour depends on **how** their segments are placed MUST now declare those cfg attributes, and consumers placing library segments MUST preserve them. §4 previously governed segment *names* only — and its stated value is that a consumer writes the `SEGMENTS{}` block themselves ("zero source patches"), so the contract handed the consumer authorship of placement while saying nothing about which attributes the library depends on.

Two measured failure modes motivate it, both from `c64-ChaCha20-Poly1305` (ld65 V2.18). Dropping `align = $100` puts a secret-indexed `.align 256` LUT one byte off a page boundary — the directive aligns relative to its segment, so absolute alignment needs the cfg — and an indexed read then crosses a page for some indices, costing an extra cycle and making execution time depend on a secret. **ld65 only warns and links anyway.** Changing `type = rw` to `type = bss` drops an initialised flag byte from the image so it reads power-on garbage, skipping a `sqtab_init` that the flag exists to gate. **ld65 emits no diagnostic at all.** Neither is an error, so a clean link is not evidence of correct placement — stated explicitly in the clause, since the silent case gives a consumer no signal short of a functional test.

Declarations live as comments on the segment lines of the example cfg §4 already requires, so they travel with the artefact consumers copy, and each states the attribute, its required value, and the consequence of getting it wrong. This is the §2 / §3 pattern applied to placement: ZP slots and REU banks are already declared, overridable and checkable rather than left for a consumer to infer. §8.1 additionally `.assert`s that `LIB_SHARED_SQTAB_BASE` is page-aligned, while nothing protected the segment that alignment is measured from — the asymmetry this closes.

MINOR per §7 — additive obligation, no symbol, macro or build-target semantics changed. Adopters with alignment-sensitive tables or initialised library data annotate their example cfg; `c64-ChaCha20-Poly1305` has both cases, `c64-nist-curves` and `c64-x25519` have page-alignment-sensitive shared tables. Resolves [JC-000/c64-lib-contract#63](https://github.com/JC-000/c64-lib-contract/issues/63).

### 0.7.5 — 2026-08-13

Doc-only (§1/§7): resolved a self-contradiction in `LIB_<X>_ABI_VERSION`. §1 defined it as "bumped on any breaking export change" **and** "matches the MAJOR bump"; §7 repeated "matches the MAJOR component" while also stating that pre-1.0 breaking changes ride MINOR bumps. Those cannot all hold: a pre-1.0 library that breaks its surface keeps MAJOR at `0`, so an ABI equate mirroring MAJOR also stays `0` and never signals the breakage. §7's own example compounded it by gating on `!= 1`, a value unreachable under "matches MAJOR" for any 0.x library.

The equate is now defined on its own terms — a monotonic generation counter for the exported surface, starting at **1**, incremented on any breaking export change, explicitly independent of MAJOR — with the reason stated: §7 permits pre-1.0 breakage on MINOR, so MAJOR carries no signal and cannot be the gate.

This documents what three of four adopters already shipped (`c64-x25519`, `c64-ChaCha20-Poly1305`, `c64-polyval` all export `1` against MAJOR `0`); `c64-nist-curves` followed the literal text, shipped `0`, and became the outlier. The cost was measured rather than theoretical: its v0.9.0 removed 17 exported symbols across two ABI-surface changes on a MINOR bump ([c64-nist-curves#90](https://github.com/JC-000/c64-nist-curves/issues/90), [#91](https://github.com/JC-000/c64-nist-curves/issues/91)) with the equate unchanged at `0`, so consumer guards written to catch exactly that stayed silent — the failure the gate exists to prevent, caused by the spec's own wording. Its bump to `1` is tracked as [c64-nist-curves#95](https://github.com/JC-000/c64-nist-curves/issues/95).

PATCH per §7 — doc-only, and the clause it replaces had no coherent prior meaning to break; three of four adopters already conform to the statement as now written. Same shape as the 0.7.3 §8.0 bit-constant clarification. Resolves [JC-000/c64-lib-contract#66](https://github.com/JC-000/c64-lib-contract/issues/66).

### 0.7.4 — 2026-08-13

Doc/macro fix (§8.4): the canonical `LIB_PRECALC_TABLE` macro now exports `_REGION` and `_SHARED` with an explicit `: abs` hint. Both are byte-valued by construction (`$01`-`$03` and `$00`/`$01`), so ca65 inferred **zeropage** for them in every adopter, while a consumer's `.import` defaults to absolute — making §8.4's own published cross-check snippet emit `ld65: Warning: Address size mismatch` on every composed build. Measured on ca65/ld65 V2.18 before and after: the pre-fix macro exports `_REGION`/`_SHARED` as `zeropage` and the copied snippet warns; after, both are `absolute` and the snippet links clean.

`_SIZE` is deliberately left unhinted — its address size is value-dependent by design, absolute at 1024 and `far` at 131072, which is what lets the oversized `reu_mul` table export without the "far but exported absolute" warning fixed in 0.4.1. Regression-checked in the same run: a 131072-byte table still exports `_SIZE` as `far` after the change.

The link always succeeded and both asserts always evaluated correctly, so this was diagnostic noise rather than breakage — but it appeared once per imported `_REGION`/`_SHARED` in every composed consumer build, and the natural way to silence it is `.import ... : zeropage`, which pins a manifest constant to an address size that is an artifact of its current value rather than a property of the symbol. Third instance of the copy-paste-facing-snippet defect class after [#41](https://github.com/JC-000/c64-lib-contract/issues/41) (`.and` vs `&`) and [#50](https://github.com/JC-000/c64-lib-contract/issues/50) (`--asm-define` vs `-D`), and the weakest of the three — it warns rather than fails.

PATCH per §7 — no symbol name, value, or semantic change; the emitted equates are identical apart from declared address size, and every existing `.import` resolves to the same value. **Adopter action:** `precalc_table.inc` is copied verbatim per §8.4, so adopters re-copy it. Only `c64-ChaCha20-Poly1305` currently ships the v0.7.0 five-argument form; `c64-x25519` has not migrated yet ([c64-x25519#78](https://github.com/JC-000/c64-x25519/issues/78) item 4), so landing this before that migration saves a second round-trip there. Resolves [JC-000/c64-lib-contract#58](https://github.com/JC-000/c64-lib-contract/issues/58), found running the merged c64-ChaCha20-Poly1305 PR #60 through the c64-wireguard two-library integration.

### 0.7.3 — 2026-08-13

Doc-only (§8.0): stated normatively that the §8.x per-primitive bit constants **MUST NOT** be `.export`ed. §8.0 already showed them as plain equates and never exported them anywhere, but never said so — and both current §8 adopters filled that silence the other way, exporting `LIB_SHARED_PRIMITIVES_SQTAB` / `_CT_MUL_8X8` (and, in `c64-x25519`, `_REU_MUL`). Because those names are unprefixed and identically valued in both libraries, a consumer importing two manifests still fails to link **after a complete and correct v0.7.0 migration** — the prefixed forms added for [#43](https://github.com/JC-000/c64-lib-contract/issues/43) cover §1 and §8.4, and this is neither. Measured on ca65/ld65 V2.18 against the shipped `c64-x25519` v0.8.0 + `c64-ChaCha20-Poly1305` v0.6.0 archives: a consumer importing only the two §5 ownership masks — the exact composition §8.0's disjointness assert calls for — dies with `Duplicate external identifier`, and ld65 halts at the first one so the visible error understates the set.

Adds the `.ifndef`-guarded copy-verbatim block and names the two per-library masks as the clause's sole exports, mirroring the §13.0 `NET_FAMILY_*` treatment from v0.6.1 — whose changelog entry already cited "exactly as the §8.x bit constants are copied" as its precedent, which was true of how §8.0 described them and false of what adopters shipped. That gap is now closed in the direction the v0.6.1 entry assumed. No contract change — no symbol, value, macro, or build-target semantics change; adopters that never exported the constants (`c64-nist-curves`) are already conformant. Resolves [JC-000/c64-lib-contract#56](https://github.com/JC-000/c64-lib-contract/issues/56); adopter-side fixes tracked as [c64-x25519#78](https://github.com/JC-000/c64-x25519/issues/78) and [c64-ChaCha20-Poly1305#57](https://github.com/JC-000/c64-ChaCha20-Poly1305/issues/57).

### 0.7.2 — 2026-08-13

Doc-only (§8.0/§8.2): corrected the claim that `od65` "reads ca65 `.o` and `.a` archives". It reads objects only. Pointed at an archive it prints `<name>: (no xo65 object file)` **and exits `0`** — so every grep-based audit the spec recommends produces zero matches and reports a clean pass, indistinguishable from "this library declares no such table." The false result is a false *negative*, which is the dangerous direction for a catch loop whose whole job is noticing that two adopters declare the same shared table. Reproduced on cc65 V2.18: `od65 --dump-exports lib.a` → `(no xo65 object file)`, exit `0`; the same members dumped as `.o` files list all six `_PRECALC_sqtab_*` equates.

Adds an "Auditing a shipped archive" block giving the extraction pattern (`ar65 t` to enumerate members, `ar65 x` to extract each — `ar65 x` extracts nothing when given an archive alone), and a recommendation that audit scripts assert the extraction produced at least one object so an empty or unreadable archive fails loudly instead of dropping through to a silent zero-match. Marks the existing `build/*.o` globs as normative — objects, not archives — and fixes the §8.4 out-of-band fallback pointer, which was the practical trap: that fallback is aimed at consumers integrating a **shipped `.a`**, exactly the input `od65` cannot read.

No contract change — no symbol, macro, section, or build-target semantics changed; the recommended commands change, the exported data does not. Resolves [JC-000/c64-lib-contract#52](https://github.com/JC-000/c64-lib-contract/issues/52), found during c64-nist-curves' v0.5.0–v0.7.1 adoption ([c64-nist-curves#86](https://github.com/JC-000/c64-nist-curves/issues/86)).

### 0.7.1 — 2026-08-12

Doc-only: fixed every consumer-override snippet to use ca65's actual symbol-define flag **`-D name[=value]`** instead of `--asm-define`, which ca65 rejects with `ca65: Unknown option: --asm-define`. `--asm-define` is `cl65`'s spelling, which `cl65` forwards to ca65 — presumably how the form entered the spec — but all eleven occurrences across ten lines (§2 ZP overrides, §3 REU bank overrides, §8's placement prose, §8.1 `LIB_SHARED_SQTAB_BASE`, §8.2 `LIB_SHARED_REU_MUL_BANK`) invoke `ca65` directly and so could not run as written. Measured on ca65 V2.18, the same version cited by the 0.4.2 entry below. Adds a normative flag-spelling note under §2's override block, since that is where the mechanism is first established and where a future snippet would copy from. Same defect class as [#41](https://github.com/JC-000/c64-lib-contract/issues/41)'s `.and`-vs-`&` collision asserts: a copy-paste-facing snippet in a copy-paste-facing document that does not work when copied. No contract change — no symbol, macro, section, or build-target semantics changed, and adopters were necessarily already using `-D` for their builds to work at all. Resolves [JC-000/c64-lib-contract#50](https://github.com/JC-000/c64-lib-contract/issues/50), found while testing the `LIB_NO_BARE_EXPORTS` define added in 0.7.0.

### 0.7.0 — 2026-08-12

Additive (§1/§5/§8.4): **library-prefixed manifest exports**, resolving the two-library link collision measured in [#43](https://github.com/JC-000/c64-lib-contract/issues/43). §1's four version equates gain required `LIB_<X>_`-prefixed forms (`LIB_X25519_VERSION_MAJOR`, ...) and the §8.4 `LIB_PRECALC_TABLE` macro gains a fifth argument, the library prefix, emitting `LIB_<X>_PRECALC_<name>_{SIZE,REGION,SHARED}` alongside the existing bare triple. The unprefixed §1 and §8.4 names remain **required through v0.x and deprecated**, so no adopter breaks and no consumer flag-day is needed; they are gated on a new `LIB_NO_BARE_EXPORTS` define (`ca65 -D LIB_NO_BARE_EXPORTS=1`) that a composing consumer sets across every library in the link, and they are scheduled for removal at v1.0. §1 additionally requires the bare exports to live in a translation unit exporting nothing else: ld65 links whole object members, so bare names sharing a member with a legitimately-imported equate enter the link uninvited — which is why TU separation alone could never have fixed `LIB_PRECALC_*`, whose bare and prefixed forms are emitted by one macro invocation in one TU. §5's aggregate equates therefore move to `src/lib_manifest.s`.

Measured against ca65 V2.18 / ld65: the pre-change two-library link reproduces `ld65: Error: Duplicate external identifier: 'LIB_PRECALC_sqtab_SHARED'` exactly as reported; with both libraries built under `-D LIB_NO_BARE_EXPORTS=1` the same link succeeds, and the consumer-side cross-check `.assert LIB_X25519_PRECALC_sqtab_SIZE = LIB_CHACHA20_POLY1305_PRECALC_sqtab_SIZE` both passes on agreement and fires on a seeded disagreement. That agreement check is a capability the bare form could not express at all — two libraries describing the same shared table emitted one symbol name, so there was nothing to compare. `make verify` now assembles the smoke test in both export modes and adds a negative case pinning the macro's guard: a legacy four-argument invocation under `-D LIB_NO_BARE_EXPORTS` emits no symbols at all and must fail with a named error rather than silently producing an empty manifest.

Audit patterns move from `LIB_PRECALC_` to `_PRECALC_` (`grep -r '_PRECALC_' src/`, `od65 --dump-exports build/lib.o | grep _PRECALC_`), which matches both forms; the older pattern would silently miss every prefixed export. The §8.1/§8.2 rule that the table *name* stays unprefixed is unchanged and now stated against its opposite: the library prefix belongs in the fifth macro argument, never in the table name, or the cross-adopter audit loses its signal.

MINOR bump — every pre-v0.7.0 adopter and consumer keeps working untouched; the four-argument macro form still assembles and still emits the bare triple. Adopters migrate in follow-up PRs (same shape as the [#21](https://github.com/JC-000/c64-lib-contract/issues/21) and [#44](https://github.com/JC-000/c64-lib-contract/issues/44) rounds). Unblocks the v0.5.0 §8.0 coverage assert for the multi-library consumers it was written for — `c64-wireguard` currently applies it to one library at link time and checks the other out-of-band. Resolves [JC-000/c64-lib-contract#43](https://github.com/JC-000/c64-lib-contract/issues/43).

### 0.6.1 — 2026-08-12

Doc-only (§13.0): gave the `NET_FAMILY_*` family bits an explicit definition site. The v0.6.0 clause used the four constants in both its manifest and consumer-assert examples but never showed where they come from, leaving each adopter to invent a home for them — the one thing §13 exists to prevent. They are now specified as plain assemble-time equates in a shared `src/net/net_families.inc`, copied verbatim by adopters exactly as the §8.x bit constants are, and explicitly **not** `.export`ed: both sides of the link carry the header, and only exported symbols can collide (`NET_BACKEND_FAMILIES` remains the clause's sole export). Also corrected the §13.0 consumer-assert example from `error` to `lderror`: `NET_BACKEND_FAMILIES` is `.import`ed, so its value is not known until link, and the identical assert in §13.8 already used `lderror`. No contract change — bit values, symbol names, and family semantics are unchanged; the corrected assert form is the one §13.8 already specified.

### 0.6.0 — 2026-08-12

Additive: new §13 "Network backend ABI" — the contract's first non-cryptographic chapter. Standardizes the symbol surface (§13.1: core / TCP / DNS / UDP families with per-entry calling conventions), the `NET_BACKEND_FAMILIES` capability bitmask (§13.0, append-only per the §8.0 discipline), the `net_last_error` namespace carve-up grandfathering the existing `UCI_ERR_*` values verbatim (§13.2), consumer-owned rx buffer contracts with a normative 16-bit-safe length rule (§13.3, motivated by the c64-https 255-byte TCP RX clamp defect, c64-https PR #27), the wall-clock-bounded-wait rule (§13.4, motivated by the c64-https `feat/net-drain-abi` cycle-budget failure at turbo), adapter-internal ZP discipline (§13.5), the UCI inter-access fence floor as a conformance requirement (§13.6, empirically bracketed 51.6 µs FAIL / 62.9 µs PASS at 64 MHz on C64 Ultimate), the fixed-address blob backend declaration pattern for position-linked driver blobs like ip65 (§13.7, explicitly contrasted with §4 relocatable segment libraries), and the `net_abi_asserts` conformance-check pattern (§13.8). Motivated by confirmed fork-and-drift between the two consumers: `c64-wireguard` copied `c64-https`'s `net_abi.inc` pattern and the surfaces have since diverged in naming (`net_dhcp` vs `net_dhcp_acquire`), data-passing conventions, ZP-helper exposure, and — most costly — robustness (`c64-wireguard`'s UCI adapter predates the bounded-wait, phantom-socket, and widened-fence hardening in `c64-https`; its `uci_errors.inc` is an older copy missing `UCI_ERR_NO_SOCKET` / `UCI_ERR_WAIT_TIMEOUT`). §13 is a **level-1** standardization: it governs in-consumer adapter surfaces; packaged `LIB_NET_<B>_*` archives (level 2) are a future promotion gated on adapter stabilization. Consumer alignment tracked via per-consumer intake issues (§13.8): [c64-https#70](https://github.com/JC-000/c64-https/issues/70), [c64-wireguard#48](https://github.com/JC-000/c64-wireguard/issues/48). MINOR bump: purely additive; no existing section renumbered, no symbol or semantics of §1–§12 changed.

### 0.5.0 — 2026-07-28

Additive (§8.0/§5): normative **three-state build-config semantics** for shared primitives — owner / deferring consumer / non-consumer — replacing the one-line "owned in this build config" gloss that left the two clear-bit states indistinguishable despite imposing opposite consumer obligations (a deferring build needs exactly one owner in the link and boot-time init; a profile-gated non-consumer needs nothing). Adds the required companion mask **`LIB_<X>_SHARED_CONSUMES`** (bit set iff the build config consumes the primitive; deferral switches do not clear it, profile gates do), the adopter-side subset invariant `.assert (OWNED & ~CONSUMES) = 0`, and the consumer-side **coverage assert** `((A_CONSUMES | B_CONSUMES) & ~(A_OWNED | B_OWNED)) = 0` that turns the missing-provider failure (ld65 unresolved external at best, silent uninitialized-table read at worst) into a named assemble-time error. All snippet forms assemble-tested against ca65 (deferral-pair pass, onchip-alone pass, missing-owner error). Per adopter review: a consumer application providing a primitive itself ORs a consumer-defined `APP_OWNED` equate into the coverage assert's owner union (all-libraries-defer is a legitimate configuration), and exporting a primitive's canonical body per its §8.x clause counts as consuming it even when no runtime path in that build config invokes it (the nist-curves `FP_ONCHIP_MUL` ct_mul_8x8 case — dropping the ownership bit instead would strand a sibling's deferral). Demonstrator: c64-x25519 v0.8.0's deferral and onchip builds both export `$0005` ownership with opposite provider requirements. MINOR bump — additive equate, bit values unchanged, append-only preserved; adopters migrate in follow-up PRs (same shape as the [#21](https://github.com/JC-000/c64-lib-contract/issues/21) conditional-mask round; c64-x25519 and c64-nist-curves committed in-thread). Cross-references [#43](https://github.com/JC-000/c64-lib-contract/issues/43): the two-library link-time import path for the new assert is subject to that issue's unprefixed-symbol collision; the §8.4 `od65` out-of-band pattern applies until it resolves. Resolves [JC-000/c64-lib-contract#44](https://github.com/JC-000/c64-lib-contract/issues/44) (escalated from [c64-nist-curves#83](https://github.com/JC-000/c64-nist-curves/issues/83)).

### 0.4.2 — 2026-07-28

Doc-only: fixed the two copy-paste collision-assert snippets to use ca65's **bitwise** `&` instead of the **boolean** `.and` — the §3 REU bank budget assert (`LIB_<X>_REU_BANKS_USED` composition) and the §8.0 shared-primitive double-ownership assert. In ca65 `A .and B` evaluates to 1 whenever both operands are nonzero, so the snippets as written failed to assemble exactly when two linked libraries each claimed anything — disjoint or not — and passed only when one mask was `$0000`, the vacuous case. Measured on ca65 V2.18; found wiring the c64-wireguard two-library consumer build (x25519 v0.8.0 + chacha20poly1305 v0.6.0). `.and` remains correct in boolean contexts (e.g. the §1 `.if` version-comparison example, which joins two comparisons); the 0.4.0 entry's prose below repeats the old form and is left as written — changelog entries are historical record. No contract change — no symbol, macro, or build-target semantics changed. Resolves [JC-000/c64-lib-contract#41](https://github.com/JC-000/c64-lib-contract/issues/41).

### 0.4.1 — 2026-07-18

Doc-only: refreshed the §9 "Compatibility timeline" so it reflects the contract's actual growth — v0.1.0's six core sections (§1–§6) plus the additive §7 (semver) and §8 (shared primitives, §8.0–§8.3) work through v0.4.0 — instead of describing v0.1.0 as "this draft," and restated the v1.0 gate as "every applicable section, core and shared-primitive" rather than "all six sections" now that §8 shared-primitive adoption is a tracked dimension in [adopters.md](adopters.md). Also brought the repo README's Status block and library list up to v0.4.0 in the same pass. No contract change — no symbol, macro, section, or build-target semantics changed.

### 0.4.0 — 2026-06-20

Additive: new §8.3 "Shared constant-time 8×8→16 multiply body (`ct_mul_8x8`)" promoting the branchless SMC-dispatched quarter-square multiply body (canonical: `c64-ChaCha20-Poly1305` `ct_mul_8x8`, 59 B) to a shared primitive. Allocates bit `$0004` (`LIB_SHARED_PRIMITIVES_CT_MUL_8X8`) in the §8.0 table, adds an `.ifdef SHARED_CT_MUL_8X8` migration switch, and pins the body shape by the cross-adopter `tools/ct_mul_brute_check.py` byte-identity ratchet (exit 0 across all three adopters as of this release: 59 B, SHA `3ed9025b…`, 65536/65536 functional). Depends on §8.1 `sqtab`; takes no §8.0 `LIB_PRECALC_TABLE` entry (it is a code body, not a table). Resolves [JC-000/c64-lib-contract#14](https://github.com/JC-000/c64-lib-contract/issues/14).

Fix (§8.0): the `LIB_<X>_SHARED_PRIMITIVES` mask is now **conditional** on each primitive's deferral switch rather than an unconditional OR of bit constants. A bit is included iff this build does *not* define that primitive's `SHARED_*` / `SHARED_*_INIT` switch, so two libraries that legitimately share a primitive produce disjoint masks and the consumer `.assert (A .and B) = 0` holds — the previous unconditional form made that assert unsatisfiable for any shared primitive. Adds the per-bit → deferral-switch mapping table and the required conditional mask-construction form. Resolves [JC-000/c64-lib-contract#21](https://github.com/JC-000/c64-lib-contract/issues/21). Adopters migrate their mask equates to the conditional form in follow-up PRs; bit values are unchanged (append-only preserved).

MINOR bump: additive §8.3 plus a corrected §8.0 mask form that is backward-compatible in bit values. Adopters that do not consume §8.3 are unaffected; adopters that shipped an unconditional mask should migrate to the conditional form to make the §8.0 disjointness assert usable.

### 0.3.2 — 2026-06-15

Doc-only: reworked the §8.0 "Consumer-side composition" example to cross-check a composed library's precalc tables via `od65 --dump-exports build/*.o | grep LIB_PRECALC_<name>` — the canonical §8.0 audit tool, which works for any table size — instead of the previous `.import LIB_PRECALC_<name>_SIZE` + `.assert` form. Added a normative address-size note: on the ca65 6502 target the assemble-time `.import` + `.assert` cross-check of `LIB_PRECALC_<name>_SIZE` is valid only for tables ≤ 65 535 B, because `.import` has no `: far` (24-bit) hint — only `: zp` / `: abs` — so importing the `_SIZE` of a larger table (e.g. `reu_mul` = 131072 B) raises `Range error (131072 not in [-32768..65535])`. The producer-side `.export LIB_PRECALC_<name>_SIZE` equate is unaffected and the `LIB_PRECALC_TABLE` macro emits the same equates as before; this is an example/clarification fix only. The retained assemble-time snippet now uses the ≤ 64 KB `sqtab` table. No contract change — no symbol, macro, or build-target semantics changed. Resolves [JC-000/c64-lib-contract#18](https://github.com/JC-000/c64-lib-contract/issues/18), found during the c64-x25519 §8.0 step-6 adoption.

### 0.3.1 — 2026-05-23

> **Tag caveat.** The `v0.3.0` and `v0.3.1` tags predate the practice of stamping the version on `SPEC.md`'s header line. Both point at commits whose header reads **0.2.0**, and no commit in this repository's history carries a `0.3.0` or `0.3.1` header. The changelog entries below are the authoritative record of what those releases contained; the tags are correct as *content* pointers and wrong as *version* labels. Left in place rather than moved, because relocating a published tag changes what anything pinned to it resolves to. All tags from `v0.3.2` onward are self-consistent.


Additive: §8.0 extended with a "Catch loop: enumeration at adopter intake" subsection that makes precalculated-table enumeration mandatory at adopter intake. Introduces (a) a size + access-pattern floor (≥ 256 B AND one of: REU-resident / hot-loop-read / page-aligned) so the catalog stays signal-rich, (b) a two-form enumeration requirement — `docs/precalc-tables.md` for human-readable shape + classification rationale, and a `LIB_PRECALC_TABLE` ca65 macro for build-time discoverability via three exported `LIB_PRECALC_<name>_{SIZE,REGION,SHARED}` equates per table (case-preserved from the macro argument), (c) the canonical [`precalc_table.inc`](precalc_table.inc) source at the repo root as the verbatim copy-target for adopters, smoke-tested under [`examples/precalc_table_smoke.s`](examples/precalc_table_smoke.s) via `make verify` covering all six (region × shared) combinations and the 65 536-byte `far`-export regression guard, (d) audit triggers covering new adopter, new-minor adding a table, **and generalisation of a previously curve-/algorithm-specific table** (with the c448 / Ed448 re-classification example), (e) per-§8.x back-link sub-paragraphs pinning canonical macro arguments (`"sqtab"` / `"reu_mul"`) as normative and forbidding library-prefixed substitutions so cross-adopter `od65 --dump-exports` grep stays signal-rich. Asymmetry between the doc and macro forms blocks adopter PRs per the new intake-reviewer-MUST rule in `adopters.md` step 6. No breaking changes — pre-existing adopters acquire a §8.0 obligation at their next adoption-status update PR. Motivated by [JC-000/c64-lib-contract#11](https://github.com/JC-000/c64-lib-contract/issues/11) and the observation that both §8.1 (`sqtab`) and §8.2 (`reu_mul`) were caught reactively rather than at intake.

### 0.3.0 — 2026-05-23

Additive: new §8.2 "Shared 8×8→16 REU multiplication table (`reu_mul`)" covering the 128 KB `(a, b) → a × b` mul tables duplicated today between `c64-nist-curves` and `c64-x25519`. Introduces consumer-placement equates `LIB_SHARED_REU_MUL_BANK` and `LIB_SHARED_REU_MUL_OFFSET` (with the latter pinned to `$0000` as a v0.x.0 constraint), a derived `LIB_SHARED_REU_MUL_BANKS_USED` equate so the §8.0 double-ownership `.assert` composes against two-bank claims, a ZP and page-aligned staging-buffer contract following the §2 / §3 `.ifndef` pattern, canonical `reu_mul_tables_init` and `reu_fetch_mul_row` entry points with "safe to call twice" semantics (explicitly *not* "idempotent" in the no-op sense), an explicit non-collapse clause preserving library-private adjacent caches under existing build-time gates (`c64-x25519`'s `SQR_DMA_K > 0` doubled banks `+3..+5`), a `SHARED_REU_MUL_INIT` migration switch, bit `$0002` (`LIB_SHARED_PRIMITIVES_REU_MUL`) in the §8.0 allocation table, and a worked TLS 1.3 stack layout example demonstrating four adopters composing under §8.0 + §8.1 + §8.2. No breaking changes — adopters that do not consume §8.2 are unaffected. Motivated by [JC-000/c64-lib-contract#10](https://github.com/JC-000/c64-lib-contract/issues/10).

### 0.2.0 — 2026-05-20

Additive: new §8 "Shared primitives" with the first entry §8.1 covering the 8×8 quarter-square multiply table (`sqtab_lo` / `sqtab_hi`, `LIB_SHARED_SQTAB_BASE` equate, page-alignment + page-delta `.assert`s, canonical `mul_tables_init` entry point, `SHARED_SQTAB_INIT` migration switch). §5 extended to require an append-only `LIB_<X>_SHARED_PRIMITIVES` bitmask manifest equate whenever an adopter consumes a §8 primitive; bit `$0001` (`LIB_SHARED_PRIMITIVES_SQTAB`) allocated for the §8.1 entry. Sections 8/9/10/11 in the previous draft renumbered to 9/10/11/12. No breaking changes — adopters that do not consume §8 primitives are unaffected. Motivated by [JC-000/c64-lib-contract#5](https://github.com/JC-000/c64-lib-contract/issues/5) and the 2026-05-17 `c64-nist-curves` boot-time corruption incident referenced there.

### 0.1.0 — 2026-05-20

Initial draft. Extracted from `c64-https/docs/library-ingestion-architecture.md` §2 (target architecture) and §3 (library-side feature requests), generalized for cross-consumer scope. Coordinated with `c64-wireguard`'s parallel restructuring work — first three adopter-side issues (`c64-x25519#43`, `c64-x25519#44`, `c64-ChaCha20-Poly1305#26`) were filed by `c64-wireguard` and endorsed by `c64-https`; remaining nine adopter-side issues were filed by `c64-https` (see adopters.md for full tracking).
