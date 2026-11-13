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
# 廃止したわけではない(2026-10-17、primeagent向けAGENTS.md(agent/harnesses/primeagent/gen-agents-md.sh)
# が加わり計7件)。
#
# 2026-10-17(primeagent-max-customize T11): prime-agent 0.10.0 の live 配置は既存2modeで表せない
# 2形を持つため、modeを2つ足した: `live-symlink-dir`(実ディレクトリ + その中の per-entry symlink 群。
# 期待エントリ集合は manifest の sources からリポジトリ内容で算出) と `live-regular-file`(symlink で
# あってはならない通常ファイル + perm)。既存2modeの挙動は変えていない。
#
# usage: agent/scripts/sync-verify.sh
# env: SYNC_VERIFY_LIVE_ROOT=<path> — live symlink照合(verify_live_symlink)の期待値の基準を
#      このパスに固定する(linked worktree内で実行し、live配線はメインのチェックアウトを指す場合に指定)
#      SYNC_VERIFY_ONLY=<ecosystem> — 指定したecosystem(targetsのキー、例: primeagent)のtargetだけを
#      検証する(primeagent/validate-harness.sh の live 検査が自ハーネス分だけを呼ぶために使う)
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

# --- live_root: live symlink照合(verify_live_symlink)専用の基準パス。$HOME側の実配線は
#     `make <ecosystem>/install` を実行したメインのチェックアウトを指すため、linked worktree内で
#     本スクリプトを実行するとlive照合だけ偽陽性になる(git情報からメインを自動推定する方式は
#     推測の穴が尽きず不採用 — 人間の判断)。SYNC_VERIFY_LIVE_ROOTで明示指定できるようにし、
#     未設定時は従来通りrootを使う。リポジトリ内容のチェック(verify_generateのSTALE判定等)は
#     この変数の影響を受けず、常にrootを使う。
live_root="$root"
if [ -n "${SYNC_VERIFY_LIVE_ROOT:-}" ]; then
  # 既存の「manifest not found」と同じ流儀(即exit 1)を踏襲する: これは呼び出し時の設定ミスであり、
  # 個別entryのFAILとしてfail_countへ積んで他entryの列挙を続ける性質のものではないため。
  if ! live_root="$(cd -P "$SYNC_VERIFY_LIVE_ROOT" 2>/dev/null && pwd)"; then
    echo "FAIL: SYNC_VERIFY_LIVE_ROOT のディレクトリが存在しない: $SYNC_VERIFY_LIVE_ROOT" >&2
    exit 1
  fi
elif git_dir="$(git -C "$root" rev-parse --path-format=absolute --git-dir 2>/dev/null)" \
  && git_common_dir="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  && [ "$git_dir" != "$git_common_dir" ]; then
  echo "NOTE: linked worktree 内で実行中です。live 配線はこの worktree を基準に照合しています。メインのチェックアウトを基準にするには SYNC_VERIFY_LIVE_ROOT=<メインのパス> を指定してください(\`git worktree list\` の先頭行が通常メインです)" >&2
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
  canonical_abs="$live_root/$canonical"

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

