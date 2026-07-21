#!/usr/bin/env bash
# Regression tests for budget-guard.sh --fable mode (Fable スポット判断層カウンタ)。
# 仕様 (SWARM.md §1 スポット判断層 / fable-spot-routing mission Design Agreement):
#   budget-guard.sh --fable <task-id> [--mission=<slug>]
#     - 1 タスク 1 回 (fable_task_max=1)・1 ミッション 2 回 (fable_mission_max=2)
#     - 許可時のみ消費 (拒否された呼び出しは Fable をスポーンさせないため、どのカウンタも増えない)
#     - 超過時 FABLE_BUDGET_EXCEEDED を stderr に出し exit 1
#     - --reset <task-id> [--mission=<slug>] は fable カウンタ・ロックも削除する
#     - 予約プレフィックス: _fable-* / _mission-total-* に加え、mission-total-* (アンダースコア
#       なし) も拒否する。fable モードの実ファイル名は _fable-<task-id> のため、task-id が
#       mission-total-<slug> だと共有カウンタ _fable-mission-total-<slug> と同一ファイルに
#       衝突しミッション予算が混線する (code-reviewer/Checker が独立に再現した実バグの回帰テスト)
#     - 通常モード (試行カウンタ) とは独立
set -u

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/budget-guard.sh"
export HOME="$(mktemp -d)"   # 実カウンタを汚さない隔離 HOME
trap 'rm -rf "$HOME"' EXIT

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

# 1. 初回 fable spot は成功する
out=$(bash "$SCRIPT" --fable t1 --mission=m1 2>&1); check "first fable spot ok" 0 $? "fable" "$out"
# 2. 同一タスク 2 回目は task 上限 (1) 超過
out=$(bash "$SCRIPT" --fable t1 --mission=m1 2>&1); check "task cap 1 enforced" 1 $? "FABLE_BUDGET_EXCEEDED" "$out"
# 3. 別タスクはミッション 2 回目として成功 (2. の拒否がミッション枠を消費していないこと)
out=$(bash "$SCRIPT" --fable t2 --mission=m1 2>&1); check "mission 2nd spot ok (denial did not consume)" 0 $? "fable" "$out"
# 4. ミッション 3 回目は mission 上限 (2) 超過
out=$(bash "$SCRIPT" --fable t3 --mission=m1 2>&1); check "mission cap 2 enforced" 1 $? "FABLE_BUDGET_EXCEEDED" "$out"
# 5. --mission 無しでも task 上限は効く
out=$(bash "$SCRIPT" --fable t4 2>&1); check "fable without mission ok" 0 $? "fable" "$out"
out=$(bash "$SCRIPT" --fable t4 2>&1); check "task cap without mission" 1 $? "FABLE_BUDGET_EXCEEDED" "$out"
# 6. --reset は fable カウンタも消す (reset 後は再度スポット可能)
out=$(bash "$SCRIPT" --reset t1 --mission=m1 2>&1); check "reset ok" 0 $? "" ""
out=$(bash "$SCRIPT" --fable t1 --mission=m1 2>&1); check "fable usable after reset" 0 $? "fable" "$out"
# 7. _fable-* に衝突する task-id は拒否 (通常モードでも)
out=$(bash "$SCRIPT" _fable-x 2>&1); check "reserved prefix _fable-" 1 $? "RESERVED_PREFIX_COLLISION" "$out"
# 8. mission-total-* (アンダースコアなし) の task-id は拒否 — fable モードで
#    _fable-mission-total-<slug> 共有カウンタと同一ファイルに衝突するため
out=$(bash "$SCRIPT" --fable mission-total-m9 --mission=m9 2>&1); check "reserved prefix mission-total- (fable collision)" 1 $? "RESERVED_PREFIX_COLLISION" "$out"
out=$(bash "$SCRIPT" mission-total-m9 2>&1); check "reserved prefix mission-total- (normal mode)" 1 $? "RESERVED_PREFIX_COLLISION" "$out"
# 9. 通常モードの試行カウンタは fable カウンタと独立
out=$(bash "$SCRIPT" t9 5 2>&1); check "normal mode unaffected" 0 $? "attempt 1/5" "$out"
out=$(bash "$SCRIPT" --fable t9 2>&1); check "fable independent of attempts" 0 $? "fable" "$out"
out=$(bash "$SCRIPT" t9 5 2>&1); check "attempts independent of fable" 0 $? "attempt 2/5" "$out"
# 10. 同一 task-id への並行 --fable は正確に 1 回だけ許可される (task カウンタ flock の回帰テスト。
#     並列 worktree からの再試行等で同一 task-id が同時に到達しても「1 タスク 1 回」が破れないこと。
#     レース検査は本質的に確率的だが、test-nesting-guards.sh Group 3 と同型の実効的な回帰網)
conc_out="$HOME/conc-out.txt"
: >"$conc_out"
for _ in $(seq 1 12); do
  ( bash "$SCRIPT" --fable tconc --mission=mconc >>"$conc_out" 2>&1 || true ) &
