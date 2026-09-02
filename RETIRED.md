# Retired sections

These sections and sub-clauses were removed in **1.0.0**. Their full text is preserved, unchanged, at tag **`v0.17.1`**:

    git show v0.17.1:SPEC.md

Every adopter citation to a retired section resolves there permanently. Surviving sections kept their original numbers, so citations to them still resolve against the current `SPEC.md`; the numbering has gaps rather than being renumbered, precisely so nothing has to be rewritten.

| Retired | Was | Why it went | Where the obligation lives now |
|---|---|---|---|
| **§6.3** | Every contemplated configuration is reachable | Build-system hygiene for five Makefiles. Its one consumer-visible protection — no `ar65` member surgery — is in §6.1, which survives. The rest failed at the adopter's own build. | §6.1 (surgery ban); §6.2 (the define-scoping rule) |
| **§6.6** | Consumer footprint asserts | A `RECOMMENDED` snippet the consumer writes in their own tree. Deleting it deleted a suggestion. | §5 — footprint equates MUST be safe-direction, and RESIDENT/COLD are a pair |
| **§6.7** | Declared non-segment reservations | The guard TU ships in no archive, so nothing it asserts crosses a library boundary. | §4 (declare load-bearing cfg attributes); §8.1 (sqtab page-alignment assert) |
| **§9** | Compatibility timeline | A narrative of the contract's own growth. | CHANGELOG.md |
| **§13** | Network backend ABI | Every network backend is source in its consumer's own tree, compiled by that consumer's Makefile into its own binary — never an archive another repository links — so there are not two independently-built artifacts (prong 1), and a violation is visible from inside the owning repository's build (prong 2). The two consumers' backend copies have already diverged, and each consumer's `net_families.inc` declares itself canonical. | The consumer repositories' own `net_abi.inc` / `net_families.inc` / `net_caps.inc` headers, which already declare themselves canonical; the v0.17.1 text for the prose |
| **§12** | Changelog | 34% of the document, and a second codebase: it required correct-forward releases to fix its account of earlier ones. | CHANGELOG.md, terse |
| **§14** | Entry-point termination and documented domain | Its MUST was discharged by its first limb for any terminating entry point, so it could not reach the preconditions its own rationale cited. The fix it named as its flagship case landed 26 hours before the clause existed. | §5 — publish a bound as a referenceable symbol (§14.2's one crossing sentence) |
| **§15** | Conformance evidence | SHOULD-level and non-retroactive. Every defect it existed to prevent had already been found and fixed by the audits that motivated it. | — |

## Existing conformance records stay valid

**A conformance record that cites a retired section remains valid at the tag it cites, and does not need restating against the post-1.0 document.** A record like "conformant with §14 at `v0.16.0`" is a claim about a specific tagged revision, which is what tag-pinning is for; the retirement does not falsify it and does not create work. Adopters should leave such records as they are.

The same holds for source comments and design docs: a citation to a retired section is a citation to `v0.17.1`, and `git show v0.17.1:SPEC.md` resolves it. Rewriting them would be churn with no reader benefit.

## Where the retired reasoning went

The retired sections are not repudiated — they are out of scope for a contract, which is a narrower claim. §14's termination reasoning and §15's "a check offered as evidence should be shown capable of failing" both remain readable, unchanged, at `v0.17.1`, and a library that finds them useful should keep applying them locally.

§15 in particular produced real findings in the hours it was in force — a per-check evidence inventory across four libraries, which surfaced defects that had survived ordinary review. That the idea works is not in dispute. What the two-prong rule says is that a shared normative clause was the wrong instrument for it: the property it governs is visible to the owning repository's own audit, which is how every one of those defects was actually found. **Keep the practice; do not keep it as an obligation this contract imposes.**

## The rule applied

A clause belongs in `SPEC.md` only if it governs **(1) a name, value or placement that two independently-built artifacts must agree on, where (2) a violation is invisible from inside any single repository's own build.** Both prongs are required.

Each retirement above fails at least one prong. §6.7's guard crosses no boundary (prong 1). §14 and §15 govern properties of a single routine or a single repository's test suite, each visible to the owning repo's own audit (prong 2) — which is how both were found, before either clause existed.

The rule keeps what it should: §2's ZP registry passes both — a slot name is linker-visible, agreement is mandatory, and three adopters independently converged on the same bare names while each built green alone. §8 likewise: two adopters (`c64-x25519` and `c64-ChaCha20-Poly1305`) each exported the §8.0 bit constants, each built green alone, and the composed link failed with `Duplicate external identifier` ([#55](https://github.com/JC-000/c64-lib-contract/issues/55), [#56](https://github.com/JC-000/c64-lib-contract/issues/56)).

## If you are re-proposing one of these

State which prong it passes, and name the failure a consumer would see that no adopter's own build would catch. If the answer is that a library author might make a mistake in their own tree, that is a matter for their source comments, tests or issue tracker.
