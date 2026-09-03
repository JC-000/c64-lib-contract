# Changelog — C64 Library ABI Contract

Terse record of what changed in each tagged version. Every version is tagged `v<version>`; use `git log v<a>..v<b>` or the tag messages for detail.

Entries before 1.0.0 were the contract's §12, which grew to a third of the specification's text and had to be corrected by later releases when it misdescribed earlier ones. It is a changelog, not contract, so it lives here and stays terse.

### 1.0.0 — 2026-08-31
Removed roughly seven eighths of the specification's text: 40,737 words at v0.17.1, 5,154 here. **No symbol, equate, bit value, segment name, build target or error code changed** — a library conformant at v0.17.1 is conformant here without edits. Retired §9, §12, §13, §14, §15 and sub-clauses §6.3, §6.6, §6.7; surviving sections keep their numbers, so existing citations still resolve. §13 went because a network backend is source in its consumer's own tree, so a backend and its consumer are never two independently built artifacts; its names now live only in the consumers' own `net_*.inc` headers. §6.2's define-scoping rule is restated, not changed: `CONTRACT_DEFINES` reaches every TU, `CONTRACT_ZP_DEFINES` every slot-defining TU and no `.importzp`-ing TU. Correction: §8.2's base-bank assert is now `LIB_SHARED_REU_MUL_BANK < 31`, since `1 .shl` a bank of 32 or more exports 0 in the 32-bit §5 mask and the old `< $FE` bound let the collision assert pass falsely; adopters' copies of the placement snippet still carry `< $FE` (c64-nist-curves `src/reu_config.s:68`, c64-x25519 `src/reu_config.s:156`) — with the default bank 0 nothing breaks, and the tighter bound may be adopted at each library's next release without an ABI event. §8.2 also restores the `LIB_SHARED_REU_MUL_STAGE_LO`/`_STAGE_HI` staging-buffer placement and a library that honours the staging knobs SHOULD export the prefixed `_STAGE_LO`/`_STAGE_HI` counterparts (as at v0.17.1). §8.2 names `reu_mul_tables_init` as the canonical init entry point (both providers already export it). §8.4's enumeration floor (≥ 256 B and REU-resident, inner-loop-read or page-aligned) is restated. Added the §3 header-import guard rule (already implemented fleet-wide). Deferred the long-scheduled removal of the bare version exports to a future MAJOR rather than bundling an ABI change with a text cut. precalc_table.inc: comment-only edits; adopters' verbatim copies need not be refreshed. Issue #167 (ABI counter on a contract change without an export change) remains open; this release does not rule on it. See RETIRED.md.

### 0.17.1 — 2026-08-31
The 0.16.0 entry's fleet position contradicted §14.2 in its own release — it said `c64-ChaCha20-Poly1305` owed a stated ceiling while §14.2 in the same tag carved that library out. Corrected in place with an inline marker. This tag is also the permanent home of the sections retired at 1.0.0.

### 0.17.0 — 2026-08-30
§15 asks that a check offered as conformance evidence be shown capable of failing

### 0.16.0 — 2026-08-30
§14 gives entry points a termination obligation — the §13.4 bounded-wait rule, one chapter over

### 0.15.0 — 2026-08-29
§8.4 gains a zero-consumer carve-out for the deprecated bare `LIB_PRECALC_<name>_*` triple

### 0.14.2 — 2026-08-29
§8.1's two `LIB_SHARED_SQTAB_BASE` override examples are shown `$`-free

### 0.14.1 — 2026-08-28
§8.2's read-once rule now names both conformant capture forms, and records that a structurally-met settle is the easiest one to lose

### 0.14.0 — 2026-08-28
§13.2 allocates the first ip65 UDP codes and forbids forwarding a driver's native error values

### 0.13.0 — 2026-08-27
§13.4 requires the adapter to start and verify its wall-clock source; §8.2 requires confirming REU DMA completion via `$DF00` bit 6 and a settle before the next REU register access

### 0.12.1 — 2026-08-27
§13.3 says a consumer MAY pin its MTU below the backend's ceilings, and that doing so does not shrink the receive buffer

