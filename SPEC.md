# C64 Library ABI Contract

**Version:** 0.4.1 (2026-07-18)
**Status:** Draft — under joint review by adopters and consumers.

## 0. Scope and audience

This contract defines the symbols, segment names, and build conventions that a C64 cryptographic library should expose so that *multiple downstream consumers* can integrate it without patching the library's source files.

- A **library** is a self-contained C64 implementation of a cryptographic primitive (ECC scalar mult, ECDSA verify, X25519, ChaCha20-Poly1305, SHA, etc.) shipped as a git repository, typically with a standalone test PRG and a `make lib` archive target.
- A **consumer** is a downstream project (TLS client, IPsec/VPN, signature verifier, ...) that vendors one or more libraries as git submodules and links their archives into its own PRG.
- The contract exists because, without it, each consumer mid-build sed-patches each library's sources to rename segments, relocate ZP slots, and strip unwanted code paths. That tightly couples consumer cfgs to library source layout — every library tag bump risks breaking the consumer's integration shell scripts. With the contract, the library publishes everything the consumer needs as code (equates, segment names, build targets), and the consumer's cfg picks up the library by name with zero source patches.

The contract is deliberately minimal. It governs symbols and conventions, not implementation choices.

## 1. Version identification

Every library MUST export the following integer equates:

| Symbol | Type | Semantics |
|---|---|---|
| `LIB_VERSION_MAJOR` | integer equate | Semantic-version major. Bumped on breaking ABI change. |
| `LIB_VERSION_MINOR` | integer equate | Semantic-version minor. Bumped on additive ABI change (new symbol, new build target). |
| `LIB_VERSION_PATCH` | integer equate | Bug-fix release. No ABI change. |
| `LIB_ABI_VERSION` | integer equate | Bumped on any breaking export change. Matches the MAJOR bump. |

The symbols live in a dedicated file, conventionally `src/lib_version.s`, and are exported via `.export`.

**Pattern:**

```asm
; src/lib_version.s
.export LIB_VERSION_MAJOR
.export LIB_VERSION_MINOR
.export LIB_VERSION_PATCH
.export LIB_ABI_VERSION

LIB_VERSION_MAJOR = 0
LIB_VERSION_MINOR = 4
LIB_VERSION_PATCH = 0
LIB_ABI_VERSION   = 1
```

**Consumer-side usage:**

```asm
.import LIB_VERSION_MAJOR
.import LIB_VERSION_MINOR

.if LIB_VERSION_MAJOR < 1 .and LIB_VERSION_MINOR < 4
    .error "this consumer needs libfoo v0.4 or later"
.endif
```

Where a consumer pins to a specific library version via git submodule SHA, the `LIB_VERSION_*` guard is a defense-in-depth assert that fires at assemble time before any 30-minute link/test cycle.

## 2. Zero-page contract

Every library that claims any ZP slots MUST publish them as `.exportzp`-ed equates in a dedicated `src/zp_config.s` (or `.inc`) file. Each equate MUST be `.ifndef`-guarded so a consumer can override the slot via `ca65 --asm-define <slot>=$<addr>`.

**Naming convention:** `<lib_prefix>_<role>`, lower-case (e.g., `fp_src1`, `cc20_state`, `x25519_w_lo`). The prefix keeps slots from colliding across libraries when a consumer links several.

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
ca65 --asm-define fp_src1=$40 --asm-define fp_src2=$44 ...
```

The library's own standalone tests assemble with the defaults; the consumer relocates as needed via `--asm-define`.

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
ca65 --asm-define X25519_REU_BANK=$03 ...
```

**Aggregate bitmask:** the library MUST also export a `LIB_<X>_REU_BANKS_USED` bitmask equate listing every REU bank the library claims. Consumers compose these per-library masks at assemble time:

```asm
.import LIB_NISTCURVES_REU_BANKS_USED
.import LIB_X25519_REU_BANKS_USED
.assert (LIB_NISTCURVES_REU_BANKS_USED .and LIB_X25519_REU_BANKS_USED) = 0, error, "REU bank collision"
```

Consumers MAY relocate any library's REU base via `--asm-define` to resolve a collision. The aggregate mask makes collisions visible at assemble time rather than runtime.

## 4. Segment naming

Library code, rodata, and BSS MUST live in segments prefixed with `LIB_<X>_` (uppercase). The default ld65 segment names (`CODE`, `RODATA`, `DATA`, `BSS`) MUST NOT appear in library sources.

**Why:** Consumer projects use their own `CODE` / `RODATA` for `main.s` and helpers. Without prefixed segments, the consumer must mid-build `sed -i ''` the library's `.segment "CODE"` directives to rename them before assembly. Prefixed segments let the consumer's cfg `SEGMENTS{}` block place library bytes by name — zero source patches.

**Pattern:**

```asm
; libfoo/src/something.s
.segment "LIB_FOO_CODE"

my_helper:
    rts
```

**Multi-variant libraries** (e.g., per-curve) MUST split per-variant segments: `LIB_NISTCURVES_P256_CODE`, `LIB_NISTCURVES_P384_CODE`. This lets a consumer link only the variants it uses.

**Library's own standalone build:** the library's example cfg (`cfg/<libname>.cfg` or similar) MUST add a `SEGMENTS{}` block that maps the prefixed names back to MAIN/RODATA/DATA for the standalone PRG. That way, the library's own tests and bench harness build unchanged.

