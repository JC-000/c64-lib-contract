# ct_mul_brute_check report

Run by `tools/ct_mul_brute_check.py` to gate c64-lib-contract
SPEC §8.3 promotion of `mul_8x8` / `ct_mul_8x8` per issue #14.

## Per-adopter findings

### `chacha`

- Source: `/Users/someone/Documents/c64-ChaCha20-Poly1305/src/lib/poly1305_lib.s`
- Entry: `ct_mul_8x8` (lines 549..582, 34 source lines)
- Body bytes: 59
- SHA-256 (first 16 hex chars): `c9fe8fdc6937e256`
- Functional brute-check: 65536/65536 (a, b) pairs match `a * b`

Opcode dump:

```
  +0000: 98 18 69 00 aa a9 9c 69 00 8d 29 10 69 02 8d 33
  +0010: 10 98 38 e9 00 8d 08 80 a9 00 e9 00 8d 09 80 4d
  +0020: 08 80 38 ed 09 80 a8 bd 00 80 38 f9 00 9c 8d 00
  +0030: 80 bd 00 82 f9 00 9e 8d 01 80 60
```

### `nist-curves`

- Source: `/Users/someone/Documents/c64-nist-curves/src/mul_8x8.s`
- Entry: `mul_8x8` (lines 225..293, 69 source lines)
- Body bytes: 63
- SHA-256 (first 16 hex chars): `913bd104417508bc`
- Functional brute-check: 65536/65536 (a, b) pairs match `a * b`

Opcode dump:

```
  +0000: a8 8e 03 80 18 6d 03 80 aa a9 9c 69 00 8d 2d 10
  +0010: 69 02 8d 37 10 98 38 ed 03 80 a8 a9 00 e9 00 8d
  +0020: 09 80 98 4d 09 80 38 ed 09 80 a8 bd 00 9c 38 f9
  +0030: 00 9c 8d 00 80 bd 00 9e f9 00 9e 8d 01 80 60
```

### `x25519`

- Source: `/Users/someone/Documents/c64-x25519/src/mul_8x8.s`
- Entry: `mul_8x8` (lines 173..227, 55 source lines)
- Body bytes: 84
- SHA-256 (first 16 hex chars): `62cdab9d62592d83`
- Functional brute-check: 65536/65536 (a, b) pairs match `a * b`

Opcode dump:

```
  +0000: 8d 02 80 8e 03 80 ad 02 80 38 ed 03 80 8d 04 80
  +0010: a9 00 e9 00 8d 05 80 4d 04 80 38 ed 05 80 a8 ad
  +0020: 02 80 18 6d 03 80 aa a9 00 69 00 8d 06 80 a9 9c
  +0030: 18 6d 06 80 8d 42 10 a9 9e 18 6d 06 80 8d 4c 10
  +0040: bd 00 9c 38 f9 00 9c 8d 00 80 bd 00 9e f9 00 9e
  +0050: 8d 01 80 60
```

## Pairwise byte-identity

| Pair | Bit-identical? |
|---|---|
| `chacha` vs `nist-curves` | NO |
| `chacha` vs `x25519` | NO |
| `nist-curves` vs `x25519` | NO |

## Divergence detail

### `chacha` vs `nist-curves`

- `chacha` body: 59 bytes
- `nist-curves` body: 63 bytes
- Byte-level diff (first 32 mismatches):

```
  +0000: chacha=98  nist-curves=a8
  +0001: chacha=18  nist-curves=8e
  +0002: chacha=69  nist-curves=03
  +0003: chacha=00  nist-curves=80
  +0004: chacha=aa  nist-curves=18
  +0005: chacha=a9  nist-curves=6d
  +0006: chacha=9c  nist-curves=03
  +0007: chacha=69  nist-curves=80
  +0008: chacha=00  nist-curves=aa
  +0009: chacha=8d  nist-curves=a9
  +000a: chacha=29  nist-curves=9c
  +000b: chacha=10  nist-curves=69
  +000c: chacha=69  nist-curves=00
  +000d: chacha=02  nist-curves=8d
  +000e: chacha=8d  nist-curves=2d
  +000f: chacha=33  nist-curves=10
  +0010: chacha=10  nist-curves=69
  +0011: chacha=98  nist-curves=02
  +0012: chacha=38  nist-curves=8d
  +0013: chacha=e9  nist-curves=37
  +0014: chacha=00  nist-curves=10
  +0015: chacha=8d  nist-curves=98
  +0016: chacha=08  nist-curves=38
  +0017: chacha=80  nist-curves=ed
  +0018: chacha=a9  nist-curves=03
  +0019: chacha=00  nist-curves=80
  +001a: chacha=e9  nist-curves=a8
  +001b: chacha=00  nist-curves=a9
  +001c: chacha=8d  nist-curves=00
  +001d: chacha=09  nist-curves=e9
  +001e: chacha=80  nist-curves=00
  +001f: chacha=4d  nist-curves=8d
  ... (truncated to first 32 mismatching offsets)
```

