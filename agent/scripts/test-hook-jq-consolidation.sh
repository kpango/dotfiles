#!/usr/bin/env bash
# agent/hooks/claude/{swarm-write-scope-gate,post-write}.sh の jq 起動回数削減(複数回→1回)が
# 判定結果・出力・終了コードを一切変えていないことを、統合前(BASE)と統合後(NEW)の同一入力表に対する
# 完全比較で固定する回帰テスト。swarm-write-scope-gate.sh は Tier B 書き込み保護のセキュリティゲート
# (impact-C)であり、fail-open/fail-closed の取り違えを機械的に検出する。
#
# 比較対象(ケースごと、BASE と NEW でそれぞれ隔離 HOME・同一 stdin で実行):
#   - 標準出力 / 標準エラー / 終了コード
#   - 副作用: 隔離 HOME 配下の全ファイルの相対パスと内容(時刻・epoch 値は正規化)
# 追加の表明:
#   - jq 起動回数(PATH 先頭の計数 stub)は NEW が BASE 以下、かつ「通常ケース」では 1 回
#
# BASE の取得: 環境変数 BASE_TREE(agent/ を含むツリー)があればそれを使う。無ければ BASE_REV
# (統合直前のコミット)から `git archive` で一時ディレクトリへ展開する。NEW は NEW_TREE
# (既定: このリポジトリ)。mutation チェックは NEW_TREE に壊した複製を指して行う。
#
# usage: agent/scripts/test-hook-jq-consolidation.sh
# exit: 0 = 全ケース一致, 1 = 1 件以上不一致
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NEW_TREE="${NEW_TREE:-$ROOT}"
BASE_REV="${BASE_REV:-6bba0630a85682e0d174384a5e564681665a6bdb}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0
ok() { pass=$((pass + 1)); }
ng() {
    fail=$((fail + 1))
    echo "[FAIL] $1"
}

REAL_JQ="$(command -v jq || true)"
if [[ -z "$REAL_JQ" ]]; then
    echo "[SKIP] jq not installed"
    exit 0
fi

BASE_TREE="${BASE_TREE:-}"
if [[ -z "$BASE_TREE" ]]; then
    # BASE_REV predates the squashed history and is absent from the remote (and from shallow CI clones).
    if ! (cd "$ROOT" && git cat-file -e "${BASE_REV}^{commit}") 2>/dev/null; then
        echo "[SKIP] BASE_REV=$BASE_REV is not in this clone (squashed/shallow history); set BASE_TREE to run"
        exit 0
    fi
    BASE_TREE="$WORK/base"
    mkdir -p "$BASE_TREE"
    if ! (cd "$ROOT" && git archive "$BASE_REV" agent/hooks/claude agent/skills/swarm-implement/scripts) 2>/dev/null | tar -x -C "$BASE_TREE" 2>/dev/null; then
        echo "[FAIL] cannot extract BASE_REV=$BASE_REV via git archive (set BASE_TREE to a pre-change tree)"
        exit 1
    fi
fi

# jq 起動回数を数える stub(実 jq へ委譲)
STUB="$WORK/stub"
mkdir -p "$STUB"
cat >"$STUB/jq" <<EOF
#!/usr/bin/env bash
echo x >>"\${JQ_COUNT_FILE:-/dev/null}"
[ -n "\${STUB_JQ_FAIL:-}" ] && exit 5 # jq 自体の失敗(fail-open/closed の維持確認用)
exec "$REAL_JQ" "\$@"
EOF
chmod +x "$STUB/jq"

# post-write.sh が実在ファイルを検証する(json/yaml/sh/py/go/toml)ための共有ファイル群
FILES="$WORK/files"
mkdir -p "$FILES"
printf '{"a":1}\n' >"$FILES/good.json"
printf '{bad\n' >"$FILES/bad.json"
printf 'a: [\n' >"$FILES/bad.yaml"
printf 'a = \n' >"$FILES/bad.toml"
printf 'if then\n' >"$FILES/bad.sh"
printf 'def (:\n' >"$FILES/bad.py"
printf 'package\n' >"$FILES/bad.go"
printf 'x\n' >"$FILES/plain.txt"
printf '{"a":1}\n' >"$FILES/tab	name.json"
printf '{bad\n' >"$FILES/-lead.json"
printf '{bad\n' >"$FILES/sp ace.json"
printf '{bad\n' >"$FILES/uni-é.json"
printf 'if then\n' >"$FILES/back\\slash.sh"

CASES="$WORK/cases"
mkdir -p "$CASES"
n=0
declare -a CASE_NAMES CASE_KINDS CASE_GRANTS CASE_JQFAIL
add() { # <kind: gate|post|both> <name> <stdin-file-or-literal via printf %b-free> -- 入力は $WORK/cases/N.in へ
    n=$((n + 1))
    CASE_KINDS[n]="$1"
    CASE_NAMES[n]="$2"
    CASE_GRANTS[n]="${4:-}"
    printf '%s' "$3" >"$CASES/$n.in"
}
addraw() { # <kind> <name> <file> [grant]
    n=$((n + 1))
    CASE_KINDS[n]="$1"
    CASE_NAMES[n]="$2"
    CASE_GRANTS[n]="${4:-}"
    command cp "$3" "$CASES/$n.in"
}

P=/tmp/zz/agent/hooks/claude # 保護パス(*/agent/hooks/claude/*)
U=/tmp/zz/docs               # 非保護パス

# ---------- gate: 通常ケース ----------
for t in Write Edit MultiEdit NotebookEdit Bash Read ""; do
    add gate "tool=$t protected" "{\"tool_name\":\"$t\",\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
    add gate "tool=$t unprotected" "{\"tool_name\":\"$t\",\"tool_input\":{\"file_path\":\"$U/x.md\"}}"