## 5. Aggregate manifest equates

Every library MUST export the following four integer equates (in `src/lib_version.s` or a separate `src/lib_manifest.s`):

| Symbol | Semantics |
|---|---|
| `LIB_<X>_ZP_USAGE_BYTES` | Total bytes of ZP slots claimed (sum of all `.exportzp` slots). |
| `LIB_<X>_REU_BANKS_USED` | Bitmask of REU banks claimed (see §3). Zero if no REU. |
| `LIB_<X>_RESIDENT_BYTES` | Approximate code+rodata footprint that must remain CPU-resident in any consumer. Refreshed per release. |
| `LIB_<X>_COLD_BYTES` | Approximate code+rodata footprint that a consumer MAY overlay-page (load on demand from REU, kernal-banked RAM, or external storage). Refreshed per release. |

Libraries that consume one or more shared primitives defined in §8 MUST additionally export a `LIB_<X>_SHARED_PRIMITIVES` bitmask equate, ORed from the per-primitive bit constants declared in each §8.x sub-clause. The bitmask lets consumers detect duplicate ownership of any shared primitive at assemble time. See §8 for the bit allocation table and per-primitive bit names.

These let a consumer's cfg do assemble-time fit checks:

```asm
.import LIB_NISTCURVES_RESIDENT_BYTES
.import __CRYPTO_HOT_SIZE__   ; ld65-published region size
.assert LIB_NISTCURVES_RESIDENT_BYTES + ... < __CRYPTO_HOT_SIZE__, error, "no room"
```

And let a CI bot decide whether to even attempt a build against a new library version before kicking off a long compile + test cycle.

The numbers MAY be approximate — within 5% is fine. The library author refreshes them when a release substantively changes any one of them.

## 6. Build target conventions

The library's Makefile MUST provide:

- `make` (no args) — build the standalone test PRG. Library author's primary integration target; what `make test` and `make bench` depend on.
- `make lib` — build a single archive `build/lib/<libname>.a` containing every exported symbol the library ships. The reasonable default for consumers that want the whole library.
- `make lib-<variant>` — minimal-subset archives for primary consumer use cases. Variants are library-specific (e.g., `make lib-p256-verify` for `c64-nist-curves` excludes the Lim-Lee fixed-base comb; `make lib-x25519-scalarmult` for `c64-x25519` excludes benchmark helpers).

Output goes in `build/lib/<libname>-<variant>.a` for variants, `build/lib/<libname>.a` for the full archive.

Consumers fetch `build/lib/<libname>-<variant>.a` and link directly. No mid-build `sed`. No copying intermediates around.

## 7. Semver expectations

- **MAJOR** — bumped on any breaking change to the exported surface (removed/renamed symbols, changed calling conventions, changed memory model, changed semver of a manifest equate).
- **MINOR** — bumped on additive changes (new symbols, new build targets, new manifest equates, new variants).
- **PATCH** — bug fix only, no ABI surface change.
- **`LIB_ABI_VERSION`** matches the MAJOR component. Consumer-side `.if LIB_ABI_VERSION != 1` is the load-bearing breakage gate.

While the contract is in v0.x (pre-1.0), breaking changes happen freely with MINOR bumps. Once v1.0 ships, breaking changes go through a one-MINOR-release deprecation cycle.

## 8. Shared primitives

Some primitives are reimplemented identically across multiple sibling libraries. When a consumer links several of those libraries into the same PRG, each one defines its own copy of the table at its own address, wasting resident RAM and boot cycles, and — more importantly — making the placement decision per-library rather than per-consumer. This section names primitives where the duplication has been confirmed across at least two adopters, fixes the *shape* every implementation must agree on, and leaves the *address* to the consumer via the `--asm-define` override mechanism already established in §2 and §3.

A primitive listed here is opt-in per library: an adopter MAY continue to ship its own private copy until it migrates. Once migrated, the library reflects ownership of the primitive in its `LIB_<X>_SHARED_PRIMITIVES` bitmask manifest equate (§5) — *conditionally*, so a build that defers the primitive to a canonical provider drops the bit (§8.0) — letting consumers detect double-ownership at assemble time.

### 8.0 Bit allocation for `LIB_<X>_SHARED_PRIMITIVES`

Each §8.x sub-clause declares one bit constant of the form `LIB_SHARED_PRIMITIVES_<NAME>`. Bits are append-only and never reused: a primitive that is later deprecated keeps its bit reserved so old consumer cfgs that `.assert` on the bit continue to parse against newer SPEC revisions. New §8.x sub-clauses allocate the next free bit and update the table below.

| Bit | Constant | Primitive | Defined in |
|---|---|---|---|
| `$0001` | `LIB_SHARED_PRIMITIVES_SQTAB` | 8×8 quarter-square multiply table | §8.1 |
| `$0002` | `LIB_SHARED_PRIMITIVES_REU_MUL` | 8×8→16 REU multiplication table (128 KB bank pair) | §8.2 |
| `$0004` | `LIB_SHARED_PRIMITIVES_CT_MUL_8X8` | constant-time 8×8→16 multiply body | §8.3 |

