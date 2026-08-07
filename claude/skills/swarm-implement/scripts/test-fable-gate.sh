#!/usr/bin/env bash
# Regression tests for claude/hooks/swarm-fable-gate.sh (PreToolUse:Task|Agent ゲート)。
# 仕様 (fable-route-hardening/closeout mission, SWARM.md §1 スポット判断層の機械化):
#   - Agent/Task ツールで model:'fable' を指定した起動は、prompt に [fable-spot:<task-id>]
#     マーカーを含めることが必須。budget-guard.sh --fable が発行した「同一 task-id の」
#     未消費 grant トークンを 1 つ消費して初めて許可される (1 grant = 1 スポーン、task 束縛 —
#     他 task の grant を窃取できない)
#   - マーカー無し / 該当 task の grant 無し / 期限切れ (TTL 600s) は {"decision":"block"} + exit 2
#   - model が fable 以外なら常に許可 (exit 0)。subagent_type=debugger で model 未指定の
#     場合のみ警告を additionalContext に出す (非ブロッキング、SWARM.md §1「Fixer は sonnet 明示」)
#   - 入力がパース不能なら fail-open (exit 0、security-gate.sh と同じ縮退方針)
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$here/../../../hooks/swarm-fable-gate.sh"
SCRIPT="$here/budget-guard.sh"
export HOME="$(mktemp -d)"   # 実カウンタ・実grantを汚さない隔離 HOME
trap 'rm -rf "$HOME"' EXIT

gdir="$HOME/.claude/session-data/swarm/budget/.fable-grants"

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
gate() { printf '%s' "$1" | bash "$HOOK" 2>&1; }
grants_left() { ls -1 "$gdir" 2>/dev/null | wc -l; }

# 1. マーカー付きでも grant が皆無ならブロック
out=$(gate '{"tool_name":"Agent","tool_input":{"model":"fable","prompt":"[fable-spot:hk0] x"}}'); check "marked but no grant blocked" 2 $? '"decision":"block"' "$out"
# 2. grant があってもマーカー無しはブロック（task 束縛の前提）— grant は消費されない
bash "$SCRIPT" --fable hk1 >/dev/null 2>&1
out=$(gate '{"tool_name":"Agent","tool_input":{"model":"fable","prompt":"no marker here"}}'); check "unmarked fable blocked even with grant" 2 $? "fable-spot" "$out"
left=$(grants_left); [ "$left" -eq 1 ]; check "unmarked attempt does not consume grant (left=$left)" 0 $? "" ""
# 3. 一致するマーカー + grant → 許可・消費
out=$(gate '{"tool_name":"Agent","tool_input":{"model":"fable","prompt":"[fable-spot:hk1] diagnose"}}'); check "matching marker allowed" 0 $? "grant consumed" "$out"
left=$(grants_left); [ "$left" -eq 0 ]; check "grant consumed exactly once (left=$left)" 0 $? "" ""
# 4. 消費済みで再度はブロック (1 grant = 1 スポーン)
out=$(gate '{"tool_name":"Agent","tool_input":{"model":"fable","prompt":"[fable-spot:hk1] again"}}'); check "second spawn without new grant blocked" 2 $? '"decision":"block"' "$out"
# 5. 他 task の grant は窃取できない（不一致マーカーはブロック・grant は生存）
bash "$SCRIPT" --fable hkA >/dev/null 2>&1
out=$(gate '{"tool_name":"Agent","tool_input":{"model":"fable","prompt":"[fable-spot:hkB] steal"}}'); check "mismatched marker blocked (no theft)" 2 $? '"decision":"block"' "$out"
left=$(grants_left); [ "$left" -eq 1 ]; check "victim grant survives theft attempt (left=$left)" 0 $? "" ""
out=$(gate '{"tool_name":"Agent","tool_input":{"model":"fable","prompt":"[fable-spot:hkA] legit"}}'); check "owner still consumes own grant" 0 $? "grant consumed" "$out"
# 6. fable 以外の model は素通し（マーカー不要）
out=$(gate '{"tool_name":"Agent","tool_input":{"model":"sonnet","prompt":"x"}}'); check "non-fable model allowed" 0 $? "" ""
# 7. tool_name "Task" も対象
out=$(gate '{"tool_name":"Task","tool_input":{"model":"fable","prompt":"[fable-spot:hk9] x"}}'); check "Task tool name also gated" 2 $? '"decision":"block"' "$out"
# 8. debugger を model 未指定で起動 → 警告 (非ブロッキング)
out=$(gate '{"tool_name":"Agent","tool_input":{"subagent_type":"debugger","prompt":"x"}}'); check "debugger without model warns" 0 $? "sonnet" "$out"
# 9. debugger でも model 明示なら無言で許可
out=$(gate '{"tool_name":"Agent","tool_input":{"subagent_type":"debugger","model":"sonnet","prompt":"x"}}'); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ]; check "debugger with explicit model silent" 0 $? "" ""
# 10. 期限切れ grant は使えず掃除される
bash "$SCRIPT" --fable hk2 >/dev/null 2>&1
for f in "$gdir"/*; do touch -d '20 minutes ago' "$f"; done
out=$(gate '{"tool_name":"Agent","tool_input":{"model":"fable","prompt":"[fable-spot:hk2] x"}}'); check "expired grant blocked" 2 $? '"decision":"block"' "$out"
left=$(grants_left); [ "$left" -eq 0 ]; check "expired grant cleaned (left=$left)" 0 $? "" ""
# 11. 対象外ツールは素通し
out=$(gate '{"tool_name":"Bash","tool_input":{"command":"echo fable"}}'); check "non-agent tool ignored" 0 $? "" ""
# 12. パース不能入力は fail-open
out=$(printf 'not-json' | bash "$HOOK" 2>&1); check "malformed input fail-open" 0 $? "" ""
# 13. 先頭ドットの一時/残骸ファイルは grant として消費されない
mkdir -p "$gdir"
touch "$gdir/.consuming.4242"
out=$(gate '{"tool_name":"Agent","tool_input":{"model":"fable","prompt":"[fable-spot:hk3] x"}}'); check "dot-prefixed stray never consumed as grant" 2 $? '"decision":"block"' "$out"
rm -f "$gdir/.consuming.4242"

# 14. TTL は fable-budget.conf の単一ソース（FABLE_BUDGET_CONF で上書き可能）
cconf="$HOME/custom-gate.conf"
printf 'FABLE_GRANT_TTL_SECONDS=1\n' >"$cconf"
bash "$SCRIPT" --fable hkttl >/dev/null 2>&1
for f in "$gdir"/*; do [ -f "$f" ] && touch -d '3 seconds ago' "$f"; done
out=$(printf '%s' '{"tool_name":"Agent","tool_input":{"model":"fable","prompt":"[fable-spot:hkttl] x"}}' | FABLE_BUDGET_CONF="$cconf" bash "$HOOK" 2>&1)
check "conf-overridden TTL expires grant" 2 $? '"decision":"block"' "$out"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
