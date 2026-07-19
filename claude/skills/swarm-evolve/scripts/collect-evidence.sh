#!/usr/bin/env bash
# swarm-evolve の証拠集約: AGENTS.md の軌跡 + hook rejection ログを機械的に集めるだけ
# (解釈・パターン判定は行わない。判定は Drafter/Checker agent が行う)。
# usage: collect-evidence.sh [repo-root] [days=30]
set -euo pipefail

root="${1:-$(git rev-parse --show-toplevel)}"
days="${2:-30}"
log="$HOME/.claude/session-data/swarm/evolve-log.jsonl"
agents="$root/AGENTS.md"

echo "## AGENTS.md 軌跡 ($agents)"
if [ -f "$agents" ]; then
  # ヘッダ行以降のテーブル行のみ抽出
  awk '/^\|.*日付.*タスク/{h=1} h && /^\|/' "$agents"
else
  echo "(AGENTS.md が存在しない)"
fi

echo
echo "## Hook rejection ログ集計 (直近 ${days} 日, $log)"
if [ -f "$log" ]; then
  cutoff=$(date -u -d "-${days} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")
  jq -sc --arg cutoff "$cutoff" --arg repo "$(basename "$root")" '
    map(select(.ts >= $cutoff and .repo == $repo))
    | group_by(.hook + "|" + .category)
    | map({hook: .[0].hook, category: .[0].category, count: length, last: (map(.ts) | max)})
    | sort_by(-.count)
  ' "$log" 2>/dev/null || echo "(集計失敗またはログなし)"
else
  echo "(evolve-log.jsonl がまだ無い — hook 発火実績なし)"
fi

echo
echo "## 直近の SKILL.md 変更履歴 (churn 確認用、直近 20 件)"
git -C "$root" log --oneline -20 -- '*/skills/*/SKILL.md' 2>/dev/null || echo "(git log 失敗)"
