#!/usr/bin/env bash
# ミッション終了後の実績記録。registry へ TSV 追記/置換する。
# usage: harness-record.sh <mission-slug> <harness> <profile-primary> <model-version> "<outcome>"
#   outcome 例: "done=4 blocked=1 attempts=7 replans=1"
#
# flock は read+modify+write の全体を 1 クリティカルセクションで囲む
# (budget-guard.sh の flock -x 番号付き fd パターン準拠)。
# 冪等: 同一 mission-slug の既存行があれば置換 (重複行を作らない)。置換も flock 内で行う。
# 入力の TAB/改行 (CR/LF) は空白に正規化 (TSV 破壊防止)。
# 仕様: /tmp/a970d944-5c72-44e0-bf62-429e73ed60c4/swarm/specs/sm-spec.md
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mission="${1:?usage: harness-record.sh <mission-slug> <harness> <profile-primary> <model-version> \"<outcome>\"}"
harness="${2:?usage: harness-record.sh <mission-slug> <harness> <profile-primary> <model-version> \"<outcome>\"}"
profile="${3:?usage: harness-record.sh <mission-slug> <harness> <profile-primary> <model-version> \"<outcome>\"}"
model_version="${4:?usage: harness-record.sh <mission-slug> <harness> <profile-primary> <model-version> \"<outcome>\"}"
outcome="${5:?usage: harness-record.sh <mission-slug> <harness> <profile-primary> <model-version> \"<outcome>\"}"

registry="${HARNESS_REGISTRY:-$here/../harness-registry.tsv}"
lockfile="$registry.lock"

# TSV 破壊防止: 各フィールドの TAB/CR/LF を空白へ正規化する。mission-slug も同様に正規化する
# (呼び出し側が汚染された値を渡しても TSV の列数が壊れないよう全フィールドに一様適用する)。
normalize() {
  local s="$1"
  s="${s//$'\t'/ }"
  s="${s//$'\r'/ }"
  s="${s//$'\n'/ }"
  printf '%s' "$s"
}

mission="$(normalize "$mission")"
harness="$(normalize "$harness")"
profile="$(normalize "$profile")"
model_version="$(normalize "$model_version")"
outcome="$(normalize "$outcome")"

date_str="$(date +%Y-%m-%d)"
new_row="$date_str	$mission	$harness	$profile	$model_version	$outcome"

{
  flock -x 200

  [ -f "$registry" ] || printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$registry"

  tmp="$registry.tmp.$$"
  replaced=false
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -z "$line" ]; then
      continue
    fi
    case "$line" in
      \#*)
        printf '%s\n' "$line" >>"$tmp"
        continue
        ;;
    esac
    row_mission="$(printf '%s' "$line" | cut -f2)"
    if [ "$row_mission" = "$mission" ]; then
      printf '%s\n' "$new_row" >>"$tmp"
      replaced=true
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$registry"

  if ! $replaced; then
    printf '%s\n' "$new_row" >>"$tmp"
  fi

  mv "$tmp" "$registry"
} 200>"$lockfile"

echo "recorded: mission=$mission harness=$harness"
