#!/usr/bin/env bash
# agent/AGENTS.md(汎用コア、AGENTS.md仕様準拠)+ agent/AGENTS-<tool>-supplement.md(ツール固有補完)を
# 連結して pi/AGENTS.md・agy/AGENTS.md(実体ファイル)を機械生成する。
#
# 背景: claude だけは CLAUDE.md の `@path` インポート構文で agent/AGENTS.md と
# agent/AGENTS-claude-supplement.md を実行時に動的合成できる(claude/CLAUDE.md 参照)。
# pi/agy にはこの種のインポート構文が無い(2026-09-03、pi.dev公式クイックスタート・agy公式ドキュメント
# 実査で確認済み)ため、生成パターンをAGENTS.mdにも適用する(pi/agents/*.mdのtools:frontmatter変換は
# 2026-09-03以降 pi/extensions/subagents.ts の実行時変換へ移行済みで本スクリプトとは別物)。
#
# usage: agent/scripts/gen-tool-agents.sh [pi|agy|all] [--check]
#   第1引数省略時は "all"(pi・agy両方を対象)。
#   --check: 書き込みは行わず、対象の現行 <tool>/AGENTS.md との差分有無のみを報告する
#            (exit 1 = 差分あり)。
#
# agent/sync-manifest.json の generate モードは「1 target = 1 script」の呼び出し契約
# (sync-verify.sh が `$script --check` を引数無しで呼ぶ)であるため、pi/agy それぞれの
# manifest entry からは本体を直接ではなく agent/scripts/gen-agents-md-for-pi.sh /
# agent/scripts/gen-agents-md-for-agy.sh という薄いラッパー経由で呼ぶ(下記参照)。
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
core="$root/agent/AGENTS.md"

target_arg="${1:-all}"
check_flag="${2:-}"
case "$target_arg" in
    --check)
        # `gen-tool-agents.sh --check` (第1引数省略の代わりに直接--checkが来た場合)も
        # "all --check" として扱う。
        check_flag="--check"
        target_arg="all"
        ;;
esac
check_only=0
[[ "$check_flag" == "--check" ]] && check_only=1

gen_one() {
    local tool="$1" dst="$2"
    local supplement="$root/agent/AGENTS-${tool}-supplement.md"
    local generated
    generated="$(
        printf '> Generated file — do not edit directly. Canonical sources: `agent/AGENTS.md`\n'
        printf '> (generic core) + `agent/AGENTS-%s-supplement.md` (tool-specific supplement).\n' "$tool"
        printf '> Regenerate with `agent/scripts/gen-tool-agents.sh %s`.\n\n' "$tool"
        cat "$core"
        printf '\n'
        cat "$supplement"
    )"
    if [[ "$check_only" -eq 1 ]]; then
        if [[ ! -f "$dst" ]]; then
            echo "STALE (missing): $dst"
            return 1
        fi
        if ! diff -q <(printf '%s' "$generated") "$dst" >/dev/null 2>&1; then
            echo "STALE: $dst"
            diff <(printf '%s' "$generated") "$dst" | head -8 | sed 's/^/    /'
            return 1
        fi
        echo "$dst は agent/AGENTS.md + agent/AGENTS-${tool}-supplement.md と同期済み"
        return 0
    fi
    printf '%s' "$generated" > "$dst"
    echo "generated: $dst"
    return 0
}

fail=0
case "$target_arg" in
    pi) gen_one "pi" "$root/agent/harnesses/pi/AGENTS.md" || fail=1 ;;
    agy) gen_one "agy" "$root/agent/harnesses/agy/AGENTS.md" || fail=1 ;;
    all)
        gen_one "pi" "$root/agent/harnesses/pi/AGENTS.md" || fail=1
        gen_one "agy" "$root/agent/harnesses/agy/AGENTS.md" || fail=1
        ;;
    *)
        echo "usage: $0 [pi|agy|all] [--check]" >&2
        exit 2
        ;;
esac

exit "$fail"
