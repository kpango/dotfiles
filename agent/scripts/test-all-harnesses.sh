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

# 7. Merged Directory Root Resolution
run_suite "Merged Directory Root Resolution" "bash '$ROOT/agent/scripts/test-merged-dir-root-resolution.sh'"

# 8. Pi Extensions Unit Tests
if command -v bun &>/dev/null; then
    run_suite "Pi & Extension Unit Tests" "for f in '$ROOT'/agent/harnesses/pi/extensions/lib/*.test.ts '$ROOT'/agent/hooks/pi/lib/*.test.ts; do bun run \"\$f\" || exit 1; done"
fi

# 9. Swarm Branch/Worktree Audit (swarm-loop Phase 5 完了処理の必須手順、
# マージ済みworktree/branchの機械的な棚卸し・削除)
run_suite "Swarm Branch/Worktree Audit" "bash '$ROOT/agent/scripts/test-swarm-branch-worktree-audit.sh'"

# 10. Supermemory Shared Client (bash consumer contract: session-start hooks +
# swarm-memory-sync's memory-guard.sh). Replaced decide.py's memory_context family
# (removed 2026-09-10, supermemory-migration mission) — this suite is its successor.
run_suite "Supermemory Shared Client" "bash '$ROOT/agent/scripts/test-supermemory-client.sh'"

# 11. Jev/Laya evidence_reducer.py + decide.py security_shell integration (T9/T11).
# python3 stdlib-only (mocks Laya over a loopback http.server; never imports
# laya/torch), so it runs unmodified in CI/ubuntu-latest.
run_suite "Evidence Reducer / decide.py Integration" "bash '$ROOT/agent/scripts/test-evidence-reducer.sh'"

# 12. gen-tool-agents.sh / gen-tool-system.sh freshness + arg-validation regressions (T5/T15).
# Isolates its own copies under mktemp -d; never writes to the real agent/harnesses/ tree.
run_suite "Gen Tool AGENTS/SYSTEM.md" "bash '$ROOT/agent/scripts/test-gen-tool-md.sh'"

# 13. Jev/Laya guard_advisor.py (T9 System-1/Laya post-stage advisory layer).
# python3 stdlib-only, same MockLayaServer fixture as #11.
run_suite "Guard Advisor" "bash '$ROOT/agent/scripts/test-guard-advisor.sh'"

# 14. Jev/Laya calibration dataset + laya-calibration.json schema (T10/T11).
# python3 stdlib-only; never imports laya/torch (that's calibrate.py's own concern,
# run separately in a laya/torch environment to regenerate the calibration file).
run_suite "Jev/Laya Calibration" "bash '$ROOT/agent/scripts/test-jev-calibration.sh'"

# 15. Jev API client (T9/T10/T11 shared HTTP client to api.typesafe.ai).
# Exercises jev_client.py against a local http.server mock; never touches the
# real endpoint or the network.
run_suite "Jev Client" "bash '$ROOT/agent/scripts/test-jev-client.sh'"

# 16. dockers/laya.Dockerfile revision gate (T9/T10/T11 shared I-13 check).
# python3 stdlib-only; tolerates a non-UTF-8/unreadable Dockerfile without crashing.
run_suite "Revision Check" "bash '$ROOT/agent/scripts/test-revision-check.sh'"

# 17. pi's security-gate.ts System-1/Laya reflection (T9/I-14). Requires `bun`
# (same gate as #8's Pi Extensions Unit Tests -- self-skips if bun is absent).
if command -v bun &>/dev/null; then
    run_suite "Security Gate (pi)" "bash '$ROOT/agent/scripts/test-security-gate-pi.sh'"
fi

# 18. sync-verify.sh's SYNC_VERIFY_LIVE_ROOT linked-worktree handling (T4b).
# Builds a throwaway git repo + linked worktree + fake $HOME under mktemp -d;
# never touches the real $HOME or this repo's own live symlinks.
run_suite "Sync Verify Live Root" "bash '$ROOT/agent/scripts/test-sync-verify-live-root.sh'"

# 19. Jev/Laya tier_advisor.py (T10 swarm-implement complexity-gate advisory CLI).
# python3 stdlib-only, same MockLayaServer fixture as #11/#13.
run_suite "Tier Advisor" "bash '$ROOT/agent/scripts/test-tier-advisor.sh'"

if [[ "$QUICK" -eq 0 ]]; then
    # 20. Individual Harness Diagnostics
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
