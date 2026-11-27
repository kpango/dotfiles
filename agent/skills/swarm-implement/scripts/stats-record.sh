#!/usr/bin/env bash
# swarm-* Skill の SKILL.stats.json へ実行結果を決定論的に記録する (LLM 不使用)。
# usage: stats-record.sh <skill> <ok|fail|partial> [duration_ms] [failure_signature] [called_by]
# 記録するのは件数・時間・失敗署名・呼び出し元のみ。プロンプト本文や秘密情報は書かない。
set -euo pipefail

skill="${1:?usage: stats-record.sh <skill> <ok|fail|partial> [duration_ms] [signature] [called_by]}"
status="${2:?status required: ok|fail|partial}"
duration="${3:-0}"
signature="${4:-}"
called_by="${5:-}"

[[ "$skill" =~ ^swarm-[a-z-]+$ ]] || { echo "INVALID_SKILL: $skill" >&2; exit 1; }
[[ "$status" =~ ^(ok|fail|partial)$ ]] || { echo "INVALID_STATUS: $status" >&2; exit 1; }
[[ "$duration" =~ ^[0-9]+$ ]] || { echo "INVALID_DURATION: $duration" >&2; exit 1; }
[[ -z "$called_by" || "$called_by" =~ ^(swarm-[a-z-]+|human)$ ]] || { echo "INVALID_CALLED_BY: $called_by" >&2; exit 1; }
# 署名は短い識別子のみ (自由文・秘密の混入防止)。
[[ -z "$signature" || "$signature" =~ ^[A-Za-z0-9_.:-]{1,64}$ ]] || { echo "INVALID_SIGNATURE (A-Za-z0-9_.:- 64字以内)" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "jq not found; stats skipped" >&2; exit 0; }

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
file="$root/$skill/SKILL.stats.json"
[ -f "$file" ] || { echo "NO_STATS_FILE: $file" >&2; exit 1; }

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
lockdir="${XDG_RUNTIME_DIR:-/tmp}"
tmp="$(mktemp "$file.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

(
  flock -x 9
  jq --arg st "$status" --argjson d "$duration" --arg sig "$signature" \
     --arg cb "$called_by" --arg now "$now" '
    .metrics.execution_count += 1
    | (if $st == "ok" then .metrics.success_count += 1
       elif $st == "fail" then .metrics.failure_count += 1
       else .metrics.retry_count += 1 end)
    | .metrics.total_duration_ms += $d
    | .metrics.avg_duration_ms = (.metrics.total_duration_ms / .metrics.execution_count)
    | .metrics.min_duration_ms = (if .metrics.execution_count == 1 then $d else ([.metrics.min_duration_ms, $d] | min) end)
    | .metrics.max_duration_ms = ([.metrics.max_duration_ms, $d] | max)
    | .metrics.success_rate = (.metrics.success_count / .metrics.execution_count)
    | (if $cb != "" then .metrics.called_by = ((.metrics.called_by // {}) | .[$cb] = ((.[$cb] // 0) + 1)) else . end)
    | (if $sig != "" then
         .failure_signatures = (
           if any(.failure_signatures[]?; .signature == $sig)
           then (.failure_signatures | map(if .signature == $sig then .count += 1 | .last_seen = $now else . end))
           else (.failure_signatures + [{signature: $sig, count: 1, last_seen: $now}]) end)
       else . end)
    | .lifecycle.first_executed = (.lifecycle.first_executed // $now)
    | .lifecycle.last_executed = $now
    | .lifecycle.last_status = $st
  ' "$file" >"$tmp"
  jq -e . "$tmp" >/dev/null
  chmod --reference="$file" "$tmp"
  mv "$tmp" "$file"
) 9>"$lockdir/swarm-stats-$skill.lock"
trap - EXIT
echo "stats recorded: $skill $status"
