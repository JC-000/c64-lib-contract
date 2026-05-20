# Library Adopters

This page tracks which libraries adopt (or are in the process of adopting) the [c64-lib-contract](SPEC.md). Each row shows the library's state per contract section; tracking issue links point at the library's own repo.

## Adoption status

✅ shipped &nbsp; ⚠️ partial &nbsp; ❌ todo &nbsp; n/a not applicable

| Library | §1 `LIB_VERSION_*` | §2 `.exportzp` ZP | §3 REU symbol contract | §4 Segment naming | §5 Manifest equates | §6 Build target variants | §8 Shared primitives |
|---|---|---|---|---|---|---|---|
| [c64-nist-curves](https://github.com/JC-000/c64-nist-curves) | ✅ shipped (v0.2.0; `LIB_VERSION_*` + `LIB_ABI_VERSION` via [PR #48](https://github.com/JC-000/c64-nist-curves/pull/48)) | ✅ shipped (`src/zp_config.s`) | ✅ shipped ([PR #43](https://github.com/JC-000/c64-nist-curves/pull/43); `LIB_NISTCURVES_REU_BANK_*` in `src/reu_config.s`) | ✅ shipped ([#41](https://github.com/JC-000/c64-nist-curves/issues/41) closed; segments `LIB_NISTCURVES_P256/P384/SHA384/MUL_*`) | ✅ shipped ([#42](https://github.com/JC-000/c64-nist-curves/issues/42) closed; `src/lib_manifest.s`) | ✅ shipped ([#40](https://github.com/JC-000/c64-nist-curves/issues/40) closed; targets `lib-p256-verify` / `lib-p384-verify` / `lib-p384-sha384` / `lib-p384-curve`) | ✅ shipped (§8.1 `sqtab` via [PR #50](https://github.com/JC-000/c64-nist-curves/pull/50); `LIB_SHARED_SQTAB_BASE` in `src/mul_8x8.s`, `LIB_NISTCURVES_SHARED_PRIMITIVES = $0001` in `src/lib_manifest.s`) |
| [c64-polyval](https://github.com/JC-000/c64-polyval) | ❌ todo — [#12](https://github.com/JC-000/c64-polyval/issues/12) | ❌ todo — [#13](https://github.com/JC-000/c64-polyval/issues/13) | ✅ n/a (no REU claims) | ❌ todo — [#14](https://github.com/JC-000/c64-polyval/issues/14) | ❌ todo — [#15](https://github.com/JC-000/c64-polyval/issues/15) | ❌ todo — [#16](https://github.com/JC-000/c64-polyval/issues/16) | n/a (GF(2^128) carry-less mult; does not consume §8.1 `sqtab`) |
| [c64-x25519](https://github.com/JC-000/c64-x25519) | ✅ shipped (v0.5.0, `src/lib_version.s`) | ✅ shipped (`src/zp_config.s`) | ✅ shipped (`src/reu_config.s` — `X25519_REU_BANK` / `X25519_REU_OFFSET`, ca65 `-D` override) | n/a (not yet required by consumers) | ✅ shipped (`src/lib_version.s`) | optional — `make lib-x25519-scalarmult` minimal variant deferred (mentioned as future-consideration in [#45](https://github.com/JC-000/c64-x25519/issues/45); no current consumer requires it) | ✅ shipped (§8.1 `sqtab` via [PR #56](https://github.com/JC-000/c64-x25519/pull/56); `LIB_SHARED_SQTAB_BASE` default `$7800` in `src/constants.s`, `LIB_X25519_SHARED_PRIMITIVES = $0001` in `src/lib_version.s`) |
| [c64-ChaCha20-Poly1305](https://github.com/JC-000/c64-ChaCha20-Poly1305) | ✅ shipped (v0.5.0, `src/lib_version.s`) | ✅ shipped (`src/zp_config.s`) | ✅ shipped via [#19](https://github.com/JC-000/c64-ChaCha20-Poly1305/issues/19) (`POLY1305_REU_BANK` / `POLY1305_REU_OFFSET`) | n/a (consumers in-tree fork today) | ✅ shipped (`src/lib/lib_manifest.s`) | n/a (whole library is small enough) | ✅ shipped (§8.1 `sqtab` via [PR #39](https://github.com/JC-000/c64-ChaCha20-Poly1305/pull/39); `LIB_SHARED_SQTAB_BASE` default `$8000` in `src/lib/poly1305_lib.s`, `LIB_CHACHA20_POLY1305_SHARED_PRIMITIVES = $0001` in `src/lib/lib_manifest.s`; ct_mul_8x8 SMC body uses equate-derived page math per §8.1 placement contract) |

### Bootstrap-era issue summary

All open adopter-side tracking issues, filed 2026-05-20:

- **c64-nist-curves**: [#40](https://github.com/JC-000/c64-nist-curves/issues/40) (minimal archives), [#41](https://github.com/JC-000/c64-nist-curves/issues/41) (segment rename), [#42](https://github.com/JC-000/c64-nist-curves/issues/42) (manifest equates)
- **c64-polyval**: [#12](https://github.com/JC-000/c64-polyval/issues/12) (`LIB_VERSION_*`), [#13](https://github.com/JC-000/c64-polyval/issues/13) (`.exportzp` header), [#14](https://github.com/JC-000/c64-polyval/issues/14) (segment rename), [#15](https://github.com/JC-000/c64-polyval/issues/15) (manifest equates), [#16](https://github.com/JC-000/c64-polyval/issues/16) (archive build targets)
- **c64-x25519**: [#43](https://github.com/JC-000/c64-x25519/issues/43) (REU bank `--asm-define`), [#44](https://github.com/JC-000/c64-x25519/issues/44) (`.exportzp` header), [#45](https://github.com/JC-000/c64-x25519/issues/45) (`LIB_VERSION_*`), [#46](https://github.com/JC-000/c64-x25519/issues/46) (manifest equates)
- **c64-ChaCha20-Poly1305**: [#26](https://github.com/JC-000/c64-ChaCha20-Poly1305/issues/26) (`.exportzp` header), [#28](https://github.com/JC-000/c64-ChaCha20-Poly1305/issues/28) (`LIB_VERSION_*`), [#29](https://github.com/JC-000/c64-ChaCha20-Poly1305/issues/29) (manifest equates)

Issues #43, #44, #26 were filed by [c64-wireguard](https://github.com/JC-000/c64-wireguard); the remaining nine were filed by [c64-https](https://github.com/JC-000/c64-https). All adopter-side maintainers see them as a single coherent ask.

## How to add your library

1. Read [SPEC.md](SPEC.md).
2. Open a PR against this repo adding a row to the status table above with current adoption state per section.
3. File tracking issues against your library's repo for each unimplemented section. Link them back to this contract repo in the issue body.
4. Cross-link this repo from your library's README so consumers can find the contract.
5. Update the row as sections land in subsequent releases.
