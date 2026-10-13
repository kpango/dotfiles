#!/usr/bin/env bash
# Regression tests for agent/scripts/gen-tool-agents.sh・gen-tool-system.sh (T5)。
# 様式: test-sync-verify-live-root.sh 準拠 (mktemp -d 隔離 / section() / [OK]・[FAIL] /
# total_fail 集計 / trap による後片付け)。
#
# 背景: 両generatorは command substitution (`generated="$(...)"`) が末尾改行を全て
# 剥ぎ取ってしまうため、`printf '%s' "$generated" > "$dst"` で書き出すと生成物が末尾改行
# 無しになる一方、commit済みの pi/agy 向け AGENTS.md・SYSTEM.md は(このリポジトリの
# Style Notesに合わせ)末尾改行1つを持つ。この不一致により `gen-*.sh --check` と
# sync-verify.sh が常時STALEを誤検出していた。修正は書き出し側で `printf '%s\n'` に
# 変更し、末尾改行ちょうど1つで揃えること。
#
# もう一つの回帰対象は引数検証: 両generatorは元々 `${2:-}` を素通しで見ていたため、
# `gen-tool-agents.sh pi --stdout` のような未知の第2引数が --check 扱いされず、
# 気づかれないまま書き込みモードへ倒れてしまっていた(オーケストレーターが実際に踏んだ事故)。
# 修正は受理形式([pi|agy|all] [--check]、計2引数まで)以外を早期にusage+exit 2する。
#
# 本テストは実際の生成物 (agent/harnesses/{pi,agy}/{AGENTS,SYSTEM}.md) を一切書き換えない:
# (a)(c) は --check のみで確認し、(b) は隔離した一時ディレクトリへ入力一式をコピーしてから
# 未知引数を渡し、コピー側のハッシュ/mtimeが変化しないことを確認する。
#
# usage: agent/scripts/test-gen-tool-md.sh
# exit: 0 = 全テストPASS, 1 = 1件以上FAIL
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
total_fail=0
section() { echo; echo "=== $1 ==="; }

check() { # check <desc> <cond: 0=pass>
  local desc="$1" cond="$2"
  if [ "$cond" -eq 0 ]; then
    echo "[OK] $desc"
  else
    echo "[FAIL] $desc"
    total_fail=$((total_fail + 1))
  fi
}

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# --- (b)用の隔離コピー: 実リポジトリのgeneratorと入力一式を$WORK配下に複製する -----------
# root解決 (`$(dirname "$0")/../..`) を成立させるため、agent/scripts/以下と、
# gen_oneが参照する core・supplement・生成先ファイルのみを同じ相対パスで複製する。
ISO="$WORK/iso"
mkdir -p "$ISO/agent/scripts" "$ISO/agent/harnesses/pi" "$ISO/agent/harnesses/agy"
cp "$ROOT/agent/scripts/gen-tool-agents.sh" "$ISO/agent/scripts/gen-tool-agents.sh"
cp "$ROOT/agent/scripts/gen-tool-system.sh" "$ISO/agent/scripts/gen-tool-system.sh"
# T15: both generators now source this lib; copy it too so the isolated (b) run works.
cp "$ROOT/agent/scripts/harness-check-lib.sh" "$ISO/agent/scripts/harness-check-lib.sh"
cp "$ROOT/agent/AGENTS.md" "$ISO/agent/AGENTS.md"
cp "$ROOT/agent/AGENTS-pi-supplement.md" "$ISO/agent/AGENTS-pi-supplement.md"
cp "$ROOT/agent/AGENTS-agy-supplement.md" "$ISO/agent/AGENTS-agy-supplement.md"
cp "$ROOT/agent/SYSTEM.md" "$ISO/agent/SYSTEM.md"
cp "$ROOT/agent/SYSTEM-pi-supplement.md" "$ISO/agent/SYSTEM-pi-supplement.md"
cp "$ROOT/agent/SYSTEM-agy-supplement.md" "$ISO/agent/SYSTEM-agy-supplement.md"
cp "$ROOT/agent/harnesses/pi/AGENTS.md" "$ISO/agent/harnesses/pi/AGENTS.md"
cp "$ROOT/agent/harnesses/agy/AGENTS.md" "$ISO/agent/harnesses/agy/AGENTS.md"
cp "$ROOT/agent/harnesses/pi/SYSTEM.md" "$ISO/agent/harnesses/pi/SYSTEM.md"
cp "$ROOT/agent/harnesses/agy/SYSTEM.md" "$ISO/agent/harnesses/agy/SYSTEM.md"

