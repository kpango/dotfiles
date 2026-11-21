#!/usr/bin/env bash
# Oh My Pi (OMP) Agent Harness Validation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -P "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../../agent/scripts/harness-check-lib.sh
source "$ROOT/agent/scripts/harness-check-lib.sh"

echo "=== Oh My Pi (OMP) Agent Harness Validation ==="
echo

echo "[ Configuration Files ]"
[[ ! -e "$SCRIPT_DIR/settings.json" ]] \
    && check "settings.json absent (YAML-only config invariant)" "OK" \
    || check "settings.json absent (YAML-only config invariant)" "FOUND (must not exist; OMP uses config.yml)"

for yml_file in config.yml models.yml lsp.yml; do
    if python3 -c 'import yaml, sys; data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")); assert isinstance(data, dict)' "$SCRIPT_DIR/$yml_file" 2>/dev/null; then
        check "$yml_file valid YAML" "OK"
    else
        check "$yml_file valid YAML" "INVALID"
    fi
done

python3 -c '
import yaml, sys
cfg = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert isinstance(cfg.get("modelRoles"), dict) and "default" in cfg["modelRoles"]
assert cfg.get("edit", {}).get("mode") == "hashline"
assert cfg.get("ttsr", {}).get("enabled") is True
' "$SCRIPT_DIR/config.yml" 2>/dev/null \
    && check "config.yml schema (modelRoles/edit/ttsr)" "OK" \
    || check "config.yml schema (modelRoles/edit/ttsr)" "INVALID"

python3 -c '
import yaml, sys
m = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
provs = m.get("providers", {})
assert isinstance(provs, dict) and "opencode-go" in provs and "ollama" in provs
assert provs["opencode-go"].get("baseUrl") == "https://opencode.ai/zen/go/v1"
' "$SCRIPT_DIR/models.yml" 2>/dev/null \
    && check "models.yml providers (opencode-go/ollama)" "OK" \
    || check "models.yml providers (opencode-go/ollama)" "INVALID"

python3 -c '
import yaml, sys
l = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
srvs = l.get("servers", {})
assert isinstance(srvs, dict) and "gopls" in srvs and "rust-analyzer" in srvs
' "$SCRIPT_DIR/lsp.yml" 2>/dev/null \
    && check "lsp.yml servers schema" "OK" \
    || check "lsp.yml servers schema" "INVALID"

python3 -m json.tool "$SCRIPT_DIR/dap.json" > /dev/null 2>&1 \
    && python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
adapters = d.get("adapters", {})
assert isinstance(adapters, dict) and "dlv" in adapters and "lldb-dap" in adapters
' "$SCRIPT_DIR/dap.json" 2>/dev/null \
    && check "dap.json valid JSON & adapters (dlv/lldb-dap)" "OK" \
    || check "dap.json valid JSON & adapters" "INVALID"

python3 -m json.tool "$SCRIPT_DIR/sol-pi.json" > /dev/null 2>&1 \
    && python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
# Upstream shape: versioned, mechanism booleans at the top level, OMP-only
# knobs in the explicit `omp` namespace. Anything else is rejected at runtime.
assert d.get("version") == 1
assert d.get("actionFusion") is True
assert d.get("observationPack") is True
assert d.get("evidencePreservingReducer") is True
assert d.get("onlineContextCompact") is False
assert d["omp"]["pricingCliffAdvisory"] is True
assert "pricingCliffs" not in d["omp"]["onlineContextCompact"]
assert d["omp"]["missionBridge"]["enabled"] is True
assert d["omp"]["missionBridge"]["traces"] is True
assert "missionBridge" not in d
assert "pricingCliffAdvisoryConfig" not in d
assert "actionFusionConfig" not in d
' "$SCRIPT_DIR/sol-pi.json" 2>/dev/null \
    && check "sol-pi.json valid JSON & upstream flags (omp namespace)" "OK" \
    || check "sol-pi.json valid JSON & upstream flags (omp namespace)" "INVALID"

python3 -m json.tool "$SCRIPT_DIR/model-routing.json" > /dev/null 2>&1 \
    && python3 "$ROOT/agent/scripts/resolve-model-tier.py" --check omp > /dev/null 2>&1 \
    && check "model-routing.json valid & tier check passed" "OK" \
    || check "model-routing.json valid & tier check" "INVALID"

python3 -m json.tool "$SCRIPT_DIR/keybindings.json" > /dev/null 2>&1 \
    && check "keybindings.json valid JSON" "OK" \
    || check "keybindings.json valid JSON" "INVALID"

