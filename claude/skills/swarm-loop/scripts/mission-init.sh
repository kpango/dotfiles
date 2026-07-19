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
  echo "REFUSE: $plan already exists — 進行中ミッションあり。loop-status.sh で状態を確認し再開せよ" >&2
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
<!-- 同一エラー再発防止のための軌跡。完了時に AGENTS.md へ転記する -->
EOF

# OSS リポジトリを汚染しない (vald 等): 未追跡なら git exclude に登録
exclude="$root/.git/info/exclude"
if [ -f "$exclude" ] && ! git -C "$root" ls-files --error-unmatch '@fix_plan.md' >/dev/null 2>&1; then
  grep -qxF '@fix_plan.md' "$exclude" || echo '@fix_plan.md' >>"$exclude"
fi

echo "$state"
