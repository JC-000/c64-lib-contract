# C64 Library ABI Contract

**Version:** 1.0.0 (2026-08-31)
**Status:** Stable.

**Referencing a version.** Every version is tagged `v<version>` in this repository, so a consumer or adopter can pin, diff or cite a specific revision rather than tracking `main`. A tag's `SPEC.md` states its own version on the line above — check it rather than assuming.

**What changed in 1.0.0, and what did not.** This release removed roughly six sevenths of the document's text. **No symbol, equate, bit value, segment name, build target or error code changed**, so a library conformant at v0.17.1 is conformant here without edits. What went was rationale, incident history and process regulation. Sections §9, §12, §14 and §15 and sub-clauses §6.3, §6.6 and §6.7 are **retired**; surviving sections keep their original numbers, so every existing citation to a surviving section still resolves. See [RETIRED.md](RETIRED.md) for where the retired text lives, and [CHANGELOG.md](CHANGELOG.md) for the release history that used to be §12.

**The scope rule this document is held to.** A clause belongs here only if it governs **(1) a name, value or placement that two independently-built artifacts must agree on, where (2) a violation is invisible from inside any single repository's own build.** Both prongs are required. Anything failing either is a matter for the library's own source comments, tests or issue tracker — not for this contract. The rule is stated so it can be applied to proposals, including by people who did not write the clause being proposed.

## 0. Scope and audience

This contract lets several independently-maintained 6502/ca65 libraries be linked into one consumer program without colliding, and lets them share a primitive rather than each shipping their own copy. Those are its two purposes; it has no others.

| Kind | Sections | Who reads it |
|---|---|---|
| **Core** — every library, every consumer | §1 versioning · §2 zero page · §3 REU layout · §4 segments · §5 manifests · §6 build-and-consume · §7 semver | everyone |
| **Domain** — only if the library implements that domain | §8 shared primitives · §13 network backend ABI | crypto libraries: §8; network backends: §13 |
| **Meta** | §10 adopters · §11 consumers | reference as needed |

RFC 2119 keywords (MUST, MUST NOT, SHOULD, MAY) carry their usual meaning.

## 1. Version identification

Every library MUST export the following integer equates, where `<X>` is the library's own UPPER_SNAKE_CASE prefix — the same `<X>` used by its §5 manifest equates (`X25519`, `NISTCURVES`, `CHACHA20_POLY1305`, `POLYVAL`, `MLKEM`):

| Symbol | Semantics |
|---|---|
| `LIB_<X>_VERSION_MAJOR` | Semantic-version major. |
| `LIB_<X>_VERSION_MINOR` | Semantic-version minor. |
| `LIB_<X>_VERSION_PATCH` | Bug-fix release. No ABI change. |
| `LIB_<X>_ABI_VERSION` | Monotonic generation counter for the exported surface, **starting at 1**. Incremented on any breaking export change. Independent of MAJOR. |

They live in a dedicated file, conventionally `src/lib_version.s`, exported with `.export ... : abs`.

**The `: abs` hint is required, not decorative.** These are small integers, so ca65 infers **zeropage** without it while a consumer's `.import` defaults to absolute — producing `ld65: Warning: Address size mismatch` at every import site.

**`LIB_<X>_ABI_VERSION` is independent of MAJOR.** It is a generation counter for the exported surface, not a mirror of the semantic version, and it increments on any breaking export change — a removed or renamed symbol, a changed calling convention, a changed memory model. It cannot track MAJOR, because a library may break its surface on a MINOR bump while pre-1.0, leaving MAJOR at `0` carrying no signal. A consumer gating on the counter would then never fire for exactly the changes the gate exists to catch.

**TU isolation (required).** The deprecated bare exports below MUST live in a translation unit that exports nothing else — no §5 manifest equates, no §8.4 table equates, no code. ld65 pulls in whole object members: if the bare names share a member with anything a consumer legitimately imports, they enter the link uninvited and collide even when the consumer never referenced them. §5's aggregate equates therefore live in `src/lib_manifest.s`.

**Deprecated bare forms.** Every library MUST *also* export unprefixed `LIB_VERSION_MAJOR` / `LIB_VERSION_MINOR` / `LIB_VERSION_PATCH` / `LIB_ABI_VERSION`, so existing single-library consumers keep working. These names are **deprecated**: they are identical across every library, so a consumer linking two of them and importing both manifests gets `ld65: Error: Duplicate external identifier`. They MUST be gated on `LIB_NO_BARE_EXPORTS` so a composing consumer can suppress them build-wide with `ca65 -D LIB_NO_BARE_EXPORTS=1`.

> Their removal was previously scheduled for contract v1.0. It is **deferred to a future MAJOR** and deliberately not bundled with this release: dropping four exports is a real ABI change for every adopter, and it should not ride along with a release whose headline is that text was deleted. It will be its own release, with its own review.

**Zero-consumer carve-out.** A library onboarding with **no released consumers** SHOULD NOT export the bare forms at all — it has no existing consumer to protect, so the export adds a claimant to the exact four colliding names and defends no one. "No released consumers" means no tagged release any consumer pins, checkable from the library's own tags and `consumers.md`. A library that has cut a release someone links keeps the MUST. This is SHOULD NOT rather than MUST NOT because the bare forms are harmless in a single-library link; what a library MUST NOT do is ship them ungated.

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
    ; Deprecated. Suppress with ca65 -D LIB_NO_BARE_EXPORTS=1
    ; when composing two or more libraries.
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

**Consumer-side guard:**

```asm
.import LIB_X25519_ABI_VERSION
.assert LIB_X25519_ABI_VERSION = 1, lderror, "c64-x25519 exported-surface generation changed; re-check the integration"
```

**Use `.assert` / `lderror`, never `.if` / `.error`.** `.if` needs an assembly-time constant, and an `.import`ed symbol has no value until link — ca65 rejects the guard outright with `Constant expression expected`, so an `.if`-based gate never assembles rather than silently passing. `.assert` with `lderror` defers evaluation to ld65, the only stage that knows the imported value. The guard fires at link rather than assemble time, still before anything runs.

A consumer linking two or more libraries builds them all with `-D LIB_NO_BARE_EXPORTS=1` and imports the prefixed forms only; the guard then names which library is out of date instead of reporting one anonymous version.

## 2. Zero-page contract

