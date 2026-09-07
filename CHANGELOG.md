# Changelog — C64 Library ABI Contract

Terse record of what changed in each tagged version. Every version is tagged `v<version>`; use `git log v<a>..v<b>` or the tag messages for detail.

Entries before 1.0.0 were the contract's §12, which grew to a third of the specification's text and had to be corrected by later releases when it misdescribed earlier ones. It is a changelog, not contract, so it lives here and stays terse.

### 1.2.3 — 2026-09-07
Pins §5's footprint basis. `RESIDENT_BYTES` and `COLD_BYTES` are the **placed span** of the library's prefixed segments — the extent they occupy in a real link, including `ld65`'s fill — not the sum of member object sizes. A sum is exact only where no segment takes fragments from two objects *and* every inter-segment gap is charged separately; neither is guaranteed and both fail silently on a file split or TU reorder. Measured: c64-https read `X25519_RODATA` at 3,808 B by sum against 3,840 B placed, a 32 B `align = $100` gap that would let a `<=` fit assert pass while the segment overflowed; c64-ChaCha20-Poly1305's five literals understated a real link by 39–295 B on the same basis (their #113). Padding arising from a segment's own alignment against the consumer's placement is explicitly excluded: c64-https demonstrated by relink that routing one of their OWN segments out of an area moved `X25519_RODATA`'s pre-segment pad by exactly one page while the segment's size was unchanged at `$F00`, so it is a consumer property the archive cannot know. Charging it worst-case would have mandated up to `align - 1` of over-declaration per aligned segment — the slack this release declines to bound — and §4 already requires the alignment itself to be declared, from which a consumer derives its own exact pad.

**A numeric limit on over-declaration was drafted and dropped**, on the measurements of all five libraries and both consumers. c64-https, the fleet's only `<=` fit assert, carries 7,334 B of slack against a region with ~200 B of real headroom, because §5 compares a library against a whole region holding the consumer's own code too — a 1024 B over-declaration is invisible there, and the 27,000 B failure the idea was modelled on was a §6.4 per-variant regression. c64-wireguard's 8,921 B is under-linking, not over-declaration. nist-curves (twelve archives, margins 98–596 B), polyval (six arms) and CCP are all conformant to any such limit today, so nothing breaks without it. The limit was also the wrong shape twice: against object-size sums a flat 1024 B penalises a library for page-aligning a constant-time segment (1,020 of CCP's apparent 1,079 B is forced fill), and a percentage limit fails polyval's `-compact.a` at 57.5%, which is 256-byte round-up on a 325 B archive.

### 1.2.2 — 2026-09-06
Corrects §6.1's member-isolation rationale, which named only one of the two collision directions the clause governs. The operative test always named both — "suppress under `LIB_NO_BARE_EXPORTS`" is the library-versus-library case (#177: two libraries each exporting the identical bare `LIB_PRECALC_sqtab_SHARED`, with no consumer definition anywhere) and "or define itself under `APP_OWNED`" is the consumer case (#179) — but the trailing sentence mentioned only consumer definitions. Every reading that went wrong today went wrong there. No test changes and no obligation is added or removed: every library conformant at 1.2.1 is conformant here.

Settles #188 by ruling rather than text. §2's dedicated `src/zp_config.s` governs *claimed slots*, and a deprecated bare alias is not one — §2's registry requires every exported slot name to carry a registered prefix, which no bare `zp_` name does. So §2 never required the alias to live there, and an adopter may export it from a separate archived translation unit. Moving an alias to another **archived** TU is not a §6.5 event (neither name, value nor archive changes; members are not consumer-named); moving it to a never-archived TU removes an exported name and does owe §6.5's window and gate. Measured before ruling: of the five adopters only c64-nist-curves is affected — c64-ChaCha20-Poly1305 ships `zp_config.o` in no archive at all, c64-x25519 moved its aliases to a never-archived `main.s`, and c64-polyval and c64-mlkem export no bare `zp_` aliases. A contract clause was disproportionate to one adopter and one file.

### 1.2.1 — 2026-09-06
Corrects §6.1's member-isolation clause, which as published in 1.2.0 forbade the arrangement §1 prescribes in its own worked `src/lib_version.s` block: the bare `LIB_VERSION_*` quadruple sits beside the prefixed forms it aliases, and a consumer imports those. Worse, it made §8.4 unsatisfiable by construction — one `LIB_PRECALC_TABLE` invocation emits the bare triple and its prefixed counterparts into the same TU, and adopters "MUST NOT hand-edit their copy" of the macro. A displaceable name may now share a translation unit with its own prefixed counterparts, and nothing else. Six words; no new obligation and none reversed. §5 aggregates are counterparts of nothing displaceable, so #177's case — bare `LIB_PRECALC_*` beside the §5 equates — stays forbidden, as does a combined version-and-precalc TU. Reported as contract#186 by c64-ChaCha20-Poly1305; four of five adopters were non-conformant to the published wording on a file the contract designs, and none needs to move.