# --- live-symlink-dir モード: target_path が(symlinkでない)実ディレクトリであることと、その中に
#     リポジトリへ張られたsymlinkのうち期待集合($4、空白区切り)に無いもの(古いエントリ、
#     install の再実行漏れ)が無いことを検証する。期待エントリ1件ずつの照合は manifest 抽出側が
#     live-symlink 行へ展開済み。利用者が置いた実ファイル・リポジトリ外へのsymlinkは対象外。 ---
verify_live_symlink_dir() {
  local name="$1" ecosystem="$2" target_path="$3" expected=" $4 " expanded l n t stale=""
  expanded="$(expand_home "$target_path")"
  if [ -L "$expanded" ] || [ ! -d "$expanded" ]; then
    fail "$name/$ecosystem: $target_path は実ディレクトリではない(symlinkか不在、make <ecosystem>/install の実行漏れの可能性)"
    return
  fi
  for l in "$expanded"/* "$expanded"/.[!.]*; do
    [ -L "$l" ] || continue
    n="${l##*/}"
    t="$(readlink "$l")"
    case "$t" in "$live_root"/* | "$root"/*) ;; *) continue ;; esac
    case "$expected" in *" $n "*) ;; *) stale="$stale $n" ;; esac
  done
  if [ -n "$stale" ]; then
    fail "$name/$ecosystem: $target_path にリポジトリ側で不要になったsymlinkが残っている:$stale(make <ecosystem>/install の再実行漏れ)"
    return
  fi
  pass "$name/$ecosystem: $target_path は実ディレクトリ(古いエントリ無し)"
}

# --- live-regular-file モード: target_path が symlink ではない通常ファイルで、perm($4、8進、
#     空なら不問)が一致することを検証する(内容は live 側の所有物なので照合しない)。 ---
verify_live_regular_file() {
  local name="$1" ecosystem="$2" target_path="$3" perm="$4" expanded actual
  expanded="$(expand_home "$target_path")"
  if [ -L "$expanded" ]; then
    fail "$name/$ecosystem: $target_path がsymlinkになっている(通常ファイルでなければならない)"
    return
  fi
  if [ ! -f "$expanded" ]; then
    fail "$name/$ecosystem: $target_path が存在しないか通常ファイルではない(make <ecosystem>/install の実行漏れの可能性)"
    return
  fi
  if ! actual="$(stat -c %a "$expanded" 2>&1)"; then
    fail "$name/$ecosystem: $target_path のpermを取得できない: $actual"
    return
  fi
  if [ -n "$perm" ] && [ "$actual" != "$perm" ]; then
    fail "$name/$ecosystem: $target_path のpermが $actual (期待値 $perm)"
    return
  fi
  pass "$name/$ecosystem: $target_path は通常ファイル${perm:+ (perm $perm)}"
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
# live-symlink-dir は期待エントリ(sources から算出)ごとに live-symlink 行へ展開し、ディレクトリ自体の
# 検査行(第8フィールド=期待エントリ名の空白区切り)を1行出す。sources の各要素は
#   {"dir": D, "list": F}   — F(# 以降と空白を除いた非空行)に並ぶ名前。D/<名前> が無ければ error 行
#   {"dir": D, "marker": M} — D 直下で M を持つサブディレクトリ名
# live-regular-file は第8フィールドに perm を載せる。
manifest_extract="$(SV_MANIFEST="$manifest" SV_ROOT="$root" SV_ONLY="${SYNC_VERIFY_ONLY:-}" python3 -c "
import json, os
root = os.environ['SV_ROOT']
only = os.environ['SV_ONLY']
with open(os.environ['SV_MANIFEST']) as f:
    m = json.load(f)
def names(src):
    d = os.path.join(root, src['dir'])
    if 'list' in src:
        out = []
        with open(os.path.join(root, src['list'])) as f:
            for line in f:
                n = ''.join(line.split('#', 1)[0].split())
                if n:
                    if not os.path.exists(os.path.join(d, n)):
                        raise ValueError(f\"{src['list']} names '{n}' but {src['dir']}/{n} does not exist\")
                    out.append(n)
        return out
    return sorted(n for n in os.listdir(d) if os.path.isfile(os.path.join(d, n, src['marker'])))
for entry in m['entries']:
    name = entry['name']
    canonical = entry.get('canonical', '')
    for eco, t in entry['targets'].items():
        if only and eco != only:
            continue
        mode = t['mode']
        if mode == 'live-symlink-dir':
            try:
                pairs = [(n, src['dir']) for src in t['sources'] for n in names(src)]
            except (OSError, KeyError, ValueError) as e:
                print(f\"{name}|{eco}|{t['path']}|error||||{e}\")
                continue
            seen = [n for n, _ in pairs]
            dup = sorted({n for n in seen if seen.count(n) > 1})
            if dup:
                print(f\"{name}|{eco}|{t['path']}|error||||entry names in more than one source: {' '.join(dup)}\")
                continue
            print(f\"{name}|{eco}|{t['path']}|{mode}||{canonical}||{' '.join(seen)}\")
            for n, d in pairs:
                print(f\"{name}|{eco}|{t['path']}/{n}|live-symlink||{d}/{n}||\")
            continue
        print(f\"{name}|{eco}|{t['path']}|{mode}|{t.get('script','')}|{canonical}|{t.get('live_path','')}|{t.get('perm','')}\")
" 2>&1)"
manifest_extract_status=$?
if [ "$manifest_extract_status" -ne 0 ]; then
  echo "FAIL: manifest のパースに失敗した(python3 exit=$manifest_extract_status)" >&2
  echo "$manifest_extract" >&2
  exit 1
fi
if [ -n "${SYNC_VERIFY_ONLY:-}" ] && [ -z "$manifest_extract" ]; then
  echo "FAIL: SYNC_VERIFY_ONLY=$SYNC_VERIFY_ONLY に該当するtargetが manifest に無い" >&2
  exit 1
fi
mapfile -t manifest_lines <<<"$manifest_extract"

for line in "${manifest_lines[@]}"; do
  IFS='|' read -r name ecosystem path mode script canonical live_path extra <<<"$line"
  case "$mode" in
    live-symlink) verify_live_symlink "$name" "$ecosystem" "$path" "$canonical" ;;
    generate) verify_generate "$name" "$ecosystem" "$path" "$script" "$live_path" ;;
    live-symlink-dir) verify_live_symlink_dir "$name" "$ecosystem" "$path" "$extra" ;;
    live-regular-file) verify_live_regular_file "$name" "$ecosystem" "$path" "$extra" ;;
    error) fail "$name/$ecosystem: $extra" ;;
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