Every library that claims any ZP slots MUST publish them as `.exportzp`-ed equates in a dedicated `src/zp_config.s` (or `.inc`). Each equate MUST be `.ifndef`-guarded so a consumer can override the slot via `ca65 -D <slot>=0x<addr>`.

**Naming convention:** `<lib_prefix>_<role>`, lower-case (`fp_src1`, `cc20_state`, `x25519_w_lo`). General-purpose scratch takes `<shortname>_zp_<role>` (`nistcurves_zp_tmp1`).

**ZP prefix registry.** Every exported slot name MUST begin with a prefix registered here to exactly one library; intake of a new adopter checks its ZP surface against this table exactly as §8.0 checks bit claims. Every library's §6.1 `<shortname>_` is registered to it by construction.

| Prefixes | Registered to |
|---|---|
| `fp_` `ec_` `sha_` `nistcurves_` | `c64-nist-curves` |
| `fe25519_` `fe_` `x25_` `mul_` `sqr_` `x25519_` | `c64-x25519` |
| `polyval_` `pv_` | `c64-polyval` |
| `cc20_` `poly_` `w32_` `ct_` `chacha_` `chacha20poly1305_` | `c64-ChaCha20-Poly1305` |
| `mlkem_` | `c64-mlkem` |

**Same-named slots across two libraries are always a defect** unless the name is a §8.x canonical contract item. Deliberate cross-library sharing is expressed only through §8.x clauses, never through incidental name equality: three adopters independently converged on bare `zp_tmp1`/`zp_ptr1`, two shipped them, and the resulting duplicate-identifier error was the only thing preventing a measured 12-byte silent overlap between actively-used scratch. A rename of a published slot rides the §6.5 window with its suppression gate — an ungated bare alias preserves the collision for the window's whole duration.

**Pattern:**

```asm
; src/zp_config.s
.ifndef fp_src1
    fp_src1 = $22
.endif
.exportzp fp_src1
```

> **Flag spelling (normative for every snippet in this document).** The ca65 symbol-define flag is **`-D name[=value]`**, not `--asm-define` — that is `cl65`'s spelling, which `cl65` forwards. `ca65 --asm-define ...` fails with `ca65: Unknown option: --asm-define`.
>
> **`$`-hex values (normative for every `-D` value).** Pass `$`-free values. Unquoted on a shell line, `-D fp_src1=$40` becomes `-D fp_src1=0` — the assemble succeeds, the `.ifndef` is satisfied, and the slot lands at `$00` with no diagnostic at any stage. Through **make** it is worse: `$40` and `$$40` both yield `0`, and `$$$$40` yields the shell's PID — a plausible address that changes between invocations, with no diagnostic from make, the shell, ca65 or ld65. ca65 accepts **`0x`-prefixed hex natively**, so `-D fp_src1=0x40` survives make and the shell unquoted; plain decimal is the alternative. A single-quoted `'fp_src1=$40'` is safe on a shell line but not through make.

## 3. REU layout contract

If a library uses any 17xx-series REU banks for precompute tables or scratch, every base bank/offset MUST be a `.ifndef`-guarded integer equate in `src/reu_config.s` (or equivalent), `.export`-ed so the consumer can `.import` it.

**Naming convention:** `<LIB>_REU_BANK` for the primary bank, `<LIB>_REU_OFFSET` for the within-bank base offset; per-table offsets where needed (`<LIB>_TABLE1_OFFSET`).

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

**Aggregate bitmask.** The library MUST also export a `LIB_<X>_REU_BANKS_USED` bitmask equate listing every REU bank it claims, so consumers can compose them at assemble time:

```asm
.import LIB_NISTCURVES_REU_BANKS_USED
.import LIB_X25519_REU_BANKS_USED
.assert (LIB_NISTCURVES_REU_BANKS_USED & LIB_X25519_REU_BANKS_USED) = 0, error, "REU bank collision"
```

Consumers MAY relocate any library's REU base via `-D` to resolve a collision.

**A header that `.import`s an overridable equate MUST guard the import.** A `-D` reaching a translation unit that also `.import`s the name is `Symbol already defined`, so the documented override fails to assemble against the library's own header. Guard the `.import` with `.ifndef` **iff** the defining TU guards the definition, and pair every such guard with an `.else` branch asserting the override against the library's exported value — a bare guard alone converts a compile error into silent divergence, letting a consumer at one bank link cleanly against an archive built for another. Where the defining TU assigns unconditionally the equate is derived, so leave the import bare and let the `-D` collide loudly.

## 4. Segment naming

Library code, rodata and BSS MUST live in segments prefixed with `LIB_<X>_` (uppercase). The default ld65 segment names (`CODE`, `RODATA`, `DATA`, `BSS`) MUST NOT appear in library sources. **`ZEROPAGE` is exempt** — zero-page allocation is governed by §2, and a misplaced ZP segment fails loudly with a range error.

Consumers use their own `CODE`/`RODATA` for `main.s` and helpers. Prefixed segments let a consumer's cfg `SEGMENTS{}` block place library bytes by name instead of `sed`-ing the library's sources mid-build.

**Multi-variant libraries** MUST split per-variant segments (`LIB_NISTCURVES_P256_CODE`, `LIB_NISTCURVES_P384_CODE`) so a consumer links only the variants it uses.

**Load-bearing cfg attributes (normative).** Segment names are only half of what a consumer must get right. A library whose correctness or constant-time behaviour depends on how its segments are *placed* MUST declare those dependencies as comments on the segment lines of the example cfg, so they travel with the thing consumers copy. State the consequence, not just the requirement — a consumer who knows only *that* `align` matters will still drop it when reorganising a memory map under pressure.

```
SEGMENTS {
    # REQUIRED align = $100 — CT invariant. Secret-indexed `.align 256` LUTs
    # are aligned relative to this segment; without page alignment an indexed
    # read crosses a page for some indices and takes an extra cycle, making
    # execution time depend on a secret. ld65 only *warns*.
    LIB_FOO_CODE: load = MAIN, type = ro, align = $100;

    # REQUIRED type = rw in a file-emitting area — holds initialised data.
    # Under `type = bss` the bytes are not emitted and read as power-on
    # garbage. ld65 says nothing at all.
    LIB_FOO_DATA: load = MAIN, type = rw;
}
```

