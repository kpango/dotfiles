#!/usr/bin/env bash
# hook結果(決定論的検証)とChecker判定の食い違いを機械的に検出する(SWARM.md §2「両者が食い違う場合は
# hook側を優先し、Checkerには理由を再提示させる」の既知の未機械化ギャップへの対応)。
# 判定そのものは上書きしない — 検出のみ。問題になるのは非対称な1パターン(hook=FAIL かつ
# Checker=PASS、Checkerが誤って甘く判定したケース)のみで、hook=PASS/Checker=FAILは通常の
# 不合格フロー(次試行)であり矛盾ではない。
#
# 呼び出し側(swarm-implement本体)は各試行で以下2ファイルを書いてから本スクリプトを呼ぶ:
#   /tmp/${CLAUDE_CODE_SESSION_ID:-manual}/swarm/task-<id>-hook-result     (PASS|FAIL の1行)
#   /tmp/${CLAUDE_CODE_SESSION_ID:-manual}/swarm/task-<id>-checker-verdict (PASS|FAIL の1行)
# usage: verify-consistency.sh <task-id>
set -euo pipefail

task="${1:?usage: verify-consistency.sh <task-id>}"
base="/tmp/${CLAUDE_CODE_SESSION_ID:-manual}/swarm"
hook_file="$base/task-$task-hook-result"
checker_file="$base/task-$task-checker-verdict"

for f in "$hook_file" "$checker_file"; do
  if [ ! -f "$f" ]; then
    echo "INCOMPLETE: missing state file $f — write hook-result and checker-verdict before calling verify-consistency.sh" >&2
    exit 1
  fi
done

hook_result=$(tr -d '[:space:]' <"$hook_file")
checker_verdict=$(tr -d '[:space:]' <"$checker_file")

case "$hook_result" in PASS|FAIL) ;; *) echo "INVALID: hook-result must be PASS or FAIL, got '$hook_result'" >&2; exit 1 ;; esac
case "$checker_verdict" in PASS|FAIL) ;; *) echo "INVALID: checker-verdict must be PASS or FAIL, got '$checker_verdict'" >&2; exit 1 ;; esac

if [ "$hook_result" = "FAIL" ] && [ "$checker_verdict" = "PASS" ]; then
  echo "CONTRADICTION: hook=FAIL but Checker=PASS (task=$task) — hookが第一権威(SWARM.md §2)。Checkerの合格判定は無効。矛盾点を提示して再判定させよ。" >&2
  exit 1
fi

echo "CONSISTENT: hook=$hook_result checker=$checker_verdict (task=$task)"