### 0.12.0 — 2026-08-27
§13.2 gains an error-code allocation table and an allocate-here-first rule

### 0.11.1 — 2026-08-23
§6.3 states which consequence its select-or-reject rule carries in which case

### 0.11.0 — 2026-08-22
§6.5 and §1 gain zero-consumer carve-outs: a library with no released consumers SHOULD prefix its archive member basenames and SHOULD NOT export the deprecated bare version equates

### 0.10.7 — 2026-08-22
`mlkem_` is registered to `c64-mlkem`

### 0.10.6 — 2026-08-15
§8.3 gains the provider-surface enumeration

### 0.10.5 — 2026-08-15
§6.3 gains the looks-reachable clause

### 0.10.4 — 2026-08-15
§6.3's no-further-matrix posture is scoped to define-reachable combinations

### 0.10.3 — 2026-08-15
§8.4 gets its heading: the fleet had cited it since v0.7.0, but the precalc-enumeration block lived unnumbered inside §8.0 (#109); `precalc_table.inc` unchanged

### 0.10.2 — 2026-08-15
§6.7's prose is corrected to obtain `LIB_SHARED_SQTAB_BASE` source-level rather than by `.import`, which §8.1 forbids (#105); §7's ABI-gate bullet and §8.0's consumes-mask snippet fixed to `.assert`/`lderror` and `.ifdef` (#107)

### 0.10.1 — 2026-08-15
Phase 4 of #76, the section reordering, resolved as a stable-numbers physical reorder: core, then domain chapters, then meta, with every section number unchanged

### 0.10.0 — 2026-08-15
§6.6 lands (#69): consumer footprint asserts against the per-archive §6.4 manifest; §6.7 added (#78): declared non-segment reservations via a never-archived `__MAIN_LAST__` guard TU; §6.5 gains the deprecated-spelling override note

### 0.9.2 — 2026-08-15
Three clarifications from wave implementations: §2 lists `chacha20poly1305_` explicitly; §8.2 makes `reu_fetch_mul_row_bank_patch` conditionally required and states import-never-stub precisely

### 0.9.1 — 2026-08-15
Re-lands three 0.9.0 review amendments that missed the tag (§6.5 suppression gate, §2 registry gate note, §8.2 export example) and fixes four defects from the c64-x25519 adoption report: §8.1 ratifies `sqtab_lo`/`sqtab_hi` and rules canonical ≠ exported; §8.2 narrows the fetch-deferral surface and requires `SHARED_REU_MUL_INIT`/`_FETCH` to move together; §6.2's ZP scoping is restated as the model-independent rule

### 0.9.0 — 2026-08-14
§6 becomes the build-and-consume chapter (§6.2 `CONTRACT_DEFINES`/`CONTRACT_ZP_DEFINES`, §6.3 reachability, §6.4 per-variant manifests, §6.5 name surface); §2 gains the ZP prefix registry; §8.1–§8.3 gain import-never-stub and `SHARED_REU_MUL_FETCH`

### 0.8.6 — 2026-08-14
Every `$`-hex `-D` shell snippet was silently broken as pasted; all are now single-quoted, and §2 gains the normative `$`-free (`0x` hex) rule for values delivered through make

### 0.8.5 — 2026-08-14
§8.1 and §8.2 gain export discipline paragraphs

### 0.8.4 — 2026-08-14
§4 states that `ZEROPAGE` is exempt from the prefixed-segment rule and that §2 owns zero-page allocation (#78 item 5)

### 0.8.3 — 2026-08-14
§4's risk table is corrected: both ld65 diagnostics are conditional on the library's shape, not on the violation, and a mid-area `bss` flip displaces everything after it (#78)

### 0.8.2 — 2026-08-14
Doc-only: every version in §12 is now tagged `v<version>` in this repository, and the header says so

### 0.8.1 — 2026-08-14
§1's two consumer-side version-guard snippets used `.if` on an imported symbol and could not assemble; both now use `.assert`/`lderror`, and the §1 pattern gains the missing `: abs` hint (#73, #74)

### 0.8.0 — 2026-08-14
§4: a library whose correctness or constant-time behaviour depends on how its segments are placed MUST declare those cfg attributes as comments on its example cfg, and consumers MUST preserve them (#63)

### 0.7.5 — 2026-08-13
Doc-only (§1/§7): resolved a self-contradiction in `LIB_<X>_ABI_VERSION`

### 0.7.4 — 2026-08-13
Doc/macro fix (§8.4): the canonical `LIB_PRECALC_TABLE` macro now exports `_REGION` and `_SHARED` with an explicit `: abs` hint

### 0.7.3 — 2026-08-13
Doc-only (§8.0): stated normatively that the §8.x per-primitive bit constants MUST NOT be `.export`ed

### 0.7.2 — 2026-08-13
Doc-only (§8.0/§8.2): corrected the claim that `od65` "reads ca65 `.o` and `.a` archives"

### 0.7.1 — 2026-08-12
Doc-only: every consumer-override snippet now uses ca65's actual flag `-D name[=value]` instead of `--asm-define`, which ca65 rejects (#50)

### 0.7.0 — 2026-08-12
Library-prefixed manifest exports (#43): §1 gains `LIB_<X>_VERSION_*`/`LIB_<X>_ABI_VERSION`, the §8.4 macro gains a library-prefix argument, the bare names are deprecated and gated on `LIB_NO_BARE_EXPORTS`, and §5's aggregates move to `src/lib_manifest.s`

### 0.6.1 — 2026-08-12
Doc-only (§13.0): gave the `NET_FAMILY_*` family bits an explicit definition site

### 0.6.0 — 2026-08-12
Additive: new §13 "Network backend ABI" — the contract's first non-cryptographic chapter

### 0.5.0 — 2026-07-28
§8.0 gains three-state build-config semantics and the companion `LIB_<X>_SHARED_CONSUMES` mask, so a deferring consumer is distinguishable from a non-consumer

### 0.4.2 — 2026-07-28
Doc-only: the §3 REU bank budget assert and the §8.0 double-ownership assert now use ca65's bitwise `&` instead of the boolean `.and` (#41)

### 0.4.1 — 2026-07-18
Doc-only: refreshed the §9 compatibility timeline to reflect growth through v0.4.0 and restated the v1.0 gate as every applicable section

### 0.4.0 — 2026-06-20
New §8.3 `ct_mul_8x8` shared body (bit `$0004`, byte-identity ratchet, #14); §8.0's ownership mask becomes conditional on each primitive's deferral switch (#21)

### 0.3.2 — 2026-06-15
Doc-only: §8.0's composition example cross-checks precalc tables via `od65 --dump-exports`, and notes that an `.import`ed `_SIZE` cannot exceed 65 535 (#18)

### 0.3.1 — 2026-05-23
§8.0 gains the precalc-table catch loop (now §8.4): the enumeration floor, the `LIB_PRECALC_TABLE` macro with canonical `precalc_table.inc`, and intake audit triggers (#11). The `v0.3.0` and `v0.3.1` tags predate header stamping, so their `SPEC.md` self-identifies as 0.2.0

### 0.3.0 — 2026-05-23
New §8.2 `reu_mul` shared REU multiplication table: `LIB_SHARED_REU_MUL_BANK`/`_OFFSET` placement, `reu_mul_tables_init`/`reu_fetch_mul_row` entry points, `SHARED_REU_MUL_INIT` switch, bit `$0002` (#10)

### 0.2.0 — 2026-05-20
New §8 shared primitives with §8.1 `sqtab` (`LIB_SHARED_SQTAB_BASE`, `mul_tables_init`, `SHARED_SQTAB_INIT`); §5 gains `LIB_<X>_SHARED_PRIMITIVES`, bit `$0001` (#5)

### 0.1.0 — 2026-05-20
Initial draft, extracted from `c64-https/docs/library-ingestion-architecture.md` §2 and §3 and generalized for cross-consumer scope