done
add gate "notebook_path protected" "{\"tool_name\":\"NotebookEdit\",\"tool_input\":{\"notebook_path\":\"$P/n.ipynb\"}}"
add gate "both paths: file_path wins" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$U/a\",\"notebook_path\":\"$P/b\"}}"
add gate "file_path null -> notebook_path" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":null,\"notebook_path\":\"$P/b\"}}"
add gate "file_path false -> notebook_path" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":false,\"notebook_path\":\"$P/b\"}}"
add gate "file_path \"\" (empty string, kept) + notebook_path" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"\",\"notebook_path\":\"$P/b\"}}"
add gate "file_path empty only" '{"tool_name":"Edit","tool_input":{"file_path":""}}'
add gate "tilde path -> HOME protected" '{"tool_name":"Edit","tool_input":{"file_path":"~/agent/hooks/claude/t.sh"}}'
add gate "tilde path unprotected" '{"tool_name":"Edit","tool_input":{"file_path":"~/x/y.md"}}'
add gate "dotdot traversal into protected" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$U/../agent/hooks/claude/x.sh\"}}"
add gate "relative protected-looking" '{"tool_name":"Edit","tool_input":{"file_path":"agent/hooks/claude/x.sh"}}'
# ---------- gate: 特殊文字パス(復元の正しさ) ----------
add gate "path tab protected" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/a\\tb.sh\"}}"
add gate "path newline protected" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/a\\nb.sh\"}}"
add gate "path trailing newline protected" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/a.sh\\n\"}}"
add gate "path trailing newlines only differ" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/a.sh\\n\\n\\n\"}}"
add gate "path leading newline" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"\\n$P/a.sh\"}}"
add gate "path only newlines" '{"tool_name":"Write","tool_input":{"file_path":"\n\n"}}'
add gate "path backslash protected" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/a\\\\b.sh\"}}"
add gate "path backslash-n literal" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/a\\\\nb.sh\"}}"
add gate "path unicode protected" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/é日本語😀.sh\"}}"
add gate "path unicode escapes protected" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/\\u00e9\\ud83d\\ude00.sh\"}}"
add gate "path leading hyphen" '{"tool_name":"Write","tool_input":{"file_path":"-x/agent/hooks/claude/a.sh"}}'
add gate "path just hyphen" '{"tool_name":"Write","tool_input":{"file_path":"-"}}'
add gate "path option-like -n" '{"tool_name":"Write","tool_input":{"file_path":"-n"}}'
add gate "path spaces protected" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/a b  c.sh\"}}"
add gate "path leading/trailing space" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\" $P/a.sh \"}}"
add gate "path quote and glob chars" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/a\\\"'\$*?[x].sh\"}}"
add gate "path control chars" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/a\\u0001\\u001f\\r.sh\"}}"
add gate "path NUL escape" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/a\\u0000b.sh\"}}"
add gate "tool_name NUL escape (Wri\\u0000te)" "{\"tool_name\":\"Wri\\u0000te\",\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
add gate "tool_name with trailing newline" "{\"tool_name\":\"Write\\n\",\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
add gate "tool_name with leading newline" "{\"tool_name\":\"\\nWrite\",\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
add gate "tool_name lowercase" "{\"tool_name\":\"write\",\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
add gate "tool_name with spaces" "{\"tool_name\":\" Write \",\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
# ---------- gate: 型・欠落 ----------
add gate "tool_name missing" "{\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
add gate "tool_name null" "{\"tool_name\":null,\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
add gate "tool_name false" "{\"tool_name\":false,\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
add gate "tool_name number" "{\"tool_name\":5,\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
add gate "tool_name array" "{\"tool_name\":[\"Write\"],\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
add gate "tool_name object" "{\"tool_name\":{\"a\":1},\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
add gate "tool_input missing" '{"tool_name":"Write"}'
add gate "tool_input null" '{"tool_name":"Write","tool_input":null}'
add gate "tool_input string" '{"tool_name":"Write","tool_input":"x"}'
add gate "tool_input number" '{"tool_name":"Write","tool_input":5}'
add gate "tool_input true" '{"tool_name":"Write","tool_input":true}'
add gate "tool_input array" "{\"tool_name\":\"Write\",\"tool_input\":[\"$P/x.sh\"]}"
add gate "tool_input {}" '{"tool_name":"Write","tool_input":{}}'
add gate "file_path number" '{"tool_name":"Write","tool_input":{"file_path":5}}'
add gate "file_path float" '{"tool_name":"Write","tool_input":{"file_path":1.50}}'
add gate "file_path true" '{"tool_name":"Write","tool_input":{"file_path":true}}'
add gate "file_path array" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":[\"$P/x.sh\"]}}"
add gate "file_path object" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":{\"a\":\"$P/x.sh\"}}}"
add gate "notebook_path number" '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":7}}'
add gate "notebook_path array" "{\"tool_name\":\"NotebookEdit\",\"tool_input\":{\"notebook_path\":[\"$P/x\"]}}"
add gate "top-level array" '[{"tool_name":"Write"}]'
add gate "top-level string" '"Write"'
add gate "top-level number" '5'
add gate "top-level true" 'true'
add gate "top-level null" 'null'
add gate "top-level {}" '{}'
# ---------- gate: 不正・空・複数ドキュメント ----------
add gate "empty input" ''
add gate "newline only" $'\n'
add gate "whitespace only" $' \t\n '
add gate "malformed" '{not json'
add gate "truncated" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/x.sh\""
add gate "truncated in string" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/x"
add gate "trailing garbage after valid doc" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/x.sh\"}} garbage"
add gate "leading garbage" "garbage {\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
add gate "two docs same" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/x.sh\"}}{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/y.sh\"}}"
add gate "two docs: tool then empty obj" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"$'\n{}'
add gate "two docs: tools differ" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/x.sh\"}} {\"tool_name\":\"Edit\"}"
add gate "doc, array doc (error), doc" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/x.sh\"}} [1] {\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$U/y\"}}"
add gate "doc with tool_input string (fp error), then doc" "{\"tool_name\":\"Write\",\"tool_input\":\"s\"} {\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P/y\"}}"
add gate "doc, number doc, bad json" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/x.sh\"}} 5 {bad"
add gate "-n option-like input" '-n'
add gate "-e option-like input" '-e'
add gate "BOM prefix" $'\xef\xbb\xbf'"{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
add gate "invalid utf8 in path" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/"$'\xff\xfe'".sh\"}}"
add gate "deep nesting" "{\"tool_name\":\"Write\",\"x\":$(printf '[%.0s' $(seq 1 200))$(printf ']%.0s' $(seq 1 200)),\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
add gate "duplicate keys (last wins)" "{\"tool_name\":\"Bash\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$U/a\",\"file_path\":\"$P/x.sh\"}}"
# 巨大入力(約 2MB のパディング / 約 1MB の保護パス)
{
    printf '{"pad":"'
    head -c 2000000 /dev/zero | tr '\0' 'a'
    printf '","tool_name":"Write","tool_input":{"file_path":"%s/x.sh"}}' "$P"
} >"$WORK/huge1.in"
addraw gate "huge padding + protected" "$WORK/huge1.in"
{
    printf '{"tool_name":"Write","tool_input":{"file_path":"/tmp/'
    head -c 1000000 /dev/zero | tr '\0' 'a'
    printf '/agent/hooks/claude/x.sh"}}'
} >"$WORK/huge2.in"
addraw gate "huge path (>NAME_MAX) protected" "$WORK/huge2.in"
{
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s/x.sh"}}\n' "$P"
    for _ in $(seq 1 2000); do printf '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/zz/docs/%s"}}\n' "$_"; done
} >"$WORK/many.in"
addraw gate "2000 docs" "$WORK/many.in"
add gate "suffix-pattern path + trailing newline" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/zz/agent/security-rules.json\n"}}'
add gate "suffix-pattern CLAUDE.md + trailing newlines" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/zz/CLAUDE.md\n\n"}}'
# tool_name は 1 ドキュメントにだけ置く(複数あると連結で不一致になり許可側)。file_path は複数ドキュメントで連結される
add gate "3 docs: fp / tool only / fp (fp concatenation, null skip)" "{\"tool_input\":{\"file_path\":\"$P/a\"}} {\"tool_name\":\"Write\"} {\"tool_input\":{\"file_path\":\"$P/b\"}}"
add gate "3 docs: tool only / fp / fp" "{\"tool_name\":\"Write\"} {\"tool_input\":{\"file_path\":\"$P/a\"}} {\"tool_input\":{\"file_path\":\"$P/b\"}}"
add gate "3 docs: fp / notebook_path / tool" "{\"tool_input\":{\"file_path\":\"$P/a\"}} {\"tool_input\":{\"notebook_path\":\"$P/n\"}} {\"tool_name\":\"NotebookEdit\"}"
# jq 自体が失敗する場合(旧: 空文字=許可側。fail-open/closed の維持)
addf() { add "$@"; CASE_JQFAIL[n]=1; }
addf gate "jq fails: protected path" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$P/x.sh\"}}"
addf post "jq fails" "{\"session_id\":\"abcd1234\",\"tool_input\":{\"file_path\":\"$FILES/bad.json\"}}"
# ---------- gate: grant 消費(grant を事前発行) ----------
add gate "grant consumed" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P/g.sh\"}}" "$P/g.sh"
add gate "grant consumed (path with space)" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P/g h.sh\"}}" "$P/g h.sh"
add gate "grant consumed (unicode)" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P/g日本.sh\"}}" "$P/g日本.sh"
add gate "grant for other path -> denied" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P/g.sh\"}}" "$P/other.sh"
add gate "grant + trailing newline path" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P/g.sh\\n\"}}" "$P/g.sh"
add gate "grant + notebook" "{\"tool_name\":\"NotebookEdit\",\"tool_input\":{\"notebook_path\":\"$P/g.ipynb\"}}" "$P/g.ipynb"

