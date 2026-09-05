#!/usr/bin/env bash
# ミッション状態の初期化: @fix_plan.md 骨子生成 + ミッション状態ディレクトリ作成。
# usage: mission-init.sh <mission-slug> "<mission goal>" [interactive|mission] [self-improve-targets] [depth]
#   self-improve-targets: カンマ区切り(例: "CLAUDE.md,settings.json,hooks")。Claude Code 自体
#     (設定/Skill/Agent)の改善・監査・リファクタリングが目的のミッションのときのみ渡す。
#     self-improve-check.sh で self-improve-registry.tsv との対象集合重複を機械判定する(非ブロッキング)。
#   depth: ネストされた /swarm-loop の深さ(省略時 0)。非負整数以外・1 超過は REFUSE(孫ネスト禁止)。
# stdout: 状態ディレクトリのパス
set -euo pipefail

slug="${1:?usage: mission-init.sh <mission-slug> \"<goal>\" [interactive|mission] [self-improve-targets] [depth]}"
goal="${2:?mission goal (1 sentence) required}"
scale="${3:-mission}"
self_improve_targets="${4:-}"
depth="${5:-0}"
slug=$(printf '%s' "$slug" | tr -c 'a-zA-Z0-9._-' '-' | cut -c1-48)

# 予算定数の単一ソース (fable-budget.conf) をミッション開始時点でスナップショットし
# @fix_plan.md へ pin する (ConstraintRot対策, arXiv:2606.22528 — compaction後に規範が
# prose からのみ失われると執行違反率が跳ね上がるとの報告に基づく)。
# BUDGET_*/FABLE_* の値の変更は fable-budget.conf 側で行うこと。既存ミッションのスナップショットは
# 追随させない (遡及適用を防ぐため)。budget-guard.sh と同じフォールバック既定値を用いる。
fable_conf="${FABLE_BUDGET_CONF:-$(dirname "$0")/../../swarm-implement/scripts/fable-budget.conf}"
[ -f "$fable_conf" ] && . "$fable_conf"
: "${BUDGET_TASK_MAX_DEFAULT:=5}" "${BUDGET_MISSION_MAX_DEFAULT:=20}" \
  "${FABLE_TASK_MAX:=1}" "${FABLE_MISSION_MAX:=2}"

if ! printf '%s' "$depth" | grep -Eq '^[0-9]+$'; then
  echo "REFUSE: depth=\"$depth\" is not a non-negative integer — mission-init.sh <slug> <goal> [scale] [self-improve-targets] [depth]" >&2
  exit 1
fi
if [ "$depth" -gt 1 ]; then
  echo "REFUSE: depth=$depth exceeds nesting limit (1) — 孫ネスト（depth>1）は禁止" >&2
  exit 1
fi

root=$(git rev-parse --show-toplevel)
state="$HOME/.claude/session-data/swarm/missions/$slug"
plan="$root/@fix_plan.md"

if [ -f "$plan" ]; then
  echo "REFUSE: $plan already exists in this mission worktree — loop-status.sh で状態を確認し再開せよ" >&2
  exit 1
fi

# 自己改善ミッションの対象集合重複チェック(非ブロッキング。判定結果は @fix_plan.md に記録するのみで
# ミッションの続行自体は妨げない — Mission の自律実行原則(SKILL.md)と矛盾させないため)。
overlap_note="<!-- self-improve-targets 未指定 — 対象外 -->"
if [ -n "$self_improve_targets" ]; then
  check_script="$(dirname "$0")/self-improve-check.sh"
  if [ -x "$check_script" ]; then
    check_out=$("$check_script" "$self_improve_targets" 2>/dev/null || true)
    if printf '%s\n' "$check_out" | grep -q '^OVERLAP'; then
      overlap_note=$(printf '%s\n' "$check_out" | sed 's/^/<!-- /; s/$/ -->/')
      overlap_note="$overlap_note
<!-- differentiation angle: <TBD — 上記過去ミッションと何を変えるかを Phase 2 PLAN 前に埋めること。
     Interactive はここが埋まる前に人間へ確認する。Mission は埋めた上で続行し GATE で提示する> -->"
    else
      overlap_note="<!-- self-improve-check.sh: NO_OVERLAP (対象集合の重複なし) -->"
    fi
  else
    overlap_note="<!-- self-improve-check.sh が見つからない — 重複チェック未実施 -->"
  fi
fi

mkdir -p "$state"
date +%Y-%m-%dT%H:%M:%S%z >"$state/started"
printf '%s\n' "$goal" >"$state/goal"

