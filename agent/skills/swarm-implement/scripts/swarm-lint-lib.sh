#!/usr/bin/env bash
# swarm系hookが共有するlint呼び出し・grant消費ロジックの単一ソース。
# write-scope-lib.sh・flock-guard-lib.sh・agents-log-lib.sh と同じ「hookからsourceする」慣行。
# 以下4関数は元々複数のagent/hooks/claude/(旧claude/hooks/)配下のhookファイルに独立コピーされて
# いたロジックを統合したもの(重複実装は片方だけ修正され食い違うバグを生むため):
#
# - grant_consume(2026-09-03統合): swarm-fable-gate.sh・swarm-write-scope-gate.sh で一字一句同一の
#   grant消費ループ(TTL失効チェック+mvによる原子的消費)が独立実装されていた。
# - swarm_lint_dockerfile / swarm_lint_go_package(2026-09-03新設、2026-09-04配線): swarm-post-edit-
#   lint.sh(PostToolUse、1ファイル単位で即block)・swarm-stop-verify.sh(Stop、セッション全体を
#   バッチ収集して報告)で hadolint呼び出し・golangci-lintのbuild-tag再試行ロジックが20行超ほぼ
#   同一のまま重複していた。呼び出し側の「即exit 2する」か「エラーを蓄積して後でまとめて報告する」
#   かという制御フロー自体は意図的に異なる(PreToolUse即時フィードバック vs Stop時のバッチ検証)
#   ため、本libは「lintツールを安全に呼び出し、出力とexit codeを返す」ところまでに留め、判定・
#   メッセージ整形・ログ記録は呼び出し側の責務として残す。新設時点(2026-09-03)ではgrant_consume()
#   の配線のみに留まり、この2関数自体はどこからも呼ばれていなかった — 2026-09-04の
#   claude-hooks-full-agent-consolidationミッションで実際に配線した。
# - swarm_lint_is_vald_repo(2026-09-04統合): swarm-post-edit-lint.sh・swarm-stop-verify.sh で
#   一字一句同一のgo.modモジュール名判定grepが重複していた。ディレクトリ名の部分一致では別名
#   クローン時にサイレントに検証が無効化されるため、go.modのモジュール名で判定する。

# swarm_lint_is_vald_repo <root>
# rootのgo.modがvdaas/valdモジュールか判定する(0=vald、1=非vald/go.mod無し)。
swarm_lint_is_vald_repo() {
    local root="$1"
    grep -qm1 '^module github\.com/vdaas/vald$' "$root/go.mod" 2>/dev/null
}

# swarm_lint_dockerfile <file> <root>
# hadolintをrootの.hadolint.yaml(あれば)で実行する。出力をstdoutへ、exit codeをそのまま返す
# (0=pass)。hadolint未インストール時は何もチェックせず0を返す(fail-open、既存2実装と同じ方針)。
swarm_lint_dockerfile() {
    local file="$1" root="$2"
    command -v hadolint >/dev/null 2>&1 || return 0
    local cfg=()
    [ -f "$root/.hadolint.yaml" ] && cfg=(--config "$root/.hadolint.yaml")
    timeout 60 hadolint "${cfg[@]}" "$file" 2>&1
}

# swarm_lint_go_package <pkg_dir> <root> <timeout_seconds> [extra_golangci_flags...]
# golangci-lintを実行する。"build constraints exclude all Go files"エラー(//go:buildタグ
# ガード付きパッケージがタグ無しでは全ファイル除外される既知の挙動)を検出した場合、パッケージ内の
# //go:buildタグを抽出して1回だけ再実行する。golangci-lint未インストール・vald以外のリポジトリ
# (呼び出し側でgo.modのモジュール名判定を先に行う想定)では呼び出し側が本関数自体を呼ばない設計
# (fail-openの判定自体は呼び出し側に残す — 本関数は「vald配下のGoパッケージをlintする」ことだけに
# 責務を絞る)。出力をstdoutへ、exit code(124=timeoutを含む)をそのまま返す。
swarm_lint_go_package() {
    local pkg_dir="$1" root="$2" timeout_seconds="$3"
    shift 3
    local extra_flags=("$@")
    local rel out rc tags
    rel=$(realpath --relative-to="$root" "$pkg_dir" 2>/dev/null) || return 1
    out=$(cd "$root" && timeout "$timeout_seconds" golangci-lint run "${extra_flags[@]}" "./$rel/" 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "build constraints exclude all Go files"; then
        tags=$(grep -rhoP '(?<=^//go:build )[a-zA-Z0-9_]+$' "$pkg_dir"/*.go 2>/dev/null | sort -u | paste -sd, -)
        if [ -n "$tags" ]; then
            out=$(cd "$root" && timeout "$timeout_seconds" golangci-lint run --build-tags "$tags" "${extra_flags[@]}" "./$rel/" 2>&1)
            rc=$?
        fi
    fi
    printf '%s' "$out"
    return "$rc"
}

# grant_consume <grants_dir> <ttl_seconds> <match_key>
# <grants_dir>内のgrantファイル(命名規則: <epoch_nanos>-<key>、budget-guard.shが発行)を走査し、
# TTLを超過したものは無条件に削除する(機会主義的クリーンアップ、対象keyを問わない)。
# <match_key>に一致する最初の(=最も古い、ファイル名の辞書順=時刻順のため)非失効grantを
# mvによる原子的消費(一時名は.consuming.$$、並行スポーンでの二重消費を防ぐ)で1件取得する。
# 消費成功時は消費したgrantファイルのbasenameをstdoutへ出力しreturn 0、
# 一致するgrantが無ければ何も出力せずreturn 1。
grant_consume() {
    local grants_dir="$1" ttl="$2" match_key="$3"
    [ -d "$grants_dir" ] || return 1
    local now gf mt gkey tmp
    now=$(date +%s)
    for gf in "$grants_dir"/*; do
        [ -f "$gf" ] || continue
        mt=$(stat -c %Y "$gf" 2>/dev/null || echo 0)
        if [ $((now - mt)) -gt "$ttl" ]; then
            rm -f "$gf"
            continue
        fi
        gkey="$(basename "$gf")"
        gkey="${gkey#*-}"
        [ "$gkey" = "$match_key" ] || continue
        tmp="$grants_dir/.consuming.$$"
        if mv "$gf" "$tmp" 2>/dev/null; then
            basename "$gf"
            rm -f "$tmp"
            return 0
        fi
    done
    return 1
}