# ---------- post-write ----------
for f in good.json bad.json bad.yaml bad.toml bad.sh bad.py bad.go plain.txt nonexistent.json nonexistent.sh nonexistent.go nonexistent.py noext; do
    add post "file=$f valid session" "{\"session_id\":\"abcd1234efgh\",\"tool_input\":{\"file_path\":\"$FILES/$f\"}}"
done
add post "tab name json" "{\"session_id\":\"s1\",\"tool_input\":{\"file_path\":\"$FILES/tab\\tname.json\"}}"
add post "leading hyphen json (relative, cwd=files)" '{"session_id":"s1","tool_input":{"file_path":"-lead.json"}}'
add post "space name" "{\"session_id\":\"s1\",\"tool_input\":{\"file_path\":\"$FILES/sp ace.json\"}}"
add post "unicode name" "{\"session_id\":\"s1\",\"tool_input\":{\"file_path\":\"$FILES/uni-é.json\"}}"
add post "backslash name" "{\"session_id\":\"s1\",\"tool_input\":{\"file_path\":\"$FILES/back\\\\slash.sh\"}}"
add post "newline in path" "{\"session_id\":\"s1\",\"tool_input\":{\"file_path\":\"$FILES/a\\nb.json\"}}"
add post "trailing newline in path" "{\"session_id\":\"s1\",\"tool_input\":{\"file_path\":\"$FILES/good.json\\n\"}}"
add post "only newlines path" '{"session_id":"s1","tool_input":{"file_path":"\n\n"}}'
add post "NUL escape in path" "{\"session_id\":\"s1\",\"tool_input\":{\"file_path\":\"$FILES/good\\u0000.json\"}}"
add post "path leading spaces" "{\"session_id\":\"s1\",\"tool_input\":{\"file_path\":\"  $FILES/good.json\"}}"
add post "path only hyphen" '{"session_id":"s1","tool_input":{"file_path":"-"}}'
add post "path dot-ext only" '{"session_id":"s1","tool_input":{"file_path":".json"}}'
add post "path quotes/glob" "{\"session_id\":\"s1\",\"tool_input\":{\"file_path\":\"$FILES/a\\\"'\$*?.sh\"}}"
add post "path invalid utf8" "{\"session_id\":\"s1\",\"tool_input\":{\"file_path\":\"$FILES/"$'\xff'".json\"}}"
for sid in 'ok-1_2.3' '..' '.' '../x' 'a/b' '' 'abc\n' 'abc\n\n' 'ab\u0000cd' 'café' 'Ａbc' ' x' 'AZaz09._-' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; do
    add post "session_id=[$sid]" "{\"session_id\":\"$sid\",\"tool_input\":{\"file_path\":\"$FILES/plain.txt\"}}"
