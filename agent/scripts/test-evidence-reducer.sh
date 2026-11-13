#!/usr/bin/env bash
# Regression test for agent/scripts/jev/evidence_reducer.py (T11) plus the T9
# decide.py/security_shell integration tests.
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JEV_DIR="$ROOT/agent/scripts/jev"

# shellcheck source=agent/scripts/lib/run-test-suite.sh
source "$ROOT/agent/scripts/lib/run-test-suite.sh"

run_suite "evidence_reducer + decide.py integration Test Suite" \
    "evidence_reducer / decide.py integration test suite" \
    "$JEV_DIR" \
    python3 -m unittest test_evidence_reducer test_decide_integration -v
