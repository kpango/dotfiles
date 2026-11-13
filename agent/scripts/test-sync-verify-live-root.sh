#!/usr/bin/env bash
# Regression tests for sync-verify.sh の SYNC_VERIFY_LIVE_ROOT (T4b)。
# 様式: test-merged-dir-root-resolution.sh 準拠 (mktemp -d 隔離 / section() / [OK]・[FAIL] /
# total_fail 集計 / trap による後片付け)。実際の $HOME・リポジトリには一切触れない —
# 使い捨てのfake HOMEと使い捨てのgit repo(+linked worktree)を都度組み立てて検証する。
#
# 背景: sync-verify.sh は live symlink 照合の基準を、従来は常にスクリプト自身の root (自分が
# 置かれているチェックアウト) から取っていた。linked worktree 内で実行すると、$HOME 側の実配線は
# make install を実行した「メイン」を指すため、live 照合だけ偽陽性になる。git情報からメインを
# 自動推定するロジックは不採用(人間の判断)なので、SYNC_VERIFY_LIVE_ROOT で明示指定できるように
# した。本テストはその挙動(未設定時の互換動作・NOTE の出し分け・明示指定時の基準切り替え・
# 存在しないパス指定時のエラー・リポジトリ内容チェックの非依存性)を検証する。
set -uo pipefail

# 呼び出し元(このテストを起動したシェル)の GIT_* 環境変数が、本テストが組み立てる使い捨て
# git repo への git 操作に漏れ込まないようにする。
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_SYNC_VERIFY="$here/sync-verify.sh"

total_fail=0
section() { echo; echo "=== $1 ==="; }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

check() { # check <desc> <cond: 0=pass>
  local desc="$1" cond="$2"
  if [ "$cond" -eq 0 ]; then
    echo "[OK] $desc"
  else
    echo "[FAIL] $desc"
    total_fail=$((total_fail + 1))
  fi
}

# --- fake repo (これが「メイン」チェックアウト役) を組み立てる -----------------------------
MAIN="$WORK/main"
mkdir -p "$MAIN/agent/scripts" "$MAIN/agent/canon-dir"
git -C "$MAIN" init -q -b trunk
git -C "$MAIN" config user.email test@example.com
git -C "$MAIN" config user.name test
# Disable commit signing for this throwaway repo regardless of the caller's global
# `commit.gpgsign` (if true, a real signing key may be configured but its gpg-agent
# cache expired, which would otherwise hang this test waiting on a passphrase prompt
# that never comes in a non-interactive/CI context). A repo-local `commit.gpgsign`
# takes precedence over the global one, so this is enough without touching the
# caller's actual git config.
git -C "$MAIN" config commit.gpgsign false
cp "$REAL_SYNC_VERIFY" "$MAIN/agent/scripts/sync-verify.sh"
chmod +x "$MAIN/agent/scripts/sync-verify.sh"
echo canon > "$MAIN/agent/canon-dir/marker.txt"

# repo内容チェック(generateモード)用のダミー生成スクリプト。常に--checkで「同期済み」を返す
# (実際のgen-*.shはSTALE検出付きだが、本テストの関心はlive_root非依存性の確認のみ)。
cat > "$MAIN/agent/scripts/gen-fake.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
[ "${1:-}" = "--check" ] || { echo "gen-fake.sh: unsupported args" >&2; exit 1; }
exit 0
EOF
chmod +x "$MAIN/agent/scripts/gen-fake.sh"

