#!/usr/bin/env bash
# Antigravity (AGY) Harness Validation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -P "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../../agent/scripts/harness-check-lib.sh
source "$ROOT/agent/scripts/harness-check-lib.sh"

echo "=== Antigravity (AGY) Harness Validation ==="
echo

echo "[ Configuration Files ]"
python3 -m json.tool "$SCRIPT_DIR/settings.json" > /dev/null 2>&1 \
    && check "settings.json valid JSON" "OK" \
    || check "settings.json valid JSON" "INVALID"

python3 -m json.tool "$SCRIPT_DIR/mcp_config.json" > /dev/null 2>&1 \
    && check "mcp_config.json valid JSON" "OK" \
    || check "mcp_config.json valid JSON" "INVALID"

python3 -m json.tool "$SCRIPT_DIR/hooks/hooks.json" > /dev/null 2>&1 \
    && check "hooks/hooks.json valid JSON" "OK" \
    || check "hooks/hooks.json valid JSON" "INVALID"

python3 -c '
import tomllib
with open("'"$SCRIPT_DIR"'/policies/policy.toml", "rb") as fp:
    tomllib.load(fp)
' > /dev/null 2>&1 \
    && check "policies/policy.toml valid TOML" "OK" \
    || check "policies/policy.toml valid TOML" "INVALID"
# policies/rules.toml はリポジトリ側には存在しない(policy.tomlの単なるsymlinkリンク先名。
# Makefile.d/install.mk・nix/modules/home/dotfiles/{shared,agent-tools}.nixが常にpolicy.tomlを
# symlinkの参照元としてrules.tomlへ配置する。過去にrepo側へbyte-identicalな複製が誤って
# 追加されていたため削除済み — 2箇所の実体を手作業で同期する必要をなくすための意図的な設計)。

[[ -f "$SCRIPT_DIR/AGENTS.md" ]] && check "AGENTS.md exists" "OK" || check "AGENTS.md" "MISSING"
[[ -f "$SCRIPT_DIR/SYSTEM.md" ]] && check "SYSTEM.md exists" "OK" || check "SYSTEM.md" "MISSING"
[[ -f "$ROOT/agent/SWARM.md" ]]  && check "agent/SWARM.md exists" "OK"  || check "agent/SWARM.md" "MISSING"
[[ -f "$ROOT/agent/RTK.md" ]]    && check "agent/RTK.md exists" "OK"    || check "agent/RTK.md" "MISSING"

# MCPサーバー定義はExecutor gateway経由へ統合済み(agent/README.md「MCPサーバー定義の統合」参照)。
python3 -c "
import json
d = json.load(open('$SCRIPT_DIR/mcp_config.json'))
srv = d.get('mcpServers', {}).get('executor', {})
raise SystemExit(0 if srv.get('serverUrl') else 1)
" \
    && check "mcp_config.json: executor gateway configured" "OK" \
    || check "mcp_config.json: executor gateway configured" "MISSING (add mcpServers.executor)"

# settings.json: model must be string or absent, not object (schema regression prevention)
python3 -c "
import json, sys
d = json.load(open('$SCRIPT_DIR/settings.json'))
model = d.get('model')
if model is not None and not isinstance(model, str):
    sys.exit(1)
" \
    && check "settings.json: model is valid string ID" "OK" \
    || check "settings.json: model is valid string ID" "INVALID (model must be string, not object)"

# settings.json: mcpServers.executor must use serverUrl if defined
python3 -c "
import json, sys
d = json.load(open('$SCRIPT_DIR/settings.json'))
mcp = d.get('mcpServers', {}).get('executor')
if mcp and not mcp.get('serverUrl'):
    sys.exit(1)
" \
    && check "settings.json: executor gateway serverUrl" "OK" \
    || check "settings.json: executor gateway serverUrl" "INVALID (must use serverUrl, not httpUrl)"

# hooks/hooks.json: all event types must be supported by Antigravity
python3 -c "
import json, sys
d = json.load(open('$SCRIPT_DIR/hooks/hooks.json'))
allowed_events = {'PreToolUse', 'PostToolUse', 'PreInvocation', 'PostInvocation', 'Stop'}
for hook_name, hook_spec in d.items():
    if not isinstance(hook_spec, dict):
        sys.exit(1)
    for k in hook_spec.keys():
        if k == 'enabled':
            continue
        if k not in allowed_events:
            sys.exit(1)
