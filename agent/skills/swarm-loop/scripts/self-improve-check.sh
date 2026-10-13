#!/usr/bin/env bash
# 自己改善ミッション(Claude Code自体の設定/Skill/Agent改善)の対象集合重複チェック。
# self-improve-registry.tsv に登録済みの過去ミッションの対象集合に対し、新ミッションの対象集合が
# 部分集合であれば重複とみなす(SWARM.md §5「学びの3段階モデル」段階3の機械化。判定基準は集合演算のみ、
# 主観判断を含まない)。
# usage: self-improve-check.sh <comma,separated,new,targets>
# stdout: 重複ありなら "OVERLAP <slug> <targets>" を該当ミッション数だけ、無ければ "NO_OVERLAP"
# exit: 0 = 重複なし, 2 = 1件以上重複あり(非ブロッキング。呼び出し側=mission-init.shが用途に応じて扱う)
set -euo pipefail

new_targets="${1:?usage: self-improve-check.sh <comma,separated,targets>}"
# readlink -f でファイル自身のsymlinkを解決してからdirnameする(GNU coreutils限定)。
# `~/.claude/skills/...`等のデプロイ済みsymlink経由・`agent/skills/...`のrepo相対パス経由の
# どちらで起動しても、常に単一の正典 agent/skills/swarm-loop/self-improve-registry.tsv を指す
# ようにするための意図的な設計(2026-09-04、claude/pi/agy個別のself-improve-registry.tsvを
# agent/へ統合したことに伴う変更 — 統合前は`cd`のみ〈-P無し〉でツール別の実体を指す設計を
# 意図的に採用していたが、集約先を単一化したためこちらへ変更した)。
# `readlink -f`を`dirname`の引数として直接ネストさせない(`resolved=$(readlink -f ...)`という
# 独立したstatementにする) — ネストした場合、readlink失敗(command not found等)の空出力を
# `dirname`がそのまま受け取り`.`(cwd相対)を返してしまい`set -e`がこれを検知できない
# (dirnameコマンド自体は正常終了するため)。独立したstatementなら`set -e`がreadlink自体の
# 失敗を確実に捕捉し、無言でcwd依存の誤ったパスへフォールバックすることを防げる。
resolved_self="$(readlink -f "$0")"
registry="$(dirname "$(dirname "$resolved_self")")/self-improve-registry.tsv"

if [ ! -f "$registry" ]; then
  echo "NO_OVERLAP"
  exit 0
fi

# macOS 既定の /bin/bash は 3.2 系で連想配列 (declare -A) 非対応。集合演算は
# ",tok1,tok2," 形式のデリミタ付き文字列 + case の部分文字列一致で代替する
# (bash 3.2+ で動作。呼び出し元 mission-init.sh が stderr/非0 exit を握り潰すため、
# ここでクラッシュすると常に無音で NO_OVERLAP 相当の偽陰性になる — 2026-08-20 発見)。
in_set() {
  # $1 = token, $2 = ",a,b,c," 形式の集合文字列
  case "$2" in *",$1,"*) return 0 ;; *) return 1 ;; esac
}
to_set() {
  # stdout: comma-separated tokens (前後空白 trim・空要素除去) を ",a,b," 形式に正規化
  local raw="$1" out="," tok arr
  IFS=',' read -ra arr <<<"$raw"
  for tok in "${arr[@]}"; do
    tok="$(echo "$tok" | xargs)"
    [ -n "$tok" ] && out="${out}${tok},"
  done
  printf '%s' "$out"
}

# 登録ファイルを配列へ全読み込みしてから for で処理する(while read <file の本体で
# echo|xargs 等の別コマンドを呼ぶと、環境によって共有される fd0 の競合で行がずれる
# 事例を実機で確認した — 2026-08-20。配列化した for ループなら fd0 の奪い合いが
# 構造的に起きない)。
lines=()
while IFS= read -r _line || [ -n "$_line" ]; do
  lines+=("$_line")
done <"$registry"

newset="$(to_set "$new_targets")"
any_new=0
IFS=',' read -ra _new_arr <<<"$new_targets"
for t in "${_new_arr[@]}"; do
  t="$(echo "$t" | xargs)"
  [ -n "$t" ] && any_new=1
done

found=0
for line in "${lines[@]}"; do
  IFS=$'\t' read -r slug date targets <<<"$line"
  case "$slug" in ''|'#'*) continue ;; esac
  oldset="$(to_set "$targets")"
  is_subset=1
  IFS=',' read -ra _new_arr <<<"$new_targets"
  for t in "${_new_arr[@]}"; do
    t="$(echo "$t" | xargs)"
    [ -n "$t" ] || continue
    if ! in_set "$t" "$oldset"; then
      is_subset=0
      break
    fi
  done
  if [ "$is_subset" -eq 1 ] && [ "$any_new" -eq 1 ]; then
    echo "OVERLAP $slug $targets"
    found=1
  fi
done

if [ "$found" -eq 0 ]; then
  echo "NO_OVERLAP"
  exit 0
fi
exit 2
