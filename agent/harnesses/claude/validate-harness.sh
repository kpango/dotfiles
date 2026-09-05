#!/usr/bin/env bash
# Claude Code Agent Harness Validation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -P "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../../agent/scripts/harness-check-lib.sh
source "$ROOT/agent/scripts/harness-check-lib.sh"

echo "=== Claude Code Agent Harness Validation ==="
echo

echo "[ Settings ]"
python3 -m json.tool ~/.claude/settings.json > /dev/null 2>&1 \
    && check "settings.json valid JSON" "OK" \
    || check "settings.json valid JSON" "INVALID"

FORK=$(python3 -c "
import json, os
d = json.load(open(os.path.expanduser('~/.claude/settings.json')))
print(d.get('env', {}).get('CLAUDE_CODE_FORK_SUBAGENT', ''))
" 2>/dev/null || true)
[[ "$FORK" == "1" ]] \
    && check "Fork subagent mode (CLAUDE_CODE_FORK_SUBAGENT)" "OK" \
    || check "Fork subagent mode (CLAUDE_CODE_FORK_SUBAGENT)" "NOT SET"

TEAMS=$(python3 -c "
import json, os
d = json.load(open(os.path.expanduser('~/.claude/settings.json')))
print(d.get('env', {}).get('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS', ''))
" 2>/dev/null || true)
[[ "$TEAMS" == "1" ]] \
    && check "Agent teams (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS)" "OK" \
    || check "Agent teams (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS)" "NOT SET"

HOOKS=$(python3 -c "
import json, os
d = json.load(open(os.path.expanduser('~/.claude/settings.json')))
total = sum(len(entry.get('hooks', [])) for entries in d.get('hooks', {}).values() for entry in entries)
print(total)
" 2>/dev/null || echo "0")
[[ "$HOOKS" -ge "10" ]] \
    && check "Hooks configured ($HOOKS hook scripts)" "OK" \
    || check "Hooks configured ($HOOKS hook scripts)" "WARN:need >= 10"

echo
echo "[ Hook Scripts (~/.claude/hooks/) ]"
for hook in session-start.sh security-gate.sh write-security-gate.sh rtk-rewrite.sh \
            post-write.sh post-tool-failure.sh permission-request.sh \
            user-prompt-submit.sh session-end.sh pre-compact.sh stop-failure.sh \
            graphify-hint.sh \
            vald-law-gate.sh vald-law2-gate.sh vald-law345-check.sh; do
    [[ -x ~/.claude/hooks/"$hook" ]] \
        && check "hook: $hook" "OK" \
        || check "hook: $hook" "MISSING or not executable"
done

echo
echo "[ Shared Rule-Data-Driven Hooks (agent/*.json 経由) ]"
# security-gate.sh・write-security-gate.sh・vald-law-gate.sh・vald-law2-gate.sh・
# vald-law345-check.sh・graphify-hint.shの個別テストケースはここに再実装せず、
# claude/agy/pi横断で共有される agent/scripts/test-*.sh(単一の実体)へ委譲する。
# 以前はここに dd/force-push/kubectl等の個別テストケースを直接ハードコードしていたが、
# agent/security-rules.json側の修正(nvme裸コントローラ・chmodサブディレクトリ・
# git add ./等)が反映されずハードコード側が陳腐化する実害が出たため、単一の実体へ統合した。
harness_run_shared_test "security-rules.json driven hooks (claude/agy/pi)" "$ROOT/agent/scripts/test-security-rules.sh"
harness_run_shared_test "vald-law-rules.json driven hooks (claude/agy/pi)" "$ROOT/agent/scripts/test-vald-law-rules.sh"
harness_run_shared_test "graphify-hint-config.json driven hooks (claude/agy/pi)" "$ROOT/agent/scripts/test-graphify-hint.sh"
harness_run_shared_test "memory-context composition (claude/agy/pi)" "$ROOT/agent/scripts/test-memory-context.sh"
harness_run_shared_test "merged directory root解決の回帰テスト (claude/agy/pi)" "$ROOT/agent/scripts/test-merged-dir-root-resolution.sh"

echo
echo "[ Permission Request Hook Functional Test ]"
KUBECTL_GET_PERM=$(printf '{"tool_name":"Bash","tool_input":{"command":"kubectl get pods -n default"}}' | \
    ~/.claude/hooks/permission-request.sh 2>/dev/null || true)
KUBECTL_DECISION=$(echo "$KUBECTL_GET_PERM" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('decision',''))" 2>/dev/null || true)
[[ "$KUBECTL_DECISION" == "allow" ]] \
    && check "permission-request: auto-approve kubectl get" "OK" \
    || check "permission-request: auto-approve kubectl get" "FAILED"

DOCKER_PS_PERM=$(printf '{"tool_name":"Bash","tool_input":{"command":"docker ps -a"}}' | \
    ~/.claude/hooks/permission-request.sh 2>/dev/null || true)
DOCKER_DECISION=$(echo "$DOCKER_PS_PERM" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('decision',''))" 2>/dev/null || true)
[[ "$DOCKER_DECISION" == "allow" ]] \
    && check "permission-request: auto-approve docker ps" "OK" \
    || check "permission-request: auto-approve docker ps" "FAILED"

HELM_LIST_PERM=$(printf '{"tool_name":"Bash","tool_input":{"command":"helm list -n default"}}' | \
    ~/.claude/hooks/permission-request.sh 2>/dev/null || true)
HELM_DECISION=$(echo "$HELM_LIST_PERM" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('decision',''))" 2>/dev/null || true)
[[ "$HELM_DECISION" == "allow" ]] \
    && check "permission-request: auto-approve helm list" "OK" \
    || check "permission-request: auto-approve helm list" "FAILED"

SYSTEMCTL_PERM=$(printf '{"tool_name":"Bash","tool_input":{"command":"systemctl status docker"}}' | \
    ~/.claude/hooks/permission-request.sh 2>/dev/null || true)
SYSTEMCTL_DECISION=$(echo "$SYSTEMCTL_PERM" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('decision',''))" 2>/dev/null || true)
[[ "$SYSTEMCTL_DECISION" == "allow" ]] \
    && check "permission-request: auto-approve systemctl status" "OK" \
    || check "permission-request: auto-approve systemctl status" "FAILED"

PARU_SS_PERM=$(printf '{"tool_name":"Bash","tool_input":{"command":"paru -Ss neovim"}}' | \
    ~/.claude/hooks/permission-request.sh 2>/dev/null || true)
PARU_DECISION=$(echo "$PARU_SS_PERM" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('decision',''))" 2>/dev/null || true)
[[ "$PARU_DECISION" == "allow" ]] \
    && check "permission-request: auto-approve paru -Ss" "OK" \
    || check "permission-request: auto-approve paru -Ss" "FAILED"

CARGO_FMT_PERM=$(printf '{"tool_name":"Bash","tool_input":{"command":"cargo fmt --check"}}' | \
    ~/.claude/hooks/permission-request.sh 2>/dev/null || true)
CARGO_FMT_DECISION=$(echo "$CARGO_FMT_PERM" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('decision',''))" 2>/dev/null || true)
[[ "$CARGO_FMT_DECISION" == "allow" ]] \
    && check "permission-request: auto-approve cargo fmt --check" "OK" \
    || check "permission-request: auto-approve cargo fmt --check" "FAILED"

TMUX_PERM=$(printf '{"tool_name":"Bash","tool_input":{"command":"tmux list-sessions"}}' | \
    ~/.claude/hooks/permission-request.sh 2>/dev/null || true)
TMUX_DECISION=$(echo "$TMUX_PERM" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('decision',''))" 2>/dev/null || true)
[[ "$TMUX_DECISION" == "allow" ]] \
    && check "permission-request: auto-approve tmux list-sessions" "OK" \
    || check "permission-request: auto-approve tmux list-sessions" "FAILED"

echo
echo "[ Custom Subagents (~/.claude/agents/) ]"
if [[ -L ~/.claude/agents ]]; then
    TARGET=$(readlink -f ~/.claude/agents)
    check "agents/ symlinked to: $TARGET" "OK"
    for agent in go-expert rust-expert arch-ops security-audit \
                 perf-analyzer code-reviewer debugger \
                 proto-expert vald-reviewer; do
        [[ -f ~/.claude/agents/"$agent".md ]] \
            && check "agent: $agent" "OK" \
            || check "agent: $agent" "MISSING"
    done
else
    check "agents/ symlink" "MISSING"
fi

echo
echo "[ MCP Servers ]"
# MCPサーバー定義はExecutor gateway経由へ統合済み(agent/README.md「MCPサーバー定義の統合」参照)。
# 個別のcodegraph/filesystem/memoryサーバー定義は claude/settings.json にはもう存在しない。
EXECUTOR_URL=$(python3 -c "
import json, os
d = json.load(open(os.path.expanduser('~/.claude/settings.json')))
srv = d.get('mcpServers', {}).get('executor', {})
print(srv.get('url', ''))
" 2>/dev/null || true)
[[ -n "$EXECUTOR_URL" ]] \
    && check "executor gateway configured ($EXECUTOR_URL)" "OK" \
    || check "executor gateway configured" "MISSING (add mcpServers.executor)"

EXECUTOR_BIN=$(command -v executor 2>/dev/null || true)
[[ -n "$EXECUTOR_BIN" ]] \
    && check "executor binary: $EXECUTOR_BIN" "OK" \
    || check "executor binary in PATH" "MISSING (bun add -g executor)"

echo
echo "[ Graphify ]"
GRAPHIFY_BIN=$(command -v graphify 2>/dev/null || true)
[[ -n "$GRAPHIFY_BIN" ]] \
    && check "graphify binary: $GRAPHIFY_BIN" "OK" \
    || check "graphify binary in PATH" "MISSING (pip install graphify)"

DOTFILES_GRAPH="$HOME/go/src/github.com/kpango/dotfiles/.claude/graph/graphify/graph.json"
[[ -f "$DOTFILES_GRAPH" ]] \
    && check "dotfiles .claude/graph/graphify/graph.json exists" "OK" \
    || check "dotfiles .claude/graph/graphify/graph.json" "WARN:run: graphify ~/go/src/github.com/kpango/dotfiles"

OPENAI_PKG=$(python3 -c "import openai; print('ok')" 2>/dev/null || true)
[[ "$OPENAI_PKG" == "ok" ]] \
    && check "openai Python package (Antigravity backend)" "OK" \
    || check "openai Python package (Antigravity backend)" "WARN:run: pip install openai"

for repo_label in "dotfiles:$HOME/go/src/github.com/kpango/dotfiles" "vald:$HOME/go/src/github.com/vdaas/vald"; do
    label="${repo_label%%:*}"
    repo="${repo_label##*:}"
    if [[ -d "$repo/.git" ]]; then
        hook_status=$(cd "$repo" && graphify hook status 2>/dev/null || true)
        echo "$hook_status" | grep -q "post-commit: installed" \
            && check "graphify post-commit hook ($label)" "OK" \
            || check "graphify post-commit hook ($label)" "WARN:run: graphify hook install in $repo"
        echo "$hook_status" | grep -q "post-checkout: installed" \
            && check "graphify post-checkout hook ($label)" "OK" \
            || check "graphify post-checkout hook ($label)" "WARN:run: graphify hook install in $repo"
    fi
done

echo
echo "[ Memory & Logging Infrastructure ]"
[[ -d ~/.claude/memory ]]       && check "~/.claude/memory/ exists" "OK"       || check "~/.claude/memory/" "MISSING"
[[ -d ~/.claude/session-data ]] && check "~/.claude/session-data/ exists" "OK" || check "~/.claude/session-data/" "MISSING"

echo
echo "[ Session Start Hook ]"
SESSION_OUT=$(printf '{"session_id":"validate-test","hook_event_name":"SessionStart"}' | \
    ~/.claude/hooks/session-start.sh 2>/dev/null || true)
CONTINUE=$(echo "$SESSION_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('continue',''))" 2>/dev/null || true)
[[ "$CONTINUE" == "True" ]] \
    && check "session-start outputs valid JSON with continue=true" "OK" \
    || check "session-start outputs valid JSON" "WARN:got: $SESSION_OUT"
CONTEXT_LEN=$(echo "$SESSION_OUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ctx=d.get('hookSpecificOutput',{}).get('additionalContext','')
print(len(ctx))
" 2>/dev/null || echo "0")
[[ "$CONTEXT_LEN" -gt 0 ]] \
    && check "session-start injects non-empty memory context" "OK" \
    || check "session-start injects memory context" "WARN:context length: ${CONTEXT_LEN}"
tail -5 ~/.claude/session-data/sessions.log 2>/dev/null | grep -q 'memory=[0-9]*files/[0-9]*bytes' \
    && check "session-start log records memory=Xfiles/Ybytes" "OK" \
    || check "session-start log records memory=Xfiles/Ybytes" "WARN:check ~/.claude/session-data/sessions.log"

echo
echo "[ User Prompt Submit Hook ]"
UPS_FILE=~/.claude/hooks/user-prompt-submit.sh
if [[ -f "$UPS_FILE" && -x "$UPS_FILE" ]]; then
    UPS_OUT=$(printf '' | "$UPS_FILE" 2>/dev/null || true)
    python3 -c "import sys,json; json.load(sys.stdin)" <<< "$UPS_OUT" 2>/dev/null \
        && check "user-prompt-submit outputs valid JSON" "OK" \
        || check "user-prompt-submit outputs valid JSON" "INVALID: $UPS_OUT"
    echo "$UPS_OUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ctx=d.get('additionalContext','')
print('ok' if 'Repo:' in ctx else 'missing')
" 2>/dev/null | grep -q ok \
        && check "user-prompt-submit includes Repo: in git repo context" "OK" \
        || check "user-prompt-submit includes Repo: in git repo context" "WARN:Repo: not found"
    CWD_OUT=$(cd "$(dirname "$0")" && printf '' | "$UPS_FILE" 2>/dev/null || true)
    echo "$CWD_OUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ctx=d.get('additionalContext','')
print('ok' if 'CWD:' in ctx else 'missing')
" 2>/dev/null | grep -q ok \
        && check "user-prompt-submit includes CWD: in subdirectory context" "OK" \
        || check "user-prompt-submit includes CWD: in subdirectory context" "WARN:CWD: not in output (run from repo root?)"
else
    check "user-prompt-submit.sh exists and executable" "MISSING"
fi

echo
echo "[ Pre-Compact Hook Functional Test ]"
PRECOMPACT_FILE=~/.claude/hooks/pre-compact.sh
if [[ -f "$PRECOMPACT_FILE" && -x "$PRECOMPACT_FILE" ]]; then
    PRECOMPACT_OUT=$(printf '{"session_id":"validate-test","hook_event_name":"PreCompact"}' | \
        "$PRECOMPACT_FILE" 2>/dev/null || true)
    PRECOMPACT_CONTINUE=$(echo "$PRECOMPACT_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('continue',''))" 2>/dev/null || true)
    [[ "$PRECOMPACT_CONTINUE" == "True" ]] \
        && check "pre-compact outputs valid JSON with continue=true" "OK" \
        || check "pre-compact outputs valid JSON with continue=true" "FAILED: $PRECOMPACT_OUT"
else
    check "pre-compact.sh exists and executable" "MISSING"
fi

echo
echo "[ Post-Write Hook Functional Test ]"
POSTWRITE_FILE=~/.claude/hooks/post-write.sh
if [[ -f "$POSTWRITE_FILE" && -x "$POSTWRITE_FILE" ]]; then
    JSON_TMP=$(mktemp --suffix=.json)
    echo '{"valid": true}' > "$JSON_TMP"
    VALID_STDERR=$(printf '{"tool_input":{"file_path":"%s"}}' "$JSON_TMP" | \
        "$POSTWRITE_FILE" 2>&1 >/dev/null || true)
    rm -f "$JSON_TMP"
    [[ -z "$VALID_STDERR" ]] \
        && check "post-write: no warning for valid JSON file" "OK" \
        || check "post-write: no warning for valid JSON file" "WARN:got: $VALID_STDERR"
    BAD_JSON_TMP=$(mktemp --suffix=.json)
    echo '{invalid json}' > "$BAD_JSON_TMP"
    BAD_STDERR=$(printf '{"tool_input":{"file_path":"%s"}}' "$BAD_JSON_TMP" | \
        "$POSTWRITE_FILE" 2>&1 >/dev/null || true)
    rm -f "$BAD_JSON_TMP"
    echo "$BAD_STDERR" | grep -qi 'warning\|invalid' \
        && check "post-write: warns on invalid JSON file" "OK" \
        || check "post-write: warns on invalid JSON file" "WARN:expected WARNING in stderr"
    # go/pyチェック(2026-09-03、agy/hooks/post-edit-lint.shとの対象拡張子superset化で追加)。
    # ERR=$(cmd) 形式の代入は set -e 下でcmd失敗時に即座にスクリプトを中断させ、後続の
    # WARNING出力に到達しない罠がある(実装時に実際に踏んだ) — このテストはその回帰を検知する。
    if command -v gofmt &>/dev/null; then
        BAD_GO_TMP=$(mktemp --suffix=.go)
        printf 'package main\n\nfunc main( {\n' > "$BAD_GO_TMP"
        BAD_GO_STDERR=$(printf '{"tool_input":{"file_path":"%s"}}' "$BAD_GO_TMP" | \
            "$POSTWRITE_FILE" 2>&1 >/dev/null; echo "exit=$?")
        rm -f "$BAD_GO_TMP"
        echo "$BAD_GO_STDERR" | grep -q 'exit=0' && echo "$BAD_GO_STDERR" | grep -qi 'warning' \
            && check "post-write: warns on invalid Go file (exits 0, does not abort)" "OK" \
            || check "post-write: warns on invalid Go file (exits 0, does not abort)" "WARN:got: $BAD_GO_STDERR"
    fi
    if command -v python3 &>/dev/null; then
        BAD_PY_TMP=$(mktemp --suffix=.py)
        printf 'def f(:\n    pass\n' > "$BAD_PY_TMP"
        BAD_PY_STDERR=$(printf '{"tool_input":{"file_path":"%s"}}' "$BAD_PY_TMP" | \
            "$POSTWRITE_FILE" 2>&1 >/dev/null; echo "exit=$?")
        rm -f "$BAD_PY_TMP" "${BAD_PY_TMP%.py}.pyc" 2>/dev/null
        rm -rf "$(dirname "$BAD_PY_TMP")/__pycache__" 2>/dev/null
        echo "$BAD_PY_STDERR" | grep -q 'exit=0' && echo "$BAD_PY_STDERR" | grep -qi 'warning' \
            && check "post-write: warns on invalid Python file (exits 0, does not abort)" "OK" \
            || check "post-write: warns on invalid Python file (exits 0, does not abort)" "WARN:got: $BAD_PY_STDERR"
    fi
    # security-audit指摘(2026-09-03、HIGH)の再発防止: `make -n -f`はGNU Makeの`$(shell ...)`を
    # dry-runでも実行してしまう(実機PoCで確認済み)。post-write.shはMakefile/`.mk`のlintを
    # 意図的に実装しない(agent/README.md参照)ため、この種のMakefileを渡しても$(shell ...)が
    # 実行されない(=マーカーファイルが作成されない)ことを回帰確認する。
    if command -v make &>/dev/null; then
        MAKE_POC_DIR=$(mktemp -d)
        MAKE_POC_MARKER="$MAKE_POC_DIR/PWNED_MARKER"
        MAKE_POC_FILE="$MAKE_POC_DIR/Makefile"
        printf 'X := $(shell touch %s)\nall:\n\t@echo ok\n' "$MAKE_POC_MARKER" > "$MAKE_POC_FILE"
        printf '{"tool_input":{"file_path":"%s"}}' "$MAKE_POC_FILE" | "$POSTWRITE_FILE" >/dev/null 2>&1 || true
        if [[ -f "$MAKE_POC_MARKER" ]]; then
            check "post-write: does not execute \$(shell ...) in Makefile (make -n RCE)" "WARN:marker file was created — Makefile lint must not be reintroduced via make -n"
        else
            check "post-write: does not execute \$(shell ...) in Makefile (make -n RCE)" "OK"
        fi
        rm -rf "$MAKE_POC_DIR" 2>/dev/null || true
    fi
else
    check "post-write.sh exists and executable" "MISSING"
fi

harness_summary "Agent Harness"
