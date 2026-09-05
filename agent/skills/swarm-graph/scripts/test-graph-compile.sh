#!/usr/bin/env bash
# Regression tests for graph-compile.sh.
# 仕様: /tmp/.../swarm/specs/sg-spec.md の「graph-compile.sh 契約」「test-graph-compile.sh 契約」
# 必須ケース 1-19 を実装する(8, 11, 18 はサブケースに分割: 8a/8b/8c, 11a/11b, 18a/18b)。
# case20 は仕様書の必須ケースに含まれない追加の回帰テスト(harden: read_plan_text() 内の
# 個別列挙 except〈FileNotFoundError/UnicodeDecodeError/IsADirectoryError/PermissionError/
# OSError の計5節〉のいずれにも該当しない例外〈KeyError等〉が compile_graph() 側で発生した
# 場合に、末尾の防御的 catch-all〈except Exception〉のみが捕捉し、生 traceback を漏らさず
# 構造化応答〈PARSE_ERROR〉に変換されることを synthetic error injection で確認する。
# 詳細は case20 本体のコメント参照)。
# 様式: claude/skills/swarm-implement/scripts/test-fable-guard.sh 準拠
#   (set -u / mktemp -d 隔離+trap削除 / check() ヘルパ / PASS-FAIL 集計 / 失敗1件以上で exit 1)。
#
# ケース対応表(このファイル内の case ラベルと仕様書「必須ケース」番号の対応):
#   case1  = 1  (ダイヤモンド DAG: width/depth/critical_path/ready)
#   case2  = 2  (3ノード純鎖 --fit → UNFIT_FALLBACK_LOOP)
#   case3  = 3  (タスク2件 --fit → UNFIT_FALLBACK_LOOP)
#   case4  = 4  (閉路 a→b→a → CYCLE)
#   case5  = 5  (存在しない depends → MISSING_DEP)
#   case6  = 6  (done上流→pending下流がready、blockedは除外)
#   case7  = 7  (--stale で下流doneのみ、pendingは含めない)
#   case8a/8b/8c = 8 (非docs-wiringのverify:skipはVERIFIER_FLOOR、docs-wiringは許可、部分一致は非マッチ)
#   case9  = 9  (depends "-" は依存なし)
#   case10 = 10 (複数 ## Tasks 節、最後の節のみ有効)
#   case11a/11b = 11 (Tasksテーブル無し/空 → NO_TASKS)
#   case12 = 12 (節スコープ: Secretary Report の表がノード化されない)
#   case13 = 13 (stale かつ依存全done → ready に含まれる)
#   case14 = 14 (未知 status → readyから除外・warningsに記録)
#   case15 = 15 (非連結の森、width=2、--fit でも OK)
#   case16 = 16 (cycle+missing-dep 共存 → 優先順どおり CYCLE(exit 3))
#   case17 = 17 (rev3: 不正 UTF-8 → PARSE_ERROR exit7, stdout に traceback を含まない)
#   case18a/18b = 18 (rev3: plan-path がディレクトリ→PARSE_ERROR exit7 / 不在→NO_TASKS exit6 従来どおり)
#   case19 = 19 (rev3: セル数9の不整形行→ノード化されず warnings 記録、他の整形行は正常処理)
#   case20 = (仕様書に無い追加ケース、上記 harden 説明参照。synthetic KeyError injection→末尾catch-all単体)
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SELF_DIR/graph-compile.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0

check() { # check <desc> <expected-exit> <actual-exit> [<must-match-pattern> <output>]
  local desc="$1" want="$2" got="$3" pat="${4:-}" out="${5:-}"
  if [ "$want" != "$got" ]; then
    echo "FAIL: $desc (exit want=$want got=$got)"
    [ -n "$out" ] && echo "  output: $out"
    fail=$((fail + 1))
    return
  fi
  if [ -n "$pat" ] && ! grep -q -- "$pat" <<<"$out"; then
    echo "FAIL: $desc (output missing '$pat'): $out"
    fail=$((fail + 1))
    return
  fi
  echo "ok: $desc"
  pass=$((pass + 1))
}