# sync-manifest.json: live-symlinkエントリ2件(メインを指すもの/worktree自身を指すもの) +
# generateエントリ1件(repo内容チェック、live_pathなし = live_root非依存であるべき)。
cat > "$MAIN/agent/sync-manifest.json" <<'EOF'
{
  "entries": [
    {
      "name": "points-to-main",
      "canonical": "agent/canon-dir",
      "targets": {
        "fake": { "path": "$HOME/.faketargets/points-to-main", "mode": "live-symlink" }
      }
    },
    {
      "name": "points-to-worktree",
      "canonical": "agent/canon-dir",
      "targets": {
        "fake": { "path": "$HOME/.faketargets/points-to-worktree", "mode": "live-symlink" }
      }
    },
    {
      "name": "repo-content",
      "canonical": "",
      "targets": {
        "fake": { "path": "agent/generated.txt", "mode": "generate", "script": "agent/scripts/gen-fake.sh" }
      }
    }
  ]
}
EOF

git -C "$MAIN" add -A
git -C "$MAIN" commit -q -m init

# --- linked worktree を作る(これがタスク本文の「linked worktree内での実行」役) -----------
WT="$WORK/wt"
git -C "$MAIN" worktree add -q -b feat-wt "$WT" >/dev/null

# --- fake HOME: 2つのlive-symlinkエントリの実体を用意する -----------------------------------
# points-to-main: 常にメイン(MAIN)のcanon-dirを指す(実運用でmake installがメインを指す状況の再現)。
# points-to-worktree: worktree自身のcanon-dirを指す(誤配線、または「worktree基準で見れば正しい」状況)。
FAKE_HOME="$WORK/home"
mkdir -p "$FAKE_HOME/.faketargets"
ln -sfn "$MAIN/agent/canon-dir" "$FAKE_HOME/.faketargets/points-to-main"
ln -sfn "$WT/agent/canon-dir" "$FAKE_HOME/.faketargets/points-to-worktree"

# PASS/NOTEはstdout/stderrに分かれて出る(pass()はstdout、fail()/NOTEはstderr) — PASS/FAIL/NOTE
# を同一の$outから判定できるよう、通常は2>&1で合流させて呼ぶ。case5だけstderr単独取得が要るので
# 別関数にする。
run_sync_verify() { # run_sync_verify <cwd> [SYNC_VERIFY_LIVE_ROOT value]  (stdout+stderr合流)
  local cwd="$1" live_root_env="${2:-}"
  (
    cd "$cwd" || exit 99
    export HOME="$FAKE_HOME"
    if [ -n "$live_root_env" ]; then
      export SYNC_VERIFY_LIVE_ROOT="$live_root_env"
    else
      unset SYNC_VERIFY_LIVE_ROOT
    fi
    bash agent/scripts/sync-verify.sh 2>&1
  )
}

run_sync_verify_stderr_only() { # run_sync_verify_stderr_only <cwd> <SYNC_VERIFY_LIVE_ROOT value>
  local cwd="$1" live_root_env="$2"
  (
    cd "$cwd" || exit 99
    export HOME="$FAKE_HOME"
    export SYNC_VERIFY_LIVE_ROOT="$live_root_env"
    bash agent/scripts/sync-verify.sh 2>&1 1>/dev/null
  )
}

# ------------------------------------------------------------------
section "bash -n: 生成した使い捨てスクリプト自体の構文確認"
if bash -n "$MAIN/agent/scripts/sync-verify.sh" 2>/dev/null; then
  check "コピーしたsync-verify.shの構文" 0
else
  check "コピーしたsync-verify.shの構文" 1
fi

# ------------------------------------------------------------------
section "ケース1: 通常のチェックアウト(メイン自身)でSYNC_VERIFY_LIVE_ROOT未設定 -> NOTEなし・root基準"
out="$(run_sync_verify "$MAIN" "")"; status=$?
check "case1: NOTEが出ない(メインはlinked worktreeではない)" $([[ "$out" != *"NOTE:"* ]] && echo 0 || echo 1)
check "case1: points-to-main(メインを指す)はPASS" $([[ "$out" == *"PASS: points-to-main/fake"* ]] && echo 0 || echo 1)
check "case1: points-to-worktree(worktreeを指す)はFAIL" $([[ "$out" == *"FAIL: points-to-worktree/fake"* ]] && echo 0 || echo 1)
check "case1: repo-content(generate)はPASS" $([[ "$out" == *"PASS: repo-content/fake"* ]] && echo 0 || echo 1)
check "case1: exit codeは1(FAILが1件あるため)" $([ "$status" -eq 1 ] && echo 0 || echo 1)

