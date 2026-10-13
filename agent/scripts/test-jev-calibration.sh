#!/usr/bin/env bash
# Regression test for agent/scripts/jev/calibration/laya-calibration.json and its
# three source datasets (guard.jsonl / tier.jsonl / loglines.jsonl).
#
# Runs the fully offline, stdlib-only unittest suite in
# agent/scripts/jev/calibration/test_calibration.py, which validates:
#   (a) laya-calibration.json schema
#   (b) recorded dataset_sha256 matches the current *.jsonl files
#   (c) revision is pinned to the expected sha (cross-checked against
#       dockers/laya.Dockerfile's `ARG LAYA_HF_REVISION` -- or, as a
#       backward-compatible fallback, the legacy LAYA_HF_EXPECTED_SHA -- when
#       that file exists), plus a standalone test of that matching/mismatch
#       logic itself against synthetic Dockerfile fragments
#   (regex) DETERMINISTIC_CRITICAL_PATTERN itself (positive/negative table)
#   (d) every capability with enabled=true actually satisfies its held-out
#       condition, recomputed from the recorded metrics
#   (e) dataset sizes and per-class minimums
#
# This suite never imports `laya`/`torch` -- unlike calibrate.py itself (which needs
# both to run inference), so it runs in the repo's ordinary test environment.
#
# Exit 0 = PASS, exit 1 = FAIL (any test failure or error). If
# laya-calibration.json does not exist yet, the checks that depend on it are
# reported as SKIPPED (via unittest's SkipTest), not as a failure -- calibrate.py
# itself must be run separately in a laya/torch environment to produce it.
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CALIB_DIR="$ROOT/agent/scripts/jev/calibration"

# shellcheck source=agent/scripts/lib/run-test-suite.sh
source "$ROOT/agent/scripts/lib/run-test-suite.sh"

run_suite "Jev/Laya Calibration Test Suite" \
    "jev calibration test suite" \
    "$CALIB_DIR" \
    python3 -m unittest test_calibration -v
