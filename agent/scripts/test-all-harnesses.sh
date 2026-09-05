#!/usr/bin/env bash
# SSoT Multi-Harness Universal Comprehensive Test Suite
#
# 全 5 ハーネス (Claude, AGY, Pi, Codex, PrimeAgent) の自己診断、
# ガードスクリプト、単体テスト、および SSoT 整合性をワンショットで検証する。
#
# usage: agent/scripts/test-all-harnesses.sh [--quick]
# exit: 0 = 全テスト成功, 1 = 1件以上失敗
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

QUICK=0
if [[ "${1:-}" == "--quick" ]]; then
    QUICK=1
fi

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_TESTS=()

run_suite() {
    local name="$1"
    local cmd="$2"
    echo
    echo "================================================================================"
    echo "  RUNNING: $name"
    echo "================================================================================"
    if eval "$cmd"; then
        echo ">>> SUCCESS: $name"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo ">>> FAILED: $name"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
        FAILED_TESTS+=("$name")
    fi
}

echo "=== SSoT Multi-Harness Universal Test Suite ==="
echo "Root: $ROOT"
echo "Timestamp: $(date -Iseconds)"

# 1. SSoT Symlink Wiring Verification
run_suite "SSoT Symlink Verification" "bash '$ROOT/agent/scripts/sync-verify.sh'"

# 2. Prompt Cache Prefix Alignment
run_suite "Prompt Cache Alignment" "bash '$ROOT/agent/scripts/verify-cache-alignment.sh'"

# 3. Model Routing & Fallback Resolution
run_suite "Model Routing & Tier Fallbacks" "bash '$ROOT/agent/scripts/test-model-routing.sh'"

# 4. Swarm Meta & Harness Guard Tests
run_suite "Swarm Meta & Harness Guard" "bash '$ROOT/agent/skills/swarm-meta/scripts/test-harness-guard.sh'"

# 5. Shared Security Rules Engine
run_suite "Security Rules Engine" "bash '$ROOT/agent/scripts/test-security-rules.sh'"

# 6. Vald Law Enforcer Engine
run_suite "Vald Law Rules Engine" "bash '$ROOT/agent/scripts/test-vald-law-rules.sh'"

# 7. Graphify Hint Engine
run_suite "Graphify Hint Engine" "bash '$ROOT/agent/scripts/test-graphify-hint.sh'"

# 8. Memory Context Composition
run_suite "Memory Context Composition" "bash '$ROOT/agent/scripts/test-memory-context.sh'"

# 9. Merged Directory Root Resolution
run_suite "Merged Directory Root Resolution" "bash '$ROOT/agent/scripts/test-merged-dir-root-resolution.sh'"

# 10. Pi Extensions Unit Tests
if command -v bun &>/dev/null; then
    run_suite "Pi & Extension Unit Tests" "for f in '$ROOT'/agent/harnesses/pi/extensions/lib/*.test.ts '$ROOT'/agent/hooks/pi/lib/*.test.ts; do bun run \"\$f\" || exit 1; done"
fi

if [[ "$QUICK" -eq 0 ]]; then
    # 11. Individual Harness Diagnostics
    run_suite "Pi Harness Diagnostic" "bash '$ROOT/agent/harnesses/pi/validate-harness.sh'"
    run_suite "AGY Harness Diagnostic" "bash '$ROOT/agent/harnesses/agy/validate-harness.sh'"
    run_suite "Claude Harness Diagnostic" "bash '$ROOT/agent/harnesses/claude/validate-harness.sh'"
    run_suite "Codex Harness Diagnostic" "bash '$ROOT/agent/harnesses/codex/validate-harness.sh'"
    run_suite "PrimeAgent Harness Diagnostic" "bash '$ROOT/agent/harnesses/primeagent/validate-harness.sh'"
fi

echo
echo "================================================================================"
echo "  TEST SUMMARY"
echo "================================================================================"
echo "Total Suites Passed: $TOTAL_PASS"
echo "Total Suites Failed: $TOTAL_FAIL"

if [[ "$TOTAL_FAIL" -gt 0 ]]; then
    echo
    echo "Failed Suites:"
    for failed in "${FAILED_TESTS[@]}"; do
        echo "  - $failed"
    done
    exit 1
fi

echo
echo ">>> ALL MULTI-HARNESS SUITES OPERATIONAL AND VERIFIED <<<"
exit 0
