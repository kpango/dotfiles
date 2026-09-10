#!/usr/bin/env bash
# agent/skills/swarm-implement/scripts/write-scope-lib.sh の write_scope_is_protected()
# (bash正典) と agent/write-scope-rules.json + rule_engine.eval_write_scope()
# (JSON駆動のPython実装、agent/scripts/hooks/decide.py の write_scope family経由) の判定結果が
# 完全一致することを検証するcross-impl parity test。write_scope_is_protected() の全caseを
# 1つ以上カバーする代表的な保護対象パス群、および非対象パス群それぞれについて突き合わせる。
# 1つでも乖離したら非0で失敗する。
#
# usage: agent/scripts/test-write-scope-parity.sh
# exit: 0 = 全ケースPASS, 1 = 1件以上FAIL
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$ROOT/agent/skills/swarm-implement/scripts/write-scope-lib.sh"
RULES_JSON="$ROOT/agent/write-scope-rules.json"
DECIDE_PY="$ROOT/agent/scripts/hooks/decide.py"

# shellcheck source=/dev/null
source "$LIB"

total_fail=0

py_result() {
    local path="$1" out decision
    out="$(jq -n --arg p "$path" --arg home "$HOME" --arg rf "$RULES_JSON" \
        '{family:"write_scope", file_path:$p, cwd:"/", home:$home, rules_file:$rf}' \
        | python3 "$DECIDE_PY")"
    decision="$(echo "$out" | jq -r '.decision')"
    if [[ "$decision" == "block" ]]; then echo "protected"; else echo "not_protected"; fi
}

check() {
    local desc="$1" path="$2" bash_result py_r
    if write_scope_is_protected "$path"; then bash_result="protected"; else bash_result="not_protected"; fi
    py_r="$(py_result "$path")"
    if [[ "$bash_result" == "$py_r" ]]; then
        echo "[OK] $desc -> $bash_result ($path)"
    else
        echo "[FAIL] $desc : bash=$bash_result python=$py_r path=$path"
        total_fail=$((total_fail + 1))
    fi
}

echo "=== protected paths (1 case per write_scope_is_protected() pattern) ==="
check "*/claude/hooks/*" "/tmp/x/claude/hooks/foo.sh"
check "*/agent/harnesses/claude/hooks/*" "/tmp/x/agent/harnesses/claude/hooks/foo.sh"
check "*/agent/hooks/claude/*" "/tmp/x/agent/hooks/claude/foo.sh"
check "*/agent/hooks/agy/*" "/tmp/x/agent/hooks/agy/foo.sh"
check "*/agent/hooks/pi/*" "/tmp/x/agent/hooks/pi/foo.ts"
check "*/agent/harnesses/agy/hooks/*" "/tmp/x/agent/harnesses/agy/hooks/foo.sh"
check "*/agent/harnesses/pi/extensions/*" "/tmp/x/agent/harnesses/pi/extensions/foo.ts"
check "*/agent/harnesses/*/model-routing.json" "/tmp/x/agent/harnesses/pi/model-routing.json"
check "*/agent/skills/*/SKILL.md" "/tmp/x/agent/skills/foo/SKILL.md"
check "*/agent/skills/*/scripts/*" "/tmp/x/agent/skills/foo/scripts/bar.sh"
check "*/agent/skills/*/*.md" "/tmp/x/agent/skills/foo/README.md"
check "*/agent/SWARM.md" "/tmp/x/agent/SWARM.md"
check "*/agent/SWARM_REFERENCES.md" "/tmp/x/agent/SWARM_REFERENCES.md"
check "*/claude/CLAUDE.md" "/tmp/x/claude/CLAUDE.md"
check "*/agent/harnesses/claude/CLAUDE.md" "/tmp/x/agent/harnesses/claude/CLAUDE.md"
check "*/claude/settings.json" "/tmp/x/claude/settings.json"
check "*/agent/harnesses/claude/settings.json" "/tmp/x/agent/harnesses/claude/settings.json"
check "*/claude/settings.local.json" "/tmp/x/claude/settings.local.json"
check "*/agent/harnesses/claude/settings.local.json" "/tmp/x/agent/harnesses/claude/settings.local.json"
check "*/agent/agents/*" "/tmp/x/agent/agents/foo.md"
check "*/agent/write-scope-rules.json (self-protection)" "/tmp/x/agent/write-scope-rules.json"
check "*/agent/scripts/hooks/*.py decide.py (engine self-protection)" "/tmp/x/agent/scripts/hooks/decide.py"
check "*/agent/scripts/hooks/*.py rule_engine.py (engine self-protection)" "/tmp/x/agent/scripts/hooks/rule_engine.py"
check "fixed: dotfiles settings.json" "$HOME/go/src/github.com/kpango/dotfiles/.claude/settings.json"
check "fixed: dotfiles worktree settings.json" "$HOME/go/src/github.com/kpango/dotfiles/.claude/worktrees/somebranch/.claude/settings.json"
check "fixed: dotfiles settings.local.json" "$HOME/go/src/github.com/kpango/dotfiles/.claude/settings.local.json"
check "fixed: dotfiles worktree settings.local.json" "$HOME/go/src/github.com/kpango/dotfiles/.claude/worktrees/somebranch/.claude/settings.local.json"
check "fixed: vald settings.json" "$HOME/go/src/github.com/vdaas/vald/.claude/settings.json"
check "fixed: vald worktree settings.json" "$HOME/go/src/github.com/vdaas/vald/.claude/worktrees/somebranch/.claude/settings.json"
check "fixed: vald settings.local.json" "$HOME/go/src/github.com/vdaas/vald/.claude/settings.local.json"
check "fixed: vald worktree settings.local.json" "$HOME/go/src/github.com/vdaas/vald/.claude/worktrees/somebranch/.claude/settings.local.json"

