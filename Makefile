# c64-lib-contract — verification targets.
#
# This repo is doc-only with one exception: precalc_table.inc, the
# canonical SPEC §8.0 catch-loop macro source. `make verify` proves the
# macro assembles cleanly in ca65 across every (region, shared) shape
# so adopter PRs land on a known-good macro.

CA65 ?= ca65
BUILD_DIR := build

.PHONY: verify clean

verify: $(BUILD_DIR)/precalc_table_smoke.o
	@echo "verify: precalc_table.inc assembles cleanly"

$(BUILD_DIR)/precalc_table_smoke.o: examples/precalc_table_smoke.s precalc_table.inc | $(BUILD_DIR)
	$(CA65) -o $@ examples/precalc_table_smoke.s

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

clean:
	@rm -rf $(BUILD_DIR)
