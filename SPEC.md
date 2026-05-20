# C64 Library ABI Contract

**Version:** 0.2.0 (2026-05-20)
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

A primitive listed here is opt-in per library: an adopter MAY continue to ship its own private copy until it migrates. Once migrated, the library reflects ownership of the primitive in its `LIB_<X>_SHARED_PRIMITIVES` bitmask manifest equate (§5) so consumers can detect double-ownership at assemble time.

### 8.0 Bit allocation for `LIB_<X>_SHARED_PRIMITIVES`

Each §8.x sub-clause declares one bit constant of the form `LIB_SHARED_PRIMITIVES_<NAME>`. Bits are append-only and never reused: a primitive that is later deprecated keeps its bit reserved so old consumer cfgs that `.assert` on the bit continue to parse against newer SPEC revisions. New §8.x sub-clauses allocate the next free bit and update the table below.

| Bit | Constant | Primitive | Defined in |
|---|---|---|---|
| `$0001` | `LIB_SHARED_PRIMITIVES_SQTAB` | 8×8 quarter-square multiply table | §8.1 |

Consumer-side composition:

```asm
.import LIB_NISTCURVES_SHARED_PRIMITIVES
.import LIB_CHACHA20_POLY1305_SHARED_PRIMITIVES
.assert (LIB_NISTCURVES_SHARED_PRIMITIVES .and LIB_CHACHA20_POLY1305_SHARED_PRIMITIVES) = 0, error, "shared-primitive double-ownership"
```

Two libraries linked into the same PRG must not both claim ownership of the same primitive; whichever lib's standalone build defined the canonical labels first owns them at integration time, the others' definitions are gated out per the per-primitive migration switch.

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

**Related future promotion.** The multiply body that consumes the table (`mul_8x8` / `ct_mul_8x8`) is duplicated across the same set of libraries. The CT-strict `ct_mul_8x8` variant (introduced by `c64-ChaCha20-Poly1305` v0.3.0, already ported by `c64-nist-curves`) is the right candidate to promote alongside `sqtab` once two or more adopters confirm bit-identical bodies. This clause does not pre-commit to that promotion; it is named here so adopters know which variant to align on if they touch the multiply body during the sqtab migration.

## 9. Compatibility timeline

- **2026-05-20 — v0.1.0 (this draft).** Contract is published; adopters land iteratively. Tracking issues filed against each adopter library.
- **v1.0 — target: when all current adopters (see [adopters.md](adopters.md)) have landed all six sections.** Contract is then stable; breaking changes go through a deprecation cycle.

The v1.0 cutover triggers a coordinated tag bump (every adopter to `LIB_ABI_VERSION = 1`) so consumers can pin against `LIB_ABI_VERSION >= 1` and know all six contract sections are present.

## 10. Adopters

See [adopters.md](adopters.md) for the status table and tracking issues per library.

## 11. Consumers

See [consumers.md](consumers.md) for the list of consumer projects relying on this contract.

## 12. Changelog

### 0.2.0 — 2026-05-20

Additive: new §8 "Shared primitives" with the first entry §8.1 covering the 8×8 quarter-square multiply table (`sqtab_lo` / `sqtab_hi`, `LIB_SHARED_SQTAB_BASE` equate, page-alignment + page-delta `.assert`s, canonical `mul_tables_init` entry point, `SHARED_SQTAB_INIT` migration switch). §5 extended to require an append-only `LIB_<X>_SHARED_PRIMITIVES` bitmask manifest equate whenever an adopter consumes a §8 primitive; bit `$0001` (`LIB_SHARED_PRIMITIVES_SQTAB`) allocated for the §8.1 entry. Sections 8/9/10/11 in the previous draft renumbered to 9/10/11/12. No breaking changes — adopters that do not consume §8 primitives are unaffected. Motivated by [JC-000/c64-lib-contract#5](https://github.com/JC-000/c64-lib-contract/issues/5) and the 2026-05-17 `c64-nist-curves` boot-time corruption incident referenced there.

### 0.1.0 — 2026-05-20

Initial draft. Extracted from `c64-https/docs/library-ingestion-architecture.md` §2 (target architecture) and §3 (library-side feature requests), generalized for cross-consumer scope. Coordinated with `c64-wireguard`'s parallel restructuring work — first three adopter-side issues (`c64-x25519#43`, `c64-x25519#44`, `c64-ChaCha20-Poly1305#26`) were filed by `c64-wireguard` and endorsed by `c64-https`; remaining nine adopter-side issues were filed by `c64-https` (see adopters.md for full tracking).