done
wait
grants=$(grep -c "fable spot" "$conc_out" || true)
denies=$(grep -c "FABLE_BUDGET_EXCEEDED" "$conc_out" || true)
[ "$grants" = "1" ] && [ "$denies" = "11" ]
check "concurrent same-task fable grants exactly once (grants=$grants denies=$denies)" 0 $? "" ""
tval=$(cat "$HOME/.claude/session-data/swarm/budget/_fable-tconc" 2>/dev/null || echo MISSING)
mval=$(cat "$HOME/.claude/session-data/swarm/budget/_fable-mission-total-mconc" 2>/dev/null || echo MISSING)
[ "$tval" = "1" ] && [ "$mval" = "1" ]
check "concurrent counters exact (task=$tval mission=$mval)" 0 $? "" ""

# 11. grant はトークンファイル (.fable-grants/) を発行し、deny は発行しない
gdir="$HOME/.claude/session-data/swarm/budget/.fable-grants"
before=$(ls -1 "$gdir" 2>/dev/null | wc -l)
bash "$SCRIPT" --fable tg1 >/dev/null 2>&1
after_grant=$(ls -1 "$gdir" 2>/dev/null | wc -l)
bash "$SCRIPT" --fable tg1 >/dev/null 2>&1   # task 上限で deny
after_deny=$(ls -1 "$gdir" 2>/dev/null | wc -l)
[ $((after_grant - before)) -eq 1 ] && [ "$after_deny" -eq "$after_grant" ]
check "grant issues token, deny does not (before=$before grant=$after_grant deny=$after_deny)" 0 $? "" ""
# 12. grant/deny が JSONL ログへ記録される
slog="$HOME/.claude/session-data/swarm/fable-spot-log.jsonl"
grants_logged=$(grep -c '"decision":"grant"' "$slog" 2>/dev/null || true)
denies_logged=$(grep -c '"decision":"deny_' "$slog" 2>/dev/null || true)
[ "${grants_logged:-0}" -ge 1 ] && [ "${denies_logged:-0}" -ge 1 ]
check "spot log records grant+deny (grants=$grants_logged denies=$denies_logged)" 0 $? "" ""
# 13. --reset は当該 task の未消費 grant も回収する
bash "$SCRIPT" --reset tg1 >/dev/null 2>&1
leftover=$(ls -1 "$gdir" 2>/dev/null | grep -c -- "-tg1$" || true)
[ "${leftover:-0}" -eq 0 ]
check "reset removes pending grants for task" 0 $? "" ""
# 14. --reset の grant 回収は task-id 完全一致（suffix 衝突の回帰テスト:
#     task "b" の reset が task "a-b" の grant を巻き込んで削除しない。
#     grant ファイル名は <epoch_nanos>-<task-id> で nanos 部にハイフンは無いため、
#     最初のハイフン以降がちょうど task-id）
bash "$SCRIPT" --fable a-b >/dev/null 2>&1
bash "$SCRIPT" --fable b >/dev/null 2>&1
bash "$SCRIPT" --reset b >/dev/null 2>&1
remain_ab=0; remain_b=0
for f in "$gdir"/*; do
  [ -f "$f" ] || continue
  tp="${f##*/}"; tp="${tp#*-}"
  [ "$tp" = "a-b" ] && remain_ab=$((remain_ab+1))
  [ "$tp" = "b" ] && remain_b=$((remain_b+1))
done
[ "$remain_ab" -eq 1 ] && [ "$remain_b" -eq 0 ]
check "reset grant sweep is exact-match (a-b survives=$remain_ab, b removed=$remain_b)" 0 $? "" ""

# 15. spot ログは 1000 行超で直近 500 行へローテーションされる（flock 保護）
slog2="$HOME/.claude/session-data/swarm/fable-spot-log.jsonl"
for i in $(seq 1 1200); do printf '{"ts":"seed","task":"seed%s","mission":"","decision":"grant","task_count":1,"mission_count":0}\n' "$i"; done >>"$slog2"
bash "$SCRIPT" --fable trot >/dev/null 2>&1
lines=$(wc -l <"$slog2")
[ "$lines" -le 501 ] && [ "$lines" -ge 400 ]
check "spot log rotated (lines=$lines, expect <=501)" 0 $? "" ""
tail -1 "$slog2" | grep -q '"task":"trot"'
check "rotation keeps newest entries (last=trot)" 0 $? "" ""
# 16. 期限切れ grant は新規発行時にも掃除される（hook 消費時掃除の補完）
old_grant="$gdir/1000000000000000000-tstale"
mkdir -p "$gdir"; touch "$old_grant"; touch -d '20 minutes ago' "$old_grant"
bash "$SCRIPT" --fable tfresh >/dev/null 2>&1
[ ! -f "$old_grant" ]
check "expired grant pruned at issue time" 0 $? "" ""

# 17. --fable-maker は base spot の消費実績が無ければ拒否（mission 枠回避の抜け穴防止）
out=$(bash "$SCRIPT" --fable-maker nobase 2>&1); check "fable-maker without base denied" 1 $? "FABLE_MAKER_NO_BASE" "$out"
# 17b. -maker サフィックスは継続専用に予約（直接 --fable で base 検証を迂回できない）
out=$(bash "$SCRIPT" --fable sneaky-maker 2>&1); check "-maker suffix reserved for --fable-maker" 1 $? "RESERVED_SUFFIX" "$out"
# 18. base spot 消費後は --fable-maker が <base>-maker の grant を発行し、mission 枠は増えない
bash "$SCRIPT" --fable tm1 --mission=mm1 >/dev/null 2>&1
mval_before=$(cat "$HOME/.claude/session-data/swarm/budget/_fable-mission-total-mm1")
out=$(bash "$SCRIPT" --fable-maker tm1 2>&1); check "fable-maker with base ok" 0 $? "tm1-maker" "$out"
mval_after=$(cat "$HOME/.claude/session-data/swarm/budget/_fable-mission-total-mm1")
[ "$mval_before" = "$mval_after" ]
check "fable-maker does not consume mission budget ($mval_before -> $mval_after)" 0 $? "" ""
# 19. 継続 grant も 1 回のみ（2 回目の --fable-maker は拒否）
out=$(bash "$SCRIPT" --fable-maker tm1 2>&1); check "second fable-maker denied" 1 $? "FABLE_BUDGET_EXCEEDED" "$out"
# 19b. 継続の連鎖は禁止（--fable-maker X-maker が継続カウンタを base 実績と誤認して
#      X-maker-maker... の mission 枠不消費な無限連鎖にならない — Checker が実測した抜け穴の回帰テスト）
out=$(bash "$SCRIPT" --fable-maker tm1-maker 2>&1); check "maker chaining denied" 1 $? "RESERVED_SUFFIX" "$out"
# 20. --reset <base> は -maker のカウンタ・grant も一緒に回収する（非対称の解消）
bash "$SCRIPT" --reset tm1 --mission=mm1 >/dev/null 2>&1
mk_counter="$HOME/.claude/session-data/swarm/budget/_fable-tm1-maker"
mk_grants=0
for f in "$gdir"/*; do
  [ -f "$f" ] || continue
  tp="${f##*/}"; tp="${tp#*-}"
  [ "$tp" = "tm1-maker" ] && mk_grants=$((mk_grants+1))
done
[ ! -f "$mk_counter" ] && [ "$mk_grants" -eq 0 ]
check "reset base cleans -maker counter and grants (counter=$([ -f "$mk_counter" ] && echo present || echo absent), grants=$mk_grants)" 0 $? "" ""

# 21. 定数は fable-budget.conf で単一ソース化（FABLE_BUDGET_CONF で上書き可能、既定は同梱 conf）
cconf="$HOME/custom-budget.conf"
printf 'FABLE_TASK_MAX=2\n' >"$cconf"
FABLE_BUDGET_CONF="$cconf" bash "$SCRIPT" --fable tcfg >/dev/null 2>&1
out=$(FABLE_BUDGET_CONF="$cconf" bash "$SCRIPT" --fable tcfg 2>&1)
check "conf override allows 2nd task spot" 0 $? "fable spot 2/2" "$out"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