" \
    && check "hooks/hooks.json: supported event types" "OK" \
    || check "hooks/hooks.json: supported event types" "INVALID (unsupported event type detected)"

echo
echo "[ CLI Binaries & Bridges ]"
for bin in agy claude pi codex rtk jq flock bun node git hx; do
    if command -v "$bin" &>/dev/null; then
        check "binary available: $bin" "OK"
    else
        check "binary available: $bin" "WARN:not found in PATH"
    fi
done

echo
echo "[ Lifecycle Hooks ($SCRIPT_DIR/hooks/ + $ROOT/agent/hooks/agy/) ]"
# security-gate.sh・graphify-hint.sh・vald-law-gate.sh・session-start.shはdecide.py委譲shim本体として、
# rtk-rewrite.shは(判定ロジック共有はないが物理配置の統一のため)agent/hooks/agy/へ実体移動済み
# (agent-hooks-and-pi-agents-unificationミッション・後続のrtk統合作業)。リポジトリ内では
# agy/hooks/配下に実ファイルが無いため、この5件のみ移動先を直接検査する(デプロイ後の$HOME側では
# 従来どおり~/.agy/hooks・~/.gemini/hooks配下にper-file symlinkとして統合される、
# Makefile.d/install.mk・nix/agent-tools.nix参照)。post-edit-lint.shはagy固有の非shimのまま
# agy/hooks/に残る。
MOVED_TO_AGENT_HOOKS=(security-gate.sh graphify-hint.sh vald-law-gate.sh session-start.sh rtk-rewrite.sh)
for hook in security-gate.sh rtk-rewrite.sh graphify-hint.sh vald-law-gate.sh session-start.sh post-edit-lint.sh; do
    hook_path="$SCRIPT_DIR/hooks/$hook"
    for moved in "${MOVED_TO_AGENT_HOOKS[@]}"; do
        [[ "$hook" == "$moved" ]] && hook_path="$ROOT/agent/hooks/agy/$hook"
    done
    if [[ -f "$hook_path" ]]; then
        if [[ -x "$hook_path" ]]; then
            check "hook script: $hook (executable)" "OK"
        else
            check "hook script: $hook" "WARN:not executable"
        fi
    else
        check "hook script: $hook" "MISSING"
    fi
done

echo
echo "[ Specialized Agents ($ROOT/agent/agents/) ]"
# agy/agents は存在しない(2026-09-03: リポジトリ内symlink全廃、$HOME/.agy/agentsはagent/agentsへ
# 直接symlinkする設計に変更したため)。正典側を検証する。
AGENT_COUNT=0
for agent_file in "$ROOT/agent/agents"/*.md; do
    [[ -f "$agent_file" ]] || continue
    AGENT_COUNT=$((AGENT_COUNT + 1))
done
if [[ "$AGENT_COUNT" -ge 20 ]]; then
    check "Agent count ($AGENT_COUNT agents discovered)" "OK"
else
    check "Agent count ($AGENT_COUNT agents discovered)" "WARN:expected >= 20"
fi

for essential in go-expert rust-expert arch-ops security-audit perf-analyzer code-reviewer debugger proto-expert vald-reviewer; do
    [[ -f "$ROOT/agent/agents/$essential.md" ]] \
        && check "agent definition: $essential" "OK" \
        || check "agent definition: $essential" "MISSING"
done

echo
echo "[ Agent Skills ($ROOT/agent/skills/) ]"
# SKILL.mdは正典 agent/skills にのみ存在する(2026-09-03: agy/skills配下のfile-level symlinkを
# 全廃し、$HOME/.agy/skillsはagent/skillsへ直接symlinkする設計に変更したため)。
SKILL_COUNT=0
for skill_dir in "$ROOT/agent/skills"/*/; do
    [[ -d "$skill_dir" ]] || continue
    SKILL_COUNT=$((SKILL_COUNT + 1))
    if [[ ! -f "${skill_dir}SKILL.md" ]]; then
        check "SKILL.md in $(basename "$skill_dir")" "MISSING"
    fi
