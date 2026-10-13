#!/usr/bin/env bash
# relay-format.sh / relay-parse.sh のラウンドトリップ・回帰テスト。
# 過去に発見された欠陥(未quote glob展開・空白区切りとの矛盾)の再発防止用。
# usage: test-relay-protocol.sh
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fmt="$dir/relay-format.sh"
parse="$dir/relay-parse.sh"

fail=0
check() { # <description> <expected-exit> <actual-exit>
  if [ "$2" != "$3" ]; then
    echo "FAIL: $1 (expected exit=$2, got exit=$3)" >&2
    fail=1
  else
    echo "PASS: $1"
  fi
}

check_eq() { # <description> <expected> <actual>
  if [ "$2" != "$3" ]; then
    echo "FAIL: $1 (expected=[$2] actual=[$3])" >&2
    fail=1
  else
    echo "PASS: $1"
  fi
}

# 1. 4イベント全てのラウンドトリップ
for case_spec in \
  "init|mission=t1 repo=/tmp scale=mission" \
  "precommit-check|mission=t1 repo=/tmp phase=execute" \
  "handoff|from-repo=/a to-repo=/b topic=ci summary=fix-deadlock" \
  "gate-done|mission=t1 repo=/tmp result=done"
do
  event="${case_spec%%|*}"
  fields="${case_spec#*|}"
  msg=$("$fmt" "$event" $fields)
  decoded=$("$parse" "$msg")
  expected="EVENT=$event
$(printf '%s\n' $fields)"
  check_eq "roundtrip:$event" "$expected" "$decoded"
done

# 2. glob文字を含むフィールド値がリテラルのまま扱われる(欠陥1の再発防止)
set +e
out=$("$parse" '[swarm-relay:gate-done] mission=t *' 2>&1)
rc=$?
set -e
check "glob-char-not-expanded:exit" 0 "$rc"
check_eq "glob-char-not-expanded:literal-star-preserved" "EVENT=gate-done
mission=t
*" "$out"

# 2b. '*' 展開の確定的回帰テスト: cwdに既存ファイルが無くても(nullglob無効時の偶然一致による
#     見逃しを避けるため)確実に候補ファイルがある専用の一時ディレクトリで再検証する。
tmpdir_glob="$(mktemp -d)"
: >"$tmpdir_glob/should-not-appear-a"
: >"$tmpdir_glob/should-not-appear-b"
set +e
out=$(cd "$tmpdir_glob" && "$parse" '[swarm-relay:gate-done] *' 2>&1)
rc=$?
set -e
rm -rf "$tmpdir_glob"
check "glob-char-not-expanded:deterministic-cwd:exit" 0 "$rc"
check_eq "glob-char-not-expanded:deterministic-cwd:literal-star-preserved" "EVENT=gate-done
*" "$out"

# 2c. glob文字 '?' 単独パターン
set +e
out=$("$parse" '[swarm-relay:gate-done] a?c' 2>&1)
rc=$?
set -e
check "glob-char-not-expanded:question-mark:exit" 0 "$rc"
check_eq "glob-char-not-expanded:question-mark:literal-preserved" "EVENT=gate-done
a?c" "$out"

# 2d. glob文字クラス '[abc]'
set +e
out=$("$parse" '[swarm-relay:gate-done] [abc]' 2>&1)
rc=$?
set -e
check "glob-char-not-expanded:bracket-class:exit" 0 "$rc"
check_eq "glob-char-not-expanded:bracket-class:literal-preserved" "EVENT=gate-done
[abc]" "$out"

# 3. 空白を含むフィールド値は relay-format.sh が拒否する(欠陥2の再発防止)
set +e
"$fmt" handoff "summary=fixed the bug" >/dev/null 2>&1
rc=$?
set -e
check "space-in-value-rejected" 1 "$rc"

# 4. 予約デリミタ(改行/|/[/])を含むフィールド値は拒否する
for bad in $'mission=a\nb' 'mission=a|b' 'mission=a[b' 'mission=a]b'; do
  set +e
  "$fmt" init "$bad" >/dev/null 2>&1
  rc=$?
  set -e
  check "reserved-delimiter-rejected:$bad" 1 "$rc"
done

# 5. 未知eventはusageを出しexit 1
set +e
"$fmt" bogus mission=t >/dev/null 2>&1
rc=$?
set -e
check "unknown-event-rejected" 1 "$rc"

# 6. 非swarm-relay形式のメッセージはNOT_SWARM_RELAY_MESSAGE+exit1
set +e
out=$("$parse" "hello world" 2>&1)
rc=$?
set -e
check "non-swarm-relay-message:exit" 1 "$rc"
check_eq "non-swarm-relay-message:output" "NOT_SWARM_RELAY_MESSAGE" "$out"

if [ "$fail" -eq 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "SOME TESTS FAILED" >&2
  exit 1
fi
