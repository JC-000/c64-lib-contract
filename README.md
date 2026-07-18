# c64-lib-contract

A cross-consumer ABI / memory-manifest contract for Commodore 64 cryptographic libraries.

C64 crypto libraries (`c64-nist-curves`, `c64-x25519`, `c64-ChaCha20-Poly1305`, `c64-polyval`, future `c64-aes256-ecdsa`, ...) are consumed by multiple downstream projects (`c64-https`, `c64-wireguard`, future C64 TLS / IPsec / VPN clients). Without a shared contract, every consumer ends up patching library sources at integration time to fit its own memory layout, ZP, and REU usage — and every library tag bump forces consumer-side cfg surgery.

This repo specifies the contract that lets libraries publish their version, ZP slots, REU layout, segment names, and minimal-archive build targets as code, so consumers can ingest cleanly. Long-term goal: a library tag push automatically triggers a downstream `build → test → open PR` pipeline without any human cfg work.

## Status

**v0.4.1 draft (2026-07-18).** The contract has grown from its bootstrap six sections to also cover §7 semver expectations and §8 shared primitives — §8.0 precalc-table enumeration, §8.1 `sqtab`, §8.2 `reu_mul`, and §8.3 `ct_mul_8x8`. All four current adopters (`c64-nist-curves`, `c64-polyval`, `c64-x25519`, `c64-ChaCha20-Poly1305`) have shipped the core sections plus the shared-primitive clauses that apply to them, verified cell-by-cell against adopter source as of 2026-07-18 — see [adopters.md](adopters.md) for the per-section status table and [SPEC.md §12](SPEC.md#12-changelog) for the version history. Will declare v1.0 once the current adopters have completed every applicable section and the shared-primitive migration has settled.

## What's in here

- [**SPEC.md**](SPEC.md) — the contract itself: version equates, `.exportzp` ZP slots, REU bank symbols, segment naming, aggregate manifest equates, build-target conventions, shared-primitive promotion clauses.
- [**adopters.md**](adopters.md) — libraries that follow (or are in the process of following) the contract, with tracking-issue links per section.
- [**consumers.md**](consumers.md) — downstream projects that rely on the contract.
- [**precalc_table.inc**](precalc_table.inc) + [**examples/precalc_table_smoke.s**](examples/precalc_table_smoke.s) + [**Makefile**](Makefile) — canonical ca65 source for the SPEC §8.0 catch-loop `LIB_PRECALC_TABLE` macro, smoke-tested via `make verify` (requires `ca65` from the cc65 toolchain).

## How to participate

- **Library authors**: read SPEC.md, open a PR adding your library to `adopters.md`, file tracking issues against your library for each unimplemented section. Cross-link to this repo from your library's README so consumers can find the contract.
- **Consumer authors**: read SPEC.md, open a PR adding your project to `consumers.md`, link to your project's library-ingestion docs. If you need new contract sections (e.g., your consumer requires a property no current library exposes), open a PR against SPEC.md with the proposed addition + rationale.
- **Contract changes**: open a PR with the change + rationale. v1.0 will gate breaking changes behind a deprecation cycle (currently in draft, breaking changes are still cheap).

## Acknowledgments

The contract was bootstrapped from `c64-https`'s library-ingestion architectural work on 2026-05-20, with parallel input from `c64-wireguard`. Both consumer agents filed coordinated issues against the libraries on the same day to seed the contract.

Specifically extracted from [`c64-https/docs/library-ingestion-architecture.md`](https://github.com/JC-000/c64-https/blob/master/docs/library-ingestion-architecture.md) §2 (target architecture) and §3 (library-side feature requests). The c64-https doc itself remains consumer-private (it covers c64-https's specific cfg restructure, overlay strategy, and CI/CD pipeline that aren't relevant to library authors).