### `chacha` vs `x25519`

- `chacha` body: 59 bytes
- `x25519` body: 84 bytes
- Byte-level diff (first 32 mismatches):

```
  +0000: chacha=98  x25519=8d
  +0001: chacha=18  x25519=02
  +0002: chacha=69  x25519=80
  +0003: chacha=00  x25519=8e
  +0004: chacha=aa  x25519=03
  +0005: chacha=a9  x25519=80
  +0006: chacha=9c  x25519=ad
  +0007: chacha=69  x25519=02
  +0008: chacha=00  x25519=80
  +0009: chacha=8d  x25519=38
  +000a: chacha=29  x25519=ed
  +000b: chacha=10  x25519=03
  +000c: chacha=69  x25519=80
  +000d: chacha=02  x25519=8d
  +000e: chacha=8d  x25519=04
  +000f: chacha=33  x25519=80
  +0010: chacha=10  x25519=a9
  +0011: chacha=98  x25519=00
  +0012: chacha=38  x25519=e9
  +0013: chacha=e9  x25519=00
  +0014: chacha=00  x25519=8d
  +0015: chacha=8d  x25519=05
  +0016: chacha=08  x25519=80
  +0017: chacha=80  x25519=4d
  +0018: chacha=a9  x25519=04
  +0019: chacha=00  x25519=80
  +001a: chacha=e9  x25519=38
  +001b: chacha=00  x25519=ed
  +001c: chacha=8d  x25519=05
  +001d: chacha=09  x25519=80
  +001e: chacha=80  x25519=a8
  +001f: chacha=4d  x25519=ad
  ... (truncated to first 32 mismatching offsets)
```

### `nist-curves` vs `x25519`

- `nist-curves` body: 63 bytes
- `x25519` body: 84 bytes
- Byte-level diff (first 32 mismatches):

```
  +0000: nist-curves=a8  x25519=8d
  +0001: nist-curves=8e  x25519=02
  +0002: nist-curves=03  x25519=80
  +0003: nist-curves=80  x25519=8e
  +0004: nist-curves=18  x25519=03
  +0005: nist-curves=6d  x25519=80
  +0006: nist-curves=03  x25519=ad
  +0007: nist-curves=80  x25519=02
  +0008: nist-curves=aa  x25519=80
  +0009: nist-curves=a9  x25519=38
  +000a: nist-curves=9c  x25519=ed
  +000b: nist-curves=69  x25519=03
  +000c: nist-curves=00  x25519=80
  +000e: nist-curves=2d  x25519=04
  +000f: nist-curves=10  x25519=80
  +0010: nist-curves=69  x25519=a9
  +0011: nist-curves=02  x25519=00
  +0012: nist-curves=8d  x25519=e9
  +0013: nist-curves=37  x25519=00
  +0014: nist-curves=10  x25519=8d
  +0015: nist-curves=98  x25519=05
  +0016: nist-curves=38  x25519=80
  +0017: nist-curves=ed  x25519=4d
  +0018: nist-curves=03  x25519=04
  +001a: nist-curves=a8  x25519=38
  +001b: nist-curves=a9  x25519=ed
  +001c: nist-curves=00  x25519=05
  +001d: nist-curves=e9  x25519=80
  +001e: nist-curves=00  x25519=a8
  +001f: nist-curves=8d  x25519=ad
  +0020: nist-curves=09  x25519=02
  +0022: nist-curves=98  x25519=18
  ... (truncated to first 32 mismatching offsets)
```

## §8.3 promotion gate

**BLOCKED.** Bodies are not byte-identical across all three
adopters. Issue #14's evidence gate requires bit-identical
instruction sequences before the body can be promoted as a
shared §8.3 primitive.
