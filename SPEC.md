# C64 Library ABI Contract

**Version:** 0.1.0 (bootstrap, 2026-05-20)
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

## 8. Compatibility timeline

- **2026-05-20 — v0.1.0 (this draft).** Contract is published; adopters land iteratively. Tracking issues filed against each adopter library.
- **v1.0 — target: when all current adopters (see [adopters.md](adopters.md)) have landed all six sections.** Contract is then stable; breaking changes go through a deprecation cycle.

The v1.0 cutover triggers a coordinated tag bump (every adopter to `LIB_ABI_VERSION = 1`) so consumers can pin against `LIB_ABI_VERSION >= 1` and know all six contract sections are present.

## 9. Adopters

See [adopters.md](adopters.md) for the status table and tracking issues per library.

## 10. Consumers

See [consumers.md](consumers.md) for the list of consumer projects relying on this contract.

## 11. Changelog

### 0.1.0 — 2026-05-20

Initial draft. Extracted from `c64-https/docs/library-ingestion-architecture.md` §2 (target architecture) and §3 (library-side feature requests), generalized for cross-consumer scope. Coordinated with `c64-wireguard`'s parallel restructuring work — first three adopter-side issues (`c64-x25519#43`, `c64-x25519#44`, `c64-ChaCha20-Poly1305#26`) were filed by `c64-wireguard` and endorsed by `c64-https`; remaining nine adopter-side issues were filed by `c64-https` (see adopters.md for full tracking).