**Consumer-side composition.** Each adopter's `LIB_<X>_SHARED_PRIMITIVES` mask reflects the primitives it **owns in this build configuration**: a primitive's bit is included **iff this build does NOT defer that primitive** via its per-primitive migration switch (the `SHARED_*` / `SHARED_*_INIT` define from the primitive's §8.x clause). A library that defers a shared primitive to a canonical provider (built with that switch defined) drops the corresponding bit, so two libraries linked into the same PRG that share a primitive end up with **disjoint** masks — exactly one keeps the bit. A consumer then asserts disjointness:

```asm
.import LIB_NISTCURVES_SHARED_PRIMITIVES
.import LIB_CHACHA20_POLY1305_SHARED_PRIMITIVES
.assert (LIB_NISTCURVES_SHARED_PRIMITIVES .and LIB_CHACHA20_POLY1305_SHARED_PRIMITIVES) = 0, error, "shared-primitive double-ownership — exactly one provider must own each shared primitive; the other(s) must build with that primitive's SHARED_* switch defined"
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

#### Catch loop: enumeration at adopter intake

A primitive becomes a §8.x candidate only after duplication is confirmed across two or more adopters. The first two §8.x clauses (`sqtab`, `reu_mul`) were both found by ad-hoc audit after the duplication had been in place for one or more releases. To make detection systematic rather than reactive, every adopter MUST enumerate its precalculated tables in a consumer-readable form at intake (per [adopters.md](adopters.md) "How to add your library" step 6).

**Floor.** Enumeration is mandatory for any precalculated table that meets *both* of the following:

- size **≥ 256 B**, AND
- one of: REU-resident, hot-loop-read (touched in a per-byte or per-row inner loop), or page-aligned for fetch-alignment reasons.

Tables below this floor (ChaCha20 quarter-round constants, mod-n reduction one-off scratch, small rotation lookup tables, etc.) are exempt — they are correctly never §8.x-eligible and listing them dilutes the catalog.

**Two-form enumeration.** Each enumerated table is recorded in *both* of the following forms:

1. **Doc-level** in `docs/precalc-tables.md` (or equivalent path linked from the adopter's `adopters.md` row): name, size, region, source file, classification (curve-/algorithm-specific *or* potentially shareable), and the rationale for the classification. The rationale is the load-bearing field — writing it down forces the maintainer to think through whether a sibling library might converge on the same shape.
2. **Assembler-level** via the `LIB_PRECALC_TABLE` macro (canonical source below). The macro emits three exported equates per invocation that survive doc rot and make build-time audits mechanical: `grep -r 'LIB_PRECALC_' src/` adopter-local, `od65 --dump-exports build/lib.o | grep LIB_PRECALC` post-build (cc65 toolchain; `od65` is the cc65 object-file inspector that reads ca65 `.o` and `.a` archives).

Both forms are required. The doc captures shape and rationale; the macro captures size, region, and sharing as build-time data. An asymmetry between the two (a `LIB_PRECALC_*` export with no `docs/precalc-tables.md` row, or vice versa) blocks the adopter PR per the intake-reviewer-MUST rule in `adopters.md`.

**Canonical `precalc_table.inc`.** The byte-for-byte canonical source lives at [`precalc_table.inc`](precalc_table.inc) in this repo's root and is smoke-tested under [`examples/precalc_table_smoke.s`](examples/precalc_table_smoke.s) via `make verify`. Adopters copy that file verbatim into one `src/precalc_table.inc` file and `.include` it from a single translation unit. Updates land via coordinated cross-repo PR; do not edit local copies. The fenced block below is shown for reading; do not retype from it — copy the file.

```ca65
; precalc_table.inc — canonical per c64-lib-contract SPEC §8.0 catch-loop.
; Copy verbatim from this repo's root into each adopter's src/. Updates
; land via coordinated cross-repo PR; do not edit local copies.

.ifndef PRECALC_TABLE_INC_INCLUDED
PRECALC_TABLE_INC_INCLUDED = 1

PRECALC_REGION_RAM     = $01
PRECALC_REGION_REU     = $02
PRECALC_REGION_RODATA  = $03

PRECALC_SHARED_NO      = $00
PRECALC_SHARED_YES     = $01

; LIB_PRECALC_TABLE "name", size_bytes, region, shared
;
;   "name":       quoted string literal (becomes the symbol suffix;
;                 use lower_snake_case, no leading digit)
;   size_bytes:   total bytes claimed by the table
;   region:       PRECALC_REGION_RAM | _REU | _RODATA
;   shared:       PRECALC_SHARED_YES | PRECALC_SHARED_NO
;
; Emits three exported equates per invocation. The macro preserves the
; case of the `name` argument verbatim (ca65 has no built-in toupper),
; so `LIB_PRECALC_TABLE "sqtab", ...` emits the symbols below in their
; lower-case form. The normative §8.x canonical names use
; lower_snake_case throughout, so cross-adopter audits grep on a single
; case convention:
;
;   LIB_PRECALC_<name>_SIZE     = size_bytes
;   LIB_PRECALC_<name>_REGION   = region
;   LIB_PRECALC_<name>_SHARED   = shared
;
; SIZE is exported without an address-size hint so values > 16 bits
; (e.g. the 131072-byte REU mul table) export cleanly as 'far' without
; a "far but exported absolute" warning. REGION and SHARED are
; byte-valued and exported without a hint for consistency.

.macro LIB_PRECALC_TABLE name, size_bytes, region, shared
    .ident (.sprintf("LIB_PRECALC_%s_SIZE",   name)) = size_bytes
    .ident (.sprintf("LIB_PRECALC_%s_REGION", name)) = region
    .ident (.sprintf("LIB_PRECALC_%s_SHARED", name)) = shared

    .export .ident (.sprintf("LIB_PRECALC_%s_SIZE",   name))
    .export .ident (.sprintf("LIB_PRECALC_%s_REGION", name))
    .export .ident (.sprintf("LIB_PRECALC_%s_SHARED", name))
.endmacro

.endif ; PRECALC_TABLE_INC_INCLUDED
```

**Example invocation** (illustrative — a curve library that consumes both §8.1 and §8.2 plus two library-private tables):

```ca65
.include "precalc_table.inc"

LIB_PRECALC_TABLE "sqtab",        1024,   PRECALC_REGION_RAM,    PRECALC_SHARED_YES
LIB_PRECALC_TABLE "reu_mul",      131072, PRECALC_REGION_REU,    PRECALC_SHARED_YES
LIB_PRECALC_TABLE "lim_lee_comb", 24576,  PRECALC_REGION_REU,    PRECALC_SHARED_NO
LIB_PRECALC_TABLE "sha384_k",     640,    PRECALC_REGION_RODATA, PRECALC_SHARED_NO
```

**Consumer-side composition** (optional, for the consumer that wants to cross-check a composed library's shape). The canonical cross-check reads the exported equates out of the post-build object via `od65 --dump-exports` — the same tool §8.0 already uses for the adopter-intake audit above — and greps for the `LIB_PRECALC_<name>_*` symbol family:

```sh
od65 --dump-exports build/*.o | grep LIB_PRECALC_reu_mul
```

This reports `LIB_PRECALC_reu_mul_SIZE`, `_REGION`, and `_SHARED` with their exported values for any table size, including the 128 KB `reu_mul` and the 192 KB `reu_mul_doubled`. A consumer build script asserts the values it expects (`_SHARED = 1`, `_SIZE = 131072`) against this dump.

> **Address-size limit (normative).** On the ca65 6502 target an *assemble-time* cross-check that `.import`s `LIB_PRECALC_<name>_SIZE` into a second translation unit and `.assert`s on it only works for tables **≤ 65 535 B**. ca65's `.import` accepts only the `: zp` (8-bit) and `: abs` (16-bit) address-size hints — there is no `: far` (24-bit) form — so importing the `_SIZE` of a larger table (e.g. `reu_mul` = 131072 B) raises `Range error (131072 not in [-32768..65535])` at the consumer. The producer-side `.export LIB_PRECALC_<name>_SIZE` equate is unaffected (ca65 `.export` accepts an absolute value of any width up to 32 bits — see the macro note in `precalc_table.inc`); only the *consuming* `.import` is constrained. For tables that fit, the assemble-time form is available:
>
> ```asm
> ; Assemble-time cross-check — VALID ONLY for tables ≤ 65 535 B.
> ; For larger tables (reu_mul, reu_mul_doubled) use the od65 dump above.
> .import LIB_PRECALC_sqtab_SHARED
> .import LIB_PRECALC_sqtab_SIZE
> .assert LIB_PRECALC_sqtab_SHARED = PRECALC_SHARED_YES, error, "if this lib reports sqtab, it MUST claim sharing"
> .assert LIB_PRECALC_sqtab_SIZE   = 1024,               error, "sqtab size mismatch — bit-identical shape required for §8.1"
> ```

Note the symbol case: `LIB_PRECALC_reu_mul_*` / `LIB_PRECALC_sqtab_*` with lower-case middle component. The macro preserves the literal case of the `name` argument since ca65 has no built-in toupper; the normative §8.x canonical names use lower_snake_case so adopters and consumers grep on a single case convention.

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

The `.ifndef` guard lets the library assemble standalone with its existing default; the consumer overrides via `ca65 --asm-define LIB_SHARED_SQTAB_BASE=$<addr>`. The two `.assert`s catch misconfigurations at assemble time:

- `LIB_SHARED_SQTAB_BASE & $00ff == 0` — CT-strict `abs,x` indexing requires a page-aligned base for cycle-stable loads.
- `sqtab_hi - sqtab_lo == $0200` — adopters that dispatch via self-modifying code on the lo→hi delta fold this constant into the opcode hi-byte patching; alternative deltas silently miscompute.

The contract pins *shape*, not *placement*. A consumer linking multiple sqtab-using libraries supplies one `--asm-define LIB_SHARED_SQTAB_BASE=$<addr>` and the libraries agree.

**Init.** The canonical init entry point is `mul_tables_init`. It populates both tables from the quarter-square recurrence and MUST be idempotent — calling it twice produces the same table state and has no side effects beyond the table bytes.

**Migration shape.** Each adopting library MAY keep its existing per-lib `sqtab_init` exported for backwards compatibility. Under `.ifdef SHARED_SQTAB_INIT`, the library's own init body is gated out and the canonical `mul_tables_init` takes over. This lets a consumer flip libraries to the shared init one at a time without an atomic cross-repo cutover.

**Bit allocation.** This primitive owns bit `$0001`:

```asm
LIB_SHARED_PRIMITIVES_SQTAB = $0001
```

Adopters OR this bit into their `LIB_<X>_SHARED_PRIMITIVES` manifest equate (§5). For a lib that consumes only `sqtab` today:

```asm
LIB_<X>_SHARED_PRIMITIVES = LIB_SHARED_PRIMITIVES_SQTAB
```

**§8.0 catch-loop registry.** Adopters consuming this primitive MUST emit, in addition to the manifest-equate bit above, one §8.0 catch-loop macro invocation:

```ca65
LIB_PRECALC_TABLE "sqtab", 1024, PRECALC_REGION_RAM, PRECALC_SHARED_YES
```

The string `"sqtab"` is **normative**; adopters MUST NOT substitute a library-prefixed variant (e.g., `"nistcurves_sqtab"` or `"chacha_sqtab"`). The cross-adopter audit `od65 --dump-exports build/*.o | grep LIB_PRECALC_sqtab_SIZE` depends on every adopter exporting the same `LIB_PRECALC_sqtab_*` symbol family. Size (`1024`) and region (`PRECALC_REGION_RAM`) are also normative — they are invariants of the shared shape — only placement (the `LIB_SHARED_SQTAB_BASE` equate above) is consumer-chosen.

**Related future promotion.** The multiply body that consumes the table (`mul_8x8` / `ct_mul_8x8`) is duplicated across the same set of libraries. The CT-strict `ct_mul_8x8` variant (introduced by `c64-ChaCha20-Poly1305` v0.3.0, already ported by `c64-nist-curves`) is the right candidate to promote alongside `sqtab` once two or more adopters confirm bit-identical bodies. This clause does not pre-commit to that promotion; it is named here so adopters know which variant to align on if they touch the multiply body during the sqtab migration. **(Resolved in v0.4.0:** `ct_mul_8x8` was promoted to §8.3, bit `$0004`, once all three adopters confirmed byte-identical bodies via the cross-adopter `ct_mul_brute_check` gate.**)**

### 8.2 Shared 8×8→16 REU multiplication table (`reu_mul`)

**Failure mode this prevents.** The 128 KB 8×8→16 multiplication table at the heart of every multi-precision field-arithmetic loop is currently built and stashed in REU by both `c64-nist-curves` and `c64-x25519`. At each library's default `--asm-define` setting both lay it down at REU banks `$00`/`$01` with byte-identical row layout (see [JC-000/c64-lib-contract#10](https://github.com/JC-000/c64-lib-contract/issues/10) for the audit). A consumer that links both libraries into a single PRG either silently collides on the same 128 KB or — after `--asm-define`-relocating one of them — wastes 128 KB of REU plus ~3-6 s of cold-boot init on a redundant build of the same table. This clause gives the consumer one placement point so the duplication becomes recoverable from the consumer's cfg.

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

The `.ifndef` guards let each library assemble standalone with its existing default; the consumer overrides via `ca65 --asm-define LIB_SHARED_REU_MUL_BANK=$<bank>` once and all consuming libraries agree. The `.assert`s catch misconfigurations at assemble time:

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

**Init.** The canonical init entry point is `reu_mul_tables_init`. It populates banks `LIB_SHARED_REU_MUL_BANK` and `LIB_SHARED_REU_MUL_BANK + 1` and nothing else. The contract is **safe to call twice**: a second call produces the same final REU state with the same observable side effects (the full ~3 s of init work runs twice). The contract does NOT promise no-op on re-call — adding an init-done flag would be an additive change deferred to a future minor bump if a consumer needs it. "Safe to call twice" is the load-bearing reading; do not infer "idempotent" in the no-op sense from this clause.

Libraries that ship adjacent caches keyed off the canonical table — e.g., `c64-x25519`'s pre-doubled 8f+8g rows in banks `+3..+5`, generated only under the build-time `SQR_DMA_K > 0` profile — generate those caches in a library-private init invoked *after* `reu_mul_tables_init` returns. The canonical init MUST NOT touch those banks, and the library-private init MUST stay gated on its existing build-time profile flag. This preserves the lean-profile reclamation those flags exist to provide (e.g., `lib-x25519-1764` with `SQR_DMA_K = 0` reclaims ~600 ms init and 3 REU banks).

**Fetch.** The canonical per-row fetch entry point is `reu_fetch_mul_row`. Calling convention: register `A = a` (row index); on return, the 512 bytes of row `a` are written to `LIB_SHARED_REU_MUL_STAGE_LO` / `LIB_SHARED_REU_MUL_STAGE_HI`. Per-call REU register touches: hi address byte (`$DF05`), bank (`$DF06`), command (`$DF01`) — three writes, ~20 cycles. The fetch MUST re-establish `reu_reu_lo` (`$DF04`) and `reu_addr_ctrl` (`$DF0A`) to `$00` defensively on entry to defend against caller residue (issue [JC-000/c64-x25519#33](https://github.com/JC-000/c64-x25519/issues/33)-class).

**Migration shape.** Each adopting library MAY keep its existing per-lib `reu_mul_init` exported for backwards compatibility. Under `.ifdef SHARED_REU_MUL_INIT`, the library's own un-doubled-banks init body is gated out and the canonical `reu_mul_tables_init` takes over. Library-private init for adjacent caches (above) stays under its own build-time gate and is invoked alongside the canonical init from the library's existing entry. A consumer flips libraries to the shared init one at a time without an atomic cross-repo cutover.

**Bit allocation.** This primitive owns bit `$0002`:

```asm
LIB_SHARED_PRIMITIVES_REU_MUL = $0002
```

Adopters OR it into their `LIB_<X>_SHARED_PRIMITIVES` manifest equate (§5) and the existing §8.0 `.assert` catches accidental cross-library double-ownership.

**§8.0 catch-loop registry.** Adopters consuming this primitive MUST emit, in addition to the manifest-equate bit above, one §8.0 catch-loop macro invocation:

```ca65
LIB_PRECALC_TABLE "reu_mul", 131072, PRECALC_REGION_REU, PRECALC_SHARED_YES
```

The string `"reu_mul"` is **normative**; adopters MUST NOT substitute a library-prefixed variant (e.g., `"nistcurves_reu_mul"` or `"x25519_reu_mul"`). The cross-adopter audit `od65 --dump-exports build/*.o | grep LIB_PRECALC_reu_mul_SIZE` depends on every adopter exporting the same `LIB_PRECALC_reu_mul_*` symbol family. (`od65` is the cc65 object-file inspector; ca65 `.o` files are not in ELF/Mach-O format so standard `nm` cannot read them. Symbol case is preserved from the macro argument — see §8.0.) Size (`131072`) and region (`PRECALC_REGION_REU`) are also normative — they are invariants of the shared shape — only placement (the `LIB_SHARED_REU_MUL_BANK` equate above) is consumer-chosen.

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
- `c64-x25519`'s `reu_fetch_doubled_row` — structurally identical to `reu_fetch_mul_row` with a different bank base. A SMC-parameterised shared fetch could replace it for a small code-size win, deferred until the §8.2 baseline ships across both adopters. Tracked in [JC-000/c64-lib-contract#15](https://github.com/JC-000/c64-lib-contract/issues/15).

#14's evidence gate (cross-adopter brute-check round-trip) is now satisfied and `ct_mul_8x8` is promoted in §8.3 (v0.4.0). The `reu_fetch_doubled_row` follow-up (#15) stays open until its §8.2-baseline gate is acted on.

### 8.3 Shared constant-time 8×8→16 multiply body (`ct_mul_8x8`)

**Failure mode this prevents.** The branchless, SMC-dispatched quarter-square multiply body that reads the §8.1 `sqtab` is reimplemented in every library that does field arithmetic. A pre-S12 ancestor of this body carried two secret-dependent branches; the constant-time rewrite (`c64-ChaCha20-Poly1305` v0.3.0 `ct_mul_8x8`) was then ported divergently into siblings (different calling conventions, block orderings, and scratch placement), so a CT-relevant edit to one copy could silently leave the others on a timing-variable shape. This clause pins one canonical body so the constant-time property is defined once and verified mechanically across adopters.

**Semantics.** A constant-time 8-bit × 8-bit → 16-bit multiply computing `a*b = t(a+b) - t(|a-b|)` over the §8.1 `sqtab` tables, with no secret-dependent branches and cycle-stable `abs,x` indexed loads (the invariant the variant exists to preserve). Entry: `Y = b`; the multiplier `a` is baked into the two `adc #imm` SMC immediate sites by the caller before the inner loop. The 16-bit product is returned in the library's product scratch (`poly_prod_lo` / `poly_prod_hi`). This clause **depends on §8.1** — the body reads `sqtab_lo` / `sqtab_hi` and inherits their page-alignment `.assert`s.

**Shape contract (pinned by gate, not by `.assert`).** Unlike §8.1 / §8.2 there is no placement equate — this is a code body, not a placed table. The canonical shape is the 59-byte `ct_mul_8x8` body in `c64-ChaCha20-Poly1305/src/lib/poly1305_lib.s`. Adopters MUST be **byte-identical** to it. This is enforced by the cross-adopter `tools/ct_mul_brute_check.py` ratchet — opcode-byte equality across all adopters plus a 65 536-case functional brute-check — which MUST return exit 0 before any body change lands. As of v0.4.0 all three adopters (`c64-ChaCha20-Poly1305`, `c64-nist-curves`, `c64-x25519`) are byte-identical (59 B, SHA-256 `3ed9025b…`, 65536/65536 functional).

**Canonical entry.** `ct_mul_8x8`. Adopters whose historical name is `mul_8x8` keep it exported as a back-compat alias of `ct_mul_8x8` (same address).

**Migration shape.** Each adopting library gates its own copy under `.ifdef SHARED_CT_MUL_8X8`. When a consumer defines that switch, the library's private body is gated out and the canonical `ct_mul_8x8` provided by the designated owner takes over. This mirrors the §8.1 `SHARED_SQTAB_INIT` switch and lets a consumer flip libraries one at a time without an atomic cross-repo cutover.

**Bit allocation.** This primitive owns bit `$0004`:

```asm
LIB_SHARED_PRIMITIVES_CT_MUL_8X8 = $0004
```

Adopters include this bit in their `LIB_<X>_SHARED_PRIMITIVES` manifest equate using the **conditional** mask construction of §8.0 — the bit is dropped when this build defines `SHARED_CT_MUL_8X8` (i.e. defers the body to a provider). The `$0004` → `SHARED_CT_MUL_8X8` mapping is registered in the §8.0 deferral-switch table.

**No §8.0 catch-loop registry entry.** §8.0's `LIB_PRECALC_TABLE` enumeration covers precalculated *tables*; `ct_mul_8x8` is a code body, not a table, so it takes **no** `LIB_PRECALC_TABLE` invocation. Its data dependency — the §8.1 `sqtab` table — is already enumerated under §8.1.

## 9. Compatibility timeline

- **2026-05-20 — v0.1.0.** Contract published with the six core sections (§1–§6); adopters land iteratively. Tracking issues filed against each adopter library.
- **2026-05-20 → 2026-06-20 — v0.2.0–v0.4.0.** Additive growth: §7 semver expectations and §8 shared primitives (§8.0 precalc-table enumeration, §8.1 `sqtab`, §8.2 `reu_mul`, §8.3 `ct_mul_8x8`). See §12 for the per-release detail.
- **v1.0 — target: when all current adopters (see [adopters.md](adopters.md)) have landed every applicable section, core and shared-primitive.** Contract is then stable; breaking changes go through a deprecation cycle.

The v1.0 cutover triggers a coordinated tag bump (every adopter to `LIB_ABI_VERSION = 1`) so consumers can pin against `LIB_ABI_VERSION >= 1` and know the full contract surface is present.

## 10. Adopters

See [adopters.md](adopters.md) for the status table and tracking issues per library.

## 11. Consumers

See [consumers.md](consumers.md) for the list of consumer projects relying on this contract.

## 12. Changelog

### 0.4.1 — 2026-07-18

Doc-only: refreshed the §9 "Compatibility timeline" so it reflects the contract's actual growth — v0.1.0's six core sections (§1–§6) plus the additive §7 (semver) and §8 (shared primitives, §8.0–§8.3) work through v0.4.0 — instead of describing v0.1.0 as "this draft," and restated the v1.0 gate as "every applicable section, core and shared-primitive" rather than "all six sections" now that §8 shared-primitive adoption is a tracked dimension in [adopters.md](adopters.md). Also brought the repo README's Status block and library list up to v0.4.0 in the same pass. No contract change — no symbol, macro, section, or build-target semantics changed.

### 0.4.0 — 2026-06-20

Additive: new §8.3 "Shared constant-time 8×8→16 multiply body (`ct_mul_8x8`)" promoting the branchless SMC-dispatched quarter-square multiply body (canonical: `c64-ChaCha20-Poly1305` `ct_mul_8x8`, 59 B) to a shared primitive. Allocates bit `$0004` (`LIB_SHARED_PRIMITIVES_CT_MUL_8X8`) in the §8.0 table, adds an `.ifdef SHARED_CT_MUL_8X8` migration switch, and pins the body shape by the cross-adopter `tools/ct_mul_brute_check.py` byte-identity ratchet (exit 0 across all three adopters as of this release: 59 B, SHA `3ed9025b…`, 65536/65536 functional). Depends on §8.1 `sqtab`; takes no §8.0 `LIB_PRECALC_TABLE` entry (it is a code body, not a table). Resolves [JC-000/c64-lib-contract#14](https://github.com/JC-000/c64-lib-contract/issues/14).

Fix (§8.0): the `LIB_<X>_SHARED_PRIMITIVES` mask is now **conditional** on each primitive's deferral switch rather than an unconditional OR of bit constants. A bit is included iff this build does *not* define that primitive's `SHARED_*` / `SHARED_*_INIT` switch, so two libraries that legitimately share a primitive produce disjoint masks and the consumer `.assert (A .and B) = 0` holds — the previous unconditional form made that assert unsatisfiable for any shared primitive. Adds the per-bit → deferral-switch mapping table and the required conditional mask-construction form. Resolves [JC-000/c64-lib-contract#21](https://github.com/JC-000/c64-lib-contract/issues/21). Adopters migrate their mask equates to the conditional form in follow-up PRs; bit values are unchanged (append-only preserved).

MINOR bump: additive §8.3 plus a corrected §8.0 mask form that is backward-compatible in bit values. Adopters that do not consume §8.3 are unaffected; adopters that shipped an unconditional mask should migrate to the conditional form to make the §8.0 disjointness assert usable.

### 0.3.2 — 2026-06-15

Doc-only: reworked the §8.0 "Consumer-side composition" example to cross-check a composed library's precalc tables via `od65 --dump-exports build/*.o | grep LIB_PRECALC_<name>` — the canonical §8.0 audit tool, which works for any table size — instead of the previous `.import LIB_PRECALC_<name>_SIZE` + `.assert` form. Added a normative address-size note: on the ca65 6502 target the assemble-time `.import` + `.assert` cross-check of `LIB_PRECALC_<name>_SIZE` is valid only for tables ≤ 65 535 B, because `.import` has no `: far` (24-bit) hint — only `: zp` / `: abs` — so importing the `_SIZE` of a larger table (e.g. `reu_mul` = 131072 B) raises `Range error (131072 not in [-32768..65535])`. The producer-side `.export LIB_PRECALC_<name>_SIZE` equate is unaffected and the `LIB_PRECALC_TABLE` macro emits the same equates as before; this is an example/clarification fix only. The retained assemble-time snippet now uses the ≤ 64 KB `sqtab` table. No contract change — no symbol, macro, or build-target semantics changed. Resolves [JC-000/c64-lib-contract#18](https://github.com/JC-000/c64-lib-contract/issues/18), found during the c64-x25519 §8.0 step-6 adoption.

### 0.3.1 — 2026-05-23

Additive: §8.0 extended with a "Catch loop: enumeration at adopter intake" subsection that makes precalculated-table enumeration mandatory at adopter intake. Introduces (a) a size + access-pattern floor (≥ 256 B AND one of: REU-resident / hot-loop-read / page-aligned) so the catalog stays signal-rich, (b) a two-form enumeration requirement — `docs/precalc-tables.md` for human-readable shape + classification rationale, and a `LIB_PRECALC_TABLE` ca65 macro for build-time discoverability via three exported `LIB_PRECALC_<name>_{SIZE,REGION,SHARED}` equates per table (case-preserved from the macro argument), (c) the canonical [`precalc_table.inc`](precalc_table.inc) source at the repo root as the verbatim copy-target for adopters, smoke-tested under [`examples/precalc_table_smoke.s`](examples/precalc_table_smoke.s) via `make verify` covering all six (region × shared) combinations and the 65 536-byte `far`-export regression guard, (d) audit triggers covering new adopter, new-minor adding a table, **and generalisation of a previously curve-/algorithm-specific table** (with the c448 / Ed448 re-classification example), (e) per-§8.x back-link sub-paragraphs pinning canonical macro arguments (`"sqtab"` / `"reu_mul"`) as normative and forbidding library-prefixed substitutions so cross-adopter `od65 --dump-exports` grep stays signal-rich. Asymmetry between the doc and macro forms blocks adopter PRs per the new intake-reviewer-MUST rule in `adopters.md` step 6. No breaking changes — pre-existing adopters acquire a §8.0 obligation at their next adoption-status update PR. Motivated by [JC-000/c64-lib-contract#11](https://github.com/JC-000/c64-lib-contract/issues/11) and the observation that both §8.1 (`sqtab`) and §8.2 (`reu_mul`) were caught reactively rather than at intake.

### 0.3.0 — 2026-05-23

Additive: new §8.2 "Shared 8×8→16 REU multiplication table (`reu_mul`)" covering the 128 KB `(a, b) → a × b` mul tables duplicated today between `c64-nist-curves` and `c64-x25519`. Introduces consumer-placement equates `LIB_SHARED_REU_MUL_BANK` and `LIB_SHARED_REU_MUL_OFFSET` (with the latter pinned to `$0000` as a v0.x.0 constraint), a derived `LIB_SHARED_REU_MUL_BANKS_USED` equate so the §8.0 double-ownership `.assert` composes against two-bank claims, a ZP and page-aligned staging-buffer contract following the §2 / §3 `.ifndef` pattern, canonical `reu_mul_tables_init` and `reu_fetch_mul_row` entry points with "safe to call twice" semantics (explicitly *not* "idempotent" in the no-op sense), an explicit non-collapse clause preserving library-private adjacent caches under existing build-time gates (`c64-x25519`'s `SQR_DMA_K > 0` doubled banks `+3..+5`), a `SHARED_REU_MUL_INIT` migration switch, bit `$0002` (`LIB_SHARED_PRIMITIVES_REU_MUL`) in the §8.0 allocation table, and a worked TLS 1.3 stack layout example demonstrating four adopters composing under §8.0 + §8.1 + §8.2. No breaking changes — adopters that do not consume §8.2 are unaffected. Motivated by [JC-000/c64-lib-contract#10](https://github.com/JC-000/c64-lib-contract/issues/10).

### 0.2.0 — 2026-05-20

Additive: new §8 "Shared primitives" with the first entry §8.1 covering the 8×8 quarter-square multiply table (`sqtab_lo` / `sqtab_hi`, `LIB_SHARED_SQTAB_BASE` equate, page-alignment + page-delta `.assert`s, canonical `mul_tables_init` entry point, `SHARED_SQTAB_INIT` migration switch). §5 extended to require an append-only `LIB_<X>_SHARED_PRIMITIVES` bitmask manifest equate whenever an adopter consumes a §8 primitive; bit `$0001` (`LIB_SHARED_PRIMITIVES_SQTAB`) allocated for the §8.1 entry. Sections 8/9/10/11 in the previous draft renumbered to 9/10/11/12. No breaking changes — adopters that do not consume §8 primitives are unaffected. Motivated by [JC-000/c64-lib-contract#5](https://github.com/JC-000/c64-lib-contract/issues/5) and the 2026-05-17 `c64-nist-curves` boot-time corruption incident referenced there.

### 0.1.0 — 2026-05-20

Initial draft. Extracted from `c64-https/docs/library-ingestion-architecture.md` §2 (target architecture) and §3 (library-side feature requests), generalized for cross-consumer scope. Coordinated with `c64-wireguard`'s parallel restructuring work — first three adopter-side issues (`c64-x25519#43`, `c64-x25519#44`, `c64-ChaCha20-Poly1305#26`) were filed by `c64-wireguard` and endorsed by `c64-https`; remaining nine adopter-side issues were filed by `c64-https` (see adopters.md for full tracking).
