# Contract Consumers

This page tracks downstream projects that rely on the [c64-lib-contract](SPEC.md). Each row links to the consumer's lead architecture / ingestion doc.

## Consumer status

| Project | Status | Lead doc |
|---|---|---|
| [c64-https](https://github.com/JC-000/c64-https) | Integrated — contract alignment merged ([PR #55](https://github.com/JC-000/c64-https/pull/55)); pins currently `libs/nistcurves` **v0.9.1** + `libs/x25519` **v0.10.0** — the pre-wave pair, which carries the [#82](https://github.com/JC-000/c64-lib-contract/issues/82)/[#83](https://github.com/JC-000/c64-lib-contract/issues/83) collisions live at those tags (measured: `Duplicate external identifier: 'LIB_SHARED_REU_MUL_BANKS_USED'` when both `reu_config` objects enter one link). The remediated pair is **nistcurves v0.10.1 × x25519 v0.11.0** — collision-free at tags, gated and ungated, verified in the phase-3 wave close; bump tracked consumer-side as [c64-https#112](https://github.com/JC-000/c64-https/issues/112) (ABI gates move: nistcurves 1→**2**, x25519 →**3**; do not pin nistcurves v0.10.0, which is documented-as-superseded). §13 net-ABI: origin surface; intake items per SPEC §13.8 ([c64-https#70](https://github.com/JC-000/c64-https/issues/70)) | [docs/library-ingestion-architecture.md](https://github.com/JC-000/c64-https/blob/master/docs/library-ingestion-architecture.md) |
| [c64-wireguard](https://github.com/JC-000/c64-wireguard) | Integrated & shipped — v1.0.0 (2026-07-28) links `libs/x25519` v0.8.0 + `libs/chacha20poly1305` v0.6.0 via §6 archives, §8.0 composition (x25519 owns sqtab/reu_mul/ct_mul), link-time §3/§8.0 asserts. Those interim gaps are all now closed — chacha [#47](https://github.com/JC-000/c64-ChaCha20-Poly1305/issues/47)/[#48](https://github.com/JC-000/c64-ChaCha20-Poly1305/issues/48) landed in chacha v0.7.0, contract [#41](https://github.com/JC-000/c64-lib-contract/issues/41)/[#43](https://github.com/JC-000/c64-lib-contract/issues/43) in v0.4.2/v0.7.0. **Master has since advanced past the v1.0.0 pins** to `libs/x25519` **v0.10.1** (`07f004b`) + `libs/chacha20poly1305` **v0.7.0** (`8d9f38b`), so it already carries the §1 prefixed exports and §4 segment renames. The phase-3 wave tags are one step further out: chacha **v0.8.0** and x25519 **v0.11.0** both carry the §2 ZP registry rename, and taking them needs [c64-wireguard#52](https://github.com/JC-000/c64-wireguard/issues/52) first — this repo defines and exports the bare `zp_tmp*`/`zp_ptr*` itself rather than assembling a library `zp_config`, so it must export the canonical spellings and advance its `contract_asserts.s` chacha ABI pin (still `= 1`, stale since chacha generation 2). §13 net-ABI: forked surface; alignment + UCI-adapter resync per SPEC §13.8 ([c64-wireguard#48](https://github.com/JC-000/c64-wireguard/issues/48)) | [docs/library-ingestion-architecture.md](https://github.com/JC-000/c64-wireguard/blob/master/docs/library-ingestion-architecture.md) |

## How to add your project

1. Read [SPEC.md](SPEC.md).
2. Open a PR against this repo adding a row to the consumer table.
3. Link to your consumer's library-ingestion architecture / cfg-restructure doc.
4. If you need a new contract section (e.g., your consumer requires a property no current library exposes), open a PR against [SPEC.md](SPEC.md) with the proposed addition + rationale. Coordinate with current consumers via cross-linked PRs so the contract stays cross-consumer-coherent.
5. Cross-link this repo from your consumer's lead doc so library authors can navigate from your consumer back to the contract.