**"The link was clean" is not evidence.** Measured on ld65 V2.18, both diagnostics are conditional on the library's own shape, not on the violation:

| Violation | ld65 warns only when | Silent when |
|---|---|---|
| `align = $100` omitted | the segment contains a source-level `.align`, giving ld65 an explicit request to check | alignment is expressed **only in the cfg** |
| `type = rw` → `type = bss` | the segment's content is non-zero | content is zero-filled (`.res n, 0` — the ordinary scratch shape) |

Neither is ever an error, and neither condition is one a consumer can evaluate: both depend on library source the consumer does not read. A library expressing page alignment in its cfg alone — normal and correct — gets **no diagnostic at all** when a consumer drops the attribute. Mid-area, a `bss` flip makes ld65 emit a shorter image and everything after the hole loads at the wrong address; such a build can appear to work by coincidence. That is why declaring is the library's obligation rather than something a careful consumer could infer.

**Standalone build.** The library's example cfg (`cfg/<libname>.cfg`) MUST add a `SEGMENTS{}` block mapping the prefixed names back to MAIN/RODATA/DATA, so the library's own tests and bench harness build unchanged.

## 5. Aggregate manifest equates

Every library MUST export the following four integer equates, from `src/lib_manifest.s` — **not** `src/lib_version.s`, which §1 requires to carry the deprecated bare exports and nothing else, so that importing a manifest equate cannot drag them into the link:

| Symbol | Semantics |
|---|---|
| `LIB_<X>_ZP_USAGE_BYTES` | Total bytes of ZP slots claimed (sum of all `.exportzp` slots). |
| `LIB_<X>_REU_BANKS_USED` | Bitmask of REU banks claimed (§3). Zero if no REU. |
| `LIB_<X>_RESIDENT_BYTES` | Code+rodata footprint that must remain CPU-resident in any consumer. |
| `LIB_<X>_COLD_BYTES` | Code+rodata footprint a consumer MAY overlay-page (load on demand from REU, kernal-banked RAM or storage). |

Libraries consuming one or more §8 shared primitives MUST additionally export `LIB_<X>_SHARED_PRIMITIVES` (ownership) and `LIB_<X>_SHARED_CONSUMES` (consumption) bitmasks, ORed from the per-primitive bit constants in each §8.x sub-clause. See §8.0 for the allocation table, the build-config state definitions and both masks' required construction forms.

**Footprint equates MUST be safe-direction: round up, never down.** They exist so a consumer can bind them to a budget at assemble time, and an equate that understates the true footprint makes that check pass while the library overruns. Refresh them when a release substantively changes one. `RESIDENT` and `COLD` are a pair — `COLD` is reclaimable after init and may legitimately live in a different region — so a consumer sizing a single region MUST budget for both.

**Where a library's real input restriction is a bound a consumer must respect** — a maximum length, a ceiling — it SHOULD publish that bound here as a symbol the consumer can reference: an equate where the bound fits one, an exported label where it does not (a 256-bit modulus bound cannot be a ca65 equate at all). A consumer SHOULD reference the published symbol rather than re-derive the value. Where the restriction is a *relation* over two caller-supplied values rather than a constant, no scalar expresses it and none should be published — publishing a vacuous or wrong one is worse than publishing nothing.

```asm
.import LIB_NISTCURVES_RESIDENT_BYTES
.import __CRYPTO_HOT_SIZE__   ; ld65-published region size
.assert LIB_NISTCURVES_RESIDENT_BYTES < __CRYPTO_HOT_SIZE__, error, "no room"
```

## 6. Build and consume

### 6.1 Targets and artifact names

Every library MUST provide `make lib`, producing `build/lib/<shortname>.a` plus the consumer-facing `.inc` header and an example `.cfg`. `<shortname>` is the library's §1 prefix, lowercased (`nistcurves`, `x25519`, `polyval`, `chacha20poly1305`, `mlkem`).

Consumers fetch `build/lib/<shortname>[-<variant>].a` and link directly. No mid-build `sed`, no copying intermediates around, and **no `ar65` member surgery** — an archive is consumed as shipped.

### 6.2 Consumer defines reach the build

A library's build MUST accept consumer-supplied ca65 defines and pass them to every translation unit, via two variables kept separate:

- `CONTRACT_DEFINES` — §3 REU bases, §8.x shared-primitive placement and deferral switches, and any other `-D` the contract defines.
- `CONTRACT_ZP_DEFINES` — §2 zero-page slot overrides.

They are separate because a consumer overriding a ZP slot and a consumer relocating an REU table are different operations with different blast radii, and a single variable makes it impossible to pass one without restating the other.

**Both MUST reach every translation unit the archive contains**, not only the ones the library's own tests exercise. A `-D` that reaches some TUs and not others produces an archive whose members disagree about a shared address, which links cleanly and fails at runtime. This is invisible from inside the library's own build, because the library's defaults are self-consistent; it appears only once a consumer overrides something.

### 6.4 The manifest describes the archive it ships in

A library shipping more than one archive (per-variant, per-profile) MUST ensure each archive's §5 manifest equates describe *that* archive. Manifest equate *names* stay per-library (`LIB_<X>_RESIDENT_BYTES`); variant identity lives in which archive the consumer links, not in the symbol name.

### 6.5 The consumer-facing name surface

Renames of exported symbols, archive members, segment names or make targets MUST go through a deprecation window: ship the new name alongside the old one from the library's next MINOR release, and drop the old form at its next MAJOR.

A deprecated alias MUST be gated by `LIB_NO_BARE_EXPORTS` wherever the old name is one that collides across libraries — an ungated alias preserves the collision it exists to retire for the whole window.

## 7. Semver expectations

- **MAJOR** — breaking change to the exported surface (removed or renamed symbols, changed calling conventions, changed memory model).
- **MINOR** — additive (new symbols, new build targets, new manifest equates, new variants).
- **PATCH** — bug fix only, no ABI surface change.
- **`LIB_<X>_ABI_VERSION`** is not derived from MAJOR (§1). The consumer-side gate `.assert LIB_<X>_ABI_VERSION = <expected>, lderror, "..."` is the load-bearing breakage check — `.assert`/`lderror`, never `.if`/`.error`.

**Whether a change is breaking is decided by one question: can a consumer that was conforming before the change be broken by it?** A widened return set breaks an exhaustive comparison, so it is breaking. Correcting documentation to match unchanged code is not — a consumer relying on the wrong documented contract was already broken, and the correction discloses that rather than causing it. Such a correction owes a prominent release note, not a counter bump.