done
for v in 123 true false null '{}' '[]' '["abc"]' '{"a":"b"}' 1.5; do
    add post "session_id=$v" "{\"session_id\":$v,\"tool_input\":{\"file_path\":\"$FILES/plain.txt\"}}"
done
add post "session_id missing" "{\"tool_input\":{\"file_path\":\"$FILES/plain.txt\"}}"
add post "file_path missing" '{"session_id":"abcd1234"}'
add post "file_path null" '{"session_id":"abcd1234","tool_input":{"file_path":null}}'
add post "file_path false" '{"session_id":"abcd1234","tool_input":{"file_path":false}}'
add post "file_path empty" '{"session_id":"abcd1234","tool_input":{"file_path":""}}'
add post "file_path number" '{"session_id":"abcd1234","tool_input":{"file_path":5}}'
add post "file_path float" '{"session_id":"abcd1234","tool_input":{"file_path":1.50}}'
add post "file_path true" '{"session_id":"abcd1234","tool_input":{"file_path":true}}'
add post "file_path array" "{\"session_id\":\"abcd1234\",\"tool_input\":{\"file_path\":[\"$FILES/good.json\"]}}"
add post "file_path object" "{\"session_id\":\"abcd1234\",\"tool_input\":{\"file_path\":{\"a\":\"$FILES/good.json\"}}}"
add post "notebook_path only (not read by post-write)" "{\"session_id\":\"abcd1234\",\"tool_input\":{\"notebook_path\":\"$FILES/good.json\"}}"
add post "tool_input string" '{"session_id":"abcd1234","tool_input":"x"}'
add post "tool_input array" '{"session_id":"abcd1234","tool_input":[1]}'
add post "tool_input number" '{"session_id":"abcd1234","tool_input":5}'
add post "tool_input null" '{"session_id":"abcd1234","tool_input":null}'
add post "top-level array" '[{"session_id":"abcd1234"}]'
add post "top-level string" '"x"'
add post "top-level number" '5'
add post "top-level null" 'null'
add post "top-level {}" '{}'
add post "empty input" ''
add post "newline only" $'\n'
add post "malformed" '{not json'
add post "truncated" "{\"session_id\":\"abcd1234\",\"tool_input\":{\"file_path\":\"$FILES/good.json\""
add post "trailing garbage after valid doc" "{\"session_id\":\"abcd1234\",\"tool_input\":{\"file_path\":\"$FILES/bad.json\"}} garbage"
add post "leading garbage" "garbage {\"session_id\":\"abcd1234\",\"tool_input\":{\"file_path\":\"$FILES/bad.json\"}}"
add post "two docs" "{\"session_id\":\"abc12345\",\"tool_input\":{\"file_path\":\"$FILES/bad.json\"}}{\"session_id\":\"def67890\",\"tool_input\":{\"file_path\":\"$FILES/bad.sh\"}}"
add post "two docs: second sets file_path only" '{"session_id":"abc12345"}{"tool_input":{"file_path":"/tmp/zz/second.txt"}}'
add post "doc, array doc (fp error), doc" "{\"session_id\":\"abc12345\",\"tool_input\":{\"file_path\":\"$FILES/plain.txt\"}} [1] {\"tool_input\":{\"file_path\":\"$FILES/bad.sh\"}}"
add post "first doc non-object, second object" "[1] {\"session_id\":\"abc12345\",\"tool_input\":{\"file_path\":\"$FILES/plain.txt\"}}"
add post "first doc null, second object" "null {\"session_id\":\"abc12345\",\"tool_input\":{\"file_path\":\"$FILES/plain.txt\"}}"
add post "doc, number doc, bad json" "{\"session_id\":\"abc12345\",\"tool_input\":{\"file_path\":\"$FILES/plain.txt\"}} 5 {bad"
add post "-n option-like input" '-n'
add post "BOM prefix" $'\xef\xbb\xbf'"{\"session_id\":\"abc12345\",\"tool_input\":{\"file_path\":\"$FILES/plain.txt\"}}"
add post "duplicate keys (last wins)" "{\"session_id\":\"aaaa1111\",\"session_id\":\"bbbb2222\",\"tool_input\":{\"file_path\":\"/tmp/zz/a.txt\",\"file_path\":\"$FILES/plain.txt\"}}"
{
    printf '{"pad":"'
    head -c 2000000 /dev/zero | tr '\0' 'a'
    printf '","session_id":"abcd1234","tool_input":{"file_path":"%s/plain.txt"}}' "$FILES"
} >"$WORK/huge3.in"
addraw post "huge padding" "$WORK/huge3.in"
{
    printf '{"session_id":"abcd1234","tool_input":{"file_path":"/tmp/'
    head -c 1000000 /dev/zero | tr '\0' 'a'
    printf '.txt"}}'
} >"$WORK/huge4.in"
addraw post "huge path" "$WORK/huge4.in"
{
    printf '{"session_id":"abcd1234","tool_input":{"file_path":"%s/plain.txt"}}\n' "$FILES"
    for _ in $(seq 1 2000); do printf '{"session_id":"x%s","tool_input":{"file_path":"/tmp/zz/%s.txt"}}\n' "$_" "$_"; done
} >"$WORK/many2.in"
addraw post "2000 docs" "$WORK/many2.in"
add post "3 docs: fp / session only / fp (concatenation, null skip)" "{\"session_id\":\"abc12345\",\"tool_input\":{\"file_path\":\"$FILES/a\"}} {\"session_id\":\"def\"} {\"tool_input\":{\"file_path\":\"$FILES/b\"}}"