python3 -m json.tool "$SCRIPT_DIR/themes/kpango-dark.json" > /dev/null 2>&1 \
    && check "themes/kpango-dark.json valid JSON" "OK" \
    || check "themes/kpango-dark.json valid JSON" "INVALID"

[[ -f "$SCRIPT_DIR/AGENTS.md" ]] && check "AGENTS.md exists" "OK" || check "AGENTS.md" "MISSING"
[[ -f "$SCRIPT_DIR/SYSTEM.md" ]] && check "SYSTEM.md exists" "OK" || check "SYSTEM.md" "MISSING"
[[ -f "$ROOT/agent/rules/vald-law-ttsr.md" ]] && check "agent/rules/vald-law-ttsr.md exists" "OK" || check "agent/rules/vald-law-ttsr.md" "MISSING"
[[ -f "$ROOT/agent/SWARM.md" ]]  && check "agent/SWARM.md exists" "OK"  || check "agent/SWARM.md" "MISSING"
[[ -f "$ROOT/agent/RTK.md" ]]    && check "agent/RTK.md exists" "OK"    || check "agent/RTK.md" "MISSING"

echo
echo "[ CLI Binaries & Bridges ]"
for bin in omp claude agy hermes rtk jq flock bun node git hx; do
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
    bridge-hermes.ts
    subagents.ts
    security-gate.ts
    rtk-optimizer.ts
    status-line.ts
    swarm-orchestrator.ts
    plan-mode.ts
    git-checkpoint.ts
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
    adversarial-reviewer.ts
    ast-grep-bridge.ts
    consensus-verifier.ts
    handoff.ts
    helix-bridge.ts
    model-failover.ts
    sandbox-run.ts
    session-search.ts
    session-tree.ts
    skill-state.ts
    swarm-dashboard.ts
    swarm-relay.ts
    thinking-budget.ts
    tool-toggle.ts
    vald-guard.ts
    web-access.ts
    fable-gate.ts
    stop-verify.ts
    sol-pi.ts
)

# security-gate.ts・auto-memory.ts はdecide.py委譲shim本体として、
# rtk-optimizer.tsは(判定ロジック共有はないが物理配置の統一のため)agent/hooks/omp/へ実体移動済み。
# リポジトリ内ではomp/extensions/配下に実ファイルが無いため、この3件のみ移動先を直接検査する
# (デプロイ後の$HOME側では~/.omp/agent/extensions/配下にper-file symlinkとして統合される、
# Makefile.d/install.mk・nix/modules/home/dotfiles/agent-tools.nix参照)。
MOVED_TO_AGENT_HOOKS=(security-gate.ts auto-memory.ts rtk-optimizer.ts)
for ext in "${EXTENSIONS[@]}"; do
    ext_path="$SCRIPT_DIR/extensions/$ext"
    for moved in "${MOVED_TO_AGENT_HOOKS[@]}"; do
        [[ "$ext" == "$moved" ]] && ext_path="$ROOT/agent/hooks/omp/$ext"
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

# SoL-Pi: sol-pi.ts本体はEXTENSIONSで検査済み。実装コア(lib/sol-pi-core.ts)とそのテストの存在・構文もここで検査する。
for lib in sol-pi-core.ts sol-pi.test.ts; do
    lib_path="$SCRIPT_DIR/extensions/lib/$lib"
    if [[ -f "$lib_path" ]]; then
        if command -v bun &>/dev/null; then
            bun build --no-bundle "$lib_path" > /dev/null 2>&1 \
                && check "extension lib: $lib (bun syntax check)" "OK" \
                || check "extension lib: $lib (bun syntax check)" "SYNTAX ERROR"
        else
            check "extension lib: $lib" "OK"
        fi
    else
        check "extension lib: $lib" "MISSING"
    fi
done

