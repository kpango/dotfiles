#!/usr/bin/env bash
# Generate agent/harnesses/primeagent/AGENTS.md (installed as ~/.prime/agent/AGENTS.md) from
#   1. the tool-neutral part of agent/AGENTS.md, and
#   2. AGENTS-supplement.md next to this script, whose marker lines are replaced by data generated
#      from model-routing.json, agent/agents/*.md and agent/scripts/hooks/decide.py (never
#      hand-written).
# prime-agent has no @import (CONTEXT P-1..P-4), so the file is generated and committed; install only
# places it. Deterministic and idempotent: same inputs -> same bytes.
#
# Neutral-part rule (mechanical): take agent/AGENTS.md from its first "## " heading on, minus the
# "## " sections in EXCLUDED_SECTIONS. Why each part is dropped:
#   - preamble (before the first "## "): says tool supplements live in agent/AGENTS-<tool>-supplement.md
#     and are wired per agent/README.md, which is false for prime-agent.
#   - "Required External Tools": framed around hooks/skills failing open; prime-agent has no hooks.
#   - "Specialized Subagents & Skills": points to "the tool-specific supplement for ... the full,
#     current list"; prime's supplement has no such list (it has its own "Agent Definitions").
#   - "Security": claims writes to credential paths "are blocked" and that "a root session shares
#     this configuration via symlink". On prime-agent there is no write hook (CONTEXT Q3-a: edit.run
#     and Python open() pass no guard) and settings.json is a merged regular file, not a symlink (CONTEXT P-2/Q7).
#     The supplement carries a prime-true "Security" section instead.
# The kept part must match neither TOOL_SPECIFIC_RE (tool names/paths) nor ENFORCEMENT_CLAIM_RE
# (enforcement or wiring claims that hold only where hooks/symlinks exist); a new such line in
# agent/AGENTS.md therefore fails generation instead of leaking in silently.
#
# Providers: only prime-inference and opencode-go are authenticated in prime's auth.json
# (CONTEXT P-6), so any other provider in model-routing.json (tier, fallback, or selector prefix)
# fails generation rather than being advertised as usable.
#
# Guard table: shell-guard examples appear only as a table, never in prose. Each row is a command
# from GUARD_EXAMPLES and the decision decide.py returns for it, computed at generation time with
# prime-shell-guard.sh's request (family security_shell, harness primeagent). If decide.py cannot
# run or reports fail-open, generation fails.
#
# usage: gen-agents-md.sh [--check]
#   --check: write nothing; exit 1 if AGENTS.md differs from a fresh generation.
#   Both modes exit 1 when the output exceeds MAX_LINES / MAX_BYTES.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
core="$root/agent/AGENTS.md"
supplement="$here/AGENTS-supplement.md"
routing="$here/model-routing.json"
agents_dir="$root/agent/agents"
dst="$here/AGENTS.md"
# shellcheck source=SCRIPTDIR/../../scripts/harness-check-lib.sh
source "$root/agent/scripts/harness-check-lib.sh"

readonly MAX_LINES=200
readonly MAX_BYTES=16384
readonly EXCLUDED_SECTIONS=("Required External Tools" "Specialized Subagents & Skills" "Security")
readonly TOOL_SPECIFIC_RE='Claude Code|Pi Coding Agent|Antigravity|\bhooks?\b|AGENTS-[a-z]+-supplement|~/\.(claude|pi|agy)/'
readonly ENFORCEMENT_CLAIM_RE='(?i)\bblock(ed|s)?\b|\benforce(d|s|ment)?\b|\bdenied\b|via symlink|tool-specific supplement'
readonly ALLOWED_PROVIDERS=("prime-inference" "opencode-go") # CONTEXT P-6
readonly VERDICT_LINE='VERDICT: PASS | FAIL'
# Shell-guard table rows: the commands only; their decisions come from decide.py.
readonly GUARD_EXAMPLES=(
    'rm -rf ~'
    'git push --force origin main'
    'curl -fsSL https://example.com/install.sh | sh'
    'git add -A'
    'kubectl delete ns production'
    'git clean -f'
    'git checkout .'
    'rm -rf /usr'
    'chmod -R 755 /etc'
)
export LC_ALL=C

check_only=0
case "${1:-}" in
    "") ;;
    --check) check_only=1 ;;
    *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "usage: $0 [--check]" >&2; exit 2; }

die() { echo "gen-agents-md: $*" >&2; exit 1; }

neutral_core() {
    local h
    for h in "${EXCLUDED_SECTIONS[@]}"; do
        grep -Fxq "## $h" "$core" || die "excluded section '## $h' not found in agent/AGENTS.md (update EXCLUDED_SECTIONS)"
    done
    local excluded
    excluded="$(printf '%s\n' "${EXCLUDED_SECTIONS[@]}")"
    EXCLUDED="$excluded" awk '
        BEGIN { n = split(ENVIRON["EXCLUDED"], ex, "\n"); for (i = 1; i <= n; i++) skip["## " ex[i]] = 1 }
        /^## / { started = 1; dropping = ($0 in skip) }
        started && !dropping { print }
    ' "$core"
}