# ---------- 実行ハーネス ----------
# 値中の U+0000 は旧実装では bash が「ヌルバイトを無視しました」と stderr に警告していた。新実装は
# jq 側で除去するため警告が出ない(判定・出力は同一)。この警告行のみ比較から除外する。
strip_nulwarn() { grep -v -e 'ヌルバイトを無視' -e 'ignored null byte' "$1" || true; }
norm() { # 時刻・epoch 値の正規化
    sed -E 's/\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]/[HH:MM:SS]/g; s/"ts":"[^"]*"/"ts":"TS"/g; s/[0-9]{10,}/EPOCH/g; s/granted_at=[-0-9T:+]+/granted_at=T/'
}
snapshot() { # <home> -> 相対パスと内容(正規化)
    (cd "$1" && find . -type f -print0 | sort -z | while IFS= read -r -d '' f; do
        printf '== %s\n' "$f" | norm
        norm <"$f"
    done)
}

run_one() { # <tree> <kind> <case#> <tag>  -> $WORK/out.<tag>.{stdout,stderr,rc,snap,jqn}
    local tree="$1" kind="$2" i="$3" tag="$4"
    local home="$WORK/home" hook
    rm -rf "$home"
    mkdir -p "$home"
    case "$kind" in
    gate) hook="$tree/agent/hooks/claude/swarm-write-scope-gate.sh" ;;
    post) hook="$tree/agent/hooks/claude/post-write.sh" ;;
    esac
    if [[ "$kind" == gate && -n "${CASE_GRANTS[i]}" ]]; then
        HOME="$home" bash "$tree/agent/skills/swarm-implement/scripts/budget-guard.sh" --write-scope-grant "${CASE_GRANTS[i]}" >/dev/null 2>&1 || true
    fi
    : >"$WORK/jqcount.$tag"
    (
        cd "$FILES" &&
            HOME="$home" PATH="$STUB:$PATH" JQ_COUNT_FILE="$WORK/jqcount.$tag" TZ=UTC STUB_JQ_FAIL="${CASE_JQFAIL[i]:-}" \
                bash "$hook" <"$CASES/$i.in" >"$WORK/out.$tag.stdout" 2>"$WORK/out.$tag.stderr"
        echo $? >"$WORK/out.$tag.rc"
    )
    snapshot "$home" >"$WORK/out.$tag.snap"
    wc -l <"$WORK/jqcount.$tag" | tr -d ' ' >"$WORK/out.$tag.jqn"
}

jq_base_total=0 jq_new_total=0
declare -A JQ_BASE_BY_KIND JQ_NEW_BY_KIND
for i in $(seq 1 "$n"); do
    kind="${CASE_KINDS[i]}"
    run_one "$BASE_TREE" "$kind" "$i" base
    run_one "$NEW_TREE" "$kind" "$i" new
    name="[$kind #$i] ${CASE_NAMES[i]}"
    bad=""
    strip_nulwarn "$WORK/out.base.stderr" >"$WORK/out.base.stderr.f"
    strip_nulwarn "$WORK/out.new.stderr" >"$WORK/out.new.stderr.f"
    mv "$WORK/out.base.stderr.f" "$WORK/out.base.stderr"
    mv "$WORK/out.new.stderr.f" "$WORK/out.new.stderr"
    for part in rc stdout stderr snap; do
        if ! cmp -s "$WORK/out.base.$part" "$WORK/out.new.$part"; then
            bad="$bad $part"
        fi
    done
    if [[ -n "$bad" ]]; then
        ng "$name: differs in:$bad (base rc=$(cat "$WORK/out.base.rc") new rc=$(cat "$WORK/out.new.rc"))"
        for part in $bad; do
            echo "  --- $part (base | new), first 5 lines each ---"
            head -c 600 "$WORK/out.base.$part" | head -5 | sed 's/^/  B: /'
            head -c 600 "$WORK/out.new.$part" | head -5 | sed 's/^/  N: /'
        done
    else
        ok
    fi
    jb=$(cat "$WORK/out.base.jqn")
    jn=$(cat "$WORK/out.new.jqn")
    jq_base_total=$((jq_base_total + jb))
    jq_new_total=$((jq_new_total + jn))
    if ((jn > jb)) && [[ -z "${CASE_JQFAIL[i]:-}" ]]; then
        ng "$name: jq invocations new=$jn > base=$jb"
    fi
    JQ_BASE_BY_KIND[$kind]=$((${JQ_BASE_BY_KIND[$kind]:-0} + jb))
    JQ_NEW_BY_KIND[$kind]=$((${JQ_NEW_BY_KIND[$kind]:-0} + jn))
done

# 開発用: 入力表の比較だけで終える(mutation の掃引を速くするため。CI/通常実行では使わない)
if [[ -n "${HOOK_JQ_TEST_TABLE_ONLY:-}" ]]; then
    echo "(table-only mode) cases: $n"
    ((fail > 0)) && { echo "test-hook-jq-consolidation(table-only): ${fail} 件のFAILあり (pass=$pass)"; exit 1; }
    echo "test-hook-jq-consolidation(table-only): 全 $pass チェック PASS"
    exit 0
fi

