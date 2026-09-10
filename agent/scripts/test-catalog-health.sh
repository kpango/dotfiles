#!/usr/bin/env bash
# Shared catalog-health audit for the Agent/Skill harness catalogs.
#
# Canonical entry point for [ Skill Catalog Health ] and [ Agent Config
# Consistency ] checks. All harnesses (claude/agy/pi) call this via
# harness_run_shared_test("... catalog health ...", "$ROOT/agent/scripts/test-catalog-health.sh");
# so the checks live in exactly one place (agent/scripts/test-*.sh single-entity
# principle documented in validate-harness.sh).
#
# Output: `[OK] <msg>` or `[FAIL] <msg>` lines; exit 1 when any check fails.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0

ok() { echo "[OK] $1"; }
fail_msg() { echo "[FAIL] $1"; fail=$((fail + 1)); }

# ---------------------------------------------------------------------------
# Skill Catalog Health
# ---------------------------------------------------------------------------
skill_count=0
for skill_md in "$root"/agent/skills/*/SKILL.md; do
    [[ -f "$skill_md" ]] || continue
    skill_count=$((skill_count + 1))
    skill_name=$(basename "$(dirname "$skill_md")")
    if ! grep -q '^name:' "$skill_md" || ! grep -q '^description:' "$skill_md"; then
        fail_msg "skill frontmatter: $skill_name (missing name/description)"
        continue
    fi

    # Delegated agent references inside the skill must resolve to agent/agents/*.md.
    # Tokens are constrained to [a-z][a-z0-9-]+ by -oE so no word-splitting or
    # injection is reachable; agent-shaped suffixes are matched explicitly and
    # known script names (budget-guard/memory-guard) are skipped.
    dangling=$(grep -oE '[`@][a-z][a-z0-9-]+' "$skill_md" \
        | tr -d '@' \
        | sed 's/^`//' \
        | sort -u \
        | while read -r tok; do
            case "$tok" in
                budget-guard|memory-guard) continue ;;
                debugger|*-expert|*-reviewer|*-auditor|*-analyzer|*-investigator|*-engineer|*-audit|*-ops)
                    [[ -f "$root/agent/agents/$tok.md" ]] || echo "$tok"
                    ;;
            esac
          done) || :
    if [[ -n "$dangling" ]]; then
        fail_msg "skill agent refs: $skill_name (dangling: $(echo "$dangling" | tr '\n' ' '))"
    fi
done
if [[ "$skill_count" -gt 0 ]]; then
    ok "skill catalog health ($skill_count skills)"
else
    fail_msg "skill catalog health (no SKILL.md found under agent/skills)"
fi

# ---------------------------------------------------------------------------
# Agent Config Consistency
# ---------------------------------------------------------------------------
exec 4< <(true)  # keep FD 4 open for associative-array safety in older bash
agent_count=0
declare -A seen_agent_names
for agent_md in "$root"/agent/agents/*.md; do
    [[ -f "$agent_md" ]] || continue
    agent_count=$((agent_count + 1))
    fname=$(grep -m1 '^name:' "$agent_md" | cut -d: -f2- | xargs) || :
    if [[ -z "$fname" ]]; then
        fail_msg "agent frontmatter: $(basename "$agent_md") (missing name)"
        continue
    fi
    if [[ -n "${seen_agent_names[$fname]:-}" ]]; then
        fail_msg "agent name uniqueness: $fname (duplicate)"
    fi
    seen_agent_names[$fname]=1

    tools_line=$(grep -m1 '^tools:' "$agent_md" | cut -d: -f2-) || :
    # Read into an array with quoted elements: no glob expansion, no word-splitting
    # (a `tools: *` value would be reported as UNKNOWN TOKEN instead of expanding).
    IFS=', ' read -ra tool_arr <<< "$tools_line" || :
    for bare in "${tool_arr[@]}"; do
        [[ -z "$bare" ]] && continue
        if [[ "$bare" != Bash && "$bare" != Read && "$bare" != Write && "$bare" != Edit \
            && "$bare" != Grep && "$bare" != Glob && "$bare" != Agent && "$bare" != Workflow \
            && "$bare" != Skill ]]; then
            fail_msg "agent tools: $fname (unknown token $bare)"
        fi
    done

    mdl=$(grep -m1 '^model:' "$agent_md" | cut -d: -f2- | xargs) || :
    if [[ -n "$mdl" ]]; then
        case "$mdl" in
            inherit|auto|sonnet|opus|haiku|fable|sonnet-5|opus-5|haiku-5|medium|high|low|xhigh|max) ;;
            anthropic/*|opencode-go/*|antigravity/*|codex/*|gemini-*|claude-*|grok-*|kimi-*|deepseek-*|qwen*|gpt-*) ;;
            *) fail_msg "agent model: $fname (unresolved $mdl)" ;;
        esac
    fi
done
if [[ "$agent_count" -gt 0 ]]; then
    ok "agent config consistency ($agent_count agents)"
else
    fail_msg "agent config consistency (no agent files found under agent/agents)"
fi

echo "catalog-health: $((skill_count + agent_count)) entries checked, $fail failure(s)"
exit "$([[ "$fail" -eq 0 ]] && echo 0 || echo 1)"