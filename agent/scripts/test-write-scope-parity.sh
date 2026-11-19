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
HARNESS_LINT="$ROOT/agent/skills/swarm-meta/scripts/harness-lint.sh"

# shellcheck source=/dev/null
source "$LIB"

# test-gen-tool-md.sh 準拠 (mktemp -d 隔離 / trap による後片付け): hl_result()・
# check_malformed() それぞれが個別に mktemp するのではなく、この1つの作業ディレクトリ配下に
# 一時ファイルを作る。set -e 下で assert/コマンドが途中で失敗して即終了しても、trap が
# 必ず一括で削除するため一時ファイルが残らない。
WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

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
    local desc="$1" path="$2" expected="${3:-}" bash_result py_r
    if write_scope_is_protected "$path"; then bash_result="protected"; else bash_result="not_protected"; fi
    py_r="$(py_result "$path")"
    if [[ "$bash_result" == "$py_r" && ( -z "$expected" || "$bash_result" == "$expected" ) ]]; then
        echo "[OK] $desc -> $bash_result ($path)"
    else
        echo "[FAIL] $desc : expected=${expected:-any} bash=$bash_result python=$py_r path=$path"
        total_fail=$((total_fail + 1))
    fi
}

# T19 (ai-env-deepresearch-overhaul): harness-lint.sh の PROTECTED 正規表現(事前lint、任意テキスト
# 中のtool-call引数照合)経由の判定を追加する第3実装。write_scope_is_protected()/decide.pyとは
# 判定対象が異なる(解決済みファイルパスではなく、Edit(...)形式のplan step文字列に対する部分文字列
# 照合)ため、$pathを埋め込んだ最小のharness-plan.jsonを都度生成してharness-lint.shへ渡し、
# 終了コード(WRITE_SCOPE=3 -> protected、PASS=0 -> not_protected)を他2実装と同じ語彙へ正規化する。
hl_result() { # <path> -> protected|not_protected|OTHER:<code>
    local path="$1" tmp code
    tmp="$(mktemp "$WORK/tmp.XXXXXX")"
    jq -n --arg p "$path" '{
        harness: "swarm-loop", scale: "quick",
        verification: {checker: "opus", deterministic: ["x"], lenses: []},
        routing: {maker: "sonnet", fixer: "sonnet"},
        budget: {task_max: 1, mission_max: 1},
        steps: [("Edit(file_path=\"" + $p + "\")")]
    }' > "$tmp"
    set +e
    bash "$HARNESS_LINT" "$tmp" >/dev/null 2>/dev/null
    code=$?
    set -e
    rm -f "$tmp"
    if [[ "$code" -eq 3 ]]; then echo "protected";
    elif [[ "$code" -eq 0 ]]; then echo "not_protected";
    else echo "OTHER:$code"; fi
}

check3() { # <desc> <path> <expected: protected|not_protected> — bash/python/harness-lint の
    # 3実装がそれぞれ$expectedと一致することを検査する(T19保護対象9件・除外兄弟専用)。既存check()の
    # 「bashを正とみなしpythonと突き合わせる」parity方式ではなく、期待値を明示的に固定する — こうしないと
    # 3実装が「全員そろって保護し忘れている」退行(mutation)を、3実装の相互一致だけでは検出できないため。
    local desc="$1" path="$2" expected="$3" bash_result py_r hl_r
    if write_scope_is_protected "$path"; then bash_result="protected"; else bash_result="not_protected"; fi
    py_r="$(py_result "$path")"
    hl_r="$(hl_result "$path")"
    if [[ "$bash_result" == "$expected" && "$py_r" == "$expected" && "$hl_r" == "$expected" ]]; then
        echo "[OK] $desc -> $expected (bash=python=harness-lint=$expected) ($path)"
    else
        echo "[FAIL] $desc : expected=$expected bash=$bash_result python=$py_r harness-lint=$hl_r path=$path"
        total_fail=$((total_fail + 1))
    fi
}