# ---------- 環境障害シナリオ(fail-open を新設していないこと) ----------
# here-string は bash が約 64KB 超で一時ファイルを使い、書けないとリダイレクト失敗→jq 不起動→空→exit 0
# (fail-open)になる。旧実装は `echo | jq` でパイプのみ。ulimit -f 0 / TMPDIR 不可 / jq 不在・異常終了の
# 各環境で、BASE と NEW の「出力+rc+副作用」が一致することを、70KB 超/1MB の入力で確認する。
NOJQ="$WORK/nojq"
mkdir -p "$NOJQ" "$WORK/jqzero" "$WORK/jqkill"
for f in /usr/bin/*; do b="${f##*/}"; [[ "$b" == jq ]] || ln -s "$f" "$NOJQ/$b"; done
printf '#!/bin/sh\nexit 0\n' >"$WORK/jqzero/jq"
printf '#!/bin/sh\nkill -9 $$\n' >"$WORK/jqkill/jq"
chmod +x "$WORK/jqzero/jq" "$WORK/jqkill/jq"
mkbig() { # <outfile> <tool> <pathfield> <path> <content-bytes>
    {
        printf '{"tool_name":"%s","tool_input":{"%s":"%s","content":"' "$2" "$3" "$4"
        head -c "$5" /dev/zero | tr '\0' 'a'
        printf '"}}'
    } >"$1"
}
mkbig "$WORK/e_gate70k.in" Write file_path "$P/a.md" 70000
mkbig "$WORK/e_gate1m.in" Write file_path "$P/a.md" 1000000
mkbig "$WORK/e_gate_unprot70k.in" Write file_path "$U/a.md" 70000
mkbig "$WORK/e_gate_nb70k.in" NotebookEdit notebook_path "$P/a.ipynb" 70000
printf '{"tool_name":"Write","tool_input":{"file_path":"%s/x.sh"}}' "$P" >"$WORK/e_gate_small.in"
{
    printf '{"session_id":"abcd1234","tool_input":{"file_path":"%s/bad.json","content":"' "$FILES"
    head -c 70000 /dev/zero | tr '\0' 'a'
    printf '"}}'
} >"$WORK/e_post70k.in"
{
    printf '{"session_id":"abcd1234","tool_input":{"file_path":"%s/bad.json","content":"' "$FILES"
    head -c 1000000 /dev/zero | tr '\0' 'a'
    printf '"}}'
} >"$WORK/e_post1m.in"

run_env() { # <tree> <kind> <infile> <mode> <outfile>
    local tree="$1" kind="$2" in="$3" mode="$4" out="$5" hdir="$WORK/env.dir" hook pre="" pth="$PATH" tmpd="$WORK/env.dir/tmp"
    local -a wrap=() xenv=()
    chmod -R u+rwx "$hdir" 2>/dev/null || true
    rm -rf "$hdir"
    mkdir -p "$hdir/tmp"
    : >"$WORK/env.jqcount"
    case "$kind" in
    gate) hook="$tree/agent/hooks/claude/swarm-write-scope-gate.sh" ;;
    post) hook="$tree/agent/hooks/claude/post-write.sh" ;;
    esac
    case "$mode" in
    ulimit0) pre='ulimit -f 0;' ;;
    monitor) xenv=(SHELLOPTS=monitor) pth="$STUB:$PATH" ;;
    monitor_brace) xenv=(SHELLOPTS=monitor:braceexpand) pth="$STUB:$PATH" ;;
    posix) xenv=(POSIXLY_CORRECT=1) pth="$STUB:$PATH" ;;
    nocase) xenv=(BASHOPTS=nocasematch) pth="$STUB:$PATH" ;;
    noproc) wrap=(unshare -rm) pre='mount -t tmpfs none /proc;' ;;
    noproc_ulimit) wrap=(unshare -rm) pre='mount -t tmpfs none /proc; ulimit -f 0;' ;;
    rotmp) chmod 500 "$hdir/tmp" ;;
    badtmp) tmpd="$hdir/no/such/dir" ;;
    jqfail) pth="$STUB:$PATH" ;;
    jqzero) pth="$WORK/jqzero:$PATH" ;;
    jqkill) pth="$WORK/jqkill:$PATH" ;;
    nojq) pth="$NOJQ" ;;
    esac
    {
        (cd "$FILES" && "${wrap[@]}" bash -c "${pre}"'exec "$@"' _ env HOME="$hdir" TMPDIR="$tmpd" PATH="$pth" TZ=UTC STUB_JQ_FAIL="$([[ $mode == jqfail ]] && echo 1)" JQ_COUNT_FILE="$WORK/env.jqcount" "${xenv[@]}" timeout -k 1 15 bash "$hook" <"$in" 2>&1)
        echo "rc=$?"
    } 2>/dev/null | cat >"$out"
    chmod -R u+rwx "$hdir" 2>/dev/null || true
    ENV_JQN=$(wc -l <"$WORK/env.jqcount" | tr -d ' ')
    snapshot "$hdir" >>"$out"
    # ツリーのパス・hook 内の行番号・PID・NUL 警告(上記 strip_nulwarn と同じ理由)を正規化して比較する
    grep -v -e 'ヌルバイトを無視' -e 'ignored null byte' "$out" |
        sed -E -e "s|$BASE_TREE|TREE|g" -e "s|$NEW_TREE|TREE|g" -e 's/: [0-9]+ 行: [0-9]+ +/: N 行: PID /' -e 's/: line [0-9]+: +[0-9]+ +/: line N: PID /' |
        norm >"$out.n" || true
    mv "$out.n" "$out"
}

