#!/usr/bin/env bash
# Regression tests for sync-verify.sh の live-symlink-dir / live-regular-file mode と SYNC_VERIFY_ONLY
# (primeagent-max-customize T11)。様式: test-sync-verify-live-root.sh 準拠(mktemp -d 隔離 / [OK]・[FAIL] /
# total_fail 集計 / trap による後片付け)。実際の $HOME・リポジトリには触れない — 使い捨ての fake repo
# (sync-verify.sh のコピー + 専用 manifest)と fake HOME を都度組み立てる。
# 期待文字列中の $HOME は sync-verify.sh が manifest の表記のまま出力するリテラルなので single quote(SC2016)。
# shellcheck disable=SC2016
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE SYNC_VERIFY_LIVE_ROOT SYNC_VERIFY_ONLY

here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
total_fail=0
section() { echo; echo "=== $1 ==="; }
check() { # check <desc> <cond: 0=pass>
  if [ "$2" -eq 0 ]; then
    echo "[OK] $1"
  else
    echo "[FAIL] $1"
    total_fail=$((total_fail + 1))
  fi
}
has() { [[ "$out" == *"$1"* ]] && echo 0 || echo 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/repo"
FH="$WORK/home"
mkdir -p "$REPO/agent/scripts" "$REPO/shared/a" "$REPO/shared/b" "$REPO/shared/unlisted" \
  "$REPO/own/p1" "$REPO/own/nomarker" "$FH"
cp "$here/sync-verify.sh" "$REPO/agent/scripts/sync-verify.sh"
touch "$REPO/own/p1/SKILL.md" "$REPO/shared/file.txt"
printf '# comment\n a # trailing comment\n\nb\n' >"$REPO/list.txt"

write_manifest() { # <list file> <second source dir>
  cat >"$REPO/agent/sync-manifest.json" <<EOF
{
  "entries": [
    {
      "name": "dir",
      "targets": {
        "eco": {
          "path": "\$HOME/d",
          "mode": "live-symlink-dir",
          "sources": [{ "dir": "shared", "list": "$1" }, { "dir": "$2", "marker": "SKILL.md" }]
        }
      }
    },
    {
      "name": "file",
      "targets": { "eco": { "path": "\$HOME/settings.json", "mode": "live-regular-file", "perm": "600" } }
    },
    {
      "name": "other",
      "canonical": "shared/file.txt",
      "targets": { "other-eco": { "path": "\$HOME/other.txt", "mode": "live-symlink" } }
    }
  ]
}
EOF
}
write_manifest list.txt own

run() { out="$(cd "$WORK" && HOME="$FH" bash "$REPO/agent/scripts/sync-verify.sh" 2>&1)"; status=$?; }
good_layout() {
  rm -rf "${FH:?}"/* "$FH"/.[!.]* 2>/dev/null
  mkdir -p "$FH/d"
  ln -s "$REPO/shared/a" "$FH/d/a"
  ln -s "$REPO/shared/b" "$FH/d/b"
  ln -s "$REPO/own/p1" "$FH/d/p1"
  printf '{}\n' >"$FH/settings.json"
  chmod 600 "$FH/settings.json"
  ln -s "$REPO/shared/file.txt" "$FH/other.txt"
}

section "正常系: 期待エントリが揃い、settings.json が 0600 の通常ファイル"
good_layout
echo user >"$FH/d/user-file"
ln -s /etc/hostname "$FH/d/foreign-link"
run
check "exit 0" "$([ "$status" -eq 0 ] && echo 0 || echo 1)"
check "list の各名前(コメント・空白除去後 a, b)が live-symlink として PASS" "$([[ "$out" == *'PASS: dir/eco: $HOME/d/a -> shared/a'* && "$out" == *'PASS: dir/eco: $HOME/d/b -> shared/b'* ]] && echo 0 || echo 1)"
check "marker を持つディレクトリ(p1)だけが期待集合に入る" "$([[ "$out" == *'$HOME/d/p1 -> own/p1'* && "$out" != *nomarker* && "$out" != *unlisted* ]] && echo 0 || echo 1)"
check "ディレクトリ行 PASS(利用者の実ファイル・リポジトリ外 symlink は無視)" "$(has 'PASS: dir/eco: $HOME/d は実ディレクトリ(古いエントリ無し)')"
check "live-regular-file PASS" "$(has 'PASS: file/eco: $HOME/settings.json は通常ファイル (perm 600)')"

section "live-symlink-dir: 古いエントリ・欠落・ディレクトリ自体が symlink"
good_layout
ln -s "$REPO/shared/unlisted" "$FH/d/unlisted"
run
check "期待集合に無いリポジトリ向け symlink は FAIL(名前を列挙)" "$([[ "$status" -eq 1 && "$out" == *'FAIL: dir/eco: $HOME/d にリポジトリ側で不要になったsymlinkが残っている: unlisted'* ]] && echo 0 || echo 1)"
good_layout
rm "$FH/d/b"
run
check "期待エントリの欠落は FAIL" "$([[ "$status" -eq 1 && "$out" == *'FAIL: dir/eco: $HOME/d/b が存在しない'* ]] && echo 0 || echo 1)"
good_layout
rm -rf "$FH/d"
ln -s "$REPO/shared" "$FH/d"
run
check "ディレクトリ自体が symlink(旧レイアウト)は FAIL" "$(has 'FAIL: dir/eco: $HOME/d は実ディレクトリではない')"

section "live-symlink-dir: sources の不整合は error 行として FAIL(他 entry の検査は続行)"
good_layout
printf 'a\nmissing\n' >"$REPO/bad-list.txt"
write_manifest bad-list.txt own
run
check "list が存在しない名前を挙げると FAIL" "$([[ "$status" -eq 1 && "$out" == *"FAIL: dir/eco: bad-list.txt names 'missing' but shared/missing does not exist"* ]] && echo 0 || echo 1)"
check "他 entry(file)は検査が続く" "$(has 'PASS: file/eco:')"
mkdir -p "$REPO/dup/a"
touch "$REPO/dup/a/SKILL.md"
write_manifest list.txt dup
run
check "同名が複数 source にあると FAIL" "$(has 'FAIL: dir/eco: entry names in more than one source: a')"
write_manifest list.txt own

section "live-regular-file: symlink / perm 違い / 不在"
good_layout
rm "$FH/settings.json"
ln -s "$REPO/shared/file.txt" "$FH/settings.json"
run
check "symlink は FAIL" "$(has 'FAIL: file/eco: $HOME/settings.json がsymlinkになっている')"
good_layout
chmod 644 "$FH/settings.json"
run
check "perm 644 は FAIL" "$(has 'FAIL: file/eco: $HOME/settings.json のpermが 644 (期待値 600)')"
good_layout
rm "$FH/settings.json"
run
check "不在は FAIL" "$(has 'FAIL: file/eco: $HOME/settings.json が存在しないか通常ファイルではない')"

section "SYNC_VERIFY_ONLY"
good_layout
rm "$FH/other.txt"
out="$(cd "$WORK" && HOME="$FH" SYNC_VERIFY_ONLY=eco bash "$REPO/agent/scripts/sync-verify.sh" 2>&1)"; status=$?
check "指定 ecosystem だけを検査(other-eco の FAIL は出ない、exit 0)" "$([[ "$status" -eq 0 && "$out" != *other* ]] && echo 0 || echo 1)"
out="$(cd "$WORK" && HOME="$FH" bash "$REPO/agent/scripts/sync-verify.sh" 2>&1)"; status=$?
check "未指定なら other-eco も検査される(FAIL、exit 1)" "$([[ "$status" -eq 1 && "$out" == *'FAIL: other/other-eco'* ]] && echo 0 || echo 1)"
out="$(cd "$WORK" && HOME="$FH" SYNC_VERIFY_ONLY=nope bash "$REPO/agent/scripts/sync-verify.sh" 2>&1)"; status=$?
check "該当 target が無い ecosystem 指定は exit 1(沈黙 PASS しない)" "$([[ "$status" -eq 1 && "$out" == *'SYNC_VERIFY_ONLY=nope'* ]] && echo 0 || echo 1)"

echo
echo "---"
if [ "$total_fail" -gt 0 ]; then
  echo "test-sync-verify-dir-modes: $total_fail 件のFAILあり"
  exit 1
fi
echo "test-sync-verify-dir-modes: 全テストPASS"
exit 0
