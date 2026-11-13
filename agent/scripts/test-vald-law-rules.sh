#!/usr/bin/env bash
# agent/vald-law-rules.json を実際に消費する実装(agent/hooks/claude/vald-law-gate.sh・
# agent/hooks/claude/vald-law2-gate.sh・agent/hooks/claude/vald-law345-check.sh・agent/hooks/agy/vald-law-gate.sh・
# agent/hooks/pi/security-gate.ts のVald Lawセクション)を横断的に検証する統合テスト。
#
# usage: agent/scripts/test-vald-law-rules.sh
# exit: 0 = 全テストPASS, 1 = 1件以上FAIL
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLAUDE_LAW1="$ROOT/agent/hooks/claude/vald-law-gate.sh"
CLAUDE_LAW2="$ROOT/agent/hooks/claude/vald-law2-gate.sh"
CLAUDE_LAW345="$ROOT/agent/hooks/claude/vald-law345-check.sh"
AGY_HOOK="$ROOT/agent/hooks/agy/vald-law-gate.sh"
PI_EXT="$ROOT/agent/hooks/pi/security-gate.ts"
VALD_CWD="/home/kpango/go/src/github.com/vdaas/vald"

total_fail=0
section() { echo; echo "=== $1 ==="; }

check_exit2() {
    local desc="$1" out="$2" ec="$3" expect_block="$4" # true|false
    local got=$([[ "$ec" -eq 2 ]] && echo block || echo allow)
    local expected=$([[ "$expect_block" == "true" ]] && echo block || echo allow)
    if [[ "$got" == "$expected" ]]; then
        echo "[OK] $desc"
    else
        echo "[FAIL] $desc : expected=$expected got=$got out=$out"
        total_fail=$((total_fail + 1))
    fi
}

# ------------------------------------------------------------------
# agent/hooks/claude/vald-law-gate.sh (Law1, PreToolUse:Write|Edit, block/allow)
# ------------------------------------------------------------------
section "agent/hooks/claude/vald-law-gate.sh (Law1)"
out="$(jq -n --arg fp "/x/foo_vtproto.pb.go" '{"tool_input":{"file_path":$fp}}' | "$CLAUDE_LAW1" 2>&1)"; ec=$?
check_exit2 "write to _vtproto.pb.go" "$out" "$ec" true
out="$(jq -n --arg fp "/x/foo.go" '{"tool_input":{"file_path":$fp}}' | "$CLAUDE_LAW1" 2>&1)"; ec=$?
check_exit2 "write to normal .go" "$out" "$ec" false

# ------------------------------------------------------------------
# agent/hooks/claude/vald-law2-gate.sh (Law2, PreToolUse:Bash, block/allow, cwd-scoped)
# ------------------------------------------------------------------
section "agent/hooks/claude/vald-law2-gate.sh (Law2)"
if [[ -d "$VALD_CWD" ]]; then
    out="$(cd "$VALD_CWD" && jq -n --arg c "go build ./..." '{"tool_input":{"command":$c}}' | "$CLAUDE_LAW2" 2>&1)"; ec=$?
    check_exit2 "go build in vald cwd" "$out" "$ec" true
    out="$(cd "$VALD_CWD" && jq -n --arg c "go test ./..." '{"tool_input":{"command":$c}}' | "$CLAUDE_LAW2" 2>&1)"; ec=$?
    check_exit2 "go test in vald cwd (now covered)" "$out" "$ec" true
else
    echo "[SKIP] go build in vald cwd : $VALD_CWD not present in this environment"
    echo "[SKIP] go test in vald cwd (now covered) : $VALD_CWD not present in this environment"
fi
# このhookはvaldのproject-scoped .claude/settings.jsonでのみ配線される(claude/CLAUDE.mdの
# 「Vald Project Hooks」参照)ため、cwdに関わらず配線されていれば無条件にチェックする設計
# (security-audit指摘2026-09-03: 以前この位置に独自のcwdゲートを追加していたことが
# `cd /other-repo && ...`でチェック自体を丸ごとスキップさせるbypassになっていたため削除した)。
out="$(cd "$ROOT" && jq -n --arg c "go build ./..." '{"tool_input":{"command":$c}}' | "$CLAUDE_LAW2" 2>&1)"; ec=$?
check_exit2 "go build (fires unconditionally once wired, cwd-independent by design)" "$out" "$ec" true
out="$(cd "$ROOT" && jq -n --arg c "cd /home/kpango/go/src/github.com/vdaas/vald && go build ./..." '{"tool_input":{"command":$c}}' | "$CLAUDE_LAW2" 2>&1)"; ec=$?
check_exit2 "compound cd+go-build now caught (pattern anchor bypass fix)" "$out" "$ec" true

