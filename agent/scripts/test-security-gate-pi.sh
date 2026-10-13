#!/usr/bin/env bash
# Regression test for agent/hooks/pi/security-gate.ts's `handleShellCommandResult`
# (T9/I-14: pi's own reflection of decide.py's Laya-adjusted top-level decision).
#
# Runs agent/scripts/jev/test_security_gate_pi.ts with `bun test` (bun >=1.0; this
# repo already depends on bun for other tooling -- see CLAUDE.md's Graft section).
# `bun test <path>` is used explicitly (not bare `bun test`, which only discovers
# files matching bun's own *.test.ts/_test_/*.spec.ts naming convention) so this
# file can keep the project's existing test_*.{py,ts} naming, consistent with
# every other new test file this task added.
#
# Exit 0 = PASS, exit 1 = FAIL.
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JEV_DIR="$ROOT/agent/scripts/jev"

# shellcheck source=agent/scripts/lib/run-test-suite.sh
source "$ROOT/agent/scripts/lib/run-test-suite.sh"

run_suite "security-gate.ts (pi) System-1 reflection Test Suite" \
    "security-gate.ts (pi) test suite" \
    "$JEV_DIR" \
    bun test ./test_security_gate_pi.ts