echo "=== protected paths (1 case per write_scope_is_protected() pattern) ==="
check "*/claude/hooks/*" "/tmp/x/claude/hooks/foo.sh"
check "*/agent/harnesses/claude/hooks/*" "/tmp/x/agent/harnesses/claude/hooks/foo.sh"
check "*/agent/hooks/claude/*" "/tmp/x/agent/hooks/claude/foo.sh"
check "*/agent/hooks/agy/*" "/tmp/x/agent/hooks/agy/foo.sh"
check "*/agent/hooks/omp/*" "/tmp/x/agent/hooks/omp/foo.ts" "protected"
check "*/agent/harnesses/agy/hooks/*" "/tmp/x/agent/harnesses/agy/hooks/foo.sh"
check "*/agent/harnesses/omp/extensions/*" "/tmp/x/agent/harnesses/omp/extensions/foo.ts" "protected"
check "*/agent/harnesses/*/model-routing.json (omp)" "/tmp/x/agent/harnesses/omp/model-routing.json" "protected"
check "*/agent/harnesses/*/model-routing.json (hermes)" "/tmp/x/agent/harnesses/hermes/model-routing.json" "protected"
check "*/agent/models/catalog.json" "/tmp/x/agent/models/catalog.json" "protected"
check "*/agent/harnesses/omp/config.yml" "/tmp/x/agent/harnesses/omp/config.yml" "protected"
check "*/agent/harnesses/omp/models.yml" "/tmp/x/agent/harnesses/omp/models.yml" "protected"
check "*/agent/harnesses/hermes/config.yaml" "/tmp/x/agent/harnesses/hermes/config.yaml" "protected"
check "*/agent/rules/*" "/tmp/x/agent/rules/vald-law-ttsr.md" "protected"
check "*/agent/skills/*/SKILL.md" "/tmp/x/agent/skills/foo/SKILL.md"
check "*/agent/skills/*/scripts/*" "/tmp/x/agent/skills/foo/scripts/bar.sh"
check "*/agent/skills/*/*.md" "/tmp/x/agent/skills/foo/README.md"
check "*/agent/SWARM.md" "/tmp/x/agent/SWARM.md"
check "*/agent/SWARM_REFERENCES.md" "/tmp/x/agent/SWARM_REFERENCES.md"
check "*/CLAUDE.md" "/tmp/x/CLAUDE.md" "protected"
check "*/AGENTS.md (root)" "/tmp/x/AGENTS.md" "protected"
check "*/AGENTS.md (harness)" "/tmp/x/agent/harnesses/omp/AGENTS.md" "protected"
check "*/claude/CLAUDE.md" "/tmp/x/claude/CLAUDE.md"
check "*/agent/harnesses/claude/CLAUDE.md" "/tmp/x/agent/harnesses/claude/CLAUDE.md"
check "*/claude/settings.json" "/tmp/x/claude/settings.json"
check "*/agent/harnesses/claude/settings.json" "/tmp/x/agent/harnesses/claude/settings.json"
check "*/claude/settings.local.json" "/tmp/x/claude/settings.local.json"
check "*/agent/harnesses/claude/settings.local.json" "/tmp/x/agent/harnesses/claude/settings.local.json"
check "*/agent/agents/*" "/tmp/x/agent/agents/foo.md"
check "*/agent/security-rules.json (self-protection)" "/tmp/x/agent/security-rules.json" "protected"
check "*/agent/write-scope-rules.json (self-protection)" "/tmp/x/agent/write-scope-rules.json" "protected"
check "*/agent/scripts/hooks/* non-py (helper.sh)" "/tmp/x/agent/scripts/hooks/helper.sh" "protected"
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
check "unrelated other markdown" "/tmp/x/other/foo.md" "not_protected"
check "unrelated omp yml" "/tmp/x/agent/harnesses/omp/other.yml" "not_protected"
check "unrelated hermes yaml" "/tmp/x/agent/harnesses/hermes/other.yaml" "not_protected"
check "agent/rules (no trailing slash segment, must NOT match agent/rules/*)" "/tmp/x/agent/rules" "not_protected"
check "CLAUDE.md.bak (must NOT match */CLAUDE.md)" "/tmp/x/CLAUDE.md.bak" "not_protected"
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
    tmp="$(mktemp "$WORK/tmp.XXXXXX")"
    printf '%s' "$rules_content" > "$tmp"
    set +e
    out="$(jq -n --arg p "/tmp/x/agent/hooks/omp/foo.ts" --arg home "$HOME" --arg rf "$tmp" \
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
