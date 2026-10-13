#!/usr/bin/env bash
# agent/scripts/test-{evidence-reducer,guard-advisor,jev-calibration,jev-client,
# revision-check,security-gate-pi,tier-advisor}.sh が持っていた、ほぼ同一の約15行の
# テンプレート(見出しechoする -> 指定ディレクトリでテストコマンドを1本走らせる ->
# 成否をPASS:/FAIL:として報告してexit 0/1する)を1箇所に集約する共有ヘルパー。
#
# usage (呼び出し側で `set -euo pipefail` 済みであること):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/run-test-suite.sh"
#   run_suite "<header>" "<name>" "<dir>" <cmd...>
#
#   <header>: 見出し行 `=== <header> ===` に使う文字列。
#   <name>:   終了時の `PASS: <name>` / `FAIL: <name>` に使う文字列
#             (headerと同じとは限らない — 各テストの既存文言を保つため別引数にしてある)。
#   <dir>:    テストコマンドを実行するディレクトリ (cd してから実行)。
#   <cmd...>: 実行するコマンドとその引数 (例: python3 -m unittest test_foo -v)。
#
# 出力形式・exit code は元の各スクリプトと完全に同じ(PASS: ... / FAIL: ... とexit 0/1)。
# このヘルパー自身がexitするため、呼び出し側スクリプトの最後の行として使う。
run_suite() {
    local header="$1" name="$2" dir="$3"
    shift 3

    echo "=== ${header} ==="
    echo

    if (cd "$dir" && "$@"); then
        echo
        echo "PASS: ${name}"
        exit 0
    else
        echo
        echo "FAIL: ${name}" >&2
        exit 1
    fi
}