echo
echo "[ Extension Tool Contracts (execute: implementation) ]"
CONTRACT_ERRORS=0
for ext in "${EXTENSIONS[@]}"; do
    ext_path="$SCRIPT_DIR/extensions/$ext"
    for moved in "${MOVED_TO_AGENT_HOOKS[@]}"; do
        [[ "$ext" == "$moved" ]] && ext_path="$ROOT/agent/hooks/omp/$ext"
    done
    [[ -f "$ext_path" ]] || continue
    broken_tools=$(python3 -c "
import sys, re
with open('$ext_path', 'r', encoding='utf-8') as f:
    c = f.read()
matches = re.finditer(r'pi\.registerTool\(\{([\s\S]*?)\}\);', c)
broken = []
for m in matches:
    b = m.group(1)
    nm = re.search(r'name:\s*[\"\\\']([^\"\\\']+)[\"\\\']', b)
    name = nm.group(1) if nm else 'unknown'
    if 'execute' not in b:
        broken.append(name)
if broken:
    print(','.join(broken))
" 2>/dev/null || true)
    if [[ -n "$broken_tools" ]]; then
        check "tool contract: $ext (missing execute for $broken_tools)" "FAIL"
        CONTRACT_ERRORS=$((CONTRACT_ERRORS + 1))
    fi
done
if [[ "$CONTRACT_ERRORS" -eq 0 ]]; then
    check "all registered tools implement execute: contract" "OK"
fi

echo
echo "[ Specialized Agents ($ROOT/agent/agents/) ]"
# ~/.omp/agent/agents が agent/agents へ直接 symlink される設計のため、
# リポジトリ内の正典である $ROOT/agent/agents を直接検査する。
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
# SKILL.mdは正典 agent/skills にのみ存在する($HOME/.omp/agent/skillsはagent/skillsへ直接symlink)。
SKILL_COUNT=0
for skill_dir in "$ROOT/agent/skills"/*/; do
    [[ -d "$skill_dir" ]] || continue
    [[ "$(basename "$skill_dir")" == "synced" || "$(basename "$skill_dir")" == _* ]] && continue  # _* = 共通ドキュメント dir (SKILL.md なし)
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
for prompt in swarm-loop swarm-graph swarm-meta review audit claude agy architect; do
    [[ -f "$SCRIPT_DIR/prompts/$prompt.md" ]] \
        && check "prompt template: $prompt.md" "OK" \
        || check "prompt template: $prompt.md" "MISSING"
done
stale_prompt_refs="$(grep -rnE --include='*.md' '~/\.pi/|agent/harnesses/pi/' "$SCRIPT_DIR/prompts" 2>/dev/null || true)"
if [[ -z "$stale_prompt_refs" ]]; then
    check "prompts/*.md free of stale ~/.pi/ or agent/harnesses/pi/ refs" "OK"
else
    check "prompts/*.md free of stale ~/.pi/ or agent/harnesses/pi/ refs" "FOUND: $(printf '%s' "$stale_prompt_refs" | head -n 1)"
fi

echo
echo "[ Shared Rule-Data-Driven Hooks (agent/*.json 経由) ]"
# claude/omp/agyが共通で読む agent/security-rules.json・agent/vald-law-rules.json
# の整合性は、個別テストケースをここに再実装せず agent/scripts/test-*.sh(単一の実体)へ委譲する。
harness_run_shared_test "security-rules.json driven hooks (claude/omp/agy)" "$ROOT/agent/scripts/test-security-rules.sh"
harness_run_shared_test "write-scope-rules.json bash⇔Python parity (claude/omp/agy)" "$ROOT/agent/scripts/test-write-scope-parity.sh"
harness_run_shared_test "vald-law-rules.json driven hooks (claude/omp/agy)" "$ROOT/agent/scripts/test-vald-law-rules.sh"
harness_run_shared_test "merged directory root解決の回帰テスト (claude/omp/agy)" "$ROOT/agent/scripts/test-merged-dir-root-resolution.sh"

echo
echo "[ Agent/Skill Catalog Health & Model Catalog Sync (shared) ]"
harness_run_shared_test "agent/skill catalog health (claude/omp/agy)" "$ROOT/agent/scripts/test-catalog-health.sh"
harness_run_shared_test "ssot model catalog updater & sync (claude/omp/agy/hermes)" "$ROOT/agent/scripts/test-model-catalog-update.sh"

echo
echo "[ OMP Extension Unit Tests (bun) ]"
# Enforce the extension unit suite (extensions/lib/*.test.ts). Made runnable by
# extensions/bunfig.toml + lib/test-preload.ts (virtual stubs for typebox /
# @earendil-works/pi-tui / @oh-my-pi/pi-coding-agent); this gate catches regressions
# in extension logic and any new runtime-only import that escapes the preload.
harness_run_shared_test "omp extension unit tests (bun test)" "$ROOT/agent/scripts/test-omp-extensions.sh"

harness_summary "Oh My Pi (OMP) SOTA Harness"
