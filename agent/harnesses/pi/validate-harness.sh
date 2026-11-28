#!/usr/bin/env bash
# Pi Coding Agent (@earendil-works/pi-coding-agent) Harness Validation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -P "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../../agent/scripts/harness-check-lib.sh
source "$ROOT/agent/scripts/harness-check-lib.sh"

echo "=== Pi Coding Agent Harness Validation ==="
echo

echo "[ Configuration Files ]"
for json_file in settings.json models.json mcp.json lsp.json dap.json keybindings.json sol-pi.json model-routing.json themes/kpango-dark.json; do
    if python3 -m json.tool "$SCRIPT_DIR/$json_file" > /dev/null 2>&1; then
        check "$json_file valid JSON" "OK"
    else
        check "$json_file valid JSON" "INVALID"
    fi
done

python3 -c '
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8"))
assert isinstance(s.get("defaultProvider"), str) and isinstance(s.get("defaultModel"), str)
assert "npm:@estebanforge/pi-antigravity-bridge@1.16.0" in (s.get("packages") or [])
tools = set(s.get("defaultTools") or [])
for t in ("read", "edit", "write", "bash", "codemode", "tool_search"):
    assert t in tools, f"missing defaultTool {t}"
assert s.get("enableAnalytics") is False
' "$SCRIPT_DIR/settings.json" 2>/dev/null \
    && check "settings.json schema (antigravity-bridge@1.16.0, defaultTools)" "OK" \
    || check "settings.json schema (antigravity-bridge@1.16.0, defaultTools)" "INVALID"

python3 -c '
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
provs = m.get("providers", {})
assert isinstance(provs, dict) and "opencode-go" in provs and "ollama" in provs
assert provs["opencode-go"].get("baseUrl") == "https://opencode.ai/zen/go/v1"
assert "apiKey" not in provs["opencode-go"]
' "$SCRIPT_DIR/models.json" 2>/dev/null \
    && check "models.json providers (opencode-go/ollama)" "OK" \
    || check "models.json providers (opencode-go/ollama)" "INVALID"

python3 -c '
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
assert m.get("mcpServers", {}).get("trail", {}).get("command") == "trail"
' "$SCRIPT_DIR/mcp.json" 2>/dev/null \
    && check "mcp.json schema (trail MCP)" "OK" \
    || check "mcp.json schema (trail MCP)" "INVALID"

python3 -c '
import json, sys
l = json.load(open(sys.argv[1], encoding="utf-8"))
srvs = l.get("servers", {})
assert isinstance(srvs, dict) and "gopls" in srvs and "rust-analyzer" in srvs
' "$SCRIPT_DIR/lsp.json" 2>/dev/null \
    && check "lsp.json servers schema" "OK" \
    || check "lsp.json servers schema" "INVALID"

python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
adapters = d.get("adapters", {})
assert isinstance(adapters, dict) and "dlv" in adapters and "lldb-dap" in adapters
' "$SCRIPT_DIR/dap.json" 2>/dev/null \
    && check "dap.json valid JSON & adapters (dlv/lldb-dap)" "OK" \
    || check "dap.json valid JSON & adapters" "INVALID"

python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d.get("version") == 1
assert d.get("actionFusion") is True
assert d.get("observationPack") is True
assert d.get("evidencePreservingReducer") is True
assert d.get("onlineContextCompact") is False
assert d["pi"]["pricingCliffAdvisory"] is True
assert "pricingCliffs" not in d["pi"]["onlineContextCompact"]
assert d["pi"]["missionBridge"]["enabled"] is True
assert d["pi"]["missionBridge"]["traces"] is True
assert "missionBridge" not in d
assert "pricingCliffAdvisoryConfig" not in d
assert "actionFusionConfig" not in d
' "$SCRIPT_DIR/sol-pi.json" 2>/dev/null \
    && check "sol-pi.json valid JSON & upstream flags (pi namespace)" "OK" \
    || check "sol-pi.json valid JSON & upstream flags (pi namespace)" "INVALID"

python3 "$ROOT/agent/scripts/resolve-model-tier.py" --check pi > /dev/null 2>&1 \
    && check "model-routing.json tier & cross-config check passed" "OK" \
    || check "model-routing.json tier & cross-config check" "INVALID"