# ------------------------------------------------------------------
section "bash -n: generator本体の構文確認"
check "gen-tool-agents.sh" $(bash -n "$ROOT/agent/scripts/gen-tool-agents.sh" 2>/dev/null; echo $?)
check "gen-tool-system.sh" $(bash -n "$ROOT/agent/scripts/gen-tool-system.sh" 2>/dev/null; echo $?)

# ------------------------------------------------------------------
# T18 Checker指摘(試行1の後退): harness_parse_tool_args()の最後の行が
# `[[ "$HARNESS_CHECK_FLAG" == "--check" ]] && HARNESS_CHECK_ONLY=1` という`&&`の
# ショートハンドで、check_flagが"--check"でない(=通常の書き込みモード)場合に
# `[[ ]]`自体の(偽の)終了statusをそのまま関数の戻り値にしてしまう。呼び出し側は
# `set -euo pipefail`下で`if`/`&&`/`||`に包まずトップレベルで呼ぶため、errexitが
# 書き込みモードの通常実行それ自体を(何も書き込まないまま)殺していた
# (`gen-tool-agents.sh all`が出力無し・exit 1で終わり、生成物が一切更新されない)。
# 下記(a)は元々この後退を検知できなかった: `set -e`が無く(b)行の終了statusを見ておらず、
# ISOには最初からcommit済みの生成物をコピー済み(48-62行目)なので、書き込みが何も
# 起きなくても(a)(a')は「たまたま」通っていた。
#
# (a-0) は書き込みモード呼び出し自体の終了statusを直接検査し、(a-1) は
# 「supplementを1行追記してstaleにした状態から書き込みモードを実行すると、
# 生成物に実際にその1行が反映される」ことを検査する — ISOに最初からコピー済みの
# 生成物がそのまま「たまたま」通ることがない、実際の変更が伝播したかの検査。
section "(a-0)/(a-1) 書き込みモードの終了statusと、staleな状態からの実更新"
MARKER_LINE="T18-mutation-marker-$$-$RANDOM"
cp "$ISO/agent/AGENTS-pi-supplement.md" "$ISO/agent/AGENTS-pi-supplement.md.orig"
printf '\n%s\n' "$MARKER_LINE" >> "$ISO/agent/AGENTS-pi-supplement.md"
check "staleセットアップ直後はまだマーカーを含まない(前提の健全性)" \
  $(grep -qF "$MARKER_LINE" "$ISO/agent/harnesses/pi/AGENTS.md" && echo 1 || echo 0)

write_status=0
(cd "$ISO" && bash agent/scripts/gen-tool-agents.sh pi >/dev/null 2>&1) || write_status=$?
check "gen-tool-agents.sh pi (書き込みモード): exit 0" "$write_status"
check "書き込みモード後、生成物にマーカーが反映されている(staleからの実更新)" \
  $(grep -qF "$MARKER_LINE" "$ISO/agent/harnesses/pi/AGENTS.md" && echo 0 || echo 1)

# supplementをマーカー追記前の状態に戻す — 以降の(a)(a')が汚染された状態で
# 「commit済みの現物と一致するはず」と誤って検査してしまわないようにする。
mv "$ISO/agent/AGENTS-pi-supplement.md.orig" "$ISO/agent/AGENTS-pi-supplement.md"

# ------------------------------------------------------------------
section "(a) generatorの書き込み出力が末尾改行ちょうど1つで終わる"
# 隔離コピー側で実際に書き込みモードを走らせ、書いたファイルの末尾を検査する
# (実リポジトリのagent/harnesses/配下は一切触らない)。上の(a-0)/(a-1)がsupplementを
# 汚しているので、ここで改めて全ツール分を書き込み直し、以降の(a')(b)がcommit済みの
# 現物と一致する状態に戻す。
write_status_agents=0
write_status_system=0
(cd "$ISO" && bash agent/scripts/gen-tool-agents.sh all >/dev/null) || write_status_agents=$?
(cd "$ISO" && bash agent/scripts/gen-tool-system.sh all >/dev/null) || write_status_system=$?
check "gen-tool-agents.sh all (書き込みモード): exit 0" "$write_status_agents"
check "gen-tool-system.sh all (書き込みモード): exit 0" "$write_status_system"
for f in agent/harnesses/pi/AGENTS.md agent/harnesses/agy/AGENTS.md \
         agent/harnesses/pi/SYSTEM.md agent/harnesses/agy/SYSTEM.md; do
  tail2="$(tail -c 2 "$ISO/$f" | od -An -c | tr -d ' \n')"
  # 末尾2バイトが "\n\n"(改行2つ)ではなく、末尾1バイトが"\n"(改行1つ)であること。
  last1="$(tail -c 1 "$ISO/$f" | od -An -c | tr -d ' \n')"
  cond=1
  if [ "$last1" = '\n' ] && [ "$tail2" != '\n\n' ]; then
    cond=0
  fi
  check "$f は末尾改行ちょうど1つ" "$cond"
