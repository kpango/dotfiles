#!/usr/bin/env bash
# 2026-09-03 agent-hooks-and-pi-agents-unificationミッションPhase 4.5で発見・修正されたCRITICAL
# 回帰(merged directory化によるroot解決崩壊)の再発を検出する回帰テスト。
#
# 背景: `~/.claude/hooks`・`~/.agy/hooks`・`~/.gemini/hooks`・`~/.pi/agent/extensions` は
# ディレクトリ全体がsymlinkだった旧設計から、実体ディレクトリ内にper-file symlinkを配置する
# 「merged directory」設計(Makefile.d/install.mk・nix/modules/home/dotfiles/agent-tools.nixが
# 構成)へ移行した。既存のroot解決idiom `cd -P "$(dirname "${BASH_SOURCE[0]}")"` は
# 「ディレクトリ自体がsymlink」を前提としており、`dirname`がファイル名を落としてから評価される
# ため、ディレクトリが実体になった新設計ではsymlinkを一切解決できず誤ったROOTに解決してしまう
# (security-gate.sh等decide.py委譲shimは全てfail-openのため、実害はセキュリティチェックの
# 無音無効化)。修正は`readlink -f`でファイル自身のsymlinkを先に解決してから`dirname`する方式。
#
# 他のtest-*.sh(test-security-rules.sh等)は agent/hooks/{claude,agy,pi}/ の実ファイルを
# リポジトリ相対パスで直接起動するため、この回帰を検出できない(symlinkチェーンを一切経由しない)。
# 本テストは`mktemp -d`上でMakefile.d/install.mkの`find ... -exec ln -sfvn`と同型の
# merged directory配置を再現し、実際にsymlink経由でHERE/ROOTが正しく解決されることを検証する。
#
# usage: agent/scripts/test-merged-dir-root-resolution.sh
# exit: 0 = 全テストPASS, 1 = 1件以上FAIL
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
total_fail=0
section() { echo; echo "=== $1 ==="; }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Makefile.d/install.mkの claude/install ターゲットと同型の merged directory を再現する:
# 実体の $HOME/.claude/hooks ディレクトリ内に、claude/hooks/ と agent/hooks/claude/ の両方から
# per-file symlinkを配置する(find ... -exec ln -sfvn {} <dest>/ \; の2連続実行と同じ結果)。
build_merged_dir() {
    local dest="$1"; shift
    mkdir -p "$dest"
    local src
    for src in "$@"; do
        find "$src" -maxdepth 1 -type f -exec ln -sfvn {} "$dest/" \;
    done
}

# ------------------------------------------------------------------
# claude: agent/hooks/claude/security-gate.sh を merged directory 経由で起動
# ------------------------------------------------------------------
section "claude: merged directory経由でのroot解決"
CLAUDE_MERGED="$WORK/home/.claude/hooks"
build_merged_dir "$CLAUDE_MERGED" "$ROOT/agent/harnesses/claude/hooks" "$ROOT/agent/hooks/claude"

if [[ -f "$CLAUDE_MERGED/security-gate.sh" ]]; then
    out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | bash "$CLAUDE_MERGED/security-gate.sh" 2>&1)"
    status=$?
    if [[ "$status" -eq 0 && -z "$out" ]]; then
        echo "[OK] claude security-gate.sh: 安全なコマンドをallow(exit 0, no output)"
    else
        echo "[FAIL] claude security-gate.sh: 安全なコマンドのallow判定に失敗 (status=$status out=$out)"
        total_fail=$((total_fail + 1))
    fi

    # 危険コマンドがblockされることを確認する(ROOT誤解決によるfail-openを検出する本命のcase:
    # RULES_FILEが見つからなければ判定ロジック自体が実行されずallowになる)。
    danger_out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' | bash "$CLAUDE_MERGED/security-gate.sh" 2>&1)"
    danger_status=$?
    if [[ "$danger_status" -ne 0 && -n "$danger_out" ]]; then
        echo "[OK] claude security-gate.sh: rm -rf / をblock(merged directory経由でもfail-openしない)"
    else
        echo "[FAIL] claude security-gate.sh: rm -rf / がblockされなかった(merged directory化でfail-open回帰の疑い、status=$danger_status out=$danger_out)"
        total_fail=$((total_fail + 1))
    fi
