#!/usr/bin/env bash
# swarm-relay メッセージプロトコル（SKILL.md §2）のデコーダ。
# usage: relay-parse.sh ["<message text>"]
#   引数を渡した場合はその文字列を、省略した場合は標準入力を入力として使う。
# stdout (一致時, exit 0): "EVENT=<event>" の1行に続けて key=value を1行ずつ
# stdout (非一致時, exit 1): "NOT_SWARM_RELAY_MESSAGE"
#   (swarm-relay の構造化メッセージではない = 普通の自由文として扱うべき、というシグナル)
set -euo pipefail

if [ "$#" -ge 1 ]; then
  input="$1"
else
  input="$(cat)"
fi

first_line="${input%%$'\n'*}"

if [[ "$first_line" =~ ^\[swarm-relay:(init|precommit-check|handoff|gate-done)\][[:space:]]*(.*)$ ]]; then
  event="${BASH_REMATCH[1]}"
  rest="${BASH_REMATCH[2]}"
  echo "EVENT=$event"
  # word-splitting のみを行い glob 展開は行わない read を使う（受信メッセージは未検証入力であり、
  # `for field in $rest` の unquoted 展開は $rest に `*`/`?`/`[...]` が含まれるとカレントディレクトリの
  # ファイル名展開を引き起こすため使わない）。
  if [ -n "$rest" ]; then
    IFS=$' \t\n' read -ra fields <<< "$rest"
    printf '%s\n' "${fields[@]}"
  fi
  exit 0
fi

echo "NOT_SWARM_RELAY_MESSAGE"
exit 1