# ------------------------------------------------------------------
section "ケース2: linked worktree内でSYNC_VERIFY_LIVE_ROOT未設定 -> NOTEが出る・root(worktree)基準"
out="$(run_sync_verify "$WT" "")"; status=$?
check "case2: NOTEが出る(linked worktree内での実行)" $([[ "$out" == *"NOTE:"* && "$out" == *"SYNC_VERIFY_LIVE_ROOT"* ]] && echo 0 || echo 1)
check "case2: points-to-main(メインを指す)はFAIL(root=worktree基準のため偽陽性)" $([[ "$out" == *"FAIL: points-to-main/fake"* ]] && echo 0 || echo 1)
check "case2: points-to-worktree(worktree自身を指す)はPASS" $([[ "$out" == *"PASS: points-to-worktree/fake"* ]] && echo 0 || echo 1)
gen_line_case2="$(grep -E 'repo-content/fake' <<<"$out" || true)"
check "case2: repo-content(generate)はPASS(live_root非依存)" $([[ "$out" == *"PASS: repo-content/fake"* ]] && echo 0 || echo 1)
check "case2: exit codeは1(FAILが1件あるため)" $([ "$status" -eq 1 ] && echo 0 || echo 1)

# ------------------------------------------------------------------
section "ケース3: linked worktree内でSYNC_VERIFY_LIVE_ROOT=メイン -> NOTEなし・メイン基準に切替"
out="$(run_sync_verify "$WT" "$MAIN")"; status=$?
check "case3: NOTEが出ない(SYNC_VERIFY_LIVE_ROOT設定時は案内を抑止)" $([[ "$out" != *"NOTE:"* ]] && echo 0 || echo 1)
check "case3: points-to-main(メインを指す)はPASS" $([[ "$out" == *"PASS: points-to-main/fake"* ]] && echo 0 || echo 1)
check "case3: points-to-worktree(worktree自身を指す誤配線)はFAIL" $([[ "$out" == *"FAIL: points-to-worktree/fake"* ]] && echo 0 || echo 1)
gen_line_case3="$(grep -E 'repo-content/fake' <<<"$out" || true)"
check "case3: repo-content(generate)はPASS(live_root非依存)" $([[ "$out" == *"PASS: repo-content/fake"* ]] && echo 0 || echo 1)
check "case3: exit codeは1(FAILが1件あるため)" $([ "$status" -eq 1 ] && echo 0 || echo 1)

section "ケース4: repo内容チェック(generate)の行がケース2/3で完全一致 -> live_rootに非依存"
check "case4: repo-content行がcase2とcase3で一致" $([ "$gen_line_case2" = "$gen_line_case3" ] && echo 0 || echo 1)

# ------------------------------------------------------------------
section "ケース5: 存在しないSYNC_VERIFY_LIVE_ROOT -> エラー表示してexit 1"
bad_path="$WORK/does-not-exist"
err="$(run_sync_verify_stderr_only "$WT" "$bad_path")"; status=$?
check "case5: exit code 1" $([ "$status" -eq 1 ] && echo 0 || echo 1)
check "case5: stderrにFAILとSYNC_VERIFY_LIVE_ROOTの案内が出る" $([[ "$err" == *"FAIL:"* && "$err" == *"SYNC_VERIFY_LIVE_ROOT"* ]] && echo 0 || echo 1)

echo
echo "---"
if [ "$total_fail" -gt 0 ]; then
  echo "test-sync-verify-live-root: $total_fail 件のFAILあり"
  exit 1
fi
echo "test-sync-verify-live-root: 全テストPASS"
exit 0
