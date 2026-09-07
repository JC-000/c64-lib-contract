# c64-lib-contract — verification targets.
#
# This repo is doc-only with one exception: precalc_table.inc, the
# canonical SPEC §8.4 macro source. `make verify` proves the
# macro assembles cleanly in ca65 across every (region, shared) shape,
# in both export modes, so adopter PRs land on a known-good macro.
#
# Modes (SPEC v0.7.0):
#   default                      bare + prefixed exports
#   -D LIB_NO_BARE_EXPORTS=1     prefixed only — the mode a consumer
#                                composing two or more libraries uses to
#                                avoid the #43 duplicate-export collision

CA65 ?= ca65
BUILD_DIR := build

.PHONY: verify verify-default verify-noBare verify-negative verify-addrsize clean

verify: verify-default verify-noBare verify-negative verify-addrsize
	@echo "verify: precalc_table.inc assembles cleanly in both export modes"

verify-default: $(BUILD_DIR)/precalc_table_smoke.o
verify-noBare:  $(BUILD_DIR)/precalc_table_smoke_nobare.o

$(BUILD_DIR)/precalc_table_smoke.o: examples/precalc_table_smoke.s precalc_table.inc | $(BUILD_DIR)
	$(CA65) -o $@ examples/precalc_table_smoke.s

$(BUILD_DIR)/precalc_table_smoke_nobare.o: examples/precalc_table_smoke.s precalc_table.inc | $(BUILD_DIR)
	$(CA65) -D LIB_NO_BARE_EXPORTS=1 -o $@ examples/precalc_table_smoke.s

# Negative case: a 4-arg invocation under -D emits nothing, so the macro
# must reject it. ca65 succeeding here is the failure.
verify-negative: examples/precalc_table_negative.s precalc_table.inc | $(BUILD_DIR)
	@$(CA65) -o $(BUILD_DIR)/precalc_table_negative.o examples/precalc_table_negative.s
	@if $(CA65) -D LIB_NO_BARE_EXPORTS=1 -o $(BUILD_DIR)/precalc_table_negative_nobare.o \
	      examples/precalc_table_negative.s 2>/dev/null; then \
	  echo "verify-negative: FAIL — 4-arg invocation under -D LIB_NO_BARE_EXPORTS should not assemble"; \
	  exit 1; \
	else \
	  echo "verify-negative: ok — 4-arg invocation under -D rejected as designed"; \
	fi

# Address-size ratchet (SPEC v0.7.4, issue #58). _REGION/_SHARED are byte-valued,
# so an unhinted export makes ca65 infer 'zeropage' while a consumer's .import
# defaults to absolute — the §8.4 snippet then warns on every composed build.
# _SIZE stays unhinted on purpose: its address size is value-dependent, and the
# 65536-byte smoke table must still export it as 'far' (the v0.4.1 fix).
OD65 ?= od65

