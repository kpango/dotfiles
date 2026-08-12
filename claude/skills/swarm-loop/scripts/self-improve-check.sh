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
registry="$(cd "$(dirname "$0")/.." && pwd)/self-improve-registry.tsv"

if [ ! -f "$registry" ]; then
  echo "NO_OVERLAP"
  exit 0
fi

declare -A newset
IFS=',' read -ra _new_arr <<<"$new_targets"
for t in "${_new_arr[@]}"; do
  t="$(echo "$t" | xargs)"
  [ -n "$t" ] && newset["$t"]=1
done

found=0
while IFS=$'\t' read -r slug date targets; do
  case "$slug" in ''|'#'*) continue ;; esac
  declare -A oldset
  IFS=',' read -ra _old_arr <<<"$targets"
  for t in "${_old_arr[@]}"; do
    t="$(echo "$t" | xargs)"
    [ -n "$t" ] && oldset["$t"]=1
  done
  is_subset=1
  for k in "${!newset[@]}"; do
    if [ -z "${oldset[$k]:-}" ]; then
      is_subset=0
      break
    fi
  done
  if [ "$is_subset" -eq 1 ] && [ "${#newset[@]}" -gt 0 ]; then
    echo "OVERLAP $slug $targets"
    found=1
  fi
  unset oldset
done <"$registry"

if [ "$found" -eq 0 ]; then
  echo "NO_OVERLAP"
  exit 0
fi
exit 2
