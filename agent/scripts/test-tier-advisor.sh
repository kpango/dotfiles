#!/usr/bin/env bash
# Regression test for agent/scripts/jev/tier_advisor.py (T10, swarm-implement's
# complexity-gate Laya advisory CLI).
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JEV_DIR="$ROOT/agent/scripts/jev"

# shellcheck source=agent/scripts/lib/run-test-suite.sh
source "$ROOT/agent/scripts/lib/run-test-suite.sh"

run_suite "tier_advisor Test Suite" \
    "tier_advisor test suite" \
    "$JEV_DIR" \
    python3 -m unittest test_tier_advisor -v