### 1.2.0 — 2026-09-06
Normative (MINOR), one new paragraph in §6.1 replacing scattered restatements: **member isolation**. ld65 links whole archive members, so a symbol a consumer may displace — suppressed under `LIB_NO_BARE_EXPORTS`, or defined by the consumer under `APP_OWNED` — MUST NOT share a translation unit with anything a consumer may import or the library's own code references. The mechanism was previously stated once in §1 for the bare version exports alone; it is now stated once in §6.1, where the `ar65` member-surgery ban that makes the failure unrecoverable already lives, and §1 and §8.4 cite it. §1 keeps its explicit enumeration and its `src/lib_manifest.s` pointer, which §5 depends on; §8.4 keeps its separate single-TU requirement, which is not an isolation rule. Settles #177 (the bare `LIB_PRECALC_*` triple shared a TU with the §5 manifest equates) and #179 (an `APP_OWNED`-able symbol shared a TU with library-private state — this cost c64-https every shipped configuration on c64-nist-curves v0.12.0). No symbol, equate, value or build target changes. c64-nist-curves already conforms. c64-x25519 was non-conformant on both counts: it split the §8.4 invocations into `src/precalc_manifest.s` for v0.14.0 and takes the staging-buffer split next; each is a file split, no exported name or value moves. SPEC.md 5,317 → 5,365 words.

### 1.1.1 — 2026-09-06
Corrects the 1.0.0 preamble here and in SPEC.md: the text cut also dropped three §6.1 build targets required at v0.17.1 (`make` with no arguments, `make lib-<variant>`, `make lib-app-owned`), which the "no build target changed" claim contradicted. Two normative changes the cut carried silently are withdrawn: §6.1's requirement that `make lib` also produce a `.inc` header and an example `.cfg` — never proposed, naming neither path, and failing §0's scope rule on both prongs — and §4's loss of "or similar" on `cfg/<libname>.cfg`. No adopter's ABI surface changes. Reported as contract#178.

### 1.1.0 — 2026-09-03
Normative (MINOR), one paragraph in §7 and a pointer in §1: the `LIB_<X>_ABI_VERSION` counter moves on what the code does, not on whether the export list changed. It moves when a consumer conforming to the previously documented contract can be broken — typically an entry point's actual return set gaining a value, which silently makes exhaustive handling non-exhaustive. It holds when undocumented behaviour becomes documented, and when documentation is corrected to match unchanged code. Settles #167, where three adopters hit this within one week and the shipped text decided none of them. **No shipped counter changes**: c64-nist-curves holds 2 at v0.12.0 (a defined return convention where none was documented), c64-x25519 holds 3 at v0.13.0 (a corrected `Clobbers` banner over unchanged code), and c64-ChaCha20-Poly1305's 3 → 4 on main (`aead_decrypt` gained a domain-guard return) is ratified before it tags. The clause governs the counter only — such a change is not thereby MAJOR and owes no deprecation cycle, since a return set has no side-by-side form. Adds 145 words; SPEC.md 5,154 → 5,299.

### 1.0.0 — 2026-09-03
Removed roughly seven eighths of the specification's text: 40,737 words at v0.17.1, 5,154 here. **No symbol, equate, bit value, segment name or error code changed.** Three build targets §6.1 required at v0.17.1 — `make` with no arguments, `make lib-<variant>` and `make lib-app-owned` — are no longer required of anyone; `make lib` is unchanged. A library conformant at v0.17.1 is conformant here without edits. Retired §9, §12, §13, §14, §15 and sub-clauses §6.3, §6.6, §6.7; surviving sections keep their numbers, so existing citations still resolve. §13 went because a network backend is source in its consumer's own tree, so a backend and its consumer are never two independently built artifacts; its names now live only in the consumers' own `net_*.inc` headers. §6.2's define-scoping rule is restated, not changed: `CONTRACT_DEFINES` reaches every TU, `CONTRACT_ZP_DEFINES` every slot-defining TU and no `.importzp`-ing TU. Correction: §8.2's base-bank assert is now `LIB_SHARED_REU_MUL_BANK < 31`, since `1 .shl` a bank of 32 or more exports 0 in the 32-bit §5 mask and the old `< $FE` bound let the collision assert pass falsely; adopters' copies of the placement snippet still carry `< $FE` (c64-nist-curves `src/reu_config.s:68`, c64-x25519 `src/reu_config.s:156`) — with the default bank 0 nothing breaks, and the tighter bound may be adopted at each library's next release without an ABI event. §8.2 also restores the `LIB_SHARED_REU_MUL_STAGE_LO`/`_STAGE_HI` staging-buffer placement and a library that honours the staging knobs SHOULD export the prefixed `_STAGE_LO`/`_STAGE_HI` counterparts (as at v0.17.1). §8.2 names `reu_mul_tables_init` as the canonical init entry point (both providers already export it). §8.4's enumeration floor (≥ 256 B and REU-resident, inner-loop-read or page-aligned) is restated. Added the §3 header-import guard rule (already implemented fleet-wide). Deferred the long-scheduled removal of the bare version exports to a future MAJOR rather than bundling an ABI change with a text cut. precalc_table.inc: comment-only edits; adopters' verbatim copies need not be refreshed. Issue #167 (ABI counter on a contract change without an export change) remains open; this release does not rule on it. See RETIRED.md.

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

