#!/usr/bin/env bash
# Unified Credit Feedback: タスクごとの試行回数を計数し、上限超過で exit 1。
# usage: budget-guard.sh <task-id> [max-attempts=5] [--mission=<root-slug>] [--mission-max=<N>=20]
#        budget-guard.sh --reset <task-id> [--mission=<root-slug>]
#   --mission=<root-slug>: ネストされた /swarm-loop ツリー全体で共有する予算カウンタ
#     (_mission-total-<root-slug>)をタスク単位カウンタとは独立にインクリメントする。
#     共有カウンタが --mission-max (省略時 20) を超えたら MISSION_BUDGET_EXCEEDED で exit 1
#     (個々の task-id が自身の max-attempts 以下でも関係ない)。
#   共有カウンタの read-modify-write は flock (util-linux) で直列化する。ロック無しの
#   cat→+1→printf は並行呼び出し(2 worktree 以上の並列実装、SWARM.md §4)でインクリメントが
#   失われるレースコンディションになるため必須。
set -euo pipefail

dir="$HOME/.claude/session-data/swarm/budget"
mkdir -p "$dir"

# root-slug に ".." や "/" が含まれても意図しないパスへ書き込まないようサニタイズする
# (task-id の "${task//\//_}" と同じ考え方 + ".." を先に潰す)。
sanitize_slug() {
  local s="$1"
  s="${s//../_}"
  s="${s//\//_}"
  printf '%s' "$s"
}

# task-id のサニタイズ後の値が共有ミッションカウンタのファイル名接頭辞 "_mission-total-" と
# 偶然衝突すると、タスク用カウンタと共有ミッションカウンタが同一ファイルを指し混線する。
check_reserved_prefix() {
  local raw="$1" sanitized="$2"
  if [[ "$sanitized" == _mission-total-* ]]; then
    echo "RESERVED_PREFIX_COLLISION: task-id '$raw' sanitizes to '$sanitized', which collides with the reserved '_mission-total-' counter-file prefix — choose a different task-id" >&2
    exit 1
  fi
}

reset_mode=false
if [ "${1:-}" = "--reset" ]; then
  reset_mode=true
  shift
fi

mission=""
mission_max=20
mission_max_explicit=false
positional=()
for arg in "$@"; do
  case "$arg" in
    --mission=*) mission="${arg#--mission=}" ;;
    --mission-max=*) mission_max="${arg#--mission-max=}"; mission_max_explicit=true ;;
    *) positional+=("$arg") ;;
  esac
done

# --mission-max は非負整数のみ許可する。depth (mission-init.sh) と同様の検証。
# 未検証のままだと不正値 (例: "abc") で `[ "$mn" -gt "$mission_max" ]` が exit status 2 で
# 失敗し、if 文の中では「超過していない」と暗黙に扱われて共有予算上限が静かに無効化される。
if $mission_max_explicit && ! [[ "$mission_max" =~ ^[0-9]+$ ]]; then
  echo "INVALID_MISSION_MAX: --mission-max=\"$mission_max\" is not a non-negative integer" >&2
  exit 1
fi

if $reset_mode; then
  task="${positional[0]:?task-id required}"
  sanitized_task="${task//\//_}"
  check_reserved_prefix "$task" "$sanitized_task"
  rm -f "$dir/$sanitized_task"
  if [ -n "$mission" ]; then
    slug="$(sanitize_slug "$mission")"
    rm -f "$dir/_mission-total-$slug" "$dir/.lock-mission-$slug"
  fi
  echo "reset: $task"
  exit 0
fi

task="${positional[0]:?usage: budget-guard.sh <task-id> [max-attempts]}"
max="${positional[1]:-5}"
sanitized_task="${task//\//_}"
check_reserved_prefix "$task" "$sanitized_task"
f="$dir/$sanitized_task"

# 共有ミッションカウンタは task 自身の予算超過判定より先に、かつ独立にインクリメントする:
# 1 回の呼び出し = 1 回の実際の消費(トークン・時間)であり、task 側が自身の上限を超えていても
# 共有予算は既に消費されているため。read-modify-write は flock で直列化し、並行呼び出しでの
# インクリメント消失(レースコンディション)を防ぐ。
mission_exceeded=false
mn=0
if [ -n "$mission" ]; then
  slug="$(sanitize_slug "$mission")"
  mf="$dir/_mission-total-$slug"
  lockfile="$dir/.lock-mission-$slug"
  {
    flock -x 200
    mn=$(cat "$mf" 2>/dev/null || echo 0)
    mn=$((mn + 1))
    printf '%s\n' "$mn" >"$mf"
  } 200>"$lockfile"
  if [ "$mn" -gt "$mission_max" ]; then
    mission_exceeded=true
  fi
fi

n=$(cat "$f" 2>/dev/null || echo 0)
n=$((n + 1))
printf '%s\n' "$n" >"$f"

if $mission_exceeded; then
  echo "MISSION_BUDGET_EXCEEDED: mission=$mission attempts=$mn max=$mission_max (task=$task) — ツリー全体の共有予算超過。即座に停止し、@fix_plan.md に軌跡を書き出して人間に報告せよ" >&2
  exit 1
fi

if [ "$n" -gt "$max" ]; then
  echo "BUDGET_EXCEEDED: task=$task attempts=$n max=$max — 即座に停止し、@fix_plan.md に軌跡を書き出して人間に報告せよ" >&2
  exit 1
fi

echo "attempt $n/$max (task=$task)"
