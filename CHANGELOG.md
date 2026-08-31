# Changelog — C64 Library ABI Contract

Terse record of what changed in each tagged version. Every version is tagged `v<version>`; use `git log v<a>..v<b>` or the tag messages for detail.

Entries before 1.0.0 were the contract's §12, which grew to a third of the specification's text and had to be corrected by later releases when it misdescribed earlier ones. It is a changelog, not contract, so it lives here and stays terse.

### 1.0.0 — 2026-08-31
Removed roughly six sevenths of the specification's text. **No symbol, equate, bit value, segment name, build target or error code changed** — a library conformant at v0.17.1 is conformant here without edits. Retired §9, §12, §14, §15 and sub-clauses §6.3, §6.6, §6.7; surviving sections keep their numbers, so existing citations still resolve. Added the §3 header-import guard rule (already implemented fleet-wide). Deferred the long-scheduled removal of the bare version exports to a future MAJOR rather than bundling an ABI change with a text cut. See RETIRED.md.

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
§13.4 requires the adapter to start and verify its wall-clock source

### 0.12.1 — 2026-08-27
§13.3 says a consumer MAY pin its MTU below the backend's ceilings, and that doing so does not shrink the receive buffer

### 0.12.0 — 2026-08-27
§13.2 gains an error-code allocation table and an allocate-here-first rule

### 0.11.1 — 2026-08-23
§6.3 states which consequence its select-or-reject rule carries in which case

### 0.11.0 — 2026-08-22
§6.5 gains a zero-consumer carve-out for archive member basenames

### 0.10.7 — 2026-08-22
`mlkem_` is registered to `c64-mlkem`

### 0.10.6 — 2026-08-15
§8.3 gains the provider-surface enumeration

### 0.10.5 — 2026-08-15
§6.3 gains the looks-reachable clause

### 0.10.4 — 2026-08-15
§6.3's no-further-matrix posture is scoped to define-reachable combinations

### 0.10.3 — 2026-08-15
Doc (PATCH): §8.4 exists now. #109 reported 13 dangling `§8.4` references as a v0.10.1 reorder casualty; ref-verification showed the truth is olde

### 0.10.2 — 2026-08-15
§6.7's prose contradicted §8.1's export discipline

### 0.10.1 — 2026-08-15
phase 4 of #76, the section reordering, resolved as a stable-numbers physical reorder

### 0.10.0 — 2026-08-15
. §6.6 lands (#69): consumer footprint asserts against the per-archive §6.4 manifest — library obligations (safe-direction round-up values; RESIDE

### 0.9.2 — 2026-08-15
, three items from wave implementations

### 0.9.1 — 2026-08-15
Two things in one PATCH, both correction-shaped

### 0.9.0 — 2026-08-14
§6 becomes the build-and-consume chapter

### 0.8.6 — 2026-08-14
every `$`-hex `-D` shell snippet was silently broken as pasted

### 0.8.5 — 2026-08-14
§8.1 and §8.2 gain export discipline paragraphs

### 0.8.4 — 2026-08-14
The fleet is split exactly two and two

### 0.8.3 — 2026-08-14
Both diagnostics are conditional on the library's shape, not on the violation

### 0.8.2 — 2026-08-14
Doc-only: every version in §12 is now tagged `v<version>` in this repository, and the header says so

### 0.8.1 — 2026-08-14
The guards could not work

### 0.8.0 — 2026-08-14
Additive (§4): libraries whose correctness or constant-time behaviour depends on how their segments are placed MUST now declare those cfg attribut

### 0.7.5 — 2026-08-13
Doc-only (§1/§7): resolved a self-contradiction in `LIB_<X>_ABI_VERSION`

### 0.7.4 — 2026-08-13
Doc/macro fix (§8.4): the canonical `LIB_PRECALC_TABLE` macro now exports `_REGION` and `_SHARED` with an explicit `: abs` hint

### 0.7.3 — 2026-08-13
Doc-only (§8.0): stated normatively that the §8.x per-primitive bit constants MUST NOT be `.export`ed

### 0.7.2 — 2026-08-13
Doc-only (§8.0/§8.2): corrected the claim that `od65` "reads ca65 `.o` and `.a` archives"

### 0.7.1 — 2026-08-12
Doc-only: fixed every consumer-override snippet to use ca65's actual symbol-define flag `-D name[=value]` instead of `--asm-define`, which ca65 re

### 0.7.0 — 2026-08-12
library-prefixed manifest exports

### 0.6.1 — 2026-08-12
Doc-only (§13.0): gave the `NET_FAMILY_*` family bits an explicit definition site

### 0.6.0 — 2026-08-12
Additive: new §13 "Network backend ABI" — the contract's first non-cryptographic chapter

### 0.5.0 — 2026-07-28
§8.0 gains three-state build-config semantics and the companion `LIB_<X>_SHARED_CONSUMES` mask, so a deferring consumer is distinguishable from a non-consumer

### 0.4.2 — 2026-07-28
Doc-only: fixed the two copy-paste collision-assert snippets to use ca65's bitwise `&` instead of the boolean `.and` — the §3 REU bank budget

### 0.4.1 — 2026-07-18
Doc-only: refreshed the §9 "Compatibility timeline" so it reflects the contract's actual growth — v0.1.0's six core sections (§1–§6) plus the additive

### 0.4.0 — 2026-06-20
Additive: new §8.3 "Shared constant-time 8×8→16 multiply body (`ct_mul_8x8`)" promoting the branchless SMC-dispatched quarter-square multiply body (ca

### 0.3.2 — 2026-06-15
Doc-only: reworked the §8.0 "Consumer-side composition" example to cross-check a composed library's precalc tables via `od65 --dump-exports build/*.o

### 0.3.1 — 2026-05-23
Doc-only. Note: the `v0.3.0` and `v0.3.1` tags predate the practice of stamping the version on `SPEC.md`'s header line, so their `SPEC.md` self-identifies as 0.2.0

### 0.3.0 — 2026-05-23
Additive: new §8.2 "Shared 8×8→16 REU multiplication table (`reu_mul`)" covering the 128 KB `(a, b) → a × b` mul tables duplicated today between `c64-nist-curves` and…

### 0.2.0 — 2026-05-20
Additive: new §8 "Shared primitives" with the first entry §8.1 covering the 8×8 quarter-square multiply table (`sqtab_lo` / `sqtab_hi`, `LIB_SHARED_SQ

### 0.1.0 — 2026-05-20
Initial draft. Extracted from `c64-https/docs/library-ingestion-architecture.md` §2 (target architecture) and §3 (library-side feature requests), generalized for…

