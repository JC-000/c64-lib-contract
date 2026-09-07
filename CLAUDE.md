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

- **The adversary must not be whoever wrote the change.** The author is the wrong sole reviewer of
  their own clause; independence is the entire point.
- **Brief it to attack, and give it a section and an adversarial framing**, not "please review".
  It has two standing jobs, to be discharged on every change regardless of what else it was asked:
  keep the contract **concise and readable**, and **refuse closure loops**.
- **The churn test — apply it to every proposed obligation.** A change that drives this repo and
  the five libraries through compliance work must deliver at least one of: easier integration for
  a consumer, a new capability, or a measurable improvement. Work whose only product is closing
  its own loop — a clause generalising an incident that its own fix already settled, a conformance
  pass that ends in a byte-identical artifact, a status table churned to match a status table —
  fails the test and does not get commissioned. The adversary says so out loud, in those terms.
  The clause never has to demonstrate it caused anything, so someone has to ask.
- **Every added sentence gets the two-prong test**, not just the deleted ones. A clause may
  regulate only (1) a name, value or placement that two independently-built artifacts must agree
  on, where (2) a violation is invisible from inside any single repo's own build. Both prongs.
  What fails either belongs in a source comment, a repo-local test, or an issue.
- **Grep every quotation and `file:line` the adversary hands you before repeating it.** Agents
  fabricate citations — verbatim quotes that were not in SPEC.md have been produced here, attached
  to substance that was otherwise sound. Verify before acting, always.
- For a multi-part change, the shape that works is: parallel auditors with distinct sections →
  a fixer in an isolated `git worktree` → a *separate* adversarial reviewer per round, with the
  supervisor verifying citations at each hand-off. Never run the fixer in a `~/Documents/*`
  checkout; parallel sessions have uncommitted work there.
- Subagent return text truncates around 6,000 characters. Tell agents to front-load verdicts and
  totals and to keep tables last.

## 2. Red/green: no check is trusted until it has been seen failing

A check that has never failed is not evidence. Drive it red against a deliberate defect, watch it
go green when the defect is removed, and **record both in the commit or PR body** — the mutation
used and the exact failure text emitted.

Before believing any green:

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
  one-line chore. Branches are `docs/…`, `spec/…`, `feat/…`, `fix/…`, `chore/…`.
- **Do not stack PRs.** Two stacked PRs merging seconds apart stranded a released version off
  `main` here; GitHub's auto-retarget did not fire in the gap. Sequential PRs against `main` cost
  one rebase and have no such failure mode.
- **Re-read a PR or issue thread immediately before commenting on or merging it.** Parallel
  sessions post between checks.
- Conventional commits with a scope: `docs(adopters): …`, `spec(1.2.2): …`, `fix(…): …`.
- `gh` bodies go through a heredoc to a file and `--body-file`, then get read back. Never
  `--body "…"` with backticks in it.
- If `precalc_table.inc` or `examples/*.s` changed, `make verify` must pass — but read section 2
  before citing a green from it as evidence; its legs are subject to these rules like any other.
- **A released SPEC.md change bumps the version line and adds a `CHANGELOG.md` entry.** Per
  release, not per commit: a multi-commit cut shares one version line, and a correction to the
  version line itself bumps nothing.
- **Never mark an adopter cell shipped without checking that adopter's source at the tag** — not
  from a maintainer's report, and not from a source grep where an archive is the real evidence.
