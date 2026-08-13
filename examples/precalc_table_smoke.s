; precalc_table_smoke.s — smoke test for the §8.0 LIB_PRECALC_TABLE macro.
;
; Exercises every (region, shared) combination so any future change to
; the canonical macro definition in precalc_table.inc proves it still
; assembles across the full matrix. Run via `make verify` at the repo
; root, which assembles this file twice: once in the default mode (bare
; + prefixed exports) and once with -D LIB_NO_BARE_EXPORTS=1 (prefixed
; only, the two-library composition mode added in SPEC v0.7.0).
;
; This is not a runnable C64 program — no .segment / .org / .code; just
; macro invocations that exercise the .ident / .sprintf / .export shape.

.include "../precalc_table.inc"

; --- SHARED_YES × all three regions ---
LIB_PRECALC_TABLE "smoke_ram_shared",    1024,  PRECALC_REGION_RAM,    PRECALC_SHARED_YES, "SMOKE"
LIB_PRECALC_TABLE "smoke_reu_shared",    65536, PRECALC_REGION_REU,    PRECALC_SHARED_YES, "SMOKE"
LIB_PRECALC_TABLE "smoke_rodata_shared", 640,   PRECALC_REGION_RODATA, PRECALC_SHARED_YES, "SMOKE"

; --- SHARED_NO × all three regions ---
LIB_PRECALC_TABLE "smoke_ram_private",    256,   PRECALC_REGION_RAM,    PRECALC_SHARED_NO, "SMOKE"
LIB_PRECALC_TABLE "smoke_reu_private",    24576, PRECALC_REGION_REU,    PRECALC_SHARED_NO, "SMOKE"
LIB_PRECALC_TABLE "smoke_rodata_private", 512,   PRECALC_REGION_RODATA, PRECALC_SHARED_NO, "SMOKE"

; --- Value cross-checks on the prefixed form (v0.7.0). The macro
;     preserves the case of both the `lib` and `name` arguments, so
;     these asserts use the UPPER_SNAKE_CASE prefix + lower_snake_case
;     name shape that adopters and audits actually see in od65 output.
;     The asserts fail to assemble if .sprintf misbuilds the two-part
;     identifier, if the LHS-of-= position doesn't accept .ident as a
;     symbol slot, or if a value > 16 bits is exported with an `abs`
;     hint (regression guard for the SIZE address-size fix). ---
.assert LIB_SMOKE_PRECALC_smoke_ram_shared_SIZE      = 1024,                 error, "prefixed smoke_ram_shared SIZE mismatch"
.assert LIB_SMOKE_PRECALC_smoke_ram_shared_REGION    = PRECALC_REGION_RAM,   error, "prefixed smoke_ram_shared REGION mismatch"
.assert LIB_SMOKE_PRECALC_smoke_ram_shared_SHARED    = PRECALC_SHARED_YES,   error, "prefixed smoke_ram_shared SHARED mismatch"

.assert LIB_SMOKE_PRECALC_smoke_reu_shared_SIZE      = 65536,                error, "prefixed smoke_reu_shared SIZE mismatch (regression guard: SIZE must export without : abs)"
.assert LIB_SMOKE_PRECALC_smoke_reu_shared_REGION    = PRECALC_REGION_REU,   error, "prefixed smoke_reu_shared REGION mismatch"

.assert LIB_SMOKE_PRECALC_smoke_rodata_private_SIZE   = 512,                 error, "prefixed smoke_rodata_private SIZE mismatch"
.assert LIB_SMOKE_PRECALC_smoke_rodata_private_SHARED = PRECALC_SHARED_NO,   error, "prefixed smoke_rodata_private SHARED mismatch"

; --- The deprecated bare form must still be emitted (and still carry the
;     same values) whenever LIB_NO_BARE_EXPORTS is not defined, and must
;     vanish when it is. Guarding these asserts on the define is itself
;     the check: under -D the symbols do not exist, and referencing them
;     would raise an unresolved-symbol error. ---
.ifndef LIB_NO_BARE_EXPORTS
    .assert LIB_PRECALC_smoke_ram_shared_SIZE     = 1024,                error, "bare smoke_ram_shared SIZE mismatch"
    .assert LIB_PRECALC_smoke_ram_shared_REGION   = PRECALC_REGION_RAM,  error, "bare smoke_ram_shared REGION mismatch"
    .assert LIB_PRECALC_smoke_reu_shared_SIZE     = 65536,               error, "bare smoke_reu_shared SIZE mismatch"
    .assert LIB_PRECALC_smoke_rodata_private_SIZE = 512,                 error, "bare smoke_rodata_private SIZE mismatch"
.endif

; --- Backward compatibility: the pre-v0.7.0 four-argument invocation
;     must keep assembling unchanged in the default mode, emitting the
;     bare form only. (Under -D LIB_NO_BARE_EXPORTS it is a named error
;     by design — covered by the negative case in `make verify`.) ---
.ifndef LIB_NO_BARE_EXPORTS
    LIB_PRECALC_TABLE "smoke_legacy_4arg", 2048, PRECALC_REGION_RAM, PRECALC_SHARED_NO
    .assert LIB_PRECALC_smoke_legacy_4arg_SIZE = 2048, error, "legacy 4-arg form mismatch"
.endif
