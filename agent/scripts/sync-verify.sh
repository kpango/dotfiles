#!/usr/bin/env bash
# agent/sync-manifest.json を読み、claude/pi/agy 各ターゲットの実際の配線を検証する。
# 「リポジトリ側は正しいがライブ環境(~/.claude 等)への反映を忘れている」というクラスの事故
# (2026-09-02 pi-agent-config-consolidation ミッション後、make install の実行漏れで
# SWARM.md/SWARM_REFERENCES.md が全エコシステムでライブ環境のみ壊れていた実例)を機械検出する
# ために新設した。
#
# 2026-09-03: リポジトリ内のclaude/pi/agy側symlink(claude/rules・claude/agents・claude/RTK.md等)を
# 全廃し、Makefile.d/install.mkがagent/から$HOME側へ直接symlinkする設計に一本化したのに伴い、
# 旧`symlink`/`symlink-per-entry`/`live-copy-or-symlink`の3modeを`live-symlink`(常に$HOME側のみを
# 検証)と`generate`(リポジトリ側の生成物の鮮度 + 任意でlive_pathのライブ検証)の2modeへ統合した。
# pi/agentsは同日中の後続ミッション(agent-hooks-and-pi-agents-unification)でgenerate方式から
# live-symlink方式へ移行済みだが、`generate`modeは現役——AGENTS.md/SYSTEM.mdのpi/agy/gemini向け
# targetが計6件(agent/sync-manifest.json参照、agent/scripts/gen-{agents,system}-md-for-{pi,agy}.sh
# 経由)`verify_generate()`を使い続けている。pi/agentsの1entryが移行しただけで、generate mode自体を
# 廃止したわけではない。
#
# usage: agent/scripts/sync-verify.sh
# exit: 0 = 全entry PASS, 1 = 1件以上FAIL(詳細を stderr に列挙)
#
# 実装メモ:
# - manifest の行読み出しをパイプ(`cmd | while read`)にすると while がサブシェルで走り
#   fail_count が親シェルへ伝播しない(bash既知の罠)。本スクリプトは manifest 全行を
#   mapfile で先にメインシェルの配列へ読み切ってから `for line in "${arr[@]}"` でループする
#   ことでこれを回避している(下記 manifest_lines 定義箇所参照)。
# - 区切り文字は tab ではなく `|` を使う: bash の `read` は IFS に空白class文字
#   (space/tab/newline)を設定すると、POSIXのフィールド分割と異なり連続する区切り文字を
#   1つに畳み込む(awkのデフォルト分割と同じ挙動)。本manifestは "script"/"live_path" フィールドが
#   live-symlinkモードでは空文字になるため、tab区切りだと空フィールドの前後でタブが連続し
#   後続フィールドがずれる実害が過去にあった。`|` は空白class外の文字のためこの問題が起きない。
# - `mapfile -t arr < <(cmd)` は process substitution の exit status を捕捉しない
#   (`set -o pipefail` の対象は `|` パイプのみで `<(...)` には効かない) ため、python3 が
#   manifest のパースに失敗しても mapfile 自体は空配列で成功したことになり、後続の
#   for ループが0回で終わって "全entry PASS" と沈黙成功しうる。コマンド置換で出力を先に受け取り、
#   終了コードを明示チェックしてから mapfile する。
set -uo pipefail

root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
manifest="$root/agent/sync-manifest.json"

if [ ! -f "$manifest" ]; then
  echo "FAIL: manifest not found: $manifest" >&2
  exit 1
fi

fail_count=0

fail() {
  echo "FAIL: $1" >&2
  fail_count=$((fail_count + 1))
}

pass() {
  echo "PASS: $1"
}

expand_home() {
  printf '%s' "${1/\$HOME/$HOME}"
}

# --- live-symlink モード: $HOME側のtargetが、リポジトリ内のcanonical(絶対パス)を指す
#     symlinkであることを検証する。docker/copy-install経路(symlinkでなく実体コピー)は対象外
#     (claude/pi/agy install ターゲットは常に ln -sfvn を使うため、通常経路では常にsymlink)。 ---
verify_live_symlink() {
  local name="$1" ecosystem="$2" target_path="$3" canonical="$4"
  local expanded canonical_abs resolved
  expanded="$(expand_home "$target_path")"
  canonical_abs="$root/$canonical"

  if [ ! -e "$expanded" ]; then
    fail "$name/$ecosystem: $target_path が存在しない(make <ecosystem>/install の実行漏れの可能性)"
    return
  fi
  if [ ! -L "$expanded" ]; then
    fail "$name/$ecosystem: $target_path はsymlinkではない(実体コピーになっている、docker/copy-install経路の可能性)"
    return
  fi
  # readlink -f はfile/directoryどちらのsymlinkでも物理パスへ解決できる(GNU coreutils限定、
  # このリポジトリの既存パターンと同じ制約)。
  resolved="$(readlink -f "$expanded" 2>/dev/null)"
  if [ "$resolved" != "$canonical_abs" ]; then
    fail "$name/$ecosystem: $target_path は $canonical ではなく $resolved を指している(配線ミス)"
    return
  fi
  pass "$name/$ecosystem: $target_path -> $canonical"
}

# --- generate モード: 対応スクリプトを --check で実行しリポジトリ側の鮮度を検証。
#     live_path が指定されていれば、そちらは target_path(生成物の実パス)への
#     live-symlinkとして追加検証する。 ---
verify_generate() {
  local name="$1" ecosystem="$2" target_path="$3" script="$4" live_path="$5"
  local abs_script="$root/$script"
  local out
  if [ ! -x "$abs_script" ]; then
    fail "$name/$ecosystem: 生成スクリプト $script が実行可能ではない"
    return
  fi
  if out="$("$abs_script" --check </dev/null 2>&1)"; then
    pass "$name/$ecosystem: $target_path は $script と同期済み"
  else
    fail "$name/$ecosystem: $target_path が $script の生成物と乖離している($(tr '\n' ' ' <<<"$out"))"
  fi
  if [ -n "$live_path" ]; then
    verify_live_symlink "$name" "$ecosystem (live)" "$live_path" "$target_path"
  fi
}

# manifest の全行を先にメモリへ読み切ってから処理する(mapfile、理由は冒頭コメント参照)。
manifest_extract="$(python3 -c "
import json
with open('$manifest') as f:
    m = json.load(f)
for entry in m['entries']:
    name = entry['name']
    canonical = entry.get('canonical', '')
    for eco, t in entry['targets'].items():
        print(f\"{name}|{eco}|{t['path']}|{t['mode']}|{t.get('script','')}|{canonical}|{t.get('live_path','')}\")
" 2>&1)"
manifest_extract_status=$?
if [ "$manifest_extract_status" -ne 0 ]; then
  echo "FAIL: manifest のパースに失敗した(python3 exit=$manifest_extract_status)" >&2
  echo "$manifest_extract" >&2
  exit 1
fi
mapfile -t manifest_lines <<<"$manifest_extract"

for line in "${manifest_lines[@]}"; do
  IFS='|' read -r name ecosystem path mode script canonical live_path <<<"$line"
  case "$mode" in
    live-symlink) verify_live_symlink "$name" "$ecosystem" "$path" "$canonical" ;;
    generate) verify_generate "$name" "$ecosystem" "$path" "$script" "$live_path" ;;
    *) fail "$name/$ecosystem: 未知のmode '$mode'" ;;
  esac
done

echo "---"
if [ "$fail_count" -gt 0 ]; then
  echo "sync-verify: $fail_count 件のFAILあり" >&2
  exit 1
fi
echo "sync-verify: 全entry PASS"
exit 0
