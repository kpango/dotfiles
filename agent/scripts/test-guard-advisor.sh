#!/usr/bin/env bash
# Regression test for agent/scripts/jev/guard_advisor.py (T9, the System-1/Laya
# post-stage advisory layer for decide.py's security_shell family).
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JEV_DIR="$ROOT/agent/scripts/jev"

# shellcheck source=agent/scripts/lib/run-test-suite.sh
source "$ROOT/agent/scripts/lib/run-test-suite.sh"

run_suite "guard_advisor Test Suite" \
    "guard_advisor test suite" \
    "$JEV_DIR" \
    python3 -m unittest test_guard_advisor -v
