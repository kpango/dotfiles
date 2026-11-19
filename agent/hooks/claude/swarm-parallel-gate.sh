#!/usr/bin/env bash
# PreToolUse:Task|Agent hook。SWARM.md §1「実装層 Maker/Checker の並列実行は独立タスクにつき最大3並列まで」
# を機械強制する。swarm-fable-gate.sh / swarm-write-scope-gate.sh と同じ marker+TTL+task束縛パターンを
# 採用する。fail-open方針(jq欠如・パース不能時はexit 0)も同じ — 本hookは並列数ガードであり安全ゲートではない。
#
# prompt に `[parallel-task:<task-id>]` マーカーが無い呼び出し(Haiku探索・一般調査エージェント等)には
# 一切干渉しない(fail-open、exit 0)。マーカーがある場合のみ以下を強制する:
#   - 同一 task-id が既にスロットを保持していれば touch して継続許可(Maker→Checkerの同一タスク内連続
#     起動を1並列としてカウントするため — 別タスクの新規スロットではない)。
#   - 他の distinct task-id が既に3スロット保持中なら block(exit 2)。
#   - それ以外は新規スロットを作成して許可(exit 0)。
# スロットは TTL(既定1800s)で自動失効する(オーケストレーターが --release を忘れた場合の安全弁)。
# 解放は parallel-gate.sh --release <task-id> を明示的に呼ぶ(worktree-release.shと同じ設計)。
set -uo pipefail

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

tool=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$tool" in Task | Agent) ;; *) exit 0 ;; esac

prompt=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null || true)
task_id=$(printf '%s' "$prompt" | grep -oE '\[parallel-task:[A-Za-z0-9_.-]+\]' | head -1 | sed -E 's/\[parallel-task:([A-Za-z0-9_.-]+)\]/\1/' || true)
[ -n "$task_id" ] || exit 0

# ROOT解決(readlink -fでファイル自身のsymlinkを先に解決してからdirnameする)の経緯・理由は
# agent/README.md「既知の限界（fail-open）」節(2026-09-03 CRITICAL回帰の記録)を参照。要点のみ:
# merged directory化(ディレクトリ全体symlink→per-file symlink)後は`dirname`がファイル名を落として
# から評価されるため、`cd -P dirname($BASH_SOURCE)`だけではファイル自身のsymlinkが未解決のまま
# (実測で確認済み)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
conf="${FABLE_BUDGET_CONF:-$ROOT/agent/skills/swarm-implement/scripts/fable-budget.conf}"
# shellcheck disable=SC1090
[ -f "$conf" ] && . "$conf"
: "${PARALLEL_GATE_TTL_SECONDS:=1800}"
: "${PARALLEL_GATE_MAX_SLOTS:=3}"

slots_dir="$HOME/.claude/session-data/swarm/.parallel-slots"
mkdir -p "$slots_dir"
find "$slots_dir" -maxdepth 1 -type f -mmin +"$(((PARALLEL_GATE_TTL_SECONDS + 59) / 60))" -delete 2>/dev/null || true

my_slot="$slots_dir/$task_id"
if [ -f "$my_slot" ]; then
  touch "$my_slot"
  exit 0
fi

active_count=$(find "$slots_dir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$active_count" -ge "$PARALLEL_GATE_MAX_SLOTS" ]; then
  echo "[swarm-parallel-gate] PARALLEL_LIMIT_EXCEEDED: $PARALLEL_GATE_MAX_SLOTS tasks already hold a Maker/Checker slot; wait for one to release (parallel-gate.sh --release <task-id>) before starting task '$task_id' (SWARM.md §1: 最大${PARALLEL_GATE_MAX_SLOTS}並列)." >&2
  exit 2
fi

touch "$my_slot"
exit 0
