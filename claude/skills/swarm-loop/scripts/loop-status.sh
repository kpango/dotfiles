#!/usr/bin/env bash
# 進行中ミッションの状態要約: @fix_plan.md のタスク集計 + 試行予算の消費状況。
# usage: loop-status.sh [mission-slug]   (省略時は @fix_plan.md から自動検出)
set -euo pipefail

root=$(git rev-parse --show-toplevel)
plan="$root/@fix_plan.md"

if [ ! -f "$plan" ]; then
  echo "NO_MISSION: $plan がない — mission-init.sh で新規ミッションを開始せよ"
  exit 0
fi

slug="${1:-$(sed -n 's/^# @fix_plan.md — mission: //p' "$plan" | head -1)}"
budget_dir="$HOME/.claude/session-data/swarm/budget"

# 上限表示の単一ソース (fable-budget.conf)。欠落時はフォールバック既定値。
# shellcheck disable=SC1090
conf="${FABLE_BUDGET_CONF:-$(dirname "${BASH_SOURCE[0]}")/../../swarm-implement/scripts/fable-budget.conf}"
[ -f "$conf" ] && . "$conf"
: "${FABLE_TASK_MAX:=1}" "${FABLE_MISSION_MAX:=2}" "${BUDGET_TASK_MAX_DEFAULT:=5}" "${BUDGET_MISSION_MAX_DEFAULT:=20}"

echo "== mission: ${slug:-unknown}"
sed -n 's/^- goal: /goal: /p; s/^- scale: /scale: /p; s/^- started: /started: /p' "$plan"

# Tasks テーブルの集計: 節スコープ (「## Tasks」で始まる見出しのうち最後に出現する節のみ、
# 見出し直後〜次の「## 」見出し/EOF) + 不整形行ガード (セル数が8でない行は除外し warning 表示)。
# 節スコープを絞る理由: 全 "|" 行を無条件に集計すると ## Secretary Report の表や replan 由来の
# 旧 "## Tasks" 節、列ずれした不整形行まで誤集計してしまう。解析意味論は
# claude/skills/swarm-graph/scripts/graph-compile.sh の
# TASKS_HEADING_RE / ANY_HEADING_RE / malformed row 判定を移植したもの。
awk '
  { lines[NR] = $0 }
  END {
    n = NR
    last_heading = 0
    for (i = 1; i <= n; i++) {
      if (lines[i] ~ /^## +Tasks$/ || lines[i] ~ /^## +Tasks[ \t]/) last_heading = i
    }
    end = n + 1
    if (last_heading > 0) {
      for (j = last_heading + 1; j <= n; j++) {
        if (lines[j] ~ /^## /) { end = j; break }
      }
    }

    total = 0
    warn_count = 0
    if (last_heading > 0) {
      for (k = last_heading + 1; k < end; k++) {
        raw = lines[k]
        if (substr(raw, 1, 1) != "|") continue
        body = raw
        sub(/^\|/, "", body)
        sub(/\|[ \t]*$/, "", body)
        ncell = split(body, cells, "|")
        for (c = 1; c <= ncell; c++) gsub(/^[ \t]+|[ \t]+$/, "", cells[c])

        is_sep = 1
        for (c = 1; c <= ncell; c++) {
          if (cells[c] == "" || cells[c] ~ /[^-: ]/) is_sep = 0
        }
        if (is_sep) continue
        if (tolower(cells[1]) == "task-id") continue

        if (ncell != 8) {
          warn_count++
          trimmed = raw
          gsub(/^[ \t]+|[ \t]+$/, "", trimmed)
          wline[warn_count] = substr(trimmed, 1, 40)
          wncells[warn_count] = ncell
          continue
        }

        total++
        st = cells[5]
        if (st != "") count[st]++
        d_id[total] = cells[1]
        d_status[total] = st
        d_summary[total] = cells[2]
      }
    }

    print "== tasks"
    if (total == 0) {
      print "  (タスク未登録 — Phase 2 PLAN 未完)"
    } else {
      for (s in count) printf "  %-16s %d\n", s, count[s]
      printf "  %-16s %d\n", "TOTAL", total
    }
    for (w = 1; w <= warn_count; w++) {
      printf "  warning: malformed row (ncells=%d): %s\n", wncells[w], wline[w]
    }

    print "== blocked / in_progress detail"
    for (t = 1; t <= total; t++) {
      if (d_status[t] ~ /blocked|in_progress/) {
        printf "  [%s] %s — %s\n", d_status[t], d_id[t], d_summary[t]
      }
    }
  }' "$plan"

echo "== attempt budgets (default max ${BUDGET_TASK_MAX_DEFAULT}/task)"
if [ -d "$budget_dir" ]; then
  found=0
  for f in "$budget_dir"/*; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in
      _fable-*) continue ;;  # fable カウンタは下の専用節へ
      _mission-total-*) printf '  %-48s %s/%s (mission, default max)\n' "$(basename "$f")" "$(cat "$f")" "$BUDGET_MISSION_MAX_DEFAULT" ;;
      *) printf '  %-48s %s/%s\n' "$(basename "$f")" "$(cat "$f")" "$BUDGET_TASK_MAX_DEFAULT" ;;
    esac
    found=1
  done
  [ "$found" -eq 0 ] && echo "  (消費なし)"
else
  echo "  (消費なし)"
fi

echo "== fable spots (SWARM.md §1 スポット判断層: max ${FABLE_TASK_MAX}/task, ${FABLE_MISSION_MAX}/mission)"
fable_found=0
for f in "$budget_dir"/_fable-*; do
  [ -f "$f" ] || continue
  b=$(basename "$f")
  case "$b" in
    _fable-mission-total-*) printf '  %-48s %s/%s\n' "$b" "$(cat "$f")" "$FABLE_MISSION_MAX" ;;
    *) printf '  %-48s %s/%s\n' "$b" "$(cat "$f")" "$FABLE_TASK_MAX" ;;
  esac
  fable_found=1
done
[ "$fable_found" -eq 0 ] && echo "  (消費なし)"
spot_log="$HOME/.claude/session-data/swarm/fable-spot-log.jsonl"
if [ -f "$spot_log" ]; then
  echo "== fable spot log (last 3)"
  tail -3 "$spot_log" | sed 's/^/  /'
fi

echo "== active worktrees"
git -C "$root" worktree list | grep -F '.claude/worktrees/' || echo "  (なし)"
