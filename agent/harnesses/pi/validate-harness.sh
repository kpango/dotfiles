#!/usr/bin/env bash
# Pi Coding Agent Harness Validation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -P "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../../agent/scripts/harness-check-lib.sh
source "$ROOT/agent/scripts/harness-check-lib.sh"

echo "=== Pi Coding Agent Harness Validation ==="
echo

echo "[ Configuration Files ]"
python3 -m json.tool "$SCRIPT_DIR/settings.json" > /dev/null 2>&1 \
    && check "settings.json valid JSON" "OK" \
    || check "settings.json valid JSON" "INVALID"

python3 -m json.tool "$SCRIPT_DIR/models.json" > /dev/null 2>&1 \
    && check "models.json valid JSON" "OK" \
    || check "models.json valid JSON" "INVALID"

python3 -m json.tool "$SCRIPT_DIR/keybindings.json" > /dev/null 2>&1 \
    && check "keybindings.json valid JSON" "OK" \
    || check "keybindings.json valid JSON" "INVALID"

python3 -m json.tool "$SCRIPT_DIR/mcp.json" > /dev/null 2>&1 \
    && check "mcp.json valid JSON" "OK" \
    || check "mcp.json valid JSON" "INVALID"

python3 -m json.tool "$SCRIPT_DIR/themes/kpango-dark.json" > /dev/null 2>&1 \
    && check "themes/kpango-dark.json valid JSON" "OK" \
    || check "themes/kpango-dark.json valid JSON" "INVALID"

[[ -f "$SCRIPT_DIR/AGENTS.md" ]] && check "AGENTS.md exists" "OK" || check "AGENTS.md" "MISSING"
[[ -f "$SCRIPT_DIR/SYSTEM.md" ]] && check "SYSTEM.md exists" "OK" || check "SYSTEM.md" "MISSING"
[[ -f "$ROOT/agent/SWARM.md" ]]  && check "agent/SWARM.md exists" "OK"  || check "agent/SWARM.md" "MISSING"
[[ -f "$ROOT/agent/RTK.md" ]]    && check "agent/RTK.md exists" "OK"    || check "agent/RTK.md" "MISSING"

# MCPサーバー定義はExecutor gateway経由へ統合済み(agent/README.md「MCPサーバー定義の統合」参照)。
# 個別のmemory/codegraph/filesystemサーバー定義はpi/mcp.jsonにはもう存在しない。
python3 -c "
import json
d = json.load(open('$SCRIPT_DIR/mcp.json'))
srv = d.get('mcpServers', {}).get('executor', {})
raise SystemExit(0 if srv.get('url') else 1)
" \
    && check "mcp.json: executor gateway configured" "OK" \
    || check "mcp.json: executor gateway configured" "MISSING (add mcpServers.executor)"

echo
echo "[ CLI Binaries & Bridges ]"
for bin in pi claude agy codex rtk jq flock bun node git hx; do
    if command -v "$bin" &>/dev/null; then
        check "binary available: $bin" "OK"
    else
        check "binary available: $bin" "WARN:not found in PATH"
    fi
done

echo
echo "[ TypeScript Extensions ($SCRIPT_DIR/extensions/) ]"
EXTENSIONS=(
    bridge-claude.ts
    bridge-antigravity.ts
    bridge-codex.ts
    subagents.ts
    security-gate.ts
    rtk-optimizer.ts
    graphify-hint.ts
    status-line.ts
    swarm-orchestrator.ts
    plan-mode.ts
    git-checkpoint.ts
    mcp-bridge.ts
    context-economy.ts
    auto-memory.ts
    interactive-question.ts
    developer-ergonomics.ts
    subagent-mesh.ts
    skill-synthesizer.ts
    loop-controller.ts
    repl-context.ts
    continual-harness.ts
    reasoning-preserver.ts
    session-journal.ts
    daemon-session.ts
    grill-elicitation.ts
    ponytail-guard.ts
)