cat >"$plan" <<EOF
# @fix_plan.md — mission: $slug

- goal: $goal
- scale: $scale
- depth: $depth
- started: $(date +%Y-%m-%d)
- state-dir: $state

## Invariants (mission-init.sh 実行時点のスナップショット、ConstraintRot対策 arXiv:2606.22528)
<!-- コンテキスト圧縮後もこのファイルの再読込のみで予算上限を復元できるようにする -->
<!-- 以下4値の変更は fable-budget.conf 側で行うこと。このスナップショットは追随しない -->
- budget-task-max-default: $BUDGET_TASK_MAX_DEFAULT
- budget-mission-max-default: $BUDGET_MISSION_MAX_DEFAULT
- fable-spot-per-task: $FABLE_TASK_MAX
- fable-spot-per-mission: $FABLE_MISSION_MAX
<!-- 以下2値は fable-budget.conf 管轄外の固定設計値。変更は各出典側で行うこと -->
- max-parallel-tasks: 3 (出典: SWARM.md §1、swarm-parallel-gate.sh フックが機械強制)
- write-scope-protected: SKILL.md, hooks/*.sh, SWARM.md, budget-guard.sh, verify.sh
  (出典: harness-lint.sh の PROTECTED 正規表現)

## Definition of Done
<!-- 完了条件を列挙。ここが埋まるまで Phase 1 に進まない -->

## Out of Scope
<!-- 今回やらないこと -->
$overlap_note

## Secretary Report
<!-- swarm-explore の秘書レポートをここへ貼り付けて永続化する -->

## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|

## Escalations / 学び (随時追記)
<!-- 同一エラー再発防止のための軌跡。完了時に軌跡ログ(agents-log-lib.sh)へ転記する -->
EOF

# Plan継承: mission-worktree-alloc.sh がステージングした @fix_plan.md.inherited があれば
# Tasks行を新骨子へマージする。ヘッダ(goal/scale/Invariants等)は継承せず今回のミッションの値を正とする
# (今回の予算スナップショットが正しいスナップショットであるべきため)。
inherited="$root/@fix_plan.md.inherited"
if [ -f "$inherited" ]; then
  inherited_tasks=$(awk '
    { lines[NR] = $0 }
    END {
      n = NR; last_heading = 0
      for (i = 1; i <= n; i++) if (lines[i] ~ /^## +Tasks$/ || lines[i] ~ /^## +Tasks[ \t]/) last_heading = i
      if (last_heading == 0) exit
      end = n + 1
      for (j = last_heading + 1; j <= n; j++) if (lines[j] ~ /^## /) { end = j; break }
      for (k = last_heading + 1; k < end; k++) {
        raw = lines[k]
        if (substr(raw, 1, 1) != "|") continue
        body = raw; sub(/^\|/, "", body); sub(/\|[ \t]*$/, "", body)
        ncell = split(body, cells, "|")
        is_sep = 1
        for (c = 1; c <= ncell; c++) { gsub(/^[ \t]+|[ \t]+$/, "", cells[c]); if (cells[c] == "" || cells[c] ~ /[^-: ]/) is_sep = 0 }
        if (is_sep) continue
        if (tolower(cells[1]) == "task-id") continue
        print raw
      }
    }
  ' "$inherited")
  if [ -n "$inherited_tasks" ]; then
    INHERITED_ROWS="$inherited_tasks" INHERITED_DATE="$(date +%Y-%m-%d)" awk '
      { print }
      /^\|---/ && !done {
        print "<!-- inherited task row(s) from source tree'\''s @fix_plan.md at mission worktree creation (" ENVIRON["INHERITED_DATE"] ") -->"
        print ENVIRON["INHERITED_ROWS"]
        done = 1
      }
    ' "$plan" >"$plan.new" && mv "$plan.new" "$plan"
  fi
  rm -f "$inherited"
fi

# OSS リポジトリを汚染しない (vald 等): 未追跡なら git exclude に登録
# worktree内では "$root/.git" はファイル(gitdir参照)であり "$root/.git/info/exclude" は存在しない —
# --git-common-dir で常に共有 .git ディレクトリを解決する
common_git_dir=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)
exclude="$common_git_dir/info/exclude"
if [ -f "$exclude" ] && ! git -C "$root" ls-files --error-unmatch '@fix_plan.md' >/dev/null 2>&1; then
  grep -qxF '@fix_plan.md' "$exclude" || echo '@fix_plan.md' >>"$exclude"
fi

echo "$state"
