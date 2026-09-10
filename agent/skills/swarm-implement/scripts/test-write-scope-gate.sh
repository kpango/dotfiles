#!/usr/bin/env bash
# Regression tests for agent/hooks/claude/swarm-write-scope-gate.sh (PreToolUse:Write|Edit|MultiEdit|
# NotebookEdit ゲート、SWARM.md §2 Tier B ガバナンスファイル保護)。
#
# 2026-09-03発見の経緯: このhookは新設当初から `$(dirname "${BASH_SOURCE[0]}")/../skills/...`
# という文字列連結でwrite-scope-lib.shをsourceしていたが、POSIXパス解決の仕様上 `..` が
# シンボリックリンクの"リンク先"を基準に解決されるため、`claude/hooks`(実体でもsymlinkでも)
# からの`../skills`は常に`claude/skills`(swarm-loop/swarm-meta の統計のみを持つ別ディレクトリ)
# に解決され、`agent/skills/swarm-implement/scripts/write-scope-lib.sh`には絶対に届かなかった。
# 結果、`[ -f "$lib" ] || exit 0` が常にtrueとなり、本hookは新設以来一度もTier Bファイルを
# 保護できていなかった(fail-openの範囲を大きく超えた、恒久的な無効化)。`cd -P`による
# 物理パス解決へ書き換えて修正した際、テストが存在しなかったため本ファイルを新設し
# 再発を防止する。
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 実hookは agent/hooks/claude/ 配下(2026-09-04、claude-hooks-full-agent-consolidationミッションで
# claude/hooks/配下の残存全ファイルをagent/hooks/claude/へ実体移動したことに伴う変更。旧パスは4階層
# 上がってclaude/hooks/へ入る必要があったが、新パスは3階層上がってhooks/claude/へ入る)。
HOOK="$(cd "$here/../../../hooks/claude" && pwd)/swarm-write-scope-gate.sh"
SCRIPT="$here/budget-guard.sh"
export HOME="$(mktemp -d)" # 実grant・実監査ログを汚さない隔離HOME
trap 'rm -rf "$HOME"' EXIT

gdir="$HOME/.claude/session-data/swarm/budget/.write-scope-grants"
audit_log="$HOME/.claude/session-data/swarm/write-scope-log.jsonl"

pass=0 fail=0
check() {
  local desc="$1" want="$2" got="$3"
  if [ "$want" != "$got" ]; then
    echo "FAIL: $desc (exit want=$want got=$got)"; fail=$((fail+1)); return
  fi
  echo "ok: $desc"; pass=$((pass+1))
}
gate() { printf '%s' "$1" | bash "$HOOK" 2>&1; }
grants_left() { ls -1 "$gdir" 2>/dev/null | wc -l; }

# lib実体が本当に見つかる(=修正が効いている)ことをまず確認する — これが崩れると
# 以降の全ケースが「protectedと判定されないので常にexit 0」という別の理由で見かけ上PASSしうる。
lib_real="$here/write-scope-lib.sh"
[ -f "$lib_real" ]; check "write-scope-lib.sh exists at expected canonical path" 0 $?

PROTECTED="$HOME/go/src/github.com/kpango/dotfiles/agent/hooks/claude/some-hook.sh"
UNPROTECTED="$HOME/go/src/github.com/kpango/dotfiles/docs/README.md"

# 1. 非保護ファイルはgrant無しで常に許可
out=$(gate "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$UNPROTECTED\"}}"); check "unprotected file allowed without grant" 0 $?

# 2. 保護ファイルはgrant無しでブロック
out=$(gate "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PROTECTED\"}}"); check "protected file blocked without grant" 2 $?
echo "$out" | grep -q "Tier B governance file write blocked" ; check "block message present" 0 $?

# 3. grant発行後は許可・消費される
bash "$SCRIPT" --write-scope-grant "$PROTECTED" >/dev/null 2>&1
out=$(gate "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$PROTECTED\"}}"); check "protected file allowed with matching grant" 0 $?
left=$(grants_left); [ "$left" -eq 0 ]; check "grant consumed exactly once (left=$left)" 0 $?

# 4. 消費済みで再度はブロック(1 grant = 1 edit)
out=$(gate "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$PROTECTED\"}}"); check "second edit without new grant blocked" 2 $?

# 5. NotebookEdit は notebook_path フィールドを見る(file_pathではない)
bash "$SCRIPT" --write-scope-grant "$PROTECTED" >/dev/null 2>&1
out=$(gate "{\"tool_name\":\"NotebookEdit\",\"tool_input\":{\"notebook_path\":\"$PROTECTED\"}}"); check "NotebookEdit uses notebook_path field" 0 $?

# 6. 対象外のtool_nameは無条件許可(grant不要)
out=$(gate "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm $PROTECTED\"}}"); check "non-gated tool_name ignored" 0 $?

# 7. 期限切れgrantはブロック・掃除される
bash "$SCRIPT" --write-scope-grant "$PROTECTED" >/dev/null 2>&1
# grant発行直後にファイルのmtimeを過去へ書き換えてTTL超過を再現する
for gf in "$gdir"/*; do touch -d "@0" "$gf" 2>/dev/null || touch -t 197001010000 "$gf" 2>/dev/null; done
out=$(gate "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PROTECTED\"}}"); check "expired grant blocked" 2 $?
left=$(grants_left); [ "$left" -eq 0 ]; check "expired grant cleaned (left=$left)" 0 $?

# 8. 監査ログに consumed/denied 両方が記録される
grep -q '"decision":"consumed"' "$audit_log" 2>/dev/null; check "audit log has consumed entry" 0 $?
grep -q '"decision":"denied"' "$audit_log" 2>/dev/null; check "audit log has denied entry" 0 $?

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
