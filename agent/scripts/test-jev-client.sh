#!/usr/bin/env bash
# Regression test for agent/scripts/jev/jev_client.py (the shared Jev API client).
#
# Runs the fully offline unittest suite in agent/scripts/jev/test_jev_client.py, which
# exercises jev_client.py against a local http.server mock bound to 127.0.0.1 on an
# ephemeral port. This suite never connects to the real https://api.typesafe.ai
# endpoint.
#
# Exit 0 = PASS, exit 1 = FAIL (any test failure or error, including the expected
# RED-phase ModuleNotFoundError before agent/scripts/jev/jev_client.py exists).
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JEV_DIR="$ROOT/agent/scripts/jev"

# shellcheck source=agent/scripts/lib/run-test-suite.sh
source "$ROOT/agent/scripts/lib/run-test-suite.sh"

run_suite "Jev Client Test Suite" \
    "jev_client test suite" \
    "$JEV_DIR" \
    python3 -m unittest test_jev_client -v