HAVE_NOPROC=0
if unshare -rm bash -c 'mount -t tmpfs none /proc' >/dev/null 2>&1; then HAVE_NOPROC=1; else echo "[SKIP] unshare -rm + mount /proc unavailable: noproc scenarios skipped"; fi
env_modes=(ulimit0 rotmp badtmp jqfail jqzero jqkill nojq monitor monitor_brace posix nocase)
((HAVE_NOPROC)) && env_modes+=(noproc noproc_ulimit)
env_cases=0
for mode in "${env_modes[@]}"; do
    for spec in "gate e_gate70k" "gate e_gate1m" "gate e_gate_unprot70k" "gate e_gate_nb70k" "gate e_gate_small" "post e_post70k" "post e_post1m"; do
        kind="${spec%% *}" inf="$WORK/${spec##* }.in"
        run_env "$BASE_TREE" "$kind" "$inf" "$mode" "$WORK/env.base"
        run_env "$NEW_TREE" "$kind" "$inf" "$mode" "$WORK/env.new"
        new_jqn=$ENV_JQN
        env_cases=$((env_cases + 1))
        if [[ "$mode" =~ ^(monitor|monitor_brace|posix|nocase)$ && ( "${spec##* }" == e_gate_unprot70k || "$kind" == post ) ]]; then
            if ((new_jqn == 1)); then ok; else ng "[env:$mode $spec] jq 起動回数 new=$new_jqn (set +m が効けば 1 回。フォールバックは 2 回)"; fi
        fi
        if cmp -s "$WORK/env.base" "$WORK/env.new"; then
            ok
        else
            ng "[env:$mode $spec] BASE と NEW の出力/rc/副作用が不一致"
            diff <(head -c 400 "$WORK/env.base") <(head -c 400 "$WORK/env.new") | head -6 | sed 's/^/  /'
        fi
        # ファイル系の障害(ulimit/TMPDIR)で保護パス Write は拒否のまま(fail-open させない)
        if [[ "$kind" == gate && "$mode" =~ ^(ulimit0|rotmp|badtmp|noproc|noproc_ulimit|monitor|monitor_brace|posix|nocase)$ && "${spec##* }" =~ ^e_gate(70k|1m|_nb70k)$ ]]; then
            if grep -q '^rc=2$' "$WORK/env.new"; then ok; else ng "[env:$mode $spec] 保護パス Write が拒否(rc=2)されていない(fail-open)"; fi
        fi
    done
done
echo "environment-failure scenarios compared: $env_cases"

# ---------- NUL 多数の値でも線形時間(gsub は O(n^2) で hook timeout に達した) ----------
nulpath="$P/$(printf '\\u0000aaaaaaaaa%.0s' $(seq 1 10000))"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$nulpath" >"$WORK/nul_gate.in"
printf '{"session_id":"abcd1234","tool_input":{"file_path":"%s"}}' "$nulpath" >"$WORK/nul_post.in"
for spec in "gate nul_gate" "post nul_post"; do
    kind="${spec%% *}" inf="$WORK/${spec##* }.in"
    t0=$EPOCHREALTIME
    run_env "$BASE_TREE" "$kind" "$inf" none "$WORK/env.base"
    t1=$EPOCHREALTIME
    run_env "$NEW_TREE" "$kind" "$inf" none "$WORK/env.new"
    t2=$EPOCHREALTIME
    bms=$(((${t1/./} - ${t0/./}) / 1000))
    ms=$(((${t2/./} - ${t1/./}) / 1000))
    if cmp -s "$WORK/env.base" "$WORK/env.new"; then ok; else ng "[nul-heavy $kind] BASE と NEW が不一致"; fi
    # gate は 1 秒未満。post-write は(bash の `${FILE_PATH##*.}` が長い値で元々遅いため)BASE+1 秒以内
    # (gsub 退行は +数秒になるので検出できる)
    limit=1000
    [[ "$kind" == post ]] && limit=$((bms + 1000))
    if ((ms < limit)); then ok; else ng "[nul-heavy $kind] 100KB/NUL 1 万個で new=${ms}ms (base=${bms}ms, limit=${limit}ms)"; fi
    echo "nul-heavy $kind: base=${bms}ms new=${ms}ms (incl. snapshot)"
done

# ---------- 末尾改行の多いパス(二次式の除去だと hook timeout で fail-open) ----------
mknl() { # <outfile> <kind> <count>
    {
        if [[ "$2" == gate ]]; then
            printf '{"tool_name":"Write","tool_input":{"file_path":"/x/agent/SWARM.md'
        else
            printf '{"session_id":"abc123456789","tool_input":{"file_path":"%s/bad.json' "$FILES"
        fi
        if (($3 > 0)); then yes '\n' | head -n "$3" | tr -d '\n'; fi
        printf '"}}'
    } >"$1"
}
for kind in gate post; do
    for cnt in 0 1 5 1000 30000 1000000; do
        mknl "$WORK/nl.in" "$kind" "$cnt"
        t0=$EPOCHREALTIME
        run_env "$BASE_TREE" "$kind" "$WORK/nl.in" none "$WORK/env.base"
        t1=$EPOCHREALTIME
        run_env "$NEW_TREE" "$kind" "$WORK/nl.in" none "$WORK/env.new"
        t2=$EPOCHREALTIME
        bms=$(((${t1/./} - ${t0/./}) / 1000))
        ms=$(((${t2/./} - ${t1/./}) / 1000))
        if cmp -s "$WORK/env.base" "$WORK/env.new"; then ok; else ng "[trailing-newlines $kind x$cnt] BASE と NEW が不一致"; fi
        # gate は 1 秒未満。post-write は(bash の ${FILE_PATH##*.} が元々遅いので)BASE の 2 倍+1 秒以内
        limit=1000
        [[ "$kind" == post ]] && limit=$((bms * 2 + 1000))
        if ((ms < limit)); then ok; else ng "[trailing-newlines $kind x$cnt] new=${ms}ms (base=${bms}ms, limit=${limit}ms)"; fi
        if [[ "$kind" == gate ]]; then
            if grep -q '^rc=2$' "$WORK/env.new"; then ok; else ng "[trailing-newlines gate x$cnt] 保護パス Write が拒否(rc=2)されていない"; fi
        fi
        echo "trailing-newlines $kind x$cnt: base=${bms}ms new=${ms}ms"
    done
done

