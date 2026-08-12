#!/usr/bin/env bash
# Regression tests for self-improve-register.sh (自己改善ミッション registry 登録)。
# 様式: swarm-implement/scripts/test-fable-guard.sh / swarm-meta/scripts/test-harness-guard.sh
#       準拠 (set -u / mktemp -d 隔離 / check() / PASS・FAIL 集計 / 失敗 1 件以上で exit 1)。
#
# ケース番号対応表:
#   1  sanity: flock を PATH から隠す手法が実際に command -v flock を失敗させることの確認
#      (util-linux 未導入環境の決定的シミュレーション)
#   2  (回帰防止) flock が到達可能な通常 PATH → 既存動作 (新規登録・冪等スキップ) は不変。
#      この実行環境に flock が全く存在しない場合は skip する
#   3  (regression) flock (util-linux) 未導入環境で fail-closed する回帰テスト。
#      exit 1 + actionable stderr (FLOCK_MISSING) + registry 無変更。
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_SCRIPT="$here/self-improve-register.sh"

export HOME="$(mktemp -d)"   # 実カウンタ類を汚さない隔離 HOME (既存 test の慣習に合わせる)
WORK="$(mktemp -d)"          # フィクスチャ・一時ファイル置き場
trap 'rm -rf "$HOME" "$WORK"' EXIT

pass=0 fail=0
check() { # check <desc> <expected-exit> <actual-exit> [<must-match> <output>]
  local desc="$1" want="$2" got="$3" pat="${4:-}" out="${5:-}"
  if [ "$want" != "$got" ]; then
    echo "FAIL: $desc (exit want=$want got=$got)"; fail=$((fail+1)); return
  fi
  if [ -n "$pat" ] && ! grep -q "$pat" <<<"$out"; then
    echo "FAIL: $desc (output missing '$pat'): $out"; fail=$((fail+1)); return
  fi
  echo "ok: $desc"; pass=$((pass+1))
}

# self-improve-register.sh は registry パスを $(dirname "$0")/../self-improve-registry.tsv で
# 解決する (HARNESS_REGISTRY のような env override が無い)。実 registry を汚さないよう、
# script を隔離 skill ディレクトリへコピーし「scripts/」の1階層上に自前の registry を置く
# (実レイアウト claude/skills/swarm-loop/{self-improve-registry.tsv,scripts/self-improve-register.sh}
# をそのまま再現する)。
# self-improve-register.sh はさらに flock-guard-lib.sh を
# "$(dirname "${BASH_SOURCE[0]}")/../../swarm-implement/scripts/flock-guard-lib.sh" という
# skill 間相対パスで source する (実レイアウト claude/skills/{swarm-loop,swarm-implement}/scripts/
# が兄弟であることに依存)。フィクスチャでもこの兄弟レイアウトを再現しないと、source 先が
# 見つからず require_flock を経由しない別の失敗 (No such file or directory) を拾ってしまう。
SKILLROOT="$WORK/skill-copy"
mkdir -p "$SKILLROOT/scripts"
cp "$REAL_SCRIPT" "$SKILLROOT/scripts/self-improve-register.sh"
SCRIPT="$SKILLROOT/scripts/self-improve-register.sh"
REGISTRY="$SKILLROOT/self-improve-registry.tsv"

REAL_FLOCK_GUARD_LIB="$here/../../swarm-implement/scripts/flock-guard-lib.sh"
mkdir -p "$WORK/swarm-implement/scripts"
cp "$REAL_FLOCK_GUARD_LIB" "$WORK/swarm-implement/scripts/flock-guard-lib.sh"

BASHBIN="$(command -v bash)"

# flock を含まない最小 PATH を構築し、util-linux 未導入環境を決定的にシミュレートする。
# 対象スクリプトが使う外部コマンドのみ symlink し、flock は意図的に含めない。
# ビルドは clean な bash -c 内で行う (対話シェルの alias 定義に汚染されないため)。
make_noflock_bin() {
  local dir="$1"
  mkdir -p "$dir"
  "$BASHBIN" -c '
    dir="$1"; shift
    for name in "$@"; do
      real="$(command -v "$name" 2>/dev/null)"
      case "$real" in
        /*) ln -sf "$real" "$dir/$name" ;;
      esac
    done
  ' _ "$dir" cat mv date awk cut mkdir rm sleep tail wc grep dirname find sed tr touch
}

NOFLOCK_BIN="$WORK/noflock-bin"
make_noflock_bin "$NOFLOCK_BIN"

# ============================================================
# Case 1: sanity — 上記手法で command -v flock が確実に失敗すること
# (このホストに元々 flock が無いことに依存しない — flock がある環境でも同じ手法で
# 決定的に隠せることを保証する)。
# ============================================================
PATH="$NOFLOCK_BIN" "$BASHBIN" -c 'command -v flock' >/dev/null 2>&1
check "case1: sanity - flock hidden from restricted PATH" 1 $? "" ""
PATH="$NOFLOCK_BIN" "$BASHBIN" -c 'echo x | cat >/dev/null && date >/dev/null && echo ok' >/dev/null 2>&1
check "case1: sanity - restricted PATH still resolves other needed commands" 0 $? "" ""

# ============================================================
# Case 2 (回帰防止): flock が到達可能な通常 PATH → 既存動作 (新規登録 + 冪等スキップ) は不変。
# この実行環境に flock が全く存在しない場合は spurious failure を避け skip する。
# ============================================================
if command -v flock >/dev/null 2>&1; then
  printf '' >"$REGISTRY"
  out2a=$(bash "$SCRIPT" case2-slug 2026-08-12 targetA,targetB 2>&1); rc2a=$?
  check "case2a (regression): first registration succeeds unchanged" 0 "$rc2a" "REGISTERED: case2-slug" "$out2a"
  lines2a=$(wc -l <"$REGISTRY")
  [ "$lines2a" -eq 1 ]
  check "case2a: registry gains exactly 1 row" 0 $? "" ""

  out2b=$(bash "$SCRIPT" case2-slug 2026-08-12 targetA,targetB 2>&1); rc2b=$?
  check "case2b (regression): re-registering same slug is an idempotent no-op unchanged" 0 "$rc2b" "SKIP: case2-slug already registered" "$out2b"
  lines2b=$(wc -l <"$REGISTRY")
  [ "$lines2b" -eq 1 ]
  check "case2b: registry still has exactly 1 row (no duplicate)" 0 $? "" ""
else
  echo "SKIP: case2 - this host has no flock anywhere on PATH; cannot exercise the happy-path mirror"
fi

# ============================================================
# Case 3 (TDAD Red): flock (util-linux) 未導入環境で fail-closed する回帰テスト
# (self-improve-register.sh line 30 `flock -x 200` の存在ガード欠落の回帰。
#  ガード未実装の現状は exit 127 でクラッシュする — Red)。
# ============================================================
printf '' >"$REGISTRY"
before3="$(cat "$REGISTRY")"

out3=$(PATH="$NOFLOCK_BIN" "$BASHBIN" "$SCRIPT" case3-slug 2026-08-12 targetX 2>&1); rc3=$?
check "case3: self-improve-register.sh fails closed (exit 1) when flock is unavailable" 1 "$rc3" "FLOCK_MISSING" "$out3"

after3="$(cat "$REGISTRY")"
[ "$before3" = "$after3" ]
check "case3: registry is NOT modified when the flock guard fires (fail-closed, no partial write)" 0 $? "" ""

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
