#!/usr/bin/env bash
# Regression test for agent/scripts/jev/revision_check.py (T9/T10/T11's shared
# I-13 revision gate), focused on the Checker-reported defect (revision 2
# review): a non-UTF-8 or permission-denied dockers/laya.Dockerfile must never
# crash the caller.
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JEV_DIR="$ROOT/agent/scripts/jev"

# shellcheck source=agent/scripts/lib/run-test-suite.sh
source "$ROOT/agent/scripts/lib/run-test-suite.sh"

run_suite "revision_check Test Suite" \
    "revision_check test suite" \
    "$JEV_DIR" \
    python3 -m unittest test_revision_check -v
