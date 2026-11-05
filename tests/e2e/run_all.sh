#!/usr/bin/env bash
# run_all.sh — Master automated E2E Test Suite and Verification Runner.
# Validates:
# - Tier 1: 5 Strict UX Invariants (test_ux_invariants.py)
# - Tier 2: 4 Benchmark Performance Thresholds (test_benchmarks.sh)
# - Tier 3: Guardrails, Syntax & Boundary Integrity (test_guardrails.sh)
# - Tier 4: Real-World Scenarios (test_runner.py --tier 4)
# - Adversarial: Challenger M1 Attacks (test_challenger_m1_adversarial.py)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

cd "${ROOT_DIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=================================================================${NC}"
echo -e "${BOLD}${BLUE} STARTING AUTOMATED MASTER E2E TEST RUNNER${NC}"
echo -e "${BOLD}${BLUE} Project: Zsh & Tmux Startup Optimization${NC}"
echo -e "${BOLD}${BLUE} Root:    ${ROOT_DIR}${NC}"
echo -e "${BOLD}${BLUE}=================================================================${NC}\n"

START_TIME=$(date +%s)

# 1. Run all Tiers (1-4)
python3 "${SCRIPT_DIR}/test_runner.py" --tier all

# 2. Run Adversarial Challenger Tests
echo -e "\n${BOLD}${BLUE}=================================================================${NC}"
echo -e "${BOLD}${BLUE} RUNNING ADVERSARIAL CHALLENGER SUITE${NC}"
echo -e "${BOLD}${BLUE}=================================================================${NC}\n"
python3 "${SCRIPT_DIR}/test_challenger_m1_adversarial.py"
python3 "${SCRIPT_DIR}/test_challenger_m2_adversarial.py"
python3 "${SCRIPT_DIR}/test_challenger_m3_adversarial.py"
python3 "${SCRIPT_DIR}/test_challenger_m3_2_adversarial.py"
python3 "${SCRIPT_DIR}/test_challenger_m4_adversarial.py"
python3 "${SCRIPT_DIR}/test_challenger_m4_2_adversarial.py"
python3 "${SCRIPT_DIR}/test_challenger_m5_1_adversarial.py"
python3 "${SCRIPT_DIR}/test_challenger_m5_2_adversarial.py"
python3 "${SCRIPT_DIR}/test_challenger_m5_it2_adversarial.py"
python3 "${SCRIPT_DIR}/test_challenger_m5_it3_adversarial.py"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo -e "\n${BOLD}${GREEN}=================================================================${NC}"
echo -e "${BOLD}${GREEN} ALL E2E & ADVERSARIAL TESTS PASSED (100% SUCCESS, ${ELAPSED}s)${NC}"
echo -e "${BOLD}${GREEN}=================================================================${NC}\n"

exit 0