done
if [[ "$SKILL_COUNT" -ge 20 ]]; then
    check "Skill count ($SKILL_COUNT skills discovered with SKILL.md)" "OK"
else
    check "Skill count ($SKILL_COUNT skills discovered)" "WARN:expected >= 20"
fi

for essential_skill in golang-patterns golang-testing rust-patterns cpp-patterns python-patterns swarm-loop swarm-graph swarm-meta swarm-explore swarm-implement swarm-architect; do
    [[ -f "$ROOT/agent/skills/$essential_skill/SKILL.md" ]] \
        && check "skill: $essential_skill" "OK" \
        || check "skill: $essential_skill" "MISSING"
done

echo
echo "[ Shared Rule-Data-Driven Hooks (agent/*.json 経由) ]"
# security-gate.sh・vald-law-gate.sh・graphify-hint.shの個別テストケースはここに再実装せず、
# claude/agy/pi横断で共有される agent/scripts/test-*.sh(単一の実体)へ委譲する。
harness_run_shared_test "security-rules.json driven hooks (claude/agy/pi)" "$ROOT/agent/scripts/test-security-rules.sh"
harness_run_shared_test "vald-law-rules.json driven hooks (claude/agy/pi)" "$ROOT/agent/scripts/test-vald-law-rules.sh"
harness_run_shared_test "graphify-hint-config.json driven hooks (claude/agy/pi)" "$ROOT/agent/scripts/test-graphify-hint.sh"
harness_run_shared_test "memory-context composition (claude/agy/pi)" "$ROOT/agent/scripts/test-memory-context.sh"
harness_run_shared_test "merged directory root解決の回帰テスト (claude/agy/pi)" "$ROOT/agent/scripts/test-merged-dir-root-resolution.sh"

echo
echo "[ Agy固有hookの複数cwd横断スモークテスト ]"
# session-start.sh・rtk-rewrite.sh・post-edit-lint.shはagy固有(共有ルールデータを持たない)ため、
# ここに残す。security-gate/vald-law-gate/graphify-hintは上記の共有テストへ委譲済みのため
# このマトリクスから除外した(重複実装の解消)。
SCRIPT_DIR_EXP="$SCRIPT_DIR" AGENT_HOOKS_AGY_EXP="$ROOT/agent/hooks/agy" python3 -c '
import json, os, subprocess, sys

script_dir = os.environ.get("SCRIPT_DIR_EXP", "")
hooks_dir = os.path.join(script_dir, "hooks")
# session-start.sh・rtk-rewrite.shはagent-hooks-and-pi-agents-unificationミッション(2026-09-03)+
# 後続のrtk統合作業でagent/hooks/agy/へ実体移動済み(session-start.shはdecide.py委譲shim本体、
# rtk-rewrite.shは判定ロジック共有はないが物理配置統一のため)。post-edit-lint.shはagy固有の
# 非shimファイルでagy/hooks/のまま。hooks_dirを移動済みの2件だけ差し替えないと、mainブランチ実行時に
# `bash <存在しないagy/hooks/*.sh>`がexit 127で無条件に落ちる(mission-worktreeでは
# set -eカスケードで手前のtest-security-rules.sh失敗が全体を無言中断させるため、このバグ自体は
# validate-harness.shが最後まで到達するmainブランチでしか顕在化しなかった — Phase 4.5敵対的レビュー
# 3ラウンドいずれもこの経路まで到達せず見逃した実例)。
agent_hooks_agy = os.environ.get("AGENT_HOOKS_AGY_EXP", "")