Breaking changes go through a one-MINOR-release deprecation cycle.

## 8. Shared primitives

Some primitives are reimplemented identically across sibling libraries. When a consumer links several into one PRG, each defines its own copy at its own address, wasting resident RAM and boot cycles and making placement a per-library rather than per-consumer decision. This section names primitives whose duplication has been confirmed across at least two adopters, fixes the **shape** every implementation must agree on, and leaves the **address** to the consumer via the `-D` mechanism of §2 and §3.

A primitive listed here is opt-in per library: an adopter MAY keep its own private copy until it migrates. Once migrated, the library reflects ownership in its `LIB_<X>_SHARED_PRIMITIVES` bitmask (§5) — *conditionally*, so a build deferring the primitive to a canonical provider drops the bit.

### 8.0 Bit allocation for `LIB_<X>_SHARED_PRIMITIVES`

Each §8.x sub-clause declares one bit constant `LIB_SHARED_PRIMITIVES_<NAME>`. Bits are append-only and never reused: a deprecated primitive keeps its bit reserved so old consumer cfgs asserting on it still parse.

| Bit | Constant | Primitive | Deferral switch | Defined in |
|---|---|---|---|---|
| `$0001` | `LIB_SHARED_PRIMITIVES_SQTAB` | 8×8 quarter-square multiply table | `SHARED_SQTAB_INIT` | §8.1 |
| `$0002` | `LIB_SHARED_PRIMITIVES_REU_MUL` | 8×8→16 REU multiplication table (128 KB bank pair) | `SHARED_REU_MUL_INIT` | §8.2 |
| `$0004` | `LIB_SHARED_PRIMITIVES_CT_MUL_8X8` | constant-time 8×8→16 multiply body | `SHARED_CT_MUL_8X8` | §8.3 |

**Definition site (normative).** These bit constants are plain assemble-time equates and **MUST NOT** be `.export`ed. Each adopter copies the block verbatim into its own source and `.ifndef`-guards it so a consumer may define them globally without a redefinition error:

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

Both sides of the link carry the values, and only exported symbols collide. The per-library `LIB_<X>_SHARED_PRIMITIVES` and `LIB_<X>_SHARED_CONSUMES` masks are this clause's **sole** exports; they carry the library prefix and cannot collide. An adopter that exports the bit constants instead produces `ld65: Error: Duplicate external identifier` in any composed link — ld65 rejects duplicate externals whether or not the values agree. **This failure is invisible to the adopter**: a library exporting them builds and tests cleanly standalone, and only a composed consumer ever sees it.

**Build-config states (normative).** For each §8.x primitive, a build configuration is in exactly one of three states. A clear ownership bit alone does not distinguish the last two, and they impose opposite obligations on the consumer:

| State | `SHARED_PRIMITIVES` bit | `SHARED_CONSUMES` bit | Obligations |
|---|---|---|---|
| **owner** | set | set | Exports the primitive's init/body per its §8.x clause. |
| **deferring consumer** | clear | set | The deferral switch is defined. The build still reads the primitive at runtime: it retains the consumption surface (placement equates, §3 REU bank claims), the composed link MUST contain exactly one owner, and boot MUST initialise the primitive before first use. |
| **non-consumer** | clear | clear | The placement/precalc export surface is absent, no aggregate claim is made, no provider obligation exists. |

**Mask construction (required form).** Build the ownership mask so a defined switch drops the bit — do **not** OR the bit constants unconditionally. An unconditional mask makes the consumer's disjointness assert unsatisfiable for any legitimately shared primitive, because both sharers keep the bit:

```asm
.ifdef SHARED_SQTAB_INIT
  _OWN_SQTAB   = 0
.else
  _OWN_SQTAB   = LIB_SHARED_PRIMITIVES_SQTAB
.endif
LIB_<X>_SHARED_PRIMITIVES = _OWN_SQTAB | ...   ; OR only the primitives this lib uses
```

**Companion mask `LIB_<X>_SHARED_CONSUMES` (required).** Every adopter consuming any §8 primitive MUST also export it: bit set **iff this build configuration consumes the primitive at all**. A deferral switch does NOT clear it; only profile-gated or permanent non-consumption does. Ownership bits are a subset of consumes bits, pinned at assemble time:

```asm
.assert (LIB_<X>_SHARED_PRIMITIVES & ~LIB_<X>_SHARED_CONSUMES) = 0, error, "a build cannot own a primitive it does not consume"
```

**Exporting a primitive's canonical body or init counts as consuming it**, even when no runtime path in that build invokes it: the body is present, callable, and available for a co-linked sibling to defer to. Do not resolve such a case by dropping the ownership bit — a sibling's deferral may depend on it.

**Consumer-side composition.** Two asserts, one for double ownership and one for coverage:

```asm
.assert (LIB_A_SHARED_PRIMITIVES & LIB_B_SHARED_PRIMITIVES) = 0, error, "shared-primitive double-ownership — exactly one provider must own each primitive"
.assert ((LIB_A_SHARED_CONSUMES | LIB_B_SHARED_CONSUMES) & ~(LIB_A_SHARED_PRIMITIVES | LIB_B_SHARED_PRIMITIVES | APP_OWNED)) = 0, error, "consumed shared primitive with no owner in the link"
```

`APP_OWNED` lets a consumer provide a primitive from its own modules, in which case every linked library legitimately defers. Without the coverage assert the missing-provider failure is an unresolved external at best and a silent wrong result at worst (table read with no init).

### 8.1 Shared 8×8 quarter-square multiply table (`sqtab`)

**Semantics.** Two byte tables `sqtab_lo` and `sqtab_hi`, each 512 bytes, with `(sqtab_hi[n] << 8) | sqtab_lo[n] = floor(n² / 4)` for `n ∈ 0..510`, implementing `a*b = t(a+b) - t(a-b)`. Index 511 is unused; the 512-byte size is forced by the page-alignment and page-delta constraints below.

**Placement contract.** The consumer chooses the base via `LIB_SHARED_SQTAB_BASE`. Each adopting library's canonical header MUST follow this shape:

```asm
.ifndef LIB_SHARED_SQTAB_BASE
    LIB_SHARED_SQTAB_BASE = $...          ; per-lib default for standalone builds
.endif
sqtab_lo = LIB_SHARED_SQTAB_BASE
sqtab_hi = LIB_SHARED_SQTAB_BASE + $0200

.assert (LIB_SHARED_SQTAB_BASE & $00ff) = 0, error, "sqtab base must be page-aligned"
.assert sqtab_hi = sqtab_lo + $0200,        error, "sqtab_hi must follow sqtab_lo by $0200"
```

- **Page alignment** — CT-strict `abs,x` indexing requires a page-aligned base for cycle-stable loads.
- **`$0200` delta** — adopters dispatching via self-modifying code on the lo→hi delta fold this constant into the patched opcode hi-byte; other deltas silently miscompute.

The consumer overrides via `ca65 -D LIB_SHARED_SQTAB_BASE=0x<addr>` — `$`-free per §2, since this define rides `CONTRACT_DEFINES` through make.

**Export discipline.** `LIB_SHARED_SQTAB_BASE` is consumer *input*; libraries MUST NOT `.export` it. `sqtab_lo`/`sqtab_hi` derive from it and MUST NOT be exported either — they are source-level names each consuming TU derives via the pattern above. Two exporters of an unprefixed name collide in any composed link.

**Init.** The canonical entry point is `mul_tables_init`. It populates both tables from the quarter-square recurrence and MUST be idempotent.

**Migration and deferral.** A library MAY keep its own `sqtab_init` exported for back-compat. Under `.ifdef SHARED_SQTAB_INIT` its private init body is gated out and `mul_tables_init` takes over, letting a consumer flip libraries one at a time. **A deferring build MUST `.import` the provider's `mul_tables_init`; exporting a stub body under the deferred name is non-conformant** — it puts two same-named canonical inits into every composed link, which is the duplicate-identifier failure the switch exists to remove.

**Registry.** Adopters MUST emit one §8.4 invocation. The table name is normative — never a library-prefixed variant, which would destroy the cross-adopter audit signal:

```ca65
LIB_PRECALC_TABLE "sqtab", 1024, PRECALC_REGION_RAM, PRECALC_SHARED_YES, "<X>"
```

### 8.2 Shared 8×8→16 REU multiplication table (`reu_mul`)

**Placement contract.** The consumer chooses the base bank; the table claims two contiguous banks:

```asm
.ifndef LIB_SHARED_REU_MUL_BANK
    LIB_SHARED_REU_MUL_BANK = $00          ; per-lib default
.endif
.ifndef LIB_SHARED_REU_MUL_OFFSET
    LIB_SHARED_REU_MUL_OFFSET = $0000
.endif
LIB_SHARED_REU_MUL_BANKS_USED = (1 .shl LIB_SHARED_REU_MUL_BANK) | (1 .shl (LIB_SHARED_REU_MUL_BANK + 1))

.assert LIB_SHARED_REU_MUL_OFFSET = $0000, error, "reu_mul must start at offset 0 within its bank pair"
.assert LIB_SHARED_REU_MUL_BANK < $FE,     error, "reu_mul base bank must leave room for the hi-half bank at base+1"
```

`LIB_SHARED_REU_MUL_BANKS_USED` names both claimed banks as one mask; libraries OR it into their own `LIB_<X>_REU_BANKS_USED` (§5), and consumers compose it into their REU budget assert rather than rewriting the shift expression at each site.

**Export discipline.** Every `LIB_SHARED_REU_MUL_*` equate above is consumer input or derived from it, and libraries MUST NOT `.export` any of them. What a consuming library MUST export instead is its library-prefixed *output* counterparts — `LIB_<X>_SHARED_REU_MUL_BANK`, `_OFFSET`, `_BANKS_USED` — so a consumer can verify co-linked libraries agree on placement. Libraries honouring the ZP/staging knobs — `LIB_SHARED_REU_MUL_ZP_INIT_A`, `LIB_SHARED_REU_MUL_ZP_INIT_B`, `LIB_SHARED_REU_MUL_STAGE_LO`, `LIB_SHARED_REU_MUL_STAGE_HI` — SHOULD export prefixed counterparts of those too.

**The exported value MUST be the value the code reads.** An export whose value the library's REU access paths do not actually consume certifies nothing.

**Fetch.** The canonical per-row entry point is `reu_fetch_mul_row`; `A = a` (row index) on entry, and on return the 512 bytes of row `a` are in the staging buffer.

**DMA completion and settle (normative).** After every REU execute, the library MUST (a) confirm completion via the `$DF00` status bit before the next REU register access, and (b) observe a post-execute settle before that access. A settle met by intervening code is conformant.

**Deferral.** `SHARED_REU_MUL_INIT` and `SHARED_REU_MUL_FETCH` **MUST be defined both or neither** — partial deferral is non-conformant. The §8.1 import-never-stub rule applies: a deferring build MUST NOT export a body under a canonical name.

**Registry.** `LIB_PRECALC_TABLE "reu_mul", 131072, PRECALC_REGION_REU, PRECALC_SHARED_YES, "<X>"` — the name `"reu_mul"` is normative.

### 8.3 Shared constant-time 8×8→16 multiply body (`ct_mul_8x8`)

**Semantics.** A constant-time 8×8→16 multiply computing `a*b = t(a+b) - t(|a-b|)` over the §8.1 tables, with no secret-dependent branches and cycle-stable `abs,x` loads. Entry: `Y = b`; the multiplier `a` is baked into the two `adc #imm` SMC sites by the caller before the inner loop. The 16-bit product returns in `poly_prod_lo` / `poly_prod_hi`. **Depends on §8.1** and inherits its page-alignment asserts.

**Shape contract.** There is no placement equate — this is a code body. Adopters MUST be **byte-identical** to the canonical 59-byte body, enforced by the cross-adopter `ct_mul_brute_check` ratchet (opcode-byte equality across adopters plus a 65 536-case functional brute-check), which MUST return exit 0 before any body change lands.

**Canonical entry.** `ct_mul_8x8`. Adopters whose historical name is `mul_8x8` keep it exported as a back-compat alias at the same address.