echo
echo "=== non-protected (safe) paths ==="
check "unrelated agent README" "/tmp/x/agent/README.md"
check "normal go file" "$HOME/project/main.go"
check "agent/scripts (not agent/skills/*/scripts)" "/tmp/x/agent/scripts/test-foo.sh"
check "dotfiles repo but not settings/worktree path" "$HOME/go/src/github.com/kpango/dotfiles/some/file.go"
check "agent/agents.md (no trailing slash segment, must NOT match agent/agents/*)" "/tmp/x/agent/agents.md"

echo
echo "=== fail-closed: malformed/structurally-invalid rules_file must block (exit 0) ==="
# Checker(2026-09-07)が発見したfail-open欠陥の回帰テスト。rules_fileが構文的に有効でも
# 期待キーを欠く場合に decide.py write_scope が allow へすり抜けないことを検証する。
# 保護対象パスを与えても rules が壊れていれば block(=fail-closed) になるべき。
check_malformed() {
    local desc="$1" rules_content="$2" tmp out decision code
    tmp="$(mktemp)"
    printf '%s' "$rules_content" > "$tmp"
    set +e
    out="$(jq -n --arg p "/tmp/x/agent/hooks/pi/foo.ts" --arg home "$HOME" --arg rf "$tmp" \
        '{family:"write_scope", file_path:$p, cwd:"/", home:$home, rules_file:$rf}' \
        | python3 "$DECIDE_PY")"
    code=$?
    set -e
    rm -f "$tmp"
    decision="$(echo "$out" | jq -r '.decision' 2>/dev/null || echo PARSE_ERR)"
    if [[ "$decision" == "block" && "$code" -eq 0 ]]; then
        echo "[OK] $desc -> block (exit $code)"
    else
        echo "[FAIL] $desc : decision=$decision exit=$code (expected block/exit0)"
        total_fail=$((total_fail + 1))
    fi
}
check_malformed "structurally-invalid truthy dict {unrelated_key}" '{"unrelated_key":123}'
check_malformed "list-type JSON [1,2,3] (no AttributeError/non-zero exit)" '[1,2,3]'
check_malformed "empty dict {}" '{}'
check_malformed "syntactically broken JSON" '{not json'
check_malformed "only suffix_patterns, missing fixed_absolute_path_patterns" '{"suffix_patterns":[]}'
check_malformed "value-type invalid: suffix_patterns is string not list" '{"suffix_patterns":"x","fixed_absolute_path_patterns":[]}'
check_malformed "value-type invalid: fixed_absolute_path_patterns is dict not list" '{"suffix_patterns":[],"fixed_absolute_path_patterns":{}}'

echo
echo "---"
if [[ "$total_fail" -gt 0 ]]; then
    echo "test-write-scope-parity: $total_fail 件のFAILあり"
    exit 1
fi
echo "test-write-scope-parity: 全テストPASS"
exit 0