else
    echo "[FAIL] claude security-gate.sh: merged directory内にsymlinkが生成されなかった"
    total_fail=$((total_fail + 1))
fi

# ------------------------------------------------------------------
# agy: agent/hooks/agy/security-gate.sh を merged directory 経由で起動
# ------------------------------------------------------------------
section "agy: merged directory経由でのroot解決"
AGY_MERGED="$WORK/home/.agy/hooks"
build_merged_dir "$AGY_MERGED" "$ROOT/agent/harnesses/agy/hooks" "$ROOT/agent/hooks/agy"

if [[ -f "$AGY_MERGED/security-gate.sh" ]]; then
    danger_out="$(jq -n '{"toolCall":{"name":"run_command","args":{"command":"rm -rf /"}}}' | bash "$AGY_MERGED/security-gate.sh" 2>&1)"
    decision="$(echo "$danger_out" | jq -r '.decision // empty' 2>/dev/null)"
    if [[ "$decision" == "deny" ]]; then
        echo "[OK] agy security-gate.sh: rm -rf / をdeny(merged directory経由でもfail-openしない)"
    else
        echo "[FAIL] agy security-gate.sh: rm -rf / がdenyされなかった(decision=$decision out=$danger_out)"
        total_fail=$((total_fail + 1))
    fi
else
    echo "[FAIL] agy security-gate.sh: merged directory内にsymlinkが生成されなかった"
    total_fail=$((total_fail + 1))
fi

# ------------------------------------------------------------------
# pi: agent/hooks/pi/security-gate.ts を merged directory 経由で起動(bun経由)
# ------------------------------------------------------------------
section "pi: merged directory経由でのroot解決"
if command -v bun &>/dev/null; then
    PI_MERGED="$WORK/home/.pi/agent/extensions"
    mkdir -p "$PI_MERGED/lib"
    find "$ROOT/agent/harnesses/pi/extensions" -maxdepth 1 -type f -exec ln -sfvn {} "$PI_MERGED/" \;
    find "$ROOT/agent/hooks/pi" -maxdepth 1 -type f -exec ln -sfvn {} "$PI_MERGED/" \;
    find "$ROOT/agent/harnesses/pi/extensions/lib" -maxdepth 1 -type f -exec ln -sfvn {} "$PI_MERGED/lib/" \;
    find "$ROOT/agent/hooks/pi/lib" -maxdepth 1 -type f -exec ln -sfvn {} "$PI_MERGED/lib/" \;

    PI_TEST_TS="$(mktemp -t pi-merged-dir-test-XXXXXX.ts)"
    trap 'rm -f "$PI_TEST_TS"; cleanup' EXIT
    cat > "$PI_TEST_TS" <<TSEOF
import securityGate from "$PI_MERGED/security-gate.ts";
type Handler = (event: any, ctx: any) => Promise<any>;
let handler: Handler | null = null;
securityGate({ on(_n: string, fn: Handler) { handler = fn; } } as any);
let fail = 0;
async function main() {
  const denied: string[] = [];
  const result = await handler!(
    { toolName: "bash", input: { command: "rm -rf /" } },
    { cwd: "$ROOT", ui: { confirm: async () => false } },
  );
  const blocked = result === false || (result && (result.deny === true || result.block === true)) || denied.length > 0;
  if (blocked) console.log("[OK] pi security-gate.ts: rm -rf / をblock(merged directory経由でもfail-openしない)");
  else { console.log("[FAIL] pi security-gate.ts: rm -rf / がblockされなかった(result=" + JSON.stringify(result) + ")"); fail++; }
  console.log(fail > 0 ? fail + " FAILURES" : "PI_ALL_PASS");
  process.exit(fail > 0 ? 1 : 0);
}
main();
TSEOF
    bun run "$PI_TEST_TS"
    pi_status=$?
    [[ "$pi_status" -ne 0 ]] && total_fail=$((total_fail + 1))
else
    echo "[SKIP] bun not found, agent/hooks/pi/security-gate.ts のmerged directory回帰テストをスキップ"
fi

echo
echo "---"
if [[ "$total_fail" -gt 0 ]]; then
    echo "test-merged-dir-root-resolution: $total_fail 件のFAILあり"
    exit 1
fi
echo "test-merged-dir-root-resolution: 全テストPASS"
exit 0
