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

verify-addrsize: $(BUILD_DIR)/precalc_table_smoke.o
	@bad=0; \
	dump=$$($(OD65) --dump-exports $(BUILD_DIR)/precalc_table_smoke.o | \
	        awk '/Address size:/{a=$$4} /Name:/{gsub(/"/,"",$$2); print $$2, a}'); \
	for sym in $$(echo "$$dump" | awk '/_REGION|_SHARED/ {print $$1"="$$2}'); do \
	  case "$$sym" in *"=(absolute)") ;; \
	    *) echo "verify-addrsize: FAIL — $$sym should be (absolute)"; bad=1;; esac; \
	done; \
	for sym in $$(echo "$$dump" | awk '/smoke_reu_shared_SIZE/ {print $$1"="$$2}'); do \
	  case "$$sym" in *"=(far)") ;; \
	    *) echo "verify-addrsize: FAIL — $$sym should be (far) for the 65536-byte table"; bad=1;; esac; \
	done; \
	if [ $$bad -ne 0 ]; then exit 1; fi; \
	echo "verify-addrsize: ok — _REGION/_SHARED absolute, oversized _SIZE still far"

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

clean:
	@rm -rf $(BUILD_DIR)
