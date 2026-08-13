; precalc_table_negative.s — negative case for the §8.0 LIB_PRECALC_TABLE macro.
;
; A four-argument (pre-v0.7.0) invocation assembled with
; -D LIB_NO_BARE_EXPORTS=1 would emit no symbols at all: the bare exports
; are suppressed and no lib prefix was supplied to emit the prefixed ones.
; The macro MUST reject that combination with a named .error rather than
; silently producing an empty manifest — a silent pass here would surface
; downstream as an unresolved external in the consumer, far from the cause.
;
; `make verify` assembles this file with -D and requires ca65 to FAIL.
; Assembled without -D it is a valid legacy invocation and succeeds.

.include "../precalc_table.inc"

LIB_PRECALC_TABLE "negative_no_prefix", 1024, PRECALC_REGION_RAM, PRECALC_SHARED_YES
