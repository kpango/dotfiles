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
    local out status
    if [[ ! -x "$script_path" ]]; then
        check "$desc" "MISSING: $script_path"
        return
    fi
    out="$("$script_path" 2>&1)"
    status=$?
    if [[ "$status" -eq 0 ]]; then
        check "$desc" "OK"
    else
        local fail_line
        fail_line=$(echo "$out" | grep -m1 "^\[FAIL\]" || echo "$out" | tail -1)
        check "$desc" "FAILED: $fail_line (see $script_path for full output)"
    fi
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
