#!/usr/bin/env bash
# swarm-relay メッセージプロトコル（SKILL.md §2）のエンコーダ。
# usage: relay-format.sh <init|precommit-check|handoff|gate-done> key1=val1 [key2=val2 ...]
# stdout: "[swarm-relay:<event>] key1=val1 key2=val2 ..." の1行
#
# 既知の制約: フィールドは空白区切りで連結する。value に空白を含めると relay-parse.sh が正しく分割
# できないため、本スクリプトは空白（タブ・改行含む）を含む value を拒否する。自由文フィールド
# （handoff の summary 等）はハイフン/アンダースコア区切りの短い要約に収めること（SKILL.md §2 参照）。
set -euo pipefail

usage() {
  echo "usage: relay-format.sh <init|precommit-check|handoff|gate-done> key1=val1 [key2=val2 ...]" >&2
  exit 1
}

event="${1:-}"
case "$event" in
  init | precommit-check | handoff | gate-done) ;;
  *) usage ;;
esac
shift

if [ "$#" -eq 0 ]; then
  usage
fi

for field in "$@"; do
  case "$field" in
    *[[:space:]]* | *'|'* | *'['* | *']'*)
      echo "swarm-relay: field '$field' contains a reserved protocol delimiter (whitespace / newline / | / [ / ])" >&2
      exit 1
      ;;
  esac
  case "$field" in
    *=*) ;;
    *)
      echo "swarm-relay: field '$field' is not in key=val form" >&2
      exit 1
      ;;
  esac
done

printf '[swarm-relay:%s] %s\n' "$event" "$*"