[[ -f "$SCRIPT_DIR/AGENTS.md" ]] && check "AGENTS.md exists" "OK" || check "AGENTS.md" "MISSING"
[[ -f "$SCRIPT_DIR/SYSTEM.md" ]] && check "SYSTEM.md exists" "OK" || check "SYSTEM.md" "MISSING"
[[ -f "$ROOT/agent/rules/vald-law-ttsr.md" ]] && check "agent/rules/vald-law-ttsr.md exists" "OK" || check "agent/rules/vald-law-ttsr.md" "MISSING"
[[ -f "$ROOT/agent/SWARM.md" ]]  && check "agent/SWARM.md exists" "OK"  || check "agent/SWARM.md" "MISSING"
[[ -f "$ROOT/agent/RTK.md" ]]    && check "agent/RTK.md exists" "OK"    || check "agent/RTK.md" "MISSING"

echo
echo "[ CLI Binaries & Bridges ]"
for bin in pi claude agy hermes rtk jq flock bun node git hx; do
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
    hashline-edit.ts
    lsp-client.ts
    dap-client.ts
    ttsr-guard.ts
    model-roles.ts
    loop-guard.ts
    lcm-context.ts
)

# security-gate.ts・auto-memory.ts・rtk-optimizer.ts live under agent/hooks/pi/ and merge into ~/.pi/agent/extensions/ on deploy.
MOVED_TO_AGENT_HOOKS=(security-gate.ts auto-memory.ts rtk-optimizer.ts)
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

for lib in sol-pi-core.ts sol-pi.test.ts hashline-core.ts lsp-core.ts dap-core.ts ttsr-core.ts model-roles-core.ts evidence-ledger.ts loop-guard-core.ts lcm-core.ts; do
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
        [[ "$ext" == "$moved" ]] && ext_path="$ROOT/agent/hooks/pi/$ext"
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
SKILL_COUNT=0
for skill_dir in "$ROOT/agent/skills"/*/; do
    [[ -d "$skill_dir" ]] || continue
    [[ "$(basename "$skill_dir")" == "synced" || "$(basename "$skill_dir")" == _* ]] && continue
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

for essential_skill in golang-patterns golang-testing rust-patterns cpp-patterns python-patterns swarm swarm-loop swarm-graph swarm-meta swarm-explore swarm-implement swarm-architect; do
    [[ -f "$ROOT/agent/skills/$essential_skill/SKILL.md" ]] \
        && check "skill: $essential_skill" "OK" \
        || check "skill: $essential_skill" "MISSING"
done

echo
echo "[ Prompt Templates ($SCRIPT_DIR/prompts/) ]"
for prompt in review audit claude agy architect; do
    [[ -f "$SCRIPT_DIR/prompts/$prompt.md" ]] \
        && check "prompt template: $prompt.md" "OK" \
        || check "prompt template: $prompt.md" "MISSING"
done
stale_prompt_refs="$(grep -rnE --include='*.md' '~/\.omp/|agent/harnesses/omp/' "$SCRIPT_DIR/prompts" 2>/dev/null || true)"
if [[ -z "$stale_prompt_refs" ]]; then
    check "prompts/*.md free of stale ~/.omp/ or agent/harnesses/omp/ refs" "OK"
else
    check "prompts/*.md free of stale ~/.omp/ or agent/harnesses/omp/ refs" "FOUND: $(printf '%s' "$stale_prompt_refs" | head -n 1)"
fi

echo
echo "[ Shared Rule-Data-Driven Hooks (agent/*.json 経由) ]"
harness_run_shared_test "security-rules.json driven hooks (claude/pi/agy)" "$ROOT/agent/scripts/test-security-rules.sh"
harness_run_shared_test "write-scope-rules.json bash⇔Python parity (claude/pi/agy)" "$ROOT/agent/scripts/test-write-scope-parity.sh"
harness_run_shared_test "vald-law-rules.json driven hooks (claude/pi/agy)" "$ROOT/agent/scripts/test-vald-law-rules.sh"
harness_run_shared_test "merged directory root解決の回帰テスト (claude/pi/agy)" "$ROOT/agent/scripts/test-merged-dir-root-resolution.sh"

echo
echo "[ Agent/Skill Catalog Health & Model Catalog Sync (shared) ]"
harness_run_shared_test "agent/skill catalog health (claude/pi/agy)" "$ROOT/agent/scripts/test-catalog-health.sh"
harness_run_shared_test "ssot model catalog updater & sync (claude/pi/agy/hermes)" "$ROOT/agent/scripts/test-model-catalog-update.sh"

echo
echo "[ Pi Extension Unit Tests (bun) ]"
harness_run_shared_test "pi extension unit tests (bun test)" "$ROOT/agent/scripts/test-pi-extensions.sh"

harness_summary "Pi Coding Agent SOTA Harness"