**Provider surface.** A §8.3 provider MUST export, and a deferring adopter MUST `.import` where referenced: `ct_mul_8x8`, the two SMC operand sites `smc_sum_a_imm` / `smc_diff_a_imm` (the caller bakes `a` into their `+1` immediates — load-bearing entry state, not internals), and the product scratch `poly_prod_lo` / `poly_prod_hi`. **A deferral switch MUST leave behind `.import`s for every name in this list that the TU's remaining code references** — gating out a definition without importing its replacement fails only in the combination nobody builds.

**No §8.4 entry.** `ct_mul_8x8` is a code body, not a table. Its data dependency is enumerated under §8.1.

### 8.4 Precalc-table enumeration

Every adopter emits one `LIB_PRECALC_TABLE` invocation per precalculated table it ships, so duplication across adopters is detectable mechanically rather than by reading five repositories. The macro emits a `LIB_<X>_PRECALC_<name>_{SIZE,REGION,SHARED}` triple.

```asm
PRECALC_REGION_RAM     = $01
PRECALC_REGION_REU     = $02
PRECALC_REGION_RODATA  = $03
PRECALC_SHARED_NO      = $00
PRECALC_SHARED_YES     = $01

; LIB_PRECALC_TABLE "name", size_bytes, region, shared [, "LIB"]
LIB_PRECALC_TABLE "sqtab",        1024,   PRECALC_REGION_RAM,    PRECALC_SHARED_YES, "NISTCURVES"
LIB_PRECALC_TABLE "reu_mul",      131072, PRECALC_REGION_REU,    PRECALC_SHARED_YES, "NISTCURVES"
LIB_PRECALC_TABLE "lim_lee_comb", 24576,  PRECALC_REGION_REU,    PRECALC_SHARED_NO,  "NISTCURVES"
```

The exports carry the `: abs` hint for the same reason as §1's. Adopters sharing a table MUST agree on its name, size and region — an asymmetry between two adopters describing the same table is the signal this enumeration exists to surface. The macro MUST be included from a single translation unit (§1's TU-isolation rule).

**Zero-consumer carve-out.** The bare `LIB_PRECALC_<name>_*` triple exists for the same reason as §1's bare version exports, and the same carve-out applies: a library with no released consumers SHOULD NOT emit it.

## 10. Adopters

See [adopters.md](adopters.md) for the status table and tracking issues per library.

## 11. Consumers

See [consumers.md](consumers.md) for the list of consumer projects relying on this contract.

## 13. Network backend ABI

A consumer that speaks a protocol over a network device should not care which device it is. This chapter fixes the symbol surface, error namespace and buffer ownership a backend presents, so a consumer can swap an ip65 Ethernet backend for a UCI WiFi one without touching protocol code.

### 13.0 Families and capability declaration

A backend declares which families it implements as a bitmask.

| Bit | Constant | Family | Surface |
|---|---|---|---|
| `$0001` | `NET_FAMILY_CORE` | lifecycle + addressing | `net_init`, `net_dhcp_acquire`, `net_poll`, `net_local_ip`, `net_last_error` |
| `$0002` | `NET_FAMILY_TCP` | TCP client | `net_tcp_connect`, `net_tcp_send`, `net_tcp_close`, `net_tcp_state`, TCP rx ring (§13.3) |
| `$0004` | `NET_FAMILY_UDP` | UDP sockets | `net_udp_listen`, `net_udp_send`, UDP rx buffer (§13.3) |
| `$0008` | `NET_FAMILY_DNS` | name resolution | `net_dns_resolve`, `net_resolved_ip` |

**Definition site.** The four `NET_FAMILY_*` constants are plain assemble-time equates, **never `.export`ed**, living in one header (`net_families.inc`) that both backend and consumer include verbatim — the §8.0 discipline, for the same reason: both sides carry the values, and only exported symbols collide.

```asm
NET_FAMILY_CORE = $0001
NET_FAMILY_TCP  = $0002
NET_FAMILY_UDP  = $0004
NET_FAMILY_DNS  = $0008
```

The backend exports one aggregate, which **MUST** carry the `: absolute` hint for the §1 reason:

```asm
.export NET_BACKEND_FAMILIES : absolute
NET_BACKEND_FAMILIES = NET_FAMILY_CORE | NET_FAMILY_TCP | NET_FAMILY_DNS
```

Bits are append-only and never reused. `NET_FAMILY_CORE` is mandatory. A backend MAY implement `NET_FAMILY_DNS` by deferral — staging the name for `net_tcp_connect` rather than resolving eagerly — and signals that through `net_resolved_ip` (below).

### 13.1 Symbol surface

**Core family:**

| Symbol | Kind | Convention |
|---|---|---|
| `net_init` | entry | No arguments. Detect + initialise the device/driver. C=0 ok; C=1 fail with `net_last_error` set. |
| `net_dhcp_acquire` | entry | No arguments. Acquire a lease; populates `net_local_ip`. Backends on multi-interface devices SHOULD probe all interfaces and take the first lease. |
| `net_poll` | entry | No arguments. Pump one unit of driver work (≤ 1 inbound packet / ≤ 1 firmware read chunk). C=1 only on backend error; **C=0 carries no "data arrived" meaning** — availability is observed through the §13.3 buffers. Clobbers A/X/Y. |
| `net_local_ip` | data, 4 B | Local IPv4 address after `net_dhcp_acquire` succeeds. Zero before. |
| `net_last_error` | data, 1 B | Last error code (§13.2). `$00` = no error. |

**TCP family:**

| Symbol | Kind | Convention |
|---|---|---|
| `net_tcp_connect` | entry | A = port low byte, X = port high byte. Destination staged by a prior `net_dns_resolve`. On failure `net_tcp_state` reflects it. |
| `net_tcp_send` | entry | A = data pointer low, X = high; `net_send_len` (2 B, exported data) = length. 16-bit lengths MUST be honoured in full (§13.3). Short writes are best-effort: the backend records detail in `net_last_error` but returns C=0. |
| `net_tcp_close` | entry | No arguments. Always leaves `net_tcp_state` = closed. |
| `net_tcp_state` | data, 1 B | `$00` `NET_TCP_CLOSED`, `$01` `NET_TCP_CONNECTED`, `$02` `NET_TCP_ERROR`, `$03` `NET_TCP_CONNECT_FAIL`. Values normative. |

**DNS family:**