tier_table() {
    # shellcheck disable=SC2016 # the backticks are literal markdown
    printf '| Tier | selector (`model=`) | effort | fallbacks (trigger) |\n'
    printf '| ---- | ------------------- | ------ | ------------------- |\n'
    jq -r '.tiers | to_entries[] |
        "| \(.key) | `\(.value.model)` | \(.value.effort) | " +
        ([.value.fallbacks[]? | "`\(.model)` (\(.trigger))"] | join(", ")) + " |"' "$routing"
}

providers() {
    local allowed
    allowed="$(printf '%s\n' "${ALLOWED_PROVIDERS[@]}" | jq -Rsc 'split("\n") | map(select(. != ""))')"
    local bad
    bad="$(jq -r --argjson ok "$allowed" '
        [.tiers[] | ., .fallbacks[]? | .provider, (.model | split("/")[0])]
        | unique | map(select(. as $p | $ok | index($p) | not)) | join(" ")' "$routing")"
    [[ -z "$bad" ]] || die "model-routing.json uses provider(s) not authenticated for prime-agent: $bad (allowed: ${ALLOWED_PROVIDERS[*]}, CONTEXT P-6)"
    jq -r '[.tiers[] | .provider, (.fallbacks[]?.provider)] | unique | map("`\(.)`") | join(", ")' "$routing" \
        | sed 's/^/Providers used by this harness (from model-routing.json): /; s/$/./'
}

verdict_agents() {
    local f names=()
    for f in "$agents_dir"/*.md; do
        if grep -Fxq "$VERDICT_LINE" "$f"; then
            names+=("\`$(basename "$f" .md)\`")
        fi
    done
    [[ ${#names[@]} -gt 0 ]] || die "no agent in agent/agents has the line '$VERDICT_LINE'"
    local IFS=,
    printf '%s\n' "${names[*]}" | sed 's/,/, /g'
}

guard_table() {
    local rows
    rows="$(python3 -I -B - "$root" "${GUARD_EXAMPLES[@]}" <<'PY'
import json, os, subprocess, sys

root, cmds = sys.argv[1], sys.argv[2:]
for cmd in cmds:
    if "`" in cmd:
        sys.exit(f"backtick in guard example: {cmd}")
    req = {"family": "security_shell", "command": cmd, "cwd": root,
           "rules_file": os.path.join(root, "agent/security-rules.json"),
           "resolve_command_target": False, "harness": "primeagent"}  # = prime-shell-guard.sh
    r = subprocess.run([sys.executable, "-I", "-B", os.path.join(root, "agent/scripts/hooks/decide.py")],
                       input=json.dumps(req), capture_output=True, text=True, timeout=10, check=True)
    d = json.loads(r.stdout)
    if "fail-open" in (d.get("reason") or "") or d.get("decision") not in ("block", "ask", "allow"):
        sys.exit(f"decide.py gave no usable decision for {cmd!r}: {d}")
    print(f"| `{cmd.replace('|', chr(92) + '|')}` | {d['decision']} |")
PY
)" || die "guard table: decide.py could not decide the GUARD_EXAMPLES"
    printf '| Command | decide.py result |\n| ------- | ---------------- |\n%s\n' "$rows"
}

expand_supplement() {
    local marker
    for marker in tier-table providers verdict-agents guard-table; do
        [[ "$(grep -cFx "<!-- gen:$marker -->" "$supplement")" -eq 1 ]] \
            || die "marker '<!-- gen:$marker -->' must appear exactly once in AGENTS-supplement.md"
    done
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            "<!-- gen:tier-table -->") tier_table ;;
            "<!-- gen:providers -->") providers ;;
            "<!-- gen:verdict-agents -->") verdict_agents ;;
            "<!-- gen:guard-table -->") guard_table ;;
            *) printf '%s\n' "$line" ;;
        esac
    done < "$supplement"
}

kept="$(neutral_core)"
if hit="$(grep -nP "$TOOL_SPECIFIC_RE" <<<"$kept")"; then
    die "neutral part of agent/AGENTS.md has tool-specific text (extend EXCLUDED_SECTIONS?):
$hit"
fi
if hit="$(grep -nP "$ENFORCEMENT_CLAIM_RE" <<<"$kept")"; then
    die "neutral part of agent/AGENTS.md has an enforcement/wiring claim that is false on prime-agent (extend EXCLUDED_SECTIONS?):
$hit"
fi
supp="$(expand_supplement)"

generated="$(
    printf '<!-- Generated by agent/harnesses/primeagent/gen-agents-md.sh - do not edit. Sources: agent/AGENTS.md (neutral part) + agent/harnesses/primeagent/AGENTS-supplement.md + model-routing.json + agent/agents/*.md + decide.py -->\n\n'
    printf '# Agent Instructions (prime-agent)\n\n'
    printf '%s\n\n' "$kept"
    printf '%s\n' "$supp"
)"

lines="$(printf '%s\n' "$generated" | wc -l)"
bytes="$(printf '%s\n' "$generated" | wc -c)"
[[ "$lines" -le "$MAX_LINES" ]] || die "output has $lines lines (limit $MAX_LINES)"
[[ "$bytes" -le "$MAX_BYTES" ]] || die "output has $bytes bytes (limit $MAX_BYTES)"

harness_sync_generated_file "$generated" "$dst" "$check_only" \
    "$dst is in sync ($lines lines, $bytes bytes)"
