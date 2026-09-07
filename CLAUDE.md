# Working standards — c64-lib-contract

How work gets done in this repo. **This is process, not contract text.** None of it belongs in
`SPEC.md`: every rule here governs a property visible to the owning repository's own audit, so it
fails prong 2 of the scope rule in SPEC.md's preamble. Retired §15 carried the red/green rule as a
SHOULD; it was cut on scope, not because it failed — it "produced real findings in the hours it was
in force" (`RETIRED.md:30`). That is precisely why the practice needs a home. `RETIRED.md` states
the disposition this file acts on: "**Keep the practice; do not keep it as an obligation this
contract imposes.**" Do not read this file as grounds to un-retire §15.

## 1. Every change gets an adversarial review

Standing rule. Applies to SPEC.md clauses, rulings on issues, `adopters.md` status claims and
tooling alike — not only to whole-document reviews.

- **The adversary must not be the agent or context that drafted the change**, and is briefed to
  attack a named section, not to "review" it. In a single-maintainer repo authorship is not the
  discriminator — freshness is. An agent re-reading its own draft ratifies it.
- **Concision has a cost, so make the proposer pay it.** Every proposed addition states its word
  count and what it deletes or subsumes. The contract is ~5,400 words governing roughly 3,000 lines
  of assembly, after an 87% cut; a change that only adds is a change that has not been thought
  through.
- **The churn test — apply it to every proposed obligation.** Work that drives this repo and the
  five libraries through compliance effort must **name what breaks if it does not exist, and count
  the adopters it actually moves.** `CHANGELOG.md:10` is the model — *"Measured before ruling: of
  the five adopters only c64-nist-curves is affected … A contract clause was disproportionate to
  one adopter and one file."* Measure before ruling; do not accept an adjective in place of a
  count. Three shapes fail the test outright, all attested:
  1. **A clause generalising an incident its own fix already settled.** §14's flagship fix landed
     26 hours before the clause existed (`RETIRED.md:17`); every defect §15 existed to prevent was
     already found and fixed by the audits that motivated it (`RETIRED.md:18`).
  2. **A conformance pass no consumer's link can observe.** c64-x25519#123 spent **+1080 −33**
     discharging a SHOULD-level §15, stating in its own body that "Nothing here was non-conformant
     before". The bar is *unobservable to a consumer's link*, not *byte-identical*: a file split
     moving no exported name is a legitimate pass.
  3. **A status table churned to match a status table.** `adopters.md` is load-bearing; README's
     banner is derived from it and is not worth a PR of its own.
  The clause never has to demonstrate it caused anything, so someone has to ask.
- **Every added sentence gets the two-prong test**, not just the deleted ones. A clause may
  regulate only (1) a name, value or placement that two independently-built artifacts must agree
  on, where (2) a violation is invisible from inside any single repo's own build. Both prongs.
  What fails either belongs in a source comment, a repo-local test, or an issue.
- **Grep every quotation and `file:line` the adversary hands you before repeating it.** Agents
  fabricate citations — verbatim quotes that were not in SPEC.md have been produced here, attached
  to substance that was otherwise sound. An adversary is also scoped to what it searched: one that
  read only this repo will call an adopter-repo instance invented.
- **Record the disposition.** The PR or issue says what the review found and what was accepted or
  rejected, with the reason. "It was reviewed" is unfalsifiable, and an unrecorded correct finding
  disappears — the same gap section 2 closes for checks by demanding the mutation and failure text.
- For a multi-part change: parallel auditors with distinct sections → a fixer in an isolated
  `git worktree` → a *separate* adversarial reviewer per round, the supervisor verifying citations
  at each hand-off. Never run the fixer in a `~/Documents/*` checkout; parallel sessions have
  uncommitted work there. Agent replies truncate near 6,000 characters, so require front-loaded
  verdicts and totals, tables last.

## 2. Red/green: no check is trusted until it has been seen failing

A check that has never failed is not evidence. Drive it red against a deliberate defect, watch it
go green when the defect is removed, and **record both in the commit or PR body** — the mutation
used and the exact failure text emitted.

**These rules bind this repo's own gates, not only adopters' and not only new work.** Not applying
them to `make verify` is how #194 shipped. Before believing any green:

- **Confirm the failure names the property under test.** A build that goes red because an adjacent
  assert fired first has not exercised your check at all. Read the failure text; do not infer it
  from the exit code.
- **Prove the leg can fail at all.** `cmd || (echo "FAIL: …"; exit 1)` mid-`;`-chain does not
  propagate its exit status — it prints the FAIL text and then reports success. Legs written this
  way have shipped here, structurally incapable of failing, inside commits whose subject was that
  very trap.
- **Any absence assertion needs a positive control.** "Found none" and "looked at nothing" are
  indistinguishable: an empty dump, a bad ref, a glob that matched nothing and a renamed file all
  satisfy a zero-count. Assert the subject was present before believing the zero.
- **Derive the population; never hand-write a roster.** A roster and a predicate look equally
  reasonable in review, and only one survives its subject growing. Rosters here have reported
  "0 names" for surfaces they had never examined.
- **A diff is blind to any error its two sides share.** A comparison check whose extractor breaks
  symmetrically does not fail — it agrees, wrongly. Keep at least one piece of evidence that is not
  comparison-shaped (byte-identity of a linked PRG, a known-answer suite), and prefer a
  reconciliation assertion whose parts must sum to a total over any count whose pass condition is
  zero.
- **Check the fixture, not just the check.** A gate whose fixture was written to the library's
  requirement rather than to the contract's surface passes by construction.

## 3. Workflow

- **`main` is PR-only.** Branch, push, `gh pr create` — never push `main` directly, not even for a
  one-line chore. Branches are conventionally `docs/…`, `spec/…`, `fix/…`, `feat/…`, `chore/…`, in
  descending order of use; `consumers/…` and `claude/…` also appear. The list is not closed.
- **Do not stack PRs.** Two stacked PRs merging seconds apart stranded a released version off
  `main` here; GitHub's auto-retarget did not fire in the gap. Sequential PRs against `main` cost
  one rebase and have no such failure mode.
- **Re-read a PR or issue thread immediately before commenting on or merging it.** Parallel
  sessions post between checks.
- Conventional commits with a scope: `docs(adopters): …`, `spec(1.2.2): …`, `fix(…): …`.
- `gh` bodies go through a heredoc to a file and `--body-file`, then get read back. Never
  `--body "…"` with backticks in it.
- If `precalc_table.inc` or `examples/*.s` changed, `make verify` must pass.
- **A released SPEC.md change bumps the version line and adds a `CHANGELOG.md` entry.** Per
  release, not per commit: a multi-commit cut shares one version line, and a correction to the
  version line itself bumps nothing.
- **Never mark an adopter cell shipped without checking that adopter's source at the tag** — not
  from a maintainer's report, and not from a source grep where an archive is the real evidence.
