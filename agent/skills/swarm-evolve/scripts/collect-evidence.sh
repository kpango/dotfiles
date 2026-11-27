#!/usr/bin/env bash
# swarm-evolve の証拠集約: 軌跡ログ + hook rejection ログを機械的に集めるだけ
# (解釈・パターン判定は行わない。判定は Drafter/Checker agent が行う)。
# usage: collect-evidence.sh [repo-root] [days=30]
#        collect-evidence.sh <repo-root> <days> --traces <target>   # JSONL for harness2-offline.py (rejection log only)
set -euo pipefail

# shellcheck disable=SC1090
. "$(dirname "${BASH_SOURCE[0]}")/../../swarm-implement/scripts/swarm-common-lib.sh"
# shellcheck disable=SC1090
. "$(dirname "${BASH_SOURCE[0]}")/../../swarm-implement/scripts/agents-log-lib.sh"

# 解析対象リポジトリ根。省略時は呼び出し位置の worktree 根 (behavior 保存)。
root="${1:-$(swarm_repo_root)}"
days="${2:-30}"
sdir="$(swarm_state_dir)"
log="$sdir/evolve-log.jsonl"
spotlog="$sdir/fable-spot-log.jsonl"
writescopelog="$sdir/write-scope-log.jsonl"
agents=$(cd "$root" && agents_log_path)
cutoff=$(date -u -d "-${days} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")

# --traces <target>: hook rejection ログを harness2-offline.py の trace 形式 (JSONL) で出力して終わる。
# signature=hook:category, task=発生日。target は変更対象の repo 相対 path (harness2-offline.py と同じ許可文字)。
# 行ごとに独立に処理し、harness2 が拒否する行 (非 object / 非 string / 制御・不可視・行区切り文字 / 長さ超過) は
# 捨てて続行する (1 行の不正で harness2 の run 全体が fail-closed になるのを防ぐ)。出力は最大 10000 行。
if [ "${3:-}" = "--traces" ]; then
  target="${4:-}"
  case "$target" in
    "" | /* | *..* | *[!A-Za-z0-9._/@+-]*)
      echo "collect-evidence.sh: --traces needs a repo-relative target (A-Z a-z 0-9 . _ / @ + -, no '..')" >&2
      exit 2
      ;;
  esac
  [ "${#target}" -le 300 ] || { echo "collect-evidence.sh: --traces target exceeds 300 chars" >&2; exit 2; }
  [ -f "$log" ] || exit 0
  jq -R -c -n --arg cutoff "$cutoff" --arg repo "$(basename "$root")" --arg target "$target" '
    def unsafe: test("[\\p{Cc}\\p{Cf}\\p{Co}\\p{Cn}\\p{Zl}\\p{Zp}]|(?! )\\p{Zs}|[\\x{FE00}-\\x{FE0F}\\x{E0100}-\\x{E01EF}\\x{180B}-\\x{180D}\\x{034F}\\x{115F}\\x{1160}\\x{17B4}\\x{17B5}\\x{2800}\\x{3164}\\x{FFA0}\\x{1D159}]");
    limit(10000; inputs
      | (try (fromjson
          | select(type == "object"
              and (.ts | type) == "string" and (.repo | type) == "string"
              and (.hook | type) == "string" and (.category | type) == "string"
              and .ts >= $cutoff and .repo == $repo
              and ((.hook + ":" + .category) | length) <= 200
              and (.ts | length) >= 10
              and ((.hook + .category + .ts) | unsafe | not))
          | {signature: (.hook + ":" + .category), task: .ts[0:10], target: $target,
             message: ((.hook + " " + .category + " " + .ts)[0:200])}) catch empty))
  ' "$log"
  exit 0
fi

echo "## 軌跡ログ ($agents)"
if [ -f "$agents" ]; then
  # ヘッダ行以降のテーブル行のみ抽出
  awk '/^\|.*日付.*タスク/{h=1} h && /^\|/' "$agents"
else
  echo "(軌跡ログが存在しない)"
fi

echo
echo "## Hook rejection ログ集計 (直近 ${days} 日, $log)"
if [ -f "$log" ]; then
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
echo "## fable スポット発火集計 (直近 ${days} 日, $spotlog)"
if [ -f "$spotlog" ]; then
  # decision 別の件数・最終発生。トリガー/上限チューニングの証跡 (機械集計のみ、判定はしない)
  jq -sc --arg cutoff "$cutoff" '
    map(select(.ts >= $cutoff))
    | {total: length,
       by_decision: (group_by(.decision)
         | map({decision: .[0].decision, count: length, last: (map(.ts) | max)})
         | sort_by(-.count))}
  ' "$spotlog" 2>/dev/null || echo "(集計失敗)"
else
  echo "(fable-spot-log.jsonl がまだ無い — スポット発火実績なし)"
fi

echo
echo "## write-scope grant/deny 集計 (直近 ${days} 日, $writescopelog)"
if [ -f "$writescopelog" ]; then
  jq -sc --arg cutoff "$cutoff" '
    map(select(.ts >= $cutoff))
    | {total: length,
       by_decision: (group_by(.decision)
         | map({decision: .[0].decision, count: length, last: (map(.ts) | max)})
         | sort_by(-.count))}
  ' "$writescopelog" 2>/dev/null || echo "(集計失敗)"
else
  echo "(write-scope-log.jsonl がまだ無い — write-scope-gate 発火実績なし)"
fi

echo
echo "## 直近の SKILL.md 変更履歴 (churn 確認用、直近 20 件)"
git -C "$root" log --oneline -20 -- '*/skills/*/SKILL.md' 2>/dev/null || echo "(git log 失敗)"
