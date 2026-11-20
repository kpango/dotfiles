#!/usr/bin/env bash
# PostToolUse:Write|Edit hook — async post-write lint trigger
set -euo pipefail

INPUT=$(cat)

if ! command -v jq &>/dev/null; then
    exit 0
fi

# file_path と session_id(下記コメント参照)を jq 1 回で取り出す(旧: 2 回起動)。
# 旧実装と挙動を一致させるための要点:
#  - 旧 file_path は `jq -r` の非 slurp 実行で、実行時エラーの入力だけが読み飛ばされ、パースエラーでのみ
#    打ち切られた(それ以前の出力は残る)。per-doc の try/catch empty が同じ挙動になる。
#  - 旧 session_id は `jq -rs`(slurp)で、パースエラー時は出力無し→"unknown"。ここでは入力終端の
#    番兵(null)到達時にだけ session_id を出力するため、パースエラー時は未出力→"unknown"になる。
#    sid の本体は旧フィルタと同一(`.[0]` を持つ 1 要素配列/空配列へ適用する)。
#  - jq への入力・出力は `printf | jq | { read … }` のパイプだけで受け渡す(一時ファイルも /dev/fd も
#    使わない)。here-string/here-doc は bash が約 64KB 超で一時ファイルを使い、process substitution は
#    /dev/fd(procfs)に依存する。いずれも使えない環境ではリダイレクト失敗で jq の出力が空になり、
#    空のまま `exit 0`(fail-open)に落ちる(旧 `echo | jq` はパイプのみで deny した)。read グループは
#    `shopt -s lastpipe` でパイプ最後の要素として現在のシェルで走り、変数が残る(非対話シェルなので有効)。
#  - 送信側は `{ … } 2>/dev/null` で包む。lastpipe だとシェル自身が「強制終了」「Broken pipe」等のジョブ状態を
#    stderr に出すため(jq 異常終了時や jq が入力を読み切らず終わるとき)、旧と同じ静かな stderr に保つ。
#  - U+0000 は jq 側で `split("\u0000")[]` により、結合せずに出力ストリームへ順に流して除去する(線形)。
#    gsub と split|join は NUL が多いと二次式で遅く hook timeout(fail-open)に達した。
#  - 末尾改行の除去は `$(printf '%s' "$x")`(旧 $() と同じ線形の意味)。`${x%"${x##*[!$'\n']}"}` 形は
#    末尾の改行数に対して二次式で、3 万個で hook timeout に達した。
#  - lastpipe はジョブ制御が有効だと効かない(SHELLOPTS=monitor 等で read ループが subshell になり、値が
#    空のまま `exit 0`=fail-open になる)。`set +m` で無効化し、それでも効かない場合は自己検査
#    (`: | _lp=1`)で検出して、旧実装と同一の 2 回 jq 方式へフォールバックする(base と同じ判定になる側)。
#  - 制約(既知): `read -d ''` は 1 バイトずつ読むため、16MB 級の値では hook timeout(5 秒)を超えうる。
#  - 値は NUL 区切りレコード(タグ NUL 値 "\n" NUL)。@tsv と違いエスケープ復元が不要で、非文字列値は
#    旧 `-r` と同じ pretty 出力。値中の U+0000 は旧 $() が捨てていたため jq 側で除去する。
set +m
shopt -s lastpipe
_lp=0
: | _lp=1
FILE_PATH="" SESSION_ID=""
if [ "$_lp" = 1 ]; then
{ printf '%s\n' "$INPUT" | jq -nj '
  def c: if type == "string" then split("\u0000")[] else . end;
  def sid: (.[0] | if type == "object" then .session_id else null end) as $s | if ($s | type) == "string" and ($s | test("\\A[A-Za-z0-9._-]+\\z")) and $s != "." and $s != ".." then $s else "unknown" end;
  foreach ((inputs | [.]), null) as $x ({n: 0, a: []};
      if $x == null then . else .n += 1 | (if .n == 1 then .a = $x else . end) end;
      if $x == null then (.a | sid | ("s\u0000", ., "\n\u0000"))
      else (($x[0] | try (.tool_input.file_path // empty) catch empty) | ("f\u0000", c, "\n\u0000")) end)
' 2>/dev/null; } 2>/dev/null | {
    while IFS= read -r -d '' _tag && IFS= read -r -d '' _val; do
        case "$_tag" in f) FILE_PATH+="$_val" ;; s) SESSION_ID+="$_val" ;; esac
    done
} || true
  FILE_PATH=$(printf '%s' "$FILE_PATH")
  SESSION_ID=${SESSION_ID%$'\n'} # 値は検証済み文字集合か unknown のみ(改行を含まない)。終端の 1 個だけ除去
else
  # lastpipe 無効: 旧実装と同一の抽出(2 回 jq)
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT" | jq -rs '(.[0] | if type == "object" then .session_id else null end) as $s | if ($s | type) == "string" and ($s | test("\\A[A-Za-z0-9._-]+\\z")) and $s != "." and $s != ".." then $s else "unknown" end' 2>/dev/null || echo unknown)
fi
[[ -z "$FILE_PATH" ]] && exit 0

EXT="${FILE_PATH##*.}"

# Log the write for audit trail
LOG_DIR="$HOME/.claude/session-data"
mkdir -p "$LOG_DIR"
# session_id comes from the hook's stdin JSON (a documented common hook input field;
# the undocumented CLAUDE_SESSION_ID env var is not used). jq validates the JSON
# value: it must be a string made only of ASCII A-Z a-z 0-9 . _ - and not "." or ".."
# (the same allowed set as `agent/scripts/test-hook-session-id.sh`'s
# `_sanitize_session_id`), otherwise "unknown". Checking in jq rather than with bash
# `[[ =~ ]]` avoids two problems: bash range matching is locale-dependent, and $()
# strips a trailing newline before bash could see it. \A...\z is used because `$` also
# matches just before a final newline.
SESSION_ID=${SESSION_ID:-unknown}
echo "[$(date '+%H:%M:%S')] write: $FILE_PATH" >> "$LOG_DIR/${SESSION_ID:0:8}-writes.log" 2>/dev/null || true

# Async validation for config and script files
case "$EXT" in
    json)
        if command -v python3 &>/dev/null; then
            python3 -m json.tool "$FILE_PATH" > /dev/null 2>&1 || \
                echo "WARNING: $FILE_PATH may have invalid JSON" >&2
        fi
        ;;
    yaml|yml)
        if command -v python3 &>/dev/null; then
            python3 -c "