done

section "(a') 生成した内容がcommit済みの現物と一致する(往復確認)"
for f in agent/harnesses/pi/AGENTS.md agent/harnesses/agy/AGENTS.md \
         agent/harnesses/pi/SYSTEM.md agent/harnesses/agy/SYSTEM.md; do
  check "$f はcommit済みの $ROOT/$f と完全一致" \
    $(diff -q "$ISO/$f" "$ROOT/$f" >/dev/null 2>&1; echo $?)
done

# ------------------------------------------------------------------
section "(b) 未知引数(--stdout等)はusage+exit 2、生成物は一切書き換えない"
# 隔離コピーを基準にする: 直前の(a)で書き込み済みの現物ハッシュ/mtimeを記録してから、
# 未知引数を渡して差分が無いことを確認する。
before_hash_pi="$(sha256sum "$ISO/agent/harnesses/pi/AGENTS.md")"
before_mtime_pi="$(stat -c %Y "$ISO/agent/harnesses/pi/AGENTS.md")"

out="$(cd "$ISO" && bash agent/scripts/gen-tool-agents.sh pi --stdout 2>&1)"; status=$?
check "gen-tool-agents.sh pi --stdout: exit 2" $([ "$status" -eq 2 ] && echo 0 || echo 1)
check "gen-tool-agents.sh pi --stdout: usageをstderrに出す" $([[ "$out" == *"usage:"* ]] && echo 0 || echo 1)

after_hash_pi="$(sha256sum "$ISO/agent/harnesses/pi/AGENTS.md")"
after_mtime_pi="$(stat -c %Y "$ISO/agent/harnesses/pi/AGENTS.md")"
check "未知引数実行後もハッシュ不変" $([ "$before_hash_pi" = "$after_hash_pi" ] && echo 0 || echo 1)
check "未知引数実行後もmtime不変" $([ "$before_mtime_pi" = "$after_mtime_pi" ] && echo 0 || echo 1)

out2="$(cd "$ISO" && bash agent/scripts/gen-tool-agents.sh foo 2>&1)"; status2=$?
check "gen-tool-agents.sh foo: exit 2" $([ "$status2" -eq 2 ] && echo 0 || echo 1)

out3="$(cd "$ISO" && bash agent/scripts/gen-tool-agents.sh pi --check extra 2>&1)"; status3=$?
check "gen-tool-agents.sh pi --check extra (3引数): exit 2" $([ "$status3" -eq 2 ] && echo 0 || echo 1)

out4="$(cd "$ISO" && bash agent/scripts/gen-tool-agents.sh --check pi 2>&1)"; status4=$?
check "gen-tool-agents.sh --check pi (順序違い): exit 2" $([ "$status4" -eq 2 ] && echo 0 || echo 1)

out5="$(cd "$ISO" && bash agent/scripts/gen-tool-system.sh agy --xyz 2>&1)"; status5=$?
check "gen-tool-system.sh agy --xyz: exit 2" $([ "$status5" -eq 2 ] && echo 0 || echo 1)
check "gen-tool-system.sh agy --xyz: usageをstderrに出す" $([[ "$out5" == *"usage:"* ]] && echo 0 || echo 1)

# ------------------------------------------------------------------
section "(c) --check は実リポジトリの4生成物すべてでexit 0(同期済み)を返す"
for wrapper in gen-agents-md-for-pi gen-agents-md-for-agy gen-system-md-for-pi gen-system-md-for-agy; do
  out="$(bash "$ROOT/agent/scripts/${wrapper}.sh" --check 2>&1)"; status=$?
  check "${wrapper}.sh --check: exit 0" $([ "$status" -eq 0 ] && echo 0 || echo 1)
  check "${wrapper}.sh --check: STALEを報告しない" $([[ "$out" != *"STALE"* ]] && echo 0 || echo 1)
done

echo
echo "---"
if [ "$total_fail" -gt 0 ]; then
  echo "test-gen-tool-md: $total_fail 件のFAILあり"
  exit 1
fi
echo "test-gen-tool-md: 全テストPASS"
exit 0