pycheck() { # pycheck <desc> <json-string> <python-assert-code (references `d`)>
  local desc="$1" json="$2" code="$3" err
  if err=$(JSON="$json" python3 -c '
import json, os
d = json.loads(os.environ["JSON"])
'"$code"'
' 2>&1); then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc: $err"
    fail=$((fail + 1))
  fi
}

run() { # run <plan-path> [options...] -> sets OUT (stdout), RC (exit code)
  local plan="$1"
  shift
  OUT=$(bash "$SCRIPT" "$@" "$plan" 2>"$WORK/stderr.log")
  RC=$?
}

# ---------------------------------------------------------------------------
# case1: ダイヤモンド DAG(4 nodes) → exit 0、width=2、depth=3、critical_path が
# 経路として妥当(長さ3・先頭がルート・隣接ペアが edges に存在)、ready=ルートのみ
plan="$WORK/case1.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | root task | - | - | pending | 0 | impl | - |
| b | left branch | a | - | pending | 0 | impl | - |
| c | right branch | a | - | pending | 0 | impl | - |
| d | join task | b,c | - | pending | 0 | impl | - |
PLAN
run "$plan"
check "case1: diamond DAG exit 0" 0 "$RC" "" "$OUT"
pycheck "case1: verdict OK" "$OUT" 'assert d["verdict"] == "OK", d["verdict"]'
pycheck "case1: width=2 depth=3" "$OUT" '
m = d["metrics"]
assert m["width"] == 2, m
assert m["depth"] == 3, m
'
pycheck "case1: critical_path plausible (len3, root-first, edges-adjacent)" "$OUT" '
nodes = {n["id"]: n for n in d["nodes"]}
edges = set(tuple(e) for e in d["edges"])
cp = d["metrics"]["critical_path"]
assert len(cp) == 3, cp
assert nodes[cp[0]]["depends"] == [], (cp, nodes[cp[0]])
for i in range(len(cp) - 1):
    assert (cp[i], cp[i + 1]) in edges, (cp, edges)
'
pycheck "case1: ready is root only" "$OUT" 'assert sorted(d["ready"]) == ["a"], d["ready"]'

# ---------------------------------------------------------------------------
# case2: 3ノード純鎖 → --fit で exit 2 / UNFIT_FALLBACK_LOOP (width==1 が発動条件)
plan="$WORK/case2.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | step1 | - | - | pending | 0 | impl | - |
| b | step2 | a | - | pending | 0 | impl | - |
| c | step3 | b | - | pending | 0 | impl | - |
PLAN
run "$plan" --fit
check "case2: 3-node chain --fit exit 2" 2 "$RC" "" "$OUT"
pycheck "case2: verdict UNFIT_FALLBACK_LOOP" "$OUT" 'assert d["verdict"] == "UNFIT_FALLBACK_LOOP", d["verdict"]'

# ---------------------------------------------------------------------------
# case3: タスク2件 → --fit で exit 2(タスク数<=2 が発動条件。width=2でも該当)
plan="$WORK/case3.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | only task 1 | - | - | pending | 0 | impl | - |
| b | only task 2 | - | - | pending | 0 | impl | - |
PLAN
run "$plan" --fit
check "case3: 2-task plan --fit exit 2" 2 "$RC" "" "$OUT"
pycheck "case3: verdict UNFIT_FALLBACK_LOOP" "$OUT" 'assert d["verdict"] == "UNFIT_FALLBACK_LOOP", d["verdict"]'

# ---------------------------------------------------------------------------
# case4: 閉路 a→b→a → exit 3
plan="$WORK/case4.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | cycle node a | b | - | pending | 0 | impl | - |
| b | cycle node b | a | - | pending | 0 | impl | - |
PLAN
run "$plan"
check "case4: cycle a<->b exit 3" 3 "$RC" "" "$OUT"
pycheck "case4: verdict CYCLE" "$OUT" 'assert d["verdict"] == "CYCLE", d["verdict"]'

# ---------------------------------------------------------------------------
# case5: 存在しない depends → exit 4
plan="$WORK/case5.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | dangling dep | zzz | - | pending | 0 | impl | - |
PLAN
run "$plan"
check "case5: missing dep exit 4" 4 "$RC" "" "$OUT"
pycheck "case5: verdict MISSING_DEP" "$OUT" 'assert d["verdict"] == "MISSING_DEP", d["verdict"]'

# ---------------------------------------------------------------------------
# case6: 上流 done のとき下流 pending が ready に入る / blocked ノードは ready に入らない
plan="$WORK/case6.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | upstream done | - | - | done | 1 | impl | - |
| b | downstream pending | a | - | pending | 0 | impl | - |
| c | downstream blocked | a | - | blocked(budget) | 5 | impl | - |
PLAN
run "$plan"
check "case6: mixed ready set exit 0" 0 "$RC" "" "$OUT"
pycheck "case6: ready includes pending, excludes done/blocked" "$OUT" 'assert sorted(d["ready"]) == ["b"], d["ready"]'

# ---------------------------------------------------------------------------
# case7: --stale <mid> → 下流の done ノードのみ列挙(pending は含まない)
plan="$WORK/case7.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | upstream | - | - | done | 1 | impl | - |
| b | mid | a | - | done | 1 | impl | - |
| c | downstream done | b | - | done | 1 | impl | - |
| d | downstream pending | b | - | pending | 0 | impl | - |
PLAN
run "$plan" --stale b
check "case7: --stale b exit 0" 0 "$RC" "" "$OUT"
pycheck "case7: stale_closure has only downstream done (excludes pending/self/upstream)" "$OUT" '
assert sorted(d["stale_closure"]) == ["c"], d["stale_closure"]
'

# ---------------------------------------------------------------------------
# case8a: 非 docs-wiring ノードの verify:skip(note の独立トークン) → exit 5
plan="$WORK/case8a.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | non docs-wiring skip | - | - | pending | 0 | impl | needs-review verify:skip |
PLAN
run "$plan"
check "case8a: verify:skip outside docs-wiring exit 5" 5 "$RC" "" "$OUT"
pycheck "case8a: verdict VERIFIER_FLOOR" "$OUT" 'assert d["verdict"] == "VERIFIER_FLOOR", d["verdict"]'

# case8b: docs-wiring ノードの verify:skip は許可 → exit 0
plan="$WORK/case8b.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | docs-wiring skip allowed | - | - | pending | 0 | docs-wiring | verify:skip |
PLAN
run "$plan"
check "case8b: verify:skip in docs-wiring exit 0" 0 "$RC" "" "$OUT"
pycheck "case8b: verdict OK" "$OUT" 'assert d["verdict"] == "OK", d["verdict"]'

# case8c: 部分一致トークン "verify:skipxyz" はマッチしない → exit 0
plan="$WORK/case8c.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | partial token no match | - | - | pending | 0 | impl | verify:skipxyz |
PLAN
run "$plan"
check "case8c: verify:skipxyz partial token no match exit 0" 0 "$RC" "" "$OUT"
pycheck "case8c: verdict OK (no VERIFIER_FLOOR)" "$OUT" 'assert d["verdict"] == "OK", d["verdict"]'

# ---------------------------------------------------------------------------
# case9: depends "-" → 依存なしとして扱う
plan="$WORK/case9.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | no deps dash | - | - | pending | 0 | impl | - |
PLAN
run "$plan"
check "case9: depends dash exit 0" 0 "$RC" "" "$OUT"
pycheck "case9: depends dash treated as no deps, node is ready" "$OUT" '
nodes = {n["id"]: n for n in d["nodes"]}
assert nodes["a"]["depends"] == [], nodes["a"]
assert sorted(d["ready"]) == ["a"], d["ready"]
'

# ---------------------------------------------------------------------------
# case10: `## Tasks` 節が複数あるとき最後の節のみ有効(v1 のみのノードは現れない)
plan="$WORK/case10.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| old | stale v1 node | - | - | pending | 0 | impl | - |

## Tasks (v2)
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| new | current v2 node | - | - | pending | 0 | impl | - |
PLAN
run "$plan"
check "case10: multiple Tasks sections exit 0" 0 "$RC" "" "$OUT"
pycheck "case10: only last section node present (old excluded)" "$OUT" '
ids = sorted(n["id"] for n in d["nodes"])
assert ids == ["new"], ids
'

# ---------------------------------------------------------------------------
# case11a: `## Tasks` 見出し自体が無い → exit 6
plan="$WORK/case11a.md"
cat >"$plan" <<'PLAN'
# @fix_plan.md — mission: no-tasks-heading

- goal: dummy mission for RED test

## Definition of Done
- N/A (test fixture, no Tasks section present)
PLAN
run "$plan"
check "case11a: no Tasks heading exit 6" 6 "$RC" "" "$OUT"
pycheck "case11a: verdict NO_TASKS" "$OUT" 'assert d["verdict"] == "NO_TASKS", d["verdict"]'

# case11b: `## Tasks` 見出しはあるがテーブルが空(ヘッダ+区切りのみ) → exit 6
plan="$WORK/case11b.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
PLAN
run "$plan"
check "case11b: empty Tasks table exit 6" 6 "$RC" "" "$OUT"
pycheck "case11b: verdict NO_TASKS" "$OUT" 'assert d["verdict"] == "NO_TASKS", d["verdict"]'

# ---------------------------------------------------------------------------
# case12: 節スコープ — `## Secretary Report` 節の markdown table 行はノード化されない
plan="$WORK/case12.md"
cat >"$plan" <<'PLAN'
## Secretary Report
| priority | note |
|----------|------|
| P0 | secret-node should not be a task node |

## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | real task | - | - | pending | 0 | impl | - |
PLAN
run "$plan"
check "case12: section-scoped parse exit 0" 0 "$RC" "" "$OUT"
pycheck "case12: secretary report row not nodeized" "$OUT" '
ids = sorted(n["id"] for n in d["nodes"])
assert ids == ["a"], ids
'

# ---------------------------------------------------------------------------
# case13: stale かつ依存全 done のノードが ready に含まれる
plan="$WORK/case13.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | upstream done | - | - | done | 1 | impl | - |
| b | stale revalidation | a | - | stale | 1 | impl | - |
PLAN
run "$plan"
check "case13: stale with done deps exit 0" 0 "$RC" "" "$OUT"
pycheck "case13: stale node is ready" "$OUT" 'assert "b" in d["ready"], d["ready"]'

# ---------------------------------------------------------------------------
# case14: 未知 status(`wip`) → ready から除外され、warnings に含まれる
plan="$WORK/case14.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| x | unknown status node | - | - | wip | 0 | impl | - |
| y | normal pending node | - | - | pending | 0 | impl | - |
PLAN
run "$plan"
check "case14: unknown status not fatal, exit 0" 0 "$RC" "" "$OUT"
code14=$(cat <<'PYCODE'
assert sorted(d["ready"]) == ["y"], d["ready"]
assert "unknown status 'wip' on x" in d["warnings"], d["warnings"]
PYCODE
)
pycheck "case14: unknown status excluded from ready + warned" "$OUT" "$code14"

# ---------------------------------------------------------------------------
# case15: 非連結の森(2つの独立チェーン 2+2) → width=2(レベル幅)、--fit でも exit 0
plan="$WORK/case15.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a1 | chain A root | - | - | pending | 0 | impl | - |
| a2 | chain A leaf | a1 | - | pending | 0 | impl | - |
| b1 | chain B root | - | - | pending | 0 | impl | - |
| b2 | chain B leaf | b1 | - | pending | 0 | impl | - |
PLAN
run "$plan" --fit
check "case15: disconnected forest --fit exit 0 (width=2 avoids UNFIT)" 0 "$RC" "" "$OUT"
pycheck "case15: width=2 across whole forest" "$OUT" '
m = d["metrics"]
assert m["width"] == 2, m
'

# ---------------------------------------------------------------------------
# case16: 複数エラー共存(cycle + missing dep) → 優先順どおり exit 3(CYCLE 優先)
plan="$WORK/case16.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | cycle node a | b | - | pending | 0 | impl | - |
| b | cycle node b | a | - | pending | 0 | impl | - |
| c | dangling dep node | zzz | - | pending | 0 | impl | - |
PLAN
run "$plan"
check "case16: cycle+missing-dep coexist, priority exit 3" 3 "$RC" "" "$OUT"
pycheck "case16: verdict CYCLE wins priority over MISSING_DEP" "$OUT" 'assert d["verdict"] == "CYCLE", d["verdict"]'

# ---------------------------------------------------------------------------
# case17 (rev3): 不正 UTF-8 バイトを含む plan → exit 7 (PARSE_ERROR)。
# stdout は有効な JSON であり、Python の生 traceback を一切含まない。
plan="$WORK/case17.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | normal task | - | - | pending | 0 | impl | - |
PLAN
printf '\xff\xfe invalid utf-8 tail\n' >>"$plan"
run "$plan"
check "case17: invalid UTF-8 exit 7 (PARSE_ERROR)" 7 "$RC" "" "$OUT"
if grep -qi "traceback" <<<"$OUT"; then
  echo "FAIL: case17: stdout leaks a Python traceback: $OUT"
  fail=$((fail + 1))
else
  echo "ok: case17: stdout has no traceback"
  pass=$((pass + 1))
fi
pycheck "case17: verdict PARSE_ERROR with a warnings cause" "$OUT" '
assert d["verdict"] == "PARSE_ERROR", d["verdict"]
assert len(d["warnings"]) >= 1, d["warnings"]
'

# ---------------------------------------------------------------------------
# case18a (rev3): plan-path にディレクトリを渡す → exit 7 / PARSE_ERROR (NO_TASKS にしない)
plan="$WORK/case18-dir"
mkdir -p "$plan"
run "$plan"
check "case18a: plan-path is a directory exit 7 (PARSE_ERROR)" 7 "$RC" "" "$OUT"
pycheck "case18a: verdict PARSE_ERROR" "$OUT" 'assert d["verdict"] == "PARSE_ERROR", d["verdict"]'

# case18b (rev3): plan-path 不在 → 従来どおり exit 6 / NO_TASKS (変更なし)
plan="$WORK/case18-missing.md"
run "$plan"
check "case18b: missing plan-path exit 6 (NO_TASKS, unchanged)" 6 "$RC" "" "$OUT"
pycheck "case18b: verdict NO_TASKS" "$OUT" 'assert d["verdict"] == "NO_TASKS", d["verdict"]'

# ---------------------------------------------------------------------------
# case19 (rev3): セル数9の不整形行(summary に生 "|") → その行はノード化されず
# warnings に malformed row エントリが記録される。他の整形行 (a) は正常処理され、
# 不整形行由来の bogus MISSING_DEP は出さない (exit 0 / OK)。
plan="$WORK/case19.md"
cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | normal task | - | - | pending | 0 | impl | - |
| b | broken|summary | - | - | pending | 0 | impl | - |
PLAN
run "$plan"
check "case19: malformed row excluded, exit 0 (no bogus MISSING_DEP)" 0 "$RC" "" "$OUT"
pycheck "case19: only well-formed node present + malformed row warned" "$OUT" '
ids = sorted(n["id"] for n in d["nodes"])
assert ids == ["a"], ids
assert d["verdict"] == "OK", d["verdict"]
assert any(w.startswith("malformed row (ncells=9)") for w in d["warnings"]), d["warnings"]
'

# ---------------------------------------------------------------------------
# case20 (harden, 仕様書の必須ケースに含まれない追加テスト、synthetic error injection):
# read_plan_text() の個別列挙 except(FileNotFoundError/UnicodeDecodeError/
# IsADirectoryError/PermissionError/OSError の計5節。symlink loop の ELOOP は OSError の
# サブクラスであり実際にはこの5番目の except で捕捉されるため、末尾 catch-all の単体テストには
# ならない — 過去の実装ミス)のいずれにも該当しない例外(KeyError 等)が発生した場合に、
# 323-329行目付近の末尾 catch-all(except Exception as e: parse_error(...))だけが捕捉して
# exit 7 / PARSE_ERROR に変換し、生 traceback を漏らさないことを確認する。
#
# 現実的な plan 入力のみで compile_graph() 内に非 OSError 例外(KeyError/TypeError 等)を
# 発生させられる箇所は存在しない(全ての辞書アクセスが既知ノード集合 `nodes` の `in` チェックで
# ガードされている、graph-compile.sh 106-315行目参照)。そのため graph-compile.sh の一時コピー
# ($WORK 配下、非コミット)を作成し、compile_graph() の先頭に合成例外
# `raise KeyError("synthetic-test-case20-injected-error")` を注入したうえで走らせる
# (synthetic error injection)。末尾 catch-all 自体は本物の graph-compile.sh からのコピーで
# 無変更であり、これが正しく機能することを検証する。
loop_script="$WORK/case20-graph-compile.sh"
sed 's/^def compile_graph(text):$/&\n    raise KeyError("synthetic-test-case20-injected-error")/' "$SCRIPT" >"$loop_script"
if ! grep -q 'synthetic-test-case20-injected-error' "$loop_script"; then
  echo "FAIL: case20: injection anchor 'def compile_graph(text):' not found in $SCRIPT"
  fail=$((fail + 1))
else
  plan="$WORK/case20.md"
  cat >"$plan" <<'PLAN'
## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | normal task | - | - | pending | 0 | impl | - |
PLAN
  OUT=$(bash "$loop_script" "$plan" 2>"$WORK/stderr.log")
  RC=$?
  check "case20: synthetic non-OSError exception exit 7 (PARSE_ERROR)" 7 "$RC" "" "$OUT"
  if grep -qi "traceback" <<<"$OUT"; then
    echo "FAIL: case20: stdout leaks a Python traceback: $OUT"
    fail=$((fail + 1))
  else
    echo "ok: case20: stdout has no traceback"
    pass=$((pass + 1))
  fi
  pycheck "case20: verdict PARSE_ERROR names the injected KeyError" "$OUT" '
assert d["verdict"] == "PARSE_ERROR", d["verdict"]
assert any("KeyError" in w for w in d["warnings"]), d["warnings"]
'
fi

# ---------------------------------------------------------------------------
echo "----"
echo "pass=$pass fail=$fail"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