| Symbol | Kind | Convention |
|---|---|---|
| `net_dns_resolve` | entry | A/X = pointer to NUL-terminated hostname (dotted-quad literals MUST pass through). Resolution MAY be lazy. |
| `net_resolved_ip` | data, 4 B | All-zero = not resolved; `$FF,$FF,$FF,$FF` = resolved internally by the device (deferral marker); anything else = the address. Consumers MUST NOT treat the deferral marker as an address. |

**UDP family:**

| Symbol | Kind | Convention |
|---|---|---|
| `net_udp_listen` | entry | A = local port low, X = high. Binds and arms inbound delivery into the §13.3 UDP rx buffer. |
| `net_udp_send` | entry | `net_udp_send_ptr` (2 B) = payload pointer, `net_udp_send_len` (2 B) = length, `net_udp_dest_ip` (4 B) + `net_udp_dest_port` (2 B) = destination — all exported ABI data, set by the caller before the call. |

Deliberately **not** in the surface: receive callbacks (the §13.3 drain model is the contract), adapter-internal wiring, and consumer UI helpers.

### 13.2 Error and state convention

Every entry point returns **C=0 on success, C=1 on failure**, with `net_last_error` set on failure.

**Callers MUST propagate.** Adapter-internal helpers that can time out (§13.4) return C=1, and every call site either handles or `bcs`-propagates. An adapter that swallows a carry converts a bounded wait into a silent wrong result.

**Advisory codes.** A backend MAY record a nonzero `net_last_error` while returning C=0, where the operation completed but something worth a post-mortem was observed.

**`net_last_error` namespace.** `$00` = OK. The range is carved so a code identifies its origin at a glance:

| Range | Owner |
|---|---|
| `$01-$3F` | Contract-generic codes — platform conditions no single family owns |
| `$40-$7F` | ip65-family backends |
| `$80-$BF` | UCI-family backends |
| `$C0-$FF` | Consumer-private experiments; never allocated by this contract |

**A backend MUST emit only `$00` or codes from its own family range.** Codes are allocated **in the table below first, then in the adapter**, and are never reassigned. A family range is one namespace shared by every consumer's adapter of that family: two adapters can each be internally consistent and still give one byte two meanings, which is what this registry exists to prevent.

| Code | Name | Condition | Disposition |
|---|---|---|---|
| `$01` | `NET_ERR_TIMEBASE_STOPPED` | `net_init` started the CIA TOD and its tenths digit did not change within the verification window | terminal (C=1) |
| `$41` | `NET_ERR_IP65_INIT` | `ip65_init` failed (no RR-Net / cs8900a) | terminal |
| `$42` | `NET_ERR_IP65_DHCP` | `ip65_dhcp_init` failed (no lease) | terminal |
| `$43` | `NET_ERR_IP65_DNS` | `ip65_dns_resolve` failed | terminal |
| `$44` | `NET_ERR_IP65_CONNECT` | `ip65_tcp_connect` failed | terminal |
| `$45` | `NET_ERR_IP65_SEND` | `ip65_tcp_send` failed | terminal |
| `$46` | `NET_ERR_IP65_UDP_LISTEN` | `udp_add_listener` refused the bind (listener table full) | terminal |
| `$47` | `NET_ERR_IP65_UDP_SEND` | `udp_send` rejected below IP | terminal |
| `$81` | `UCI_ERR_NOT_PRESENT` | `$DF1D` did not read back the UCI ID byte `$C9` | terminal |
| `$82` | `UCI_ERR_CMD_FAILED` | error bit set after PUSH_CMD | terminal |
| `$83` | `UCI_ERR_NO_IP` | GET_IPADDR returned all-zero on every probed interface | terminal |
| `$84` | `UCI_ERR_CONNECT_FAIL` | TCP_CONNECT returned an error bit | terminal |
| `$85` | `UCI_ERR_SEND_FAIL` | SOCKET_WRITE returned an error bit | terminal |
| `$86` | `UCI_ERR_READ_FAIL` | SOCKET_READ returned an error bit | terminal |
| `$87` | `UCI_ERR_SHORT_WRITE` | SOCKET_WRITE wrote fewer bytes than requested | **advisory** (C=0) |
| `$88` | `UCI_ERR_NO_SOCKET` | socket-open response yielded no socket id (phantom socket) | terminal |
| `$89` | `UCI_ERR_WAIT_TIMEOUT` | a §13.4 bounded wait exceeded its wall-clock budget | terminal |
| `$8A` | `UCI_ERR_LONG_READ` | SOCKET_READ response header claimed more bytes than requested, and was not the `$FFFF` sentinel | terminal |
| `$8B` | `UCI_ERR_BAD_READ_HDR` | stream-family counterpart of `$8A`; unobserved, reserved defensively | terminal |
| `$8C` | `UCI_ERR_SEND_TOO_LONG` | `net_udp_send_len` exceeds `NET_UDP_SEND_MAX` (§13.3) | terminal |
| `$8D` | `UCI_ERR_OPEN_REFUSED` | firmware refused a socket open: ERROR bit clear, no socket id on RESP_DATA | terminal |

**`$FFFF` is a no-data sentinel on both transports and MUST be excluded before any length arithmetic.** Treating it as a length is how a device-supplied count becomes an unbounded copy; treating it as an over-claim aborts every healthy handshake. Never let a device-supplied count be the only bound on a store loop.

### 13.3 Buffer ownership and 16-bit-safe lengths

The backend owns the buffers; the consumer drains them. No callbacks.

| Symbol | Kind | Convention |
|---|---|---|
| `tcp_recv_buf` | equate | Ring base address. |
| `TCP_RECV_MASK` | equate | Ring size − 1. MUST be a power-of-two minus one. |
| `tcp_recv_head` | data, 2 B | Consumer read position (16-bit, masked). |
| `tcp_recv_tail` | data, 2 B | Backend write position (16-bit, masked). |
| `tcp_recv_overflow` | data, 1 B | Set to 1 by the backend when the ring fills; the backend then drops. Consumers SHOULD surface it in diagnostics. |

**Datagram ceilings are published by the backend (normative).** A UDP backend ships `net_caps.inc` alongside `net_abi.inc`, carrying two assemble-time equates — a header, never `.export`ed, because `.res` sizing and `.assert`s need the values at assembly time:

```asm
; src/net/<backend>/net_caps.inc
NET_UDP_SEND_MAX = 892
NET_UDP_RECV_MAX = 893
```

