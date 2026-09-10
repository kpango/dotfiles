#!/usr/bin/env bash
# agent/graphify-hint-config.json を実際に消費する3実装(agent/hooks/claude/graphify-hint.sh・
# agent/hooks/agy/graphify-hint.sh・agent/hooks/pi/graphify-hint.ts)を横断的に検証する統合テスト。
#
# usage: agent/scripts/test-graphify-hint.sh
# exit: 0 = 全テストPASS, 1 = 1件以上FAIL
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLAUDE_HOOK="$ROOT/agent/hooks/claude/graphify-hint.sh"
AGY_HOOK="$ROOT/agent/hooks/agy/graphify-hint.sh"
PI_EXT="$ROOT/agent/hooks/pi/graphify-hint.ts"

total_fail=0
section() { echo; echo "=== $1 ==="; }

# ------------------------------------------------------------------
# agent/hooks/claude/graphify-hint.sh (cwd相対でグラフ存在を確認する設計のため cd してから起動)
# ------------------------------------------------------------------
section "agent/hooks/claude/graphify-hint.sh"
claude_check() {
    local desc="$1" cmd="$2" dir="$3" expected="$4" out got="empty" # hint|empty
    out="$(cd "$dir" && jq -n --arg c "$cmd" '{"tool_input":{"command":$c}}' | "$CLAUDE_HOOK" 2>&1)"
    [[ -n "$out" ]] && got="hint"
    if [[ "$got" == "$expected" ]]; then
        echo "[OK] $desc"
    else
        echo "[FAIL] $desc : expected=$expected got=$got out=$out"
        total_fail=$((total_fail + 1))
    fi
}
claude_check "grep command, graph present (repo root)" "grep -rn foo ." "$ROOT" hint
claude_check "non-matching command, graph present" "echo hello" "$ROOT" empty
claude_check "grep command, graph absent" "grep -rn foo ." "/tmp" empty

# ------------------------------------------------------------------
# agent/hooks/agy/graphify-hint.sh (workspacePaths経由でグラフ存在を確認)
# ------------------------------------------------------------------
section "agent/hooks/agy/graphify-hint.sh"
agy_check() {
    local desc="$1" cmd="$2" ws="$3" expected="$4" out got context
    out="$(jq -n --arg c "$cmd" --arg ws "$ws" '{"toolCall":{"name":"run_command","args":{"command":$c}},"workspacePaths":[$ws]}' | "$AGY_HOOK" 2>&1)"
    context=$(echo "$out" | jq -r '.reason // .context // empty' 2>/dev/null)
    got=$([[ -n "$context" ]] && echo hint || echo empty)
    if [[ "$got" == "$expected" ]]; then
        echo "[OK] $desc"
    else
        echo "[FAIL] $desc : expected=$expected got=$got out=$out"
        total_fail=$((total_fail + 1))
    fi
}
agy_check "grep command, graph present" "grep -rn foo ." "$ROOT" hint
agy_check "non-matching command, graph present" "echo hello" "$ROOT" empty
agy_check "grep command, graph absent" "grep -rn foo ." "/tmp" empty

# ------------------------------------------------------------------
# agent/hooks/pi/graphify-hint.ts (bun経由でハンドラを直接起動)
# ------------------------------------------------------------------
section "agent/hooks/pi/graphify-hint.ts"
if command -v bun &>/dev/null; then
    PI_TEST_TS="$(mktemp -t pi-graphify-hint-test-XXXXXX.ts)"
    trap 'rm -f "$PI_TEST_TS"' EXIT
    cat > "$PI_TEST_TS" <<TSEOF
import graphifyHint from "$PI_EXT";
type Handler = (event: any, ctx: any) => Promise<any>;
let handler: Handler | null = null;
graphifyHint({ on(_n: string, fn: Handler) { handler = fn; } } as any);
let fail = 0;
async function check(desc: string, command: string, cwd: string, expected: "hint" | "empty") {
  const statuses: string[] = [];
  await handler!({ toolName: "bash", input: { command } }, { cwd, ui: { setStatus: (_k: string, v: string) => statuses.push(v) } });
  const got = statuses.length > 0 ? "hint" : "empty";
  if (got === expected) console.log("[OK] " + desc);
  else { console.log("[FAIL] " + desc + " expected=" + expected + " got=" + got); fail++; }
}
async function main() {
  await check("grep command, graph present", "grep -rn foo .", "$ROOT", "hint");
  await check("non-matching command, graph present", "echo hello", "$ROOT", "empty");
  await check("grep command, graph absent", "grep -rn foo .", "/tmp", "empty");
  console.log(fail > 0 ? fail + " FAILURES" : "PI_ALL_PASS");
  process.exit(fail > 0 ? 1 : 0);
}
main();
TSEOF
    bun run "$PI_TEST_TS"
    pi_status=$?
    rm -f "$PI_TEST_TS"
    trap - EXIT
    [[ "$pi_status" -ne 0 ]] && total_fail=$((total_fail + 1))
else
    echo "[SKIP] bun not found, agent/hooks/pi/graphify-hint.ts の統合テストをスキップ"
fi

echo
echo "---"
if [[ "$total_fail" -gt 0 ]]; then
    echo "test-graphify-hint: $total_fail 件のFAILあり"
    exit 1
fi
echo "test-graphify-hint: 全テストPASS"
exit 0