test_cases = [
    {"script": f"{agent_hooks_agy}/session-start.sh", "name": "session-start: memory injection", "payload": {"session_id": "audit-test-01"}, "expected": "allow"},
    {"script": f"{agent_hooks_agy}/rtk-rewrite.sh", "name": "rtk-rewrite: status check", "payload": {"toolCall": {"name": "run_command", "args": {"CommandLine": "git status"}}}, "expected": "allow"},
    {"script": f"{hooks_dir}/post-edit-lint.sh", "name": "post-edit-lint: json verification", "payload": {"toolCall": {"name": "write_to_file", "args": {"TargetFile": "/home/kpango/go/src/github.com/kpango/dotfiles/agy/settings.json"}}}, "expected": None},
    # yaml/tomlチェック(2026-09-03、claude/hooks/post-write.shとの対象拡張子superset化で追加)が
    # クラッシュせず既存の"{}"を返す設計を維持していることの回帰確認。
    {"script": f"{hooks_dir}/post-edit-lint.sh", "name": "post-edit-lint: yaml verification", "payload": {"toolCall": {"name": "write_to_file", "args": {"TargetFile": os.path.join(script_dir, "..", ".hadolint.yaml")}}}, "expected": None},
    {"script": f"{hooks_dir}/post-edit-lint.sh", "name": "post-edit-lint: toml verification", "payload": {"toolCall": {"name": "write_to_file", "args": {"TargetFile": os.path.join(script_dir, "..", "starship.toml")}}}, "expected": None},
    # Makefileチェックは意図的に実装しない(security-audit指摘、HIGH: `make -n`はdry-runでも
    # `$(shell ...)`をパース時に評価してしまい任意コマンド実行になる、agent/README.md参照)。
    # このケースはMakefileを渡してもクラッシュせず素通り(no-op)することの回帰確認に留める。
    {"script": f"{hooks_dir}/post-edit-lint.sh", "name": "post-edit-lint: Makefile passthrough (no unsafe make -n)", "payload": {"toolCall": {"name": "write_to_file", "args": {"TargetFile": os.path.join(script_dir, "..", "Makefile")}}}, "expected": None},
]

cwds = ["/tmp", "/home/kpango", "/home/kpango/go/src/github.com/kpango/dotfiles"]
failed = 0

for cwd in cwds:
    for tc in test_cases:
        tname = tc["name"]
        p = subprocess.run(["bash", tc["script"]], input=json.dumps(tc["payload"]), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=cwd)
        if p.returncode != 0:
            print("  NG  [" + cwd + "] " + tname + ": exit code " + str(p.returncode))
            failed += 1
            continue
        try:
            out = json.loads(p.stdout)
        except Exception:
            print("  NG  [" + cwd + "] " + tname + ": invalid JSON")
            failed += 1
            continue
        if tc["expected"] is not None and out.get("decision") != tc["expected"]:
            print("  NG  [" + cwd + "] " + tname + ": expected " + str(tc["expected"]) + ", got " + str(out.get("decision")))
            failed += 1
            continue
        print("  OK  [" + cwd + "] " + tname)

if failed > 0:
    sys.exit(1)
' && check "agy固有hooks: /tmp, home, dotfiles 全cwdで検証通過" "OK" || check "agy固有hooks: 複数cwd検証" "FAILED"

# security-audit指摘(2026-09-03、HIGH)の再発防止: `make -n -f`はGNU Makeの`$(shell ...)`を
# dry-runでも実行してしまう(実機PoCで確認済み)。post-edit-lint.shはMakefileのlintを意図的に
# 実装しない(agent/README.md参照)ため、この種のMakefileを渡しても$(shell ...)が実行されない
# (=マーカーファイルが作成されない)ことを回帰確認する。
if command -v make &>/dev/null; then
    MAKE_POC_DIR=$(mktemp -d)
    MAKE_POC_MARKER="$MAKE_POC_DIR/PWNED_MARKER"
    MAKE_POC_FILE="$MAKE_POC_DIR/Makefile"
    printf 'X := $(shell touch %s)\nall:\n\t@echo ok\n' "$MAKE_POC_MARKER" > "$MAKE_POC_FILE"
    MAKE_POC_PAYLOAD=$(jq -n --arg fp "$MAKE_POC_FILE" '{"toolCall":{"name":"write_to_file","args":{"TargetFile":$fp}}}')
    echo "$MAKE_POC_PAYLOAD" | bash "$SCRIPT_DIR/hooks/post-edit-lint.sh" >/dev/null 2>&1 || true
    if [[ -f "$MAKE_POC_MARKER" ]]; then
        check "post-edit-lint: does not execute \$(shell ...) in Makefile (make -n RCE)" "WARN:marker file was created — Makefile lint must not be reintroduced via make -n"
    else
        check "post-edit-lint: does not execute \$(shell ...) in Makefile (make -n RCE)" "OK"
    fi
    rm -rf "$MAKE_POC_DIR" 2>/dev/null || true
fi

harness_summary "Antigravity (AGY) Harness"