# ---------- NUL 多数の巨大値(線形であること: BASE の 2 倍+0.5 秒以内かつ 5 秒未満) ----------
mknul() { # <outfile> <kind> <total-bytes> <nuls>
    local chunk=$(($3 / $4 - 6))
    {
        if [[ "$2" == gate ]]; then
            printf '{"tool_name":"Write","tool_input":{"file_path":"/x/agent/SWARM.md/'
        else
            printf '{"session_id":"abc123456789","tool_input":{"file_path":"%s/' "$FILES"
        fi
        yes "$(head -c "$chunk" /dev/zero | tr '\0' 'a')\\u0000" | head -n "$4" | tr -d '\n'
        # 末尾を '.' にする: `${FILE_PATH##*.}` は末尾が '.' なら即一致し、二次式にならない(post-write 用)
        printf '."}}'
    } >"$1"
}
for kind in gate post; do
    for tier in "1000000 10000" "3000000 30000"; do
        # shellcheck disable=SC2086
        set -- $tier
        mknul "$WORK/nul.in" "$kind" "$1" "$2"
        t0=$EPOCHREALTIME
        run_env "$BASE_TREE" "$kind" "$WORK/nul.in" none "$WORK/env.base"
        t1=$EPOCHREALTIME
        run_env "$NEW_TREE" "$kind" "$WORK/nul.in" none "$WORK/env.new"
        t2=$EPOCHREALTIME
        bms=$(((${t1/./} - ${t0/./}) / 1000))
        ms=$(((${t2/./} - ${t1/./}) / 1000))
        if cmp -s "$WORK/env.base" "$WORK/env.new"; then ok; else ng "[nul-huge $kind $1B/$2 NULs] BASE と NEW が不一致"; fi
        if ((ms < 5000 && ms <= bms * 2 + 500)); then ok; else ng "[nul-huge $kind $1B/$2 NULs] new=${ms}ms (base=${bms}ms; need < 5000 and <= 2x base + 500)"; fi
        echo "nul-huge $kind ${1}B/${2} NULs: base=${bms}ms new=${ms}ms"
    done
done

# ---------- 不正 Unicode(孤立サロゲート)と NUL の組み合わせで BASE と出力が変わらない ----------
add_u() { # 通常テーブルとは別に即時比較する
    printf '%s' "$2" >"$WORK/u.in"
    run_env "$BASE_TREE" "$1" "$WORK/u.in" none "$WORK/env.base"
    run_env "$NEW_TREE" "$1" "$WORK/u.in" none "$WORK/env.new"
    if cmp -s "$WORK/env.base" "$WORK/env.new"; then ok; else ng "[unicode $1] $3: BASE と NEW が不一致"; fi
}
for kind in gate post; do
    pre='{"tool_name":"Write","tool_input":{"file_path":"'
    post_='"}}'
    if [[ "$kind" == post ]]; then
        pre='{"session_id":"abc123456789","tool_input":{"file_path":"'"$FILES"/
    fi
    [[ "$kind" == gate ]] && pre='{"tool_name":"Write","tool_input":{"file_path":"/x/agent/SWARM.md/'
    add_u "$kind" "${pre}a\\ud800b\\u0000c${post_}" "lone high surrogate + NUL"
    add_u "$kind" "${pre}a\\udc00\\u0000b${post_}" "lone low surrogate + NUL"
    add_u "$kind" "${pre}\\ud83d\\ude00\\u0000\\ud83d${post_}" "valid pair + NUL + lone high"
    add_u "$kind" "${pre}\\ude00\\ud83d\\u0000${post_}" "reversed pair + NUL"
    add_u "$kind" "${pre}"$'\xff\xfe'"\\u0000z${post_}" "invalid UTF-8 bytes + NUL"
    add_u "$kind" "${pre}\\u0000\\u0000\\u0000${post_}" "only NULs"
    add_u "$kind" "${pre}\\u0000${post_}" "single NUL"
done

# jq 起動回数の表明(通常ケース = 正常 JSON・非保護パス・通常 tool)は NEW が 1 回、BASE が gate=2 / post=2
std_gate='{"tool_name":"Write","tool_input":{"file_path":"/tmp/zz/docs/x.md"}}'
std_post="{\"session_id\":\"abcd1234\",\"tool_input\":{\"file_path\":\"$FILES/plain.txt\"}}"
count_std() { # <tree> <kind> <stdin> -> jq 回数
    local tree="$1" kind="$2" input="$3" hook
    case "$kind" in
    gate) hook="$tree/agent/hooks/claude/swarm-write-scope-gate.sh" ;;
    post) hook="$tree/agent/hooks/claude/post-write.sh" ;;
    esac
    : >"$WORK/jqcount.std"
    printf '%s' "$input" | HOME="$WORK/home.std" PATH="$STUB:$PATH" JQ_COUNT_FILE="$WORK/jqcount.std" bash "$hook" >/dev/null 2>&1
    wc -l <"$WORK/jqcount.std" | tr -d ' '
}
mkdir -p "$WORK/home.std"
gb=$(count_std "$BASE_TREE" gate "$std_gate")
gn=$(count_std "$NEW_TREE" gate "$std_gate")
pb=$(count_std "$BASE_TREE" post "$std_post")
pn=$(count_std "$NEW_TREE" post "$std_post")
echo "jq invocations (standard input): gate base=$gb new=$gn | post-write base=$pb new=$pn"
[[ "$gn" == 1 ]] && ok || ng "gate standard-case jq invocations expected 1, got $gn"
[[ "$pn" == 1 ]] && ok || ng "post-write standard-case jq invocations expected 1, got $pn"
((gb > gn)) && ok || ng "gate: base ($gb) should exceed new ($gn)"
((pb > pn)) && ok || ng "post-write: base ($pb) should exceed new ($pn)"

echo "cases: $n, jq invocations over all cases: base=$jq_base_total new=$jq_new_total"
echo "----"
if ((fail > 0)); then
    echo "test-hook-jq-consolidation: ${fail} 件のFAILあり (pass=$pass)"
    exit 1
fi
echo "test-hook-jq-consolidation: 全 $pass チェック PASS"
