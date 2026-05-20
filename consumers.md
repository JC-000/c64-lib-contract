# Contract Consumers

This page tracks downstream projects that rely on the [c64-lib-contract](SPEC.md). Each row links to the consumer's lead architecture / ingestion doc.

## Consumer status

| Project | Status | Lead doc |
|---|---|---|
| [c64-https](https://github.com/JC-000/c64-https) | Drafting integration plan | [docs/library-ingestion-architecture.md](https://github.com/JC-000/c64-https/blob/master/docs/library-ingestion-architecture.md) *(URL becomes stable once the doc lands on master; presently uncommitted local file. Plan is dated 2026-05-20.)* |
| [c64-wireguard](https://github.com/JC-000/c64-wireguard) | Drafting integration plan | *(link tbd — see c64-wireguard's docs/ tree; issues [c64-x25519#43](https://github.com/JC-000/c64-x25519/issues/43), [#44](https://github.com/JC-000/c64-x25519/issues/44), [c64-ChaCha20-Poly1305#26](https://github.com/JC-000/c64-ChaCha20-Poly1305/issues/26) reflect their parallel restructuring work)* |

## How to add your project

1. Read [SPEC.md](SPEC.md).
2. Open a PR against this repo adding a row to the consumer table.
3. Link to your consumer's library-ingestion architecture / cfg-restructure doc.
4. If you need a new contract section (e.g., your consumer requires a property no current library exposes), open a PR against [SPEC.md](SPEC.md) with the proposed addition + rationale. Coordinate with current consumers via cross-linked PRs so the contract stays cross-consumer-coherent.
5. Cross-link this repo from your consumer's lead doc so library authors can navigate from your consumer back to the contract.
