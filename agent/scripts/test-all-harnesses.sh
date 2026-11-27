#!/usr/bin/env bash
# SSoT Multi-Harness Universal Comprehensive Test Suite
#
# 全 4 ハーネス (Claude, OMP, AGY, Hermes) の自己診断、
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

# 3b. SSoT Model Catalog Daily Updater & Pareto Optimizer
run_suite "SSoT Model Catalog Updater" "bash '$ROOT/agent/scripts/test-model-catalog-update.sh'"
run_suite "Harness Model List Fetcher" "bash '$ROOT/agent/scripts/test-fetch-harness-models.sh'"

# 4. Swarm Meta & Harness Guard Tests
run_suite "Swarm Meta & Harness Guard" "bash '$ROOT/agent/skills/swarm-meta/scripts/test-harness-guard.sh'"

# 5. Shared Security Rules Engine
run_suite "Security Rules Engine" "bash '$ROOT/agent/scripts/test-security-rules.sh'"

# 6. Vald Law Enforcer Engine
run_suite "Vald Law Rules Engine" "bash '$ROOT/agent/scripts/test-vald-law-rules.sh'"

# 7. Merged Directory Root Resolution
run_suite "Merged Directory Root Resolution" "bash '$ROOT/agent/scripts/test-merged-dir-root-resolution.sh'"

# 8. OMP Extensions & Hooks Unit Tests
run_suite "OMP Extension Unit Tests" "bash '$ROOT/agent/scripts/test-omp-extensions.sh'"
if command -v bun &>/dev/null; then
    run_suite "OMP Hook Unit Tests" "for f in '$ROOT'/agent/hooks/omp/lib/*.test.ts; do bun run \"\$f\" || exit 1; done"
fi

run_suite "Semgrep Scan Wrapper" "bash '$ROOT/agent/scripts/test-semgrep-scan.sh'"
run_suite "Root Agent Instruction Files" "bash '$ROOT/agent/scripts/test-root-agent-files.sh'"

# 9. Swarm Branch/Worktree Audit (swarm-loop Phase 5 完了処理の必須手順、
# マージ済みworktree/branchの機械的な棚卸し・削除)
run_suite "Swarm Branch/Worktree Audit" "bash '$ROOT/agent/scripts/test-swarm-branch-worktree-audit.sh'"

# 10. gen-tool-agents.sh / gen-tool-system.sh freshness + arg-validation regressions (T5/T15).
# Isolates its own copies under mktemp -d; never writes to the real agent/harnesses/ tree.
run_suite "Gen Tool AGENTS/SYSTEM.md" "bash '$ROOT/agent/scripts/test-gen-tool-md.sh'"

# 11. Settings Common, Write-Scope Parity, Catalog Health, Hook Session ID
run_suite "Settings Common Consistency" "bash '$ROOT/agent/scripts/test-settings-common.sh'"
run_suite "Harness Project and MCP Parity" "bash '$ROOT/agent/scripts/test-harness-parity.sh'"
run_suite "Write-Scope Parity" "bash '$ROOT/agent/scripts/test-write-scope-parity.sh'"
run_suite "Agent/Skill Catalog Health" "bash '$ROOT/agent/scripts/test-catalog-health.sh'"
run_suite "Hook Session ID Parity" "bash '$ROOT/agent/scripts/test-hook-session-id.sh'"

# 12. sync-verify.sh's SYNC_VERIFY_LIVE_ROOT linked-worktree handling (T4b).
# Builds a throwaway git repo + linked worktree + fake $HOME under mktemp -d;
# never touches the real $HOME or this repo's own live symlinks.
run_suite "Sync Verify Live Root" "bash '$ROOT/agent/scripts/test-sync-verify-live-root.sh'"
# sync-verify.sh's live-symlink-dir / live-regular-file modes and SYNC_VERIFY_ONLY,
# same isolation (throwaway repo copy + fake $HOME under mktemp -d).
run_suite "Sync Verify Dir Modes" "bash '$ROOT/agent/scripts/test-sync-verify-dir-modes.sh'"

# 13. fix-plan.md work areas (WA1-WA7): SoL-Pi / RLM / Harness2 / hook jq + daemon / bench suite.
if command -v bun &>/dev/null; then
    run_suite "SoL-Pi Unit Tests" "cd '$ROOT/agent/harnesses/omp/extensions' && bun test lib/sol-pi.test.ts lib/continual-harness.test.ts lib/repl-context.test.ts lib/context-economy-pressure.test.ts"
fi
run_suite "Sandbox Precheck (gondolin/zshenv)" "bash '$ROOT/agent/scripts/test-sandbox-precheck.sh'"
run_suite "RLM Bounded Query" "bash '$ROOT/agent/scripts/test-rlm-bounded.sh'"
run_suite "Harness2 Offline Evolution" "bash '$ROOT/agent/scripts/test-harness2-offline.sh'"
run_suite "OMP Host Capability Conformance" "bash '$ROOT/agent/scripts/test-host-capabilities.sh'"
run_suite "Hook jq Consolidation" "bash '$ROOT/agent/scripts/test-hook-jq-consolidation.sh'"
run_suite "Decide Daemon" "bash '$ROOT/agent/scripts/test-decide-daemon.sh'"
run_suite "Hermes Cron Installer" "bash '$ROOT/agent/scripts/test-hermes-cron.sh'"
run_suite "Agent Bench Suite Test" "bash '$ROOT/agent/scripts/test-agent-bench.sh'"
run_suite "Agent Bench Hooks (quick)" "bash '$ROOT/agent/scripts/bench/run-agent-bench.sh' --hooks --quick"
run_suite "Agent Bench Suite (quick)" "bash '$ROOT/agent/scripts/bench/run-agent-bench.sh' --suite --quick"

if [[ "$QUICK" -eq 0 ]]; then
    # 20. Individual Harness Diagnostics
    run_suite "OMP Harness Diagnostic" "bash '$ROOT/agent/harnesses/omp/validate-harness.sh'"
    run_suite "AGY Harness Diagnostic" "bash '$ROOT/agent/harnesses/agy/validate-harness.sh'"
    run_suite "Claude Harness Diagnostic" "bash '$ROOT/agent/harnesses/claude/validate-harness.sh'"
    run_suite "Hermes Harness Diagnostic" "bash '$ROOT/agent/harnesses/hermes/validate-harness.sh'"
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
