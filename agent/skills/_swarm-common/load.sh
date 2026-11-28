#!/usr/bin/env bash
# swarm-* 共通ドキュメントの読み込み。--once で「同一コンテキストでの再読込」を 1 行スタブに置換してトークンを節約する。
# usage: load.sh <core|handoff|memory|skill-state> [--once] [--force]
#   --once   : 同一セッションで TTL(既定 90 分)以内に読み込み済みなら、本文の代わりにスタブを出力する
#   --force  : --once の記録を無視して常に本文を出力する(コンテキスト圧縮後・サブエージェント内ではこちら)
# 注意: --once は「呼び出し元コンテキストが既に本文を持っている」前提の最適化。サブエージェント/Workflow の
#       子コンテキストは別コンテキストなので --once を使わず(または --force で)読み込むこと。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
name="${1:?usage: load.sh <core|handoff|memory|skill-state> [--once] [--force]}"
shift || true

case "$name" in
  core) file="CORE.md" ;;
  handoff) file="HANDOFF.md" ;;
  memory) file="MEMORY_PROTOCOL.md" ;;
  skill-state) file="SKILL_STATE.md" ;;
  *) echo "UNKNOWN_DOC: $name (core|handoff|memory|skill-state)" >&2; exit 1 ;;
esac

once=false; force=false
for a in "$@"; do
  case "$a" in
    --once) once=true ;;
    --force) force=true ;;
    *) echo "UNKNOWN_OPTION: $a" >&2; exit 1 ;;
  esac
done

if $once && ! $force; then
  key="${SWARM_SESSION_KEY:-${CLAUDE_CODE_SESSION_ID:-default}}"
  key="${key//[^A-Za-z0-9_.-]/_}"
  dir="${XDG_RUNTIME_DIR:-/tmp}/swarm-common-loaded-$(id -u)"
  mkdir -p "$dir"; chmod 700 "$dir"
  marker="$dir/$key.$name"
  ttl="${SWARM_COMMON_TTL_MIN:-90}"
  if [ -f "$marker" ] && [ -z "$(find "$marker" -mmin +"$ttl" 2>/dev/null)" ]; then
    echo "[swarm-common:$name already loaded this session at $(date -r "$marker" +%H:%M) — skip. After context compaction or in a subagent, run: load.sh $name --force]"
    exit 0
  fi
  : >"$marker"
fi

cat "$here/$file"