The two values are **adapter guarantees, not firmware facts**: each is the bound the backend holds on *every* device and firmware the build claims to support, so a backend supporting several revisions publishes the minimum across them, and a build dropping an older firmware MAY raise a value. The header SHOULD state which firmware floor each value assumes. The ceilings are independent and MAY differ in either direction — the contract names two numbers, never "the UDP ceiling".

**Backend obligations.** A `net_udp_send` with `net_udp_send_len > NET_UDP_SEND_MAX` MUST fail C=1 with a family code (UCI: `$8C`) **before any byte reaches the device**. A backend MUST NOT split one datagram across several device writes — on a connected UDP socket each write is its own datagram, so a split is several malformed packets — and MUST NOT truncate a send. It MUST size its own read request so a datagram of at most `NET_UDP_RECV_MAX` bytes is never truncated on any supported firmware.

**Consumer obligations.** Derive any protocol MTU as **`min(NET_UDP_SEND_MAX, NET_UDP_RECV_MAX) − own framing`** for a symmetric protocol, and `.assert` at assembly time that the largest datagram built fits `NET_UDP_SEND_MAX` and that the receive buffer is ≥ `NET_UDP_RECV_MAX`. The asserts are against the consumer's own size equates, since a `.res` in another translation unit has no size ca65 can see. A consumer MUST NOT derive these from adapter-internal equates. A consumer MAY pin its MTU **below** what the ceilings allow by folding its own cap into the minimum; that does **not** relax the receive-buffer obligation, because the backend still delivers any datagram up to `NET_UDP_RECV_MAX` whole and a peer is not bound by this consumer's MTU.

**Truncation is silent at the ABI on some firmware** — a truncated datagram and a complete shorter one can be byte-identical in every register the adapter can read, so it reaches the consumer looking intact and fails its AEAD, presenting as an authentication failure. The MTU pin is the only defence.

**16-bit-safe lengths (normative).** Every rx copy path and every send path MUST handle 16-bit lengths in full. Two measured traps for anyone writing a length cap: a guard of the shape `cmp #>CAP` / `bcc ok` / `bne bad` / `lda lo` / `beq ok` accepts the equal-high-byte case it means to reject, and an 8-bit compare silently passes any length whose low byte happens to be small.

Future ceilings (a stream window, a socket count) join the same header under the `NET_<TRANSPORT>_<THING>_MAX` pattern rather than a second file.

### 13.4 Bounded waits (wall-clock, never cycle-counted)

Any adapter loop waiting on device state — status registers, response drains, data-available flags — MUST bound the wait using a **wall-clock time source** (CIA TOD or timer), never a cycle count or spin counter, and MUST return C=1 with a family timeout code (UCI: `$89`) when the bound is exceeded.

**The time source MUST be started and verified by the adapter.** A CIA TOD does not run until its tenths register is written, and neither the KERNAL nor a preceding program can be assumed to have done so. An adapter that reads a stopped TOD sees a constant, so every bound becomes infinite and the wait it was meant to bound never terminates. Verify that the tenths digit advances within a startup window, and fail `net_init` with `NET_ERR_TIMEBASE_STOPPED` (`$01`) if it does not.

CRA (`$DC0E`) bit 7 selects the 50 Hz / 60 Hz TOD input, which shifts every bound by 20% between the two. Bounds SHOULD be stated with that tolerance.

### 13.5 Zero-page discipline

ZP save/restore around driver calls is **adapter-internal**. A backend MUST NOT require the consumer to perform it, and MUST NOT export save/restore entry points as part of the ABI.

### 13.6 Device timing fences (UCI family)

Every UCI register access is fenced, and the fence duration MUST meet the empirically-bracketed floor across all supported devices — not the floor observed on the developer's own machine.

### 13.7 Fixed-address blob backends

A backend built as a fixed-address binary blob MUST declare its footprint as exported equates so consumer cfgs can compose around it at assemble time:

```asm
.export LIB_NET_IP65_BLOB_BASE, LIB_NET_IP65_BLOB_SIZE
.export LIB_NET_IP65_BLOB_BSS_BASE, LIB_NET_IP65_BLOB_BSS_SIZE

LIB_NET_IP65_BLOB_BASE     = $2000
LIB_NET_IP65_BLOB_SIZE     = $1B27          ; refreshed per blob rebuild
LIB_NET_IP65_BLOB_BSS_BASE = $4000
LIB_NET_IP65_BLOB_BSS_SIZE = $0F8C
```

**Relocation is a relink, not a cfg edit.** The blob is produced by a scripted ld65 relink of the driver's object libraries against a stub and cfg; a consumer MUST NOT attempt to move a blob by changing addresses in its own cfg.

### 13.8 Conformance asserts and consumer intake

A consumer verifies its backend at assemble time rather than discovering a missing family at runtime:

```asm
.import NET_BACKEND_FAMILIES
.assert (NET_BACKEND_FAMILIES & NET_FAMILY_CORE) = NET_FAMILY_CORE, lderror, "backend missing core family"
.assert (NET_BACKEND_FAMILIES & NET_REQUIRED_FAMILIES) = NET_REQUIRED_FAMILIES, lderror, "backend missing a family this consumer needs"

; TCP consumers only
.assert (TCP_RECV_MASK & (TCP_RECV_MASK + 1)) = 0, error, "TCP ring mask must be 2^n - 1"

; UDP consumers only — net_caps.inc is mandatory and buffers are sized from it
.include "net_caps.inc"
.assert NET_UDP_SEND_MAX >= 1, error, "backend must publish NET_UDP_SEND_MAX (SPEC 13.3)"
.assert NET_UDP_RECV_MAX >= 1, error, "backend must publish NET_UDP_RECV_MAX (SPEC 13.3)"
.assert UDP_RECV_BUF_SIZE >= NET_UDP_RECV_MAX, error, "udp_recv_buf smaller than the backend's receive ceiling"
.assert (MY_MTU + MY_FRAMING) <= NET_UDP_SEND_MAX, error, "outbound datagrams would be refused"
.assert (MY_MTU + MY_FRAMING) <= NET_UDP_RECV_MAX, error, "inbound datagrams at MTU would be silently truncated"
```

`net_caps.inc` is per-backend (`src/net/<backend>/`), unlike the shared `net_families.inc`, so **backend selection MUST also select the include path** (`-I src/net/<backend>`). The `NET_UDP_*_MAX` asserts guard against a header that declares the names but never sets them.
