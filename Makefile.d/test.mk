.PHONY: test/e2e test/e2e/tier1 test/e2e/tier2 test/e2e/tier3 test/e2e/tier4 test/adversarial test/harness

## run complete E2E test suite (all tiers)
test/e2e:
	@python3 tests/e2e/test_runner.py --tier all

## run Tier 1 feature coverage tests
test/e2e/tier1:
	@python3 tests/e2e/test_runner.py --tier 1

## run Tier 2 boundary and corner case tests
test/e2e/tier2:
	@python3 tests/e2e/test_runner.py --tier 2

## run Tier 3 cross-feature combination tests
test/e2e/tier3:
	@python3 tests/e2e/test_runner.py --tier 3

## run Tier 4 real-world application scenario tests
test/e2e/tier4:
	@python3 tests/e2e/test_runner.py --tier 4

## run adversarial challenger tests
test/adversarial:
	@python3 tests/e2e/test_challenger_m1_adversarial.py

## run validation harness
test/harness:
	@bash agy/validate-harness.sh