verify-addrsize: $(BUILD_DIR)/precalc_table_smoke.o examples/precalc_table_smoke.s
	@exp=$$(awk '\
	  { line = $$0; sub(/^[ \t]+/, "", line) } \
	  line ~ /^;/ { next } \
	  line !~ /^LIB_PRECALC_TABLE[ \t]+"/ { next } \
	  { n = split(line, arg, ","); \
	    lib = (n >= 5 ? arg[5] : ""); gsub(/[ \t]+$$/, "", lib); \
	    if (n == 5 && lib != "") n5++; \
	    else if (n == 4 || (n == 5 && lib == "")) n4++; \
	    else { bad++; next } \
	    sizef = arg[2]; gsub(/[^0-9]/, "", sizef); \
	    if (sizef + 0 > 65535) far += (n == 5 ? 2 : 1) } \
	  END { if (bad || (n5 + n4) == 0) exit 1; \
	        printf "%d %d %d\n", 6*n5 + 3*n4, 4*n5 + 2*n4, far }' \
	  examples/precalc_table_smoke.s) || { \
	  echo "verify-addrsize: FAIL — cannot derive the expected population from examples/precalc_table_smoke.s"; \
	  exit 1; }; \
	set -- $$exp; exp_total=$$1; exp_hinted=$$2; exp_far=$$3; \
	raw=$$($(OD65) --dump-exports $<) || { \
	  echo "verify-addrsize: FAIL — od65 did not run"; exit 1; }; \
	declared=$$(printf '%s\n' "$$raw" | awk '/Exports:/{f=1} f && /Count:/{print $$2; exit}'); \
	case "$$declared" in ''|*[!0-9]*) \
	  echo "verify-addrsize: FAIL — export Count is not a number: '$$declared'"; exit 1;; esac; \
	dump=$$(printf '%s\n' "$$raw" | awk \
	  '/Exports:/{f=1; next} /Imports:|Segments:|Debug/{f=0} \
	   !f{next} \
	   /Index:/{a=""} \
	   /Address size:/{a=$$0; sub(/.*\(/,"",a); sub(/\).*/,"",a)} \
	   /Name:/{n=$$0; sub(/^[^"]*"/,"",n); sub(/".*/,"",n); pend=n; next} \
	   /Value:/ && pend != "" {v=$$2; \
	           print pend, (a == "" ? "MISSING" : a), v; pend=""}'); \
	parsed=$$(printf '%s\n' "$$dump" | grep -c . || true); \
	if [ "$$parsed" -ne "$$declared" ]; then \
	  echo "verify-addrsize: FAIL — parsed $$parsed of the $$declared exports od65 declared"; \
	  exit 1; \
	fi; \
	if [ "$$declared" -ne "$$exp_total" ]; then \
	  echo "verify-addrsize: FAIL — object exports $$declared symbols; the source derives $$exp_total"; \
	  exit 1; \
	fi; \
	hinted=$$(printf '%s\n' "$$dump" | grep -cE '(_REGION|_SHARED) ' || true); \
	sized=$$(printf '%s\n' "$$dump" | grep -c 'smoke_reu_shared_SIZE ' || true); \
	if [ "$$hinted" -ne "$$exp_hinted" ] || [ "$$sized" -ne "$$exp_far" ]; then \
	  echo "verify-addrsize: FAIL — subject count off: $$hinted/$$exp_hinted _REGION/_SHARED, $$sized/$$exp_far oversized _SIZE"; \
	  exit 1; \
	fi; \
	cover=$$(printf '%s\n' "$$dump" | awk \
	  '$$1 ~ /^LIB_PRECALC_.*_REGION$$/ {t=$$1; sub(/^LIB_PRECALC_/,"",t); sub(/_REGION$$/,"",t); reg[t]=$$3} \
	   $$1 ~ /^LIB_PRECALC_.*_SHARED$$/ {t=$$1; sub(/^LIB_PRECALC_/,"",t); sub(/_SHARED$$/,"",t); shr[t]=$$3} \
	   END {for (t in reg) if (t in shr) seen[reg[t] "/" shr[t]] = 1; \
	        n=0; for (k in seen) n++; print n}'); \
	if [ "$$cover" -ne 6 ]; then \
	  echo "verify-addrsize: FAIL — the object covers $$cover of the 6 (region, shared) combinations; the smoke matrix is incomplete"; \
	  exit 1; \
	fi; \
	bad=0; \
	for sym in $$(printf '%s\n' "$$dump" | awk '/(_REGION|_SHARED) /{print $$1"="$$2}'); do \
	  case "$$sym" in *=absolute) ;; \
	    *) echo "verify-addrsize: FAIL — $$sym should be absolute"; bad=1;; esac; \
	done; \
	for sym in $$(printf '%s\n' "$$dump" | awk '/smoke_reu_shared_SIZE /{print $$1"="$$2}'); do \
	  case "$$sym" in *=far) ;; \
	    *) echo "verify-addrsize: FAIL — $$sym should be far for the 65536-byte table"; bad=1;; esac; \
	done; \
	if printf '%s\n' "$$dump" | grep -q ' MISSING$$'; then \
	  echo "verify-addrsize: FAIL — export with no Address size field:"; \
	  printf '%s\n' "$$dump" | grep ' MISSING$$'; bad=1; \
	fi; \
	if [ $$bad -ne 0 ]; then exit 1; fi; \
	echo "verify-addrsize: ok — $$hinted/$$exp_hinted _REGION/_SHARED absolute, $$sized/$$exp_far oversized _SIZE far, $$parsed/$$declared exports, source-derived $$exp_total, $$cover/6 (region, shared) cells"

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

clean:
	@rm -rf $(BUILD_DIR)
