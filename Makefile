# c64-lib-contract — verification targets.
#
# This repo is doc-only with one exception: precalc_table.inc, the
# canonical SPEC §8.0 catch-loop macro source. `make verify` proves the
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

.PHONY: verify verify-default verify-noBare verify-negative clean

verify: verify-default verify-noBare verify-negative
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

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

clean:
	@rm -rf $(BUILD_DIR)
