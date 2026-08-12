#!/usr/bin/env bash
# Phase 5 GATE の budget-guard --reset 全task-idループ + worktree-release 複数回呼び出しを
# 1回のスクリプト実行へ集約する(CodeAct型のツールコール往復削減パターンを参照)。
# Tasks節の解析は loop-status.sh の節スコープ・malformed row ガードをそのまま移植したもの。
# usage: mission-cleanup.sh <mission-slug> --budget-only
#        mission-cleanup.sh <mission-slug> --release-worktrees [--delete-branches]
set -euo pipefail
slug="${1:?usage: mission-cleanup.sh <mission-slug> --budget-only|--release-worktrees [--delete-branches]}"
mode="${2:?mode required: --budget-only or --release-worktrees}"
delete_branches=false
[ "${3:-}" = "--delete-branches" ] && delete_branches=true

# worktree内からの実行でも main リポジトリ根を返す (worktree-release.sh と同じ idiom。
# 無引数 --show-toplevel はworktree内で自身の根を返しsplit-brainになるため使わない)。
root=$(git rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')
plan="$root/@fix_plan.md"
[ -f "$plan" ] || { echo "no @fix_plan.md at $root — nothing to clean up"; exit 0; }
scripts_dir="$(dirname "${BASH_SOURCE[0]}")"

rows=$(awk '
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
    if (last_heading == 0) exit
    for (k = last_heading + 1; k < end; k++) {
      raw = lines[k]
      if (substr(raw, 1, 1) != "|") continue
      body = raw
      sub(/^\|/, "", body); sub(/\|[ \t]*$/, "", body)
      ncell = split(body, cells, "|")
      for (c = 1; c <= ncell; c++) gsub(/^[ \t]+|[ \t]+$/, "", cells[c])
      is_sep = 1
      for (c = 1; c <= ncell; c++) if (cells[c] == "" || cells[c] ~ /[^-: ]/) is_sep = 0
      if (is_sep) continue
      if (tolower(cells[1]) == "task-id") continue
      if (ncell != 8) { print "malformed row (ncells=" ncell "): " substr(raw,1,40) > "/dev/stderr"; continue }
      print cells[1] "\t" cells[4]
    }
  }
' "$plan")

case "$mode" in --budget-only | --release-worktrees) ;; *)
  echo "usage: mission-cleanup.sh <slug> --budget-only|--release-worktrees [--delete-branches]" >&2
  exit 1
  ;;
esac

count=0
failed=0
fail_lines=()
while IFS=$'\t' read -r tid wt; do
  [ -z "$tid" ] && continue
  count=$((count + 1))
  case "$mode" in
    --budget-only)
      if ! out=$("$scripts_dir/budget-guard.sh" --reset "$tid" --mission="$slug" 2>&1); then
        failed=$((failed + 1))
        fail_lines+=("budget-reset failed for $tid: $out")
      fi
      ;;
    --release-worktrees)
      if [ -n "$wt" ] && [ "$wt" != "-" ] && [ -d "$wt" ]; then
        if $delete_branches; then
          out=$("$scripts_dir/worktree-release.sh" "$wt" --delete-branch 2>&1) \
            || { failed=$((failed + 1)); fail_lines+=("worktree-release failed for $wt: $out"); }
        else
          out=$("$scripts_dir/worktree-release.sh" "$wt" 2>&1) \
            || { failed=$((failed + 1)); fail_lines+=("worktree-release failed for $wt: $out"); }
        fi
      fi
      ;;
  esac
done <<<"$rows"

if [ "$failed" -gt 0 ]; then
  echo "mission-cleanup ($mode) FAILED: slug=$slug tasks=$count failed=$failed" >&2
  printf '%s\n' "${fail_lines[@]}" >&2
  exit 1
fi
echo "mission-cleanup ($mode) done: slug=$slug tasks=$count"
