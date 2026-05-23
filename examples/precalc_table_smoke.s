; precalc_table_smoke.s — smoke test for the §8.0 LIB_PRECALC_TABLE macro.
;
; Exercises every (region, shared) combination so any future change to
; the canonical macro definition in precalc_table.inc proves it still
; assembles across the full matrix. Run via `make verify` at the repo
; root.
;
; This is not a runnable C64 program — no .segment / .org / .code; just
; macro invocations that exercise the .ident / .sprintf / .export shape.

.include "../precalc_table.inc"

; --- SHARED_YES × all three regions ---
LIB_PRECALC_TABLE "smoke_ram_shared",    1024,  PRECALC_REGION_RAM,    PRECALC_SHARED_YES
LIB_PRECALC_TABLE "smoke_reu_shared",    65536, PRECALC_REGION_REU,    PRECALC_SHARED_YES
LIB_PRECALC_TABLE "smoke_rodata_shared", 640,   PRECALC_REGION_RODATA, PRECALC_SHARED_YES

; --- SHARED_NO × all three regions ---
LIB_PRECALC_TABLE "smoke_ram_private",    256,   PRECALC_REGION_RAM,    PRECALC_SHARED_NO
LIB_PRECALC_TABLE "smoke_reu_private",    24576, PRECALC_REGION_REU,    PRECALC_SHARED_NO
LIB_PRECALC_TABLE "smoke_rodata_private", 512,   PRECALC_REGION_RODATA, PRECALC_SHARED_NO

; --- Value cross-checks. The macro preserves the case of the `name`
;     argument, so these asserts use the lower_snake_case form that
;     adopters and audits actually see in `nm` output. The asserts fail
;     to assemble if .sprintf misbuilds the identifier, if the LHS-of-=
;     position doesn't accept .ident as a symbol slot, or if a value
;     > 16 bits is exported with an `abs` hint (regression guard for
;     the SIZE address-size fix). ---
.assert LIB_PRECALC_smoke_ram_shared_SIZE      = 1024,                 error, "smoke_ram_shared SIZE mismatch"
.assert LIB_PRECALC_smoke_ram_shared_REGION    = PRECALC_REGION_RAM,   error, "smoke_ram_shared REGION mismatch"
.assert LIB_PRECALC_smoke_ram_shared_SHARED    = PRECALC_SHARED_YES,   error, "smoke_ram_shared SHARED mismatch"

.assert LIB_PRECALC_smoke_reu_shared_SIZE      = 65536,                error, "smoke_reu_shared SIZE mismatch (regression guard: SIZE must export without : abs)"
.assert LIB_PRECALC_smoke_reu_shared_REGION    = PRECALC_REGION_REU,   error, "smoke_reu_shared REGION mismatch"

.assert LIB_PRECALC_smoke_rodata_private_SIZE    = 512,                error, "smoke_rodata_private SIZE mismatch"
.assert LIB_PRECALC_smoke_rodata_private_SHARED  = PRECALC_SHARED_NO,  error, "smoke_rodata_private SHARED mismatch"