import sys
try:
    import yaml
    yaml.safe_load(open(sys.argv[1]))
except ImportError:
    pass
except Exception as e:
    print(f'WARNING: {sys.argv[1]} may have invalid YAML: {e}', file=sys.stderr)
" "$FILE_PATH" 2>&1 || true
        fi
        ;;
    toml)
        if python3 -c "import tomllib" 2>/dev/null; then
            python3 -c "
import sys, tomllib
try:
    tomllib.load(open(sys.argv[1], 'rb'))
except Exception as e:
    print(f'WARNING: {sys.argv[1]} may have invalid TOML: {e}', file=sys.stderr)
" "$FILE_PATH" 2>&1 || true
        fi
        ;;
    sh|bash)
        bash -n -- "$FILE_PATH" 2>&1 || \
            echo "WARNING: $FILE_PATH has shell syntax errors" >&2
        ;;
    go)
        # agy/hooks/post-edit-lint.sh 同様 gofmt を使うが、claude側は読み取り専用方針
        # (agyは -w で自動整形するが、claudeは書き込みを警告表示に留める既存の意図的な差異)
        # のため -l (要整形ファイル一覧、パース不能なら stderr にエラー) に留める。
        if command -v gofmt &>/dev/null; then
            ERR=$(gofmt -l -- "$FILE_PATH" 2>&1 >/dev/null) || true
            [[ -n "$ERR" ]] && echo "WARNING: $FILE_PATH has Go syntax errors: $ERR" >&2
        fi
        ;;
    py)
        if command -v python3 &>/dev/null; then
            PYERR=$(python3 -m py_compile -- "$FILE_PATH" 2>&1 >/dev/null) || true
            [[ -n "$PYERR" ]] && echo "WARNING: $FILE_PATH may have invalid Python: $PYERR" >&2
        fi
        ;;
esac

exit 0
