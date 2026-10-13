#!/usr/bin/env bash
# claude/pi/agy の validate-harness.sh が共通で source する軽量ライブラリ。
# 「何を検査するか」(settings.jsonスキーマはツールごとに別物)はここに持たず、
# 「検査結果をどう記録・集計・表示するか」というボイラープレートのみを共通化する
# (3ファイルでバイト単位に一致していたcheck()関数+集計ロジックの重複を解消)。
#
# usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/../../agent/scripts/harness-check-lib.sh"
#   check "some check" "OK"                    # PASS
#   check "some check" "WARN:reason text"       # WARN
#   check "some check" "reason text"            # FAIL(それ以外は全てFAIL扱い)
#   harness_summary "Claude Code"               # 末尾で1回呼ぶ。非0 FAILならexit 1する。

PASS=0
FAIL=0
WARN=0

check() {
    local desc="$1"
    local result="$2"
    if [[ "$result" == "OK" ]]; then
        printf "  OK  %s\n" "$desc"
        PASS=$((PASS + 1))
    elif [[ "$result" == "WARN:"* ]]; then
        printf "  WN  %s: %s\n" "$desc" "${result#WARN:}"
        WARN=$((WARN + 1))
    else
        printf "  NG  %s: %s\n" "$desc" "$result"
        FAIL=$((FAIL + 1))
    fi
}

# 共有テストスクリプト(agent/scripts/test-*.sh)を1本実行し、その終了コードのみをcheck()へ
# 畳み込むヘルパー。個別テストケースをvalidate-harness.sh側に再実装せず、実体を1箇所
# (agent/scripts/test-*.sh)に保つことで、ルールデータが変わってもvalidate-harness側の
# ハードコードされたテストケースが乖離する事故(pi/validate-harness.shで実際に発生した -
# agent/security-rules.jsonのnvme/chmod/git add修正が反映されないまま古い正規表現を検査していた)
# を構造的に防ぐ。
harness_run_shared_test() {
    local desc="$1" script_path="$2"
    local out
    if [[ ! -x "$script_path" ]]; then
        check "$desc" "MISSING: $script_path"
        return
    fi
    if out="$("$script_path" 2>&1)"; then
        check "$desc" "OK"
    else
        local status=$?
        local fail_line
        fail_line=$(echo "$out" | grep -m1 "^\[FAIL\]" || echo "$out" | tail -1)
        check "$desc" "FAILED (exit $status): $fail_line (see $script_path for full output)"
    fi
}

# gen-tool-{agents,system}.sh が重複していた引数検証(usage・$#検査・--check特例・case文、
# 約25行)の集約。呼び出し側は:
#   source ".../harness-check-lib.sh"
#   harness_parse_tool_args "$0" "$@"
#   # 以降 $HARNESS_TARGET_ARG ([pi|agy|all]) / $HARNESS_CHECK_FLAG ("" か "--check") /
#   # $HARNESS_CHECK_ONLY (0 か 1) を使う。
# 未知の引数(例: --stdout)は早期にusage+exit 2する(受理形式は[pi|agy|all] [--check]、計2引数まで)。
harness_tool_usage() {
    echo "usage: $1 [pi|agy|all] [--check]" >&2
}

harness_parse_tool_args() {
    local prog="$1"
    shift
    if [[ $# -gt 2 ]]; then
        harness_tool_usage "$prog"
        exit 2
    fi

    HARNESS_TARGET_ARG="${1:-all}"
    HARNESS_CHECK_FLAG="${2:-}"
    case "$HARNESS_TARGET_ARG" in
        --check)
            # `<prog> --check` (第1引数省略の代わりに直接--checkが来た場合)も "all --check" として
            # 扱う。ただしこの形では2引数目を受け付けない。
            if [[ $# -gt 1 ]]; then
                harness_tool_usage "$prog"
                exit 2
            fi
            HARNESS_CHECK_FLAG="--check"
            HARNESS_TARGET_ARG="all"
            ;;
    esac

    case "$HARNESS_TARGET_ARG" in
        pi|agy|all) : ;;
        *)
            harness_tool_usage "$prog"
            exit 2
            ;;
    esac

    case "$HARNESS_CHECK_FLAG" in
        ""|--check) : ;;
        *)
            harness_tool_usage "$prog"
            exit 2
            ;;
    esac

    HARNESS_CHECK_ONLY=0
    # Checker-reported regression (T18 review, trial 1): `[[ ... ]] && HARNESS_CHECK_ONLY=1`
    # returns the `[[ ]]` test's own (false) exit status whenever check_flag isn't
    # "--check" (i.e. the normal write-mode invocation). That was the LAST statement in
    # this function, and callers run this under `set -euo pipefail` without wrapping the
    # call in `if`/`&&`/`||` -- errexit therefore killed the whole script on ordinary
    # write-mode runs (`gen-tool-agents.sh all` produced no output and exited 1, silently
    # writing nothing). The original pre-refactor code had this same `&&` shorthand but
    # sat at file top level, outside any function, where `set -e` does not apply the same
    # way. An explicit `if`/`fi` (whose own exit status is always 0 when the condition is
    # false and there is no `else`) plus an explicit `return 0` makes this immune to that.
    if [[ "$HARNESS_CHECK_FLAG" == "--check" ]]; then
        HARNESS_CHECK_ONLY=1
    fi
    return 0
}

# gen-tool-{agents,system}.sh が重複していた「生成内容($1)と実ファイル($2)の比較」ロジックの集約。
harness_sync_generated_file() {
    local generated="$1" dst="$2" check_only="$3" synced_msg="$4"
    if [[ "$check_only" -eq 1 ]]; then
        if [[ ! -f "$dst" ]]; then
            echo "STALE (missing): $dst"
            return 1
        fi
        if ! diff -q <(printf '%s\n' "$generated") "$dst" >/dev/null 2>&1; then
            echo "STALE: $dst"
            diff <(printf '%s\n' "$generated") "$dst" | head -8 | sed 's/^/    /'
            return 1
        fi
        echo "$synced_msg"
        return 0
    fi
    printf '%s\n' "$generated" > "$dst"
    echo "generated: $dst"
    return 0
}

harness_summary() {
    local label="${1:-Agent Harness}"
    echo
    TOTAL=$((PASS + FAIL + WARN))
    echo "=== Results: ${PASS}/${TOTAL} passed, ${WARN} warnings, ${FAIL} failed ==="
    if [[ "$FAIL" -eq 0 ]]; then
        echo ">>> ${label} OPERATIONAL <<<"
    else
        echo ">>> ${label} has ${FAIL} ISSUE(S) <<<"
        exit 1
    fi
}