# ------------------------------------------------------------------
# agent/hooks/claude/vald-law345-check.sh (Law3/4/5, PreToolUse:Write|Edit|MultiEdit, ask/allow)
# ------------------------------------------------------------------
section "agent/hooks/claude/vald-law345-check.sh (Law3/4/5)"
check345() {
    local desc="$1" tool_json="$2" expect_ask="$3"
    local out got
    out="$(echo "$tool_json" | "$CLAUDE_LAW345" 2>&1)"
    got=$(echo "$out" | jq -e '.hookSpecificOutput.permissionDecision=="ask"' >/dev/null 2>&1 && echo ask || echo allow)
    local expected=$([[ "$expect_ask" == "true" ]] && echo ask || echo allow)
    if [[ "$got" == "$expected" ]]; then echo "[OK] $desc"; else echo "[FAIL] $desc : expected=$expected got=$got out=$out"; total_fail=$((total_fail + 1)); fi
}
check345 "panic() via Write content" \
    "$(jq -n --arg fp "/x/foo.go" --arg c 'func f() { panic("bad") }' '{"tool_name":"Write","tool_input":{"file_path":$fp,"content":$c}}')" true
check345 "discarded error via Edit new_string" \
    "$(jq -n --arg fp "/x/foo.go" --arg old x --arg new '_ = doSomething()' '{"tool_name":"Edit","tool_input":{"file_path":$fp,"old_string":$old,"new_string":$new}}')" true
check345 "clean content" \
    "$(jq -n --arg fp "/x/foo.go" --arg c 'func f() { return nil }' '{"tool_name":"Write","tool_input":{"file_path":$fp,"content":$c}}')" false
check345 "_test.go excluded" \
    "$(jq -n --arg fp "/x/foo_test.go" --arg c 'func f() { panic("bad") }' '{"tool_name":"Write","tool_input":{"file_path":$fp,"content":$c}}')" false

# ------------------------------------------------------------------
# agent/hooks/agy/vald-law-gate.sh (Law1/2/3-5, toolCall schema, deny/allow)
# ------------------------------------------------------------------
section "agent/hooks/agy/vald-law-gate.sh"
agy_check() {
    local desc="$1" payload="$2" expected="$3" out got
    out="$(echo "$payload" | "$AGY_HOOK" 2>&1)"
    got=$(echo "$out" | jq -r '.decision' 2>/dev/null || echo ERROR)
    got=$([[ "$got" == "deny" ]] && echo deny || echo allow)
    if [[ "$got" == "$expected" ]]; then echo "[OK] $desc"; else echo "[FAIL] $desc : expected=$expected got=$got out=$out"; total_fail=$((total_fail + 1)); fi
}
agy_check "Law1: write to _vtproto.pb.go" \
    '{"toolCall":{"name":"write_to_file","args":{"file_path":"/x/foo_vtproto.pb.go","code_content":"x"}}}' deny
agy_check "Law2: go test in vald workspace (now covered)" \
    '{"toolCall":{"name":"run_command","args":{"command":"go test ./..."}},"workspacePaths":["/home/kpango/go/src/github.com/vdaas/vald"]}' deny
agy_check "Law2: go build outside vald" \
    '{"toolCall":{"name":"run_command","args":{"command":"go build ./..."}},"workspacePaths":["/home/kpango/go/src/github.com/kpango/dotfiles"]}' allow
agy_check "Law repo precision: 'myvald-test' no longer false-positives" \
    '{"toolCall":{"name":"run_command","args":{"command":"go build ./..."}},"workspacePaths":["/tmp/myvald-test"]}' allow
agy_check "Law2: compound cd+go-build now caught (pattern anchor bypass fix)" \
    '{"toolCall":{"name":"run_command","args":{"command":"cd /home/kpango/go/src/github.com/vdaas/vald && go build ./..."}},"workspacePaths":["/tmp/somewhere-else"]}' deny
# regression: security-audit指摘(2026-09-03) — workspace_and_cwd_and_command_string scope_modeは
# 元々cd/-Cターゲットのディレクトリ解決を行わず、cwd/workspaces/コマンド文字列そのものへの直接
# 一致のみだったため、`cd ../vald && ...` のような相対パスcdでコマンド文字列自体に
# "vdaas/vald" が literal に出現しないケースが丸ごとすり抜けていた(cwd_and_resolved_pathとの
# 非対称な弱点)。vald_command_targets へのcd/-C解決の追加でこの経路も検出できることを確認する。
if [[ -d /home/kpango/go/src/github.com/vdaas/qbg ]]; then
    out="$(cd /home/kpango/go/src/github.com/vdaas/qbg && echo '{"toolCall":{"name":"run_command","args":{"command":"cd ../vald && go build ./..."}},"workspacePaths":["/home/kpango/go/src/github.com/vdaas/qbg"]}' | "$AGY_HOOK" 2>&1)"
    got=$(echo "$out" | jq -r '.decision' 2>/dev/null || echo ERROR)
    got=$([[ "$got" == "deny" ]] && echo deny || echo allow)
    if [[ "$got" == "deny" ]]; then echo "[OK] Law2: relative cd+go-build now caught (resolved-path bypass fix)"; else echo "[FAIL] Law2: relative cd+go-build now caught (resolved-path bypass fix) : expected=deny got=$got out=$out"; total_fail=$((total_fail + 1)); fi
else
    echo "[SKIP] Law2: relative cd+go-build now caught (resolved-path bypass fix) : /home/kpango/go/src/github.com/vdaas/qbg not present in this environment"
