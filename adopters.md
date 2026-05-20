# Library Adopters

This page tracks which libraries adopt (or are in the process of adopting) the [c64-lib-contract](SPEC.md). Each row shows the library's state per contract section; tracking issue links point at the library's own repo.

## Adoption status

✅ shipped &nbsp; ⚠️ partial &nbsp; ❌ todo &nbsp; n/a not applicable

| Library | §1 `LIB_VERSION_*` | §2 `.exportzp` ZP | §3 REU symbol contract | §4 Segment naming | §5 Manifest equates | §6 Build target variants |
|---|---|---|---|---|---|---|
| [c64-nist-curves](https://github.com/JC-000/c64-nist-curves) | ✅ shipped (v0.2.0) | ✅ shipped (`src/zp_config.s`) | ⚠️ partial (banks hardcoded; `LIB_NISTCURVES_REU_BANKS_USED` mask not yet exported) | ❌ todo — [#41](https://github.com/JC-000/c64-nist-curves/issues/41) | ❌ todo — [#42](https://github.com/JC-000/c64-nist-curves/issues/42) | ❌ todo — [#40](https://github.com/JC-000/c64-nist-curves/issues/40) |
| [c64-x25519](https://github.com/JC-000/c64-x25519) | ❌ todo — [#45](https://github.com/JC-000/c64-x25519/issues/45) | ❌ todo — [#44](https://github.com/JC-000/c64-x25519/issues/44) | ❌ todo — [#43](https://github.com/JC-000/c64-x25519/issues/43) | n/a (not yet required by consumers) | ❌ todo — [#46](https://github.com/JC-000/c64-x25519/issues/46) | optional — see [#45](https://github.com/JC-000/c64-x25519/issues/45) |
| [c64-ChaCha20-Poly1305](https://github.com/JC-000/c64-ChaCha20-Poly1305) | ✅ shipped (v0.5.0, `src/lib_version.s`) | ✅ shipped (`src/zp_config.s`) | ✅ shipped via [#19](https://github.com/JC-000/c64-ChaCha20-Poly1305/issues/19) (`POLY1305_REU_BANK` / `POLY1305_REU_OFFSET`) | n/a (consumers in-tree fork today) | ✅ shipped (`src/lib/lib_manifest.s`) | n/a (whole library is small enough) |

### Bootstrap-era issue summary

All open adopter-side tracking issues, filed 2026-05-20:

- **c64-nist-curves**: [#40](https://github.com/JC-000/c64-nist-curves/issues/40) (minimal archives), [#41](https://github.com/JC-000/c64-nist-curves/issues/41) (segment rename), [#42](https://github.com/JC-000/c64-nist-curves/issues/42) (manifest equates)
- **c64-x25519**: [#43](https://github.com/JC-000/c64-x25519/issues/43) (REU bank `--asm-define`), [#44](https://github.com/JC-000/c64-x25519/issues/44) (`.exportzp` header), [#45](https://github.com/JC-000/c64-x25519/issues/45) (`LIB_VERSION_*`), [#46](https://github.com/JC-000/c64-x25519/issues/46) (manifest equates)
- **c64-ChaCha20-Poly1305**: [#26](https://github.com/JC-000/c64-ChaCha20-Poly1305/issues/26) (`.exportzp` header), [#28](https://github.com/JC-000/c64-ChaCha20-Poly1305/issues/28) (`LIB_VERSION_*`), [#29](https://github.com/JC-000/c64-ChaCha20-Poly1305/issues/29) (manifest equates)

Issues #43, #44, #26 were filed by [c64-wireguard](https://github.com/JC-000/c64-wireguard); the remaining nine were filed by [c64-https](https://github.com/JC-000/c64-https). All adopter-side maintainers see them as a single coherent ask.

## How to add your library

1. Read [SPEC.md](SPEC.md).
2. Open a PR against this repo adding a row to the status table above with current adoption state per section.
3. File tracking issues against your library's repo for each unimplemented section. Link them back to this contract repo in the issue body.
4. Cross-link this repo from your library's README so consumers can find the contract.
5. Update the row as sections land in subsequent releases.