# security-gate.ts・graphify-hint.ts・auto-memory.ts はdecide.py委譲shim本体として、
# rtk-optimizer.tsは(判定ロジック共有はないが物理配置の統一のため)agent/hooks/pi/へ実体移動済み
# (agent-hooks-and-pi-agents-unificationミッション・後続のrtk統合作業)。リポジトリ内では
# pi/extensions/配下に実ファイルが無いため、この4件のみ移動先を直接検査する
# (デプロイ後の$HOME側では従来どおり~/.pi/agent/extensions/配下にper-file symlinkとして統合される、
# Makefile.d/install.mk・nix/agent-tools.nix参照)。
MOVED_TO_AGENT_HOOKS=(security-gate.ts graphify-hint.ts auto-memory.ts rtk-optimizer.ts)
for ext in "${EXTENSIONS[@]}"; do
    ext_path="$SCRIPT_DIR/extensions/$ext"
    for moved in "${MOVED_TO_AGENT_HOOKS[@]}"; do
        [[ "$ext" == "$moved" ]] && ext_path="$ROOT/agent/hooks/pi/$ext"
    done
    if [[ -f "$ext_path" ]]; then
        if command -v bun &>/dev/null; then
            bun build --no-bundle "$ext_path" > /dev/null 2>&1 \
                && check "extension: $ext (bun syntax check)" "OK" \
                || check "extension: $ext (bun syntax check)" "SYNTAX ERROR"
        else
            check "extension: $ext" "OK"
        fi
    else
        check "extension: $ext" "MISSING"
    fi
done

echo
echo "[ Specialized Agents ($ROOT/agent/agents/) ]"
# 2026-09-03以前はpi/agentsがagent/scripts/gen-pi-agents.shの生成する実ディレクトリで、
# 本スクリプトも$SCRIPT_DIR/agents(リポジトリ相対のpi/agents)を検査対象にしていたが、
# ~/.pi/agent/agentsがagent/agentsへ直接symlinkされる方式へ移行した(claude/agyと同型、
# agent-hooks-and-pi-agents-unificationミッション)ため、リポジトリ内の正典である
# $ROOT/agent/agentsを直接検査する(pi/agentsという中間実体は無くなったため)。
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
# SKILL.mdは正典 agent/skills にのみ存在する(2026-09-03: pi/skills配下のfile-level symlinkを
# 全廃し、$HOME/.pi/agent/skillsはagent/skillsへ直接symlinkする設計に変更したため)。
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
echo "[ Prompt Templates ($SCRIPT_DIR/prompts/) ]"
for prompt in swarm-loop swarm-graph swarm-meta review audit claude agy codex architect; do
    [[ -f "$SCRIPT_DIR/prompts/$prompt.md" ]] \
        && check "prompt template: $prompt.md" "OK" \
        || check "prompt template: $prompt.md" "MISSING"
done

echo
echo "[ Shared Rule-Data-Driven Hooks (agent/*.json 経由) ]"
# claude/agy/piが共通で読む agent/security-rules.json・agent/vald-law-rules.json・
# agent/graphify-hint-config.json の整合性は、個別テストケースをここに再実装せず
# agent/scripts/test-*.sh(単一の実体)へ委譲する。pi実装(agent/hooks/pi/security-gate.ts等)を
# 含めて検証されるため、ここで重複再実装しない。
harness_run_shared_test "security-rules.json driven hooks (claude/agy/pi)" "$ROOT/agent/scripts/test-security-rules.sh"
harness_run_shared_test "vald-law-rules.json driven hooks (claude/agy/pi)" "$ROOT/agent/scripts/test-vald-law-rules.sh"
harness_run_shared_test "graphify-hint-config.json driven hooks (claude/agy/pi)" "$ROOT/agent/scripts/test-graphify-hint.sh"
harness_run_shared_test "memory-context composition (claude/agy/pi)" "$ROOT/agent/scripts/test-memory-context.sh"
harness_run_shared_test "merged directory root解決の回帰テスト (claude/agy/pi)" "$ROOT/agent/scripts/test-merged-dir-root-resolution.sh"

harness_summary "Pi Coding Agent SOTA Harness"