fi
PANIC_PAYLOAD=$(jq -n --arg fp "/x/foo.go" --arg c 'func f() { panic("bad") }' '{"toolCall":{"name":"write_to_file","args":{"TargetFile":$fp,"CodeContent":$c}},"workspacePaths":["/home/kpango/go/src/github.com/vdaas/vald"]}')
# regression: security-audit指摘(2026-09-03) — is_vald が workspacePaths のみで判定されており、
# Write/Editの実ターゲットパスがvald配下でもworkspacePathsに一致entryが無ければLaw3/4/5が
# 丸ごとすり抜けていた。target自体もvald_repo_patternで判定に加える修正の再発防止テスト。
PANIC_TARGET_ONLY_PAYLOAD=$(jq -n --arg fp "/home/kpango/go/src/github.com/vdaas/vald/internal/foo.go" --arg c 'func f() { panic("bad") }' '{"toolCall":{"name":"write_to_file","args":{"TargetFile":$fp,"CodeContent":$c}},"workspacePaths":["/tmp/somewhere-else"]}')
agy_check "Law3: panic() caught via target path even when workspacePaths is non-vald (regression check)" "$PANIC_TARGET_ONLY_PAYLOAD" deny
EDIT_PANIC_PAYLOAD=$(jq -n --arg fp "/x/foo.go" --arg c 'func f() { panic("bad") }' '{"toolCall":{"name":"edit_file","args":{"TargetFile":$fp,"CodeContent":$c}},"workspacePaths":["/home/kpango/go/src/github.com/vdaas/vald"]}')
agy_check "Law3: edit_file now covered (was missing from tool_name whitelist)" "$EDIT_PANIC_PAYLOAD" deny
agy_check "Law3: panic() in vald Go content" "$PANIC_PAYLOAD" deny

# ------------------------------------------------------------------
# agent/hooks/pi/security-gate.ts (Law1/2/3-5, bun経由でハンドラを直接起動)
# ------------------------------------------------------------------
section "agent/hooks/pi/security-gate.ts (Vald Law)"
if command -v bun &>/dev/null; then
    PI_TEST_TS="$(mktemp -t pi-vald-law-test-XXXXXX.ts)"
    trap 'rm -f "$PI_TEST_TS"' EXIT
    cat > "$PI_TEST_TS" <<TSEOF
import securityGate from "$PI_EXT";
type Handler = (event: any, ctx: any) => Promise<any>;
let handler: Handler | null = null;
securityGate({ on(_n: string, fn: Handler) { handler = fn; } } as any);
let fail = 0;
const VALD_CWD = "$VALD_CWD";
const NONVALD_CWD = "$ROOT";
async function checkCmd(desc: string, command: string, cwd: string, expected: "block" | "allow") {
  const r = await handler!({ toolName: "bash", input: { command } }, { cwd, hasUI: false });
  const got = r?.block ? "block" : "allow";
  if (got === expected) console.log("[OK] " + desc);
  else { console.log("[FAIL] " + desc + " expected=" + expected + " got=" + got); fail++; }
}
async function checkWrite(desc: string, filePath: string, content: string, cwd: string, expected: "block" | "allow") {
  const r = await handler!({ toolName: "write", input: { path: filePath, content } }, { cwd, hasUI: false });
  const got = r?.block ? "block" : "allow";
  if (got === expected) console.log("[OK] " + desc);
  else { console.log("[FAIL] " + desc + " expected=" + expected + " got=" + got); fail++; }
}
async function main() {
  await checkWrite("Law1: write to _vtproto.pb.go", "/x/foo_vtproto.pb.go", "x", VALD_CWD, "block");
  await checkCmd("Law2: go test in vald cwd (now covered)", "go test ./...", VALD_CWD, "block");
  await checkCmd("Law2: go build outside vald", "go build ./...", NONVALD_CWD, "allow");
  // regression: security-audit指摘(2026-09-03) — pi はglobal extensionのためctx.cwdだけで
  // 判定すると、cwdがvald外のセッションで"cd <vald> && go build"のような複合コマンドが
  // 丸ごとすり抜けた。commandTargetsVald()でcd/-Cターゲット解決を追加した修正の再発防止。
  await checkCmd("Law2: compound cd+go-build from non-vald cwd now caught (bypass fix)", "cd " + VALD_CWD + " && go build ./...", NONVALD_CWD, "block");
  await checkWrite("Law3: panic() in vald Go write content (new protection)", "/x/foo.go", 'func f() { panic("bad") }', VALD_CWD, "block");
  await checkWrite("Law3: panic() in _test.go excluded", "/x/foo_test.go", 'func f() { panic("bad") }', VALD_CWD, "allow");
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
    echo "[SKIP] bun not found, agent/hooks/pi/security-gate.ts のVald Law統合テストをスキップ"
fi

echo
echo "---"
if [[ "$total_fail" -gt 0 ]]; then
    echo "test-vald-law-rules: $total_fail 件のFAILあり"
    exit 1
fi
echo "test-vald-law-rules: 全テストPASS"
exit 0
