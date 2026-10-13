#!/usr/bin/env bash
# Regression tests for harness-select.sh / harness-lint.sh / harness-record.sh
# (swarm-meta skill の回帰テストスイート)。
# 仕様: /tmp/a970d944-5c72-44e0-bf62-429e73ed60c4/swarm/specs/sm-spec.md
#       「test-harness-guard.sh 契約」必須ケース 1〜15。
# 様式: swarm-implement/scripts/test-fable-guard.sh 準拠 (set -u / mktemp -d 隔離 / check() /
#       PASS・FAIL 集計 / 失敗 1 件以上で exit 1)。
#
# ケース番号対応表 (report 用):
#   1  select: 並行語彙 goal → harness=swarm-graph
#   2  select: 逐次/小規模 goal → harness=swarm-loop
#   3  select: 中立 goal → harness=swarm-loop (保守デフォルト)
#   4  select: リスク+逐次 goal → harness=swarm-loop かつ lenses に code-reviewer
#      (+ secret 語で security-audit も追加)
#   5  select: registry 降格 (2/3 で降格・1/3 で非降格・パース不能行は分母除外)
#   6  select: est_tasks 抽出 (3→非該当, 2→<=2 で swarm-loop, 無し→null)
#   7  select: --profile-only は recommendation 無し・exit 0
#   8  select: 存在ガード (swarm-graph/SKILL.md 欠如 → swarm-loop + harness-unavailable)
#   9  lint: 正常 plan → exit 0
#   10 lint: VERIFIER_FLOOR (checker!=opus / deterministic空 / skip checker 文言) → exit 2
#   11 lint: WRITE_SCOPE (sed -i / Edit(...) 形式) → exit 3、誤検知ガード3種 → exit 0
#   12 lint: LINT_SCHEMA/BUDGET_BOUNDS/ROUTING 各種単独違反 → exit 1/4/5
#   13 lint: 多重違反の優先順 (1→4→5→2→3) → exit 4
#   14 record: 新規追記/同一slug置換/TAB・改行正規化
#   15 record: 並行8プロセス追記で行落ちなし (flock)
#   16 select: 存在ガード両欠落 (swarm-loop/swarm-graph 共に無し → 自己矛盾を避け swarm-loop)
#   17 select: 実 git リポジトリでの profile 抽出 (`git ls-files | python3 - <<EOF` stdin競合の回帰)
#   18 (impl-meta) select: 不正 UTF-8 registry → クラッシュせず exit 0・rationale に registry-unreadable
#   19 (impl-meta) lint: 不正 UTF-8 plan → exit 1・stderr が LINT_SCHEMA: で始まり Traceback 非含有
#   20 (impl-meta) lint: plan にディレクトリを渡す → 19 と同様 exit 1・LINT_SCHEMA: 形式
#   21-24 (impl-meta) harness-status.sh: 空registry/複数行集計/不正行skip+warning/primary反復判定
#   25 (impl-meta rev2) select: 正常blocked>done過半3行+不正UTF-8行1行 → (C)降格は行単位skipで引き続き
#      発火 (all-or-nothingで安全弁を沈黙無効化しない)・rationaleにlines skipped言及
#   26 (regression) record: flock (util-linux) 未導入環境で fail-closed (exit 1・registry無変更)。
#      既存 1-25 の番号は不変のため 25 の後ろへ割り当てるが、内容的関連は Case 15 (flock 使用箇所)
#      側にあるためファイル本文では Case 15 の直後に配置する
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELECT="$here/harness-select.sh"
LINT="$here/harness-lint.sh"
STATUS="$here/harness-status.sh"
RECORD="$here/harness-record.sh"

export HOME="$(mktemp -d)"      # 実 ~/.claude/skills を汚さない隔離 HOME
WORK="$(mktemp -d)"             # フィクスチャ・一時ファイル置き場
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

# JSON 内容の厳密な検証 (文字列 grep だけに頼らない)。stdin の python コードは
# 変数 d (json.load 済み) を参照できる。assert 失敗 or 例外で FAIL。
pyassert() { # pyassert <desc> <jsonfile>  (python code via stdin)
  local desc="$1" jsonfile="$2" pyfile errout rc
  pyfile="$(mktemp -p "$WORK")"
  { printf 'import json,sys\n'; printf 'd=json.load(open(sys.argv[1]))\n'; cat; } >"$pyfile"
  errout=$(python3 "$pyfile" "$jsonfile" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "ok: $desc"; pass=$((pass+1))
  else
    echo "FAIL: $desc ($errout)"; fail=$((fail+1))
  fi
}

# --- select.sh 用の既定 fixture (repo-root は非 git tmp dir で langs=[] に固定) ---
REPO="$WORK/repo-root"
mkdir -p "$REPO"

DEFAULT_SKILLS="$WORK/default-skills"
mkdir -p "$DEFAULT_SKILLS/swarm-loop" "$DEFAULT_SKILLS/swarm-graph"
printf '# swarm-loop dummy SKILL.md\n' >"$DEFAULT_SKILLS/swarm-loop/SKILL.md"
printf '# swarm-graph dummy SKILL.md\n' >"$DEFAULT_SKILLS/swarm-graph/SKILL.md"

DEFAULT_REGISTRY="$WORK/default-registry.tsv"
printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$DEFAULT_REGISTRY"

export HARNESS_SKILLS_DIR="$DEFAULT_SKILLS"
export HARNESS_REGISTRY="$DEFAULT_REGISTRY"

run_select() { # run_select [--profile-only] <goal> [repo-root] ; sets SOUT(stdout) SRC
  SOUT=$(bash "$SELECT" "$@" 2>"$WORK/last_select_stderr.log")
  SRC=$?
}

# ============================================================
# Case 1: 並行語彙 goal → recommendation.harness=swarm-graph
# ============================================================
GOAL_PARALLEL="全 SKILL.md を横断監査して並列修正"
run_select "$GOAL_PARALLEL" "$REPO"
check "case1: select exits 0" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case1.json"
pyassert "case1: harness=swarm-graph for parallel-vocab goal" "$WORK/case1.json" <<'PYEOF'
h = d["recommendation"]["harness"]
assert h == "swarm-graph", "got harness=%r" % h
PYEOF

# ============================================================
# Case 2: 逐次/小規模 goal → swarm-loop
# ============================================================
GOAL_SEQUENTIAL="zshrc の typo を 1 ファイル直す"
run_select "$GOAL_SEQUENTIAL" "$REPO"
check "case2: select exits 0" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case2.json"
pyassert "case2: harness=swarm-loop for sequential/small-scope goal" "$WORK/case2.json" <<'PYEOF'
h = d["recommendation"]["harness"]
assert h == "swarm-loop", "got harness=%r" % h
PYEOF

# ============================================================
# Case 3: シグナル無し中立 goal → swarm-loop (保守デフォルト)
# ============================================================
GOAL_NEUTRAL="ドキュメントの表記を整える"
run_select "$GOAL_NEUTRAL" "$REPO"
check "case3: select exits 0" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case3.json"
pyassert "case3: harness=swarm-loop for neutral/no-signal goal (conservative default)" "$WORK/case3.json" <<'PYEOF'
h = d["recommendation"]["harness"]
assert h == "swarm-loop", "got harness=%r" % h
PYEOF

# ============================================================
# Case 4: リスク+逐次 goal → harness=swarm-loop かつ lenses に code-reviewer
#         ((A)lenses と (B)harness の独立性)。secret 語を含む場合は security-audit も追加
# ============================================================
GOAL_RISK_SEQ="本番 hook を順に修正して merge"
run_select "$GOAL_RISK_SEQ" "$REPO"
check "case4: select exits 0" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case4.json"
pyassert "case4: harness=swarm-loop with code-reviewer lens (risk+sequential goal)" "$WORK/case4.json" <<'PYEOF'
r = d["recommendation"]
assert r["harness"] == "swarm-loop", "got harness=%r" % r["harness"]
assert "code-reviewer" in r["lenses"], "lenses missing code-reviewer: %r" % r["lenses"]
assert "security-audit" not in r["lenses"], "security-audit unexpectedly added: %r" % r["lenses"]
PYEOF

GOAL_RISK_SEQ_SECRET="本番 hook の secret 設定を順に修正して merge"
run_select "$GOAL_RISK_SEQ_SECRET" "$REPO"
check "case4b: select exits 0 (secret variant)" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case4b.json"
pyassert "case4b: secret goal adds security-audit alongside code-reviewer" "$WORK/case4b.json" <<'PYEOF'
r = d["recommendation"]
assert r["harness"] == "swarm-loop", "got harness=%r" % r["harness"]
assert "code-reviewer" in r["lenses"], "lenses missing code-reviewer: %r" % r["lenses"]
assert "security-audit" in r["lenses"], "lenses missing security-audit: %r" % r["lenses"]
PYEOF

# ============================================================
# Case 5: registry 降格 (harness=swarm-graph 行のみが対象、primary 一致行から抽出)
# ============================================================
# 5a: 3件中2件 blocked>done → 降格 + rationale に registry-downgrade:2/3
#     (同 primary だが harness=swarm-loop のノイズ行が 1 件混在 → (C) の harness フィルタで
#     除外されねばならない。誤って含めると分母が変わり "2/3" という厳密文字列に一致しなくなる)
REG_A="$WORK/registry-a.tsv"
printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$REG_A"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-01" "rgA-1" "swarm-graph" "parallel" "claude-sonnet-5" "done=1 blocked=3 attempts=6 replans=1" >>"$REG_A"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-02" "rgA-2" "swarm-graph" "parallel" "claude-sonnet-5" "done=4 blocked=5 attempts=9 replans=0" >>"$REG_A"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-03" "rgA-3" "swarm-graph" "parallel" "claude-sonnet-5" "done=5 blocked=1 attempts=6 replans=0" >>"$REG_A"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-04" "rgA-4" "swarm-loop"  "parallel" "claude-sonnet-5" "done=1 blocked=9 attempts=10 replans=2" >>"$REG_A"
SOUT=$(HARNESS_REGISTRY="$REG_A" bash "$SELECT" "$GOAL_PARALLEL" "$REPO" 2>"$WORK/last_select_stderr.log"); SRC=$?
check "case5a: select exits 0" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case5a.json"
pyassert "case5a: 2/3 swarm-graph rows blocked>done -> downgrade to swarm-loop" "$WORK/case5a.json" <<'PYEOF'
r = d["recommendation"]
assert r["harness"] == "swarm-loop", "expected downgrade to swarm-loop, got %r" % r["harness"]
assert any("registry-downgrade:2/3" in x for x in r["rationale"]), "rationale missing registry-downgrade:2/3: %r" % r["rationale"]
PYEOF

# 5b: 3件中1件のみ blocked>done → 非降格 (harness=swarm-graph のまま)
REG_B="$WORK/registry-b.tsv"
printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$REG_B"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-05" "rgB-1" "swarm-graph" "parallel" "claude-sonnet-5" "done=1 blocked=2 attempts=5 replans=0" >>"$REG_B"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-06" "rgB-2" "swarm-graph" "parallel" "claude-sonnet-5" "done=5 blocked=1 attempts=6 replans=0" >>"$REG_B"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-07" "rgB-3" "swarm-graph" "parallel" "claude-sonnet-5" "done=6 blocked=2 attempts=8 replans=0" >>"$REG_B"
SOUT=$(HARNESS_REGISTRY="$REG_B" bash "$SELECT" "$GOAL_PARALLEL" "$REPO" 2>"$WORK/last_select_stderr.log"); SRC=$?
check "case5b: select exits 0" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case5b.json"
pyassert "case5b: 1/3 blocked>done -> no downgrade, harness stays swarm-graph" "$WORK/case5b.json" <<'PYEOF'
r = d["recommendation"]
assert r["harness"] == "swarm-graph", "expected no downgrade, got %r" % r["harness"]
assert not any("registry-downgrade" in x for x in r["rationale"]), "unexpected downgrade rationale: %r" % r["rationale"]
PYEOF

# 5c: パース不能行 1 件を含む 4 行中、パース可能な 3 行のうち 2 件 blocked>done
#     → 分母はパース不能行を除いた 3 (denominator=3、"2/4" になってはいけない)
REG_C="$WORK/registry-c.tsv"
printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$REG_C"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-08" "rgC-1" "swarm-graph" "parallel" "claude-sonnet-5" "done=1 blocked=3 attempts=6 replans=1" >>"$REG_C"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-09" "rgC-2" "swarm-graph" "parallel" "claude-sonnet-5" "done=4 blocked=5 attempts=9 replans=0" >>"$REG_C"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-10" "rgC-3" "swarm-graph" "parallel" "claude-sonnet-5" "done=5 blocked=1 attempts=6 replans=0" >>"$REG_C"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-11" "rgC-4" "swarm-graph" "parallel" "claude-sonnet-5" "status=unknown" >>"$REG_C"
SOUT=$(HARNESS_REGISTRY="$REG_C" bash "$SELECT" "$GOAL_PARALLEL" "$REPO" 2>"$WORK/last_select_stderr.log"); SRC=$?
check "case5c: select exits 0" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case5c.json"
pyassert "case5c: unparseable row excluded from denominator (2/3, not 2/4)" "$WORK/case5c.json" <<'PYEOF'
r = d["recommendation"]
assert r["harness"] == "swarm-loop", "expected downgrade to swarm-loop, got %r" % r["harness"]
assert any("registry-downgrade:2/3" in x for x in r["rationale"]), "rationale missing registry-downgrade:2/3: %r" % r["rationale"]
assert not any("2/4" in x for x in r["rationale"]), "unparseable row leaked into denominator: %r" % r["rationale"]
PYEOF

# ============================================================
# Case 6: est_tasks 抽出
# ============================================================
GOAL_EST3="3 ファイルの修正をお願いします"
run_select "$GOAL_EST3" "$REPO"
check "case6a: select exits 0" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case6a.json"
pyassert "case6a: est_tasks=3 extracted, not <=2 so rule1 non-applicable (default swarm-loop)" "$WORK/case6a.json" <<'PYEOF'
et = d["profile"]["est_tasks"]
assert et == 3, "expected est_tasks=3, got %r" % et
h = d["recommendation"]["harness"]
assert h == "swarm-loop", "expected default swarm-loop (est_tasks=3 not <=2), got %r" % h
PYEOF

GOAL_EST2="2 箇所直す"
run_select "$GOAL_EST2" "$REPO"
check "case6b: select exits 0" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case6b.json"
pyassert "case6b: est_tasks=2 extracted and <=2 triggers harness=swarm-loop" "$WORK/case6b.json" <<'PYEOF'
et = d["profile"]["est_tasks"]
assert et == 2, "expected est_tasks=2, got %r" % et
h = d["recommendation"]["harness"]
assert h == "swarm-loop", "expected swarm-loop via est_tasks<=2 rule, got %r" % h
PYEOF

GOAL_EST_NONE="デザインを検討する"
run_select "$GOAL_EST_NONE" "$REPO"
check "case6c: select exits 0" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case6c.json"
pyassert "case6c: no scale hint -> est_tasks is null" "$WORK/case6c.json" <<'PYEOF'
et = d["profile"]["est_tasks"]
assert et is None, "expected est_tasks=null, got %r" % et
PYEOF

# ============================================================
# Case 7: --profile-only は recommendation キーを含まない・exit は常に 0
# ============================================================
run_select --profile-only "$GOAL_PARALLEL" "$REPO"
check "case7: --profile-only exits 0" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case7.json"
pyassert "case7: --profile-only output has no recommendation key" "$WORK/case7.json" <<'PYEOF'
assert "recommendation" not in d, "recommendation key unexpectedly present: %r" % list(d.keys())
assert "profile" in d, "profile key missing: %r" % list(d.keys())
PYEOF

# ============================================================
# Case 8: 存在ガード — HARNESS_SKILLS_DIR に swarm-graph/SKILL.md が無い状態で並行 goal
#         → swarm-loop + rationale に harness-unavailable:swarm-graph
# ============================================================
NOGRAPH_SKILLS="$WORK/noGraph-skills"
mkdir -p "$NOGRAPH_SKILLS/swarm-loop"
printf '# swarm-loop dummy\n' >"$NOGRAPH_SKILLS/swarm-loop/SKILL.md"
# swarm-graph は意図的に欠落させる (mkdir しない)
SOUT=$(HARNESS_SKILLS_DIR="$NOGRAPH_SKILLS" bash "$SELECT" "$GOAL_PARALLEL" "$REPO" 2>"$WORK/last_select_stderr.log"); SRC=$?
check "case8: select exits 0" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case8.json"
pyassert "case8: missing swarm-graph/SKILL.md -> fallback swarm-loop + harness-unavailable rationale" "$WORK/case8.json" <<'PYEOF'
r = d["recommendation"]
assert r["harness"] == "swarm-loop", "expected fallback swarm-loop, got %r" % r["harness"]
assert any("harness-unavailable:swarm-graph" in x for x in r["rationale"]), "rationale missing harness-unavailable:swarm-graph: %r" % r["rationale"]
PYEOF

# ============================================================
# lint.sh 用フィクスチャ
# ============================================================
PLANDIR="$WORK/plans"
mkdir -p "$PLANDIR"

run_lint() { # run_lint <planfile> ; sets LOUT(stderr) LRC
  LOUT=$(bash "$LINT" "$1" 2>&1 1>/dev/null)
  LRC=$?
}

# baseline: 完全に正常な plan (case9 で使用、以降の case はここから 1 箇所ずつ変更する)
cat >"$PLANDIR/valid.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "verification": {
    "checker": "opus",
    "deterministic": ["make lint", "make test/pkg"],
    "lenses": ["code-reviewer"]
  },
  "budget": {"task_max": 5, "mission_max": 20},
  "routing": {"maker": "sonnet", "fixer": "sonnet"},
  "steps": ["Read swarm-loop/SKILL.md", "Dispatch to swarm-loop Phase -1 per goal"]
}
JSONEOF

# ============================================================
# Case 9: 正常 plan → exit 0
# ============================================================
run_lint "$PLANDIR/valid.json"
check "case9: valid plan passes lint" 0 "$LRC" "" ""

# ============================================================
# Case 10: VERIFIER_FLOOR (exit 2)
# ============================================================
cat >"$PLANDIR/c10a-checker.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "verification": {
    "checker": "sonnet",
    "deterministic": ["make lint"],
    "lenses": []
  },
  "budget": {"task_max": 5, "mission_max": 20},
  "routing": {"maker": "sonnet", "fixer": "sonnet"},
  "steps": ["Read swarm-loop/SKILL.md"]
}
JSONEOF
run_lint "$PLANDIR/c10a-checker.json"
check "case10a: checker!=opus -> VERIFIER_FLOOR exit 2" 2 "$LRC" "" ""

cat >"$PLANDIR/c10b-empty-deterministic.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "verification": {
    "checker": "opus",
    "deterministic": [],
    "lenses": []
  },
  "budget": {"task_max": 5, "mission_max": 20},
  "routing": {"maker": "sonnet", "fixer": "sonnet"},
  "steps": ["Read swarm-loop/SKILL.md"]
}
JSONEOF
run_lint "$PLANDIR/c10b-empty-deterministic.json"
check "case10b: empty deterministic[] -> VERIFIER_FLOOR exit 2" 2 "$LRC" "" ""

cat >"$PLANDIR/c10c-skip-checker.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "verification": {
    "checker": "opus",
    "deterministic": ["make lint"],
    "lenses": []
  },
  "budget": {"task_max": 5, "mission_max": 20},
  "routing": {"maker": "sonnet", "fixer": "sonnet"},
  "steps": ["Read swarm-loop/SKILL.md", "Proceed fast and skip checker for this step"]
}
JSONEOF
run_lint "$PLANDIR/c10c-skip-checker.json"
check "case10c: steps contains 'skip checker' phrase -> VERIFIER_FLOOR exit 2" 2 "$LRC" "" ""

# ============================================================
# Case 11: WRITE_SCOPE (exit 3) + 誤検知ガード (exit 0)
# ============================================================
cat >"$PLANDIR/c11a-sed.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "verification": {
    "checker": "opus",
    "deterministic": ["make lint"],
    "lenses": []
  },
  "budget": {"task_max": 5, "mission_max": 20},
  "routing": {"maker": "sonnet", "fixer": "sonnet"},
  "steps": ["sed -i 's/foo/bar/' claude/hooks/swarm-fable-gate.sh"]
}
JSONEOF
run_lint "$PLANDIR/c11a-sed.json"
check "case11a: sed -i on claude/hooks/... -> WRITE_SCOPE exit 3" 3 "$LRC" "" ""

cat >"$PLANDIR/c11b-edit-call.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "verification": {
    "checker": "opus",
    "deterministic": ["make lint"],
    "lenses": []
  },
  "budget": {"task_max": 5, "mission_max": 20},
  "routing": {"maker": "sonnet", "fixer": "sonnet"},
  "steps": ["Edit(claude/hooks/swarm-stop-verify.sh) to relax a guard"]
}
JSONEOF
run_lint "$PLANDIR/c11b-edit-call.json"
check "case11b: Edit(claude/hooks/swarm-stop-verify.sh) -> WRITE_SCOPE exit 3" 3 "$LRC" "" ""

cat >"$PLANDIR/c11c-grep-redirect.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "verification": {
    "checker": "opus",
    "deterministic": ["make lint"],
    "lenses": []
  },
  "budget": {"task_max": 5, "mission_max": 20},
  "routing": {"maker": "sonnet", "fixer": "sonnet"},
  "steps": ["grep SKILL.md > /tmp/notes"]
}
JSONEOF
run_lint "$PLANDIR/c11c-grep-redirect.json"
check "case11c: grep SKILL.md > /tmp/notes (safe redirect target) -> exit 0" 0 "$LRC" "" ""

cat >"$PLANDIR/c11d-verify-exec.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "verification": {
    "checker": "opus",
    "deterministic": ["make lint"],
    "lenses": []
  },
  "budget": {"task_max": 5, "mission_max": 20},
  "routing": {"maker": "sonnet", "fixer": "sonnet"},
  "steps": ["bash claude/skills/swarm-release-gate/scripts/verify.sh を実行"]
}
JSONEOF
run_lint "$PLANDIR/c11d-verify-exec.json"
check "case11d: executing verify.sh (not writing to it) -> exit 0" 0 "$LRC" "" ""

cat >"$PLANDIR/c11e-write-then-read.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "verification": {
    "checker": "opus",
    "deterministic": ["make lint"],
    "lenses": []
  },
  "budget": {"task_max": 5, "mission_max": 20},
  "routing": {"maker": "sonnet", "fixer": "sonnet"},
  "steps": ["Write(/tmp/x.json) したのち SKILL.md を Read する"]
}
JSONEOF
run_lint "$PLANDIR/c11e-write-then-read.json"
check "case11e: protected token outside Write(...) args -> exit 0" 0 "$LRC" "" ""

# ============================================================
# Case 12: LINT_SCHEMA / BUDGET_BOUNDS / ROUTING の単独違反
# ============================================================
cat >"$PLANDIR/c12a-task-max.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "verification": {"checker": "opus", "deterministic": ["make lint"], "lenses": []},
  "budget": {"task_max": 9, "mission_max": 20},
  "routing": {"maker": "sonnet", "fixer": "sonnet"},
  "steps": ["Read swarm-loop/SKILL.md"]
}
JSONEOF
run_lint "$PLANDIR/c12a-task-max.json"
check "case12a: budget.task_max=9 (>5) -> BUDGET_BOUNDS exit 4" 4 "$LRC" "" ""

cat >"$PLANDIR/c12b-mission-max.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "verification": {"checker": "opus", "deterministic": ["make lint"], "lenses": []},
  "budget": {"task_max": 5, "mission_max": 30},
  "routing": {"maker": "sonnet", "fixer": "sonnet"},
  "steps": ["Read swarm-loop/SKILL.md"]
}
JSONEOF
run_lint "$PLANDIR/c12b-mission-max.json"
check "case12b: budget.mission_max=30 (>20) -> BUDGET_BOUNDS exit 4" 4 "$LRC" "" ""

cat >"$PLANDIR/c12c-budget-missing.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "verification": {"checker": "opus", "deterministic": ["make lint"], "lenses": []},
  "routing": {"maker": "sonnet", "fixer": "sonnet"},
  "steps": ["Read swarm-loop/SKILL.md"]
}
JSONEOF
run_lint "$PLANDIR/c12c-budget-missing.json"
check "case12c: budget key missing entirely -> BUDGET_BOUNDS exit 4" 4 "$LRC" "" ""

cat >"$PLANDIR/c12d-maker-fable.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "verification": {"checker": "opus", "deterministic": ["make lint"], "lenses": []},
  "budget": {"task_max": 5, "mission_max": 20},
  "routing": {"maker": "fable", "fixer": "sonnet"},
  "steps": ["Read swarm-loop/SKILL.md"]
}
JSONEOF
run_lint "$PLANDIR/c12d-maker-fable.json"
check "case12d: routing.maker=fable -> ROUTING exit 5" 5 "$LRC" "" ""

# 壊れた JSON (steps 配列の閉じ括弧欠落)
cat >"$PLANDIR/c12e-broken.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "verification": {"checker": "opus", "deterministic": ["make lint"], "lenses": []},
  "budget": {"task_max": 5, "mission_max": 20},
  "routing": {"maker": "sonnet", "fixer": "sonnet"},
  "steps": ["Read swarm-loop/SKILL.md"
}
JSONEOF
run_lint "$PLANDIR/c12e-broken.json"
check "case12e: malformed JSON -> LINT_SCHEMA exit 1" 1 "$LRC" "" ""

cat >"$PLANDIR/c12f-no-verification.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "budget": {"task_max": 5, "mission_max": 20},
  "routing": {"maker": "sonnet", "fixer": "sonnet"},
  "steps": ["Read swarm-loop/SKILL.md"]
}
JSONEOF
run_lint "$PLANDIR/c12f-no-verification.json"
check "case12f: valid JSON but verification key missing -> LINT_SCHEMA exit 1" 1 "$LRC" "" ""

cat >"$PLANDIR/c12g-bad-harness.json" <<'JSONEOF'
{
  "harness": "swarm-explore",
  "scale": "mission",
  "verification": {"checker": "opus", "deterministic": ["make lint"], "lenses": []},
  "budget": {"task_max": 5, "mission_max": 20},
  "routing": {"maker": "sonnet", "fixer": "sonnet"},
  "steps": ["Read swarm-loop/SKILL.md"]
}
JSONEOF
run_lint "$PLANDIR/c12g-bad-harness.json"
check "case12g: harness=swarm-explore (out of enum) -> LINT_SCHEMA exit 1" 1 "$LRC" "" ""

# ============================================================
# Case 13: 多重違反 (budget超過 + maker=fable + steps書き込み) → 優先順どおり exit 4
# ============================================================
cat >"$PLANDIR/c13-multi.json" <<'JSONEOF'
{
  "harness": "swarm-loop",
  "scale": "mission",
  "verification": {"checker": "opus", "deterministic": ["make lint"], "lenses": []},
  "budget": {"task_max": 9, "mission_max": 20},
  "routing": {"maker": "fable", "fixer": "sonnet"},
  "steps": ["sed -i 's/x/y/' claude/hooks/swarm-fable-gate.sh"]
}
JSONEOF
run_lint "$PLANDIR/c13-multi.json"
check "case13: multi-violation (budget+routing+write_scope) -> priority exit 4" 4 "$LRC" "" ""

# ============================================================
# Case 14: record — 新規追記/同一slug置換/TAB・改行の正規化
# ============================================================
REC14="$WORK/rec14.tsv"
printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$REC14"

HARNESS_REGISTRY="$REC14" bash "$RECORD" missionA swarm-loop parallel claude-sonnet-5 "done=2 blocked=1 attempts=3 replans=0" >/dev/null 2>&1
lines1=$(wc -l <"$REC14")
[ "$lines1" -eq 2 ]
check "case14: first record appends 1 row (lines=$lines1, expect 2)" 0 $? "" ""

HARNESS_REGISTRY="$REC14" bash "$RECORD" missionA swarm-loop parallel claude-sonnet-5 "done=3 blocked=0 attempts=3 replans=0" >/dev/null 2>&1
lines2=$(wc -l <"$REC14")
[ "$lines2" -eq 2 ]
check "case14: re-record same slug replaces (not appends), lines unchanged ($lines2, expect 2)" 0 $? "" ""

row_a=$(grep -P '\tmissionA\t' "$REC14" 2>/dev/null || grep 'missionA' "$REC14" 2>/dev/null || true)
printf '%s' "$row_a" | grep -q 'done=3'
check "case14: replaced row reflects updated outcome (done=3)" 0 $? "" ""

HARNESS_REGISTRY="$REC14" bash "$RECORD" missionB swarm-graph sequential claude-fable-5 "$(printf 'done=1\tblocked=0\rattempts=1')" >/dev/null 2>&1
lines3=$(wc -l <"$REC14")
[ "$lines3" -eq 3 ]
check "case14: second distinct slug appends (lines=$lines3, expect 3)" 0 $? "" ""

fieldcount=$(awk -F'\t' '$2=="missionB"{print NF; exit}' "$REC14" 2>/dev/null)
fieldcount="${fieldcount:-0}"
[ "$fieldcount" -eq 6 ]
check "case14: TAB/CR in outcome normalized to spaces (fields=$fieldcount, expect 6 = well-formed TSV row)" 0 $? "" ""

# ============================================================
# Case 15: record — 並行8プロセス同時 append で行落ちしない (flock 検証)
# ============================================================
REC15="$WORK/rec15.tsv"
printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$REC15"

for i in $(seq 1 8); do
  ( HARNESS_REGISTRY="$REC15" bash "$RECORD" "mrec$i" swarm-loop parallel claude-sonnet-5 "done=$i blocked=0 attempts=1 replans=0" >/dev/null 2>&1 ) &
done
wait

total15=$(wc -l <"$REC15")
datalines15=$((total15 - 1))
[ "$datalines15" -eq 8 ]
check "case15: 8 concurrent distinct-slug appends, none lost (datalines=$datalines15, expect 8)" 0 $? "" ""

badrows15=$(awk -F'\t' 'NR>1 && NF!=6' "$REC15" 2>/dev/null | wc -l)
[ "$badrows15" -eq 0 ]
check "case15: all concurrently-written rows are well-formed 6-field TSV (badrows=$badrows15)" 0 $? "" ""

# ============================================================
# Case 26 (TDAD Red, 番号は末尾だが Case 15 と同じ flock 使用箇所の話題のためここに配置):
# harness-record.sh line 44 `flock -x 200` には存在ガードが無く、util-linux flock 未導入環境
# (例: Homebrew 未導入の macOS) では exit 127 でクラッシュする。ガード実装後は
# 「exit 1 + actionable stderr + registry 無変更」で fail-closed するはずの回帰テスト。
# 現状 (ガード未実装) はこの Case 26 が FAIL する — TDAD の Red 確認。
# ============================================================
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
  ' _ "$dir" cat mv date awk cut mkdir rm sleep tail wc grep dirname find sed tr touch readlink
}

NOFLOCK_BIN="$WORK/noflock-bin"
make_noflock_bin "$NOFLOCK_BIN"

# sanity: この PATH 制限下で command -v flock が確実に失敗すること
# (このホストに元々 flock が無いことに依存しない — flock がある環境でも同じ手法で
# 決定的に隠せることを保証する)。
PATH="$NOFLOCK_BIN" "$BASHBIN" -c 'command -v flock' >/dev/null 2>&1
check "case26: sanity - flock hidden from restricted PATH" 1 $? "" ""
PATH="$NOFLOCK_BIN" "$BASHBIN" -c 'echo x | cat >/dev/null && date >/dev/null && echo ok' >/dev/null 2>&1
check "case26: sanity - restricted PATH still resolves other needed commands" 0 $? "" ""

REC26="$WORK/rec26.tsv"
printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$REC26"
before26="$(cat "$REC26")"

out26=$(PATH="$NOFLOCK_BIN" HARNESS_REGISTRY="$REC26" "$BASHBIN" "$RECORD" mission26 swarm-loop parallel claude-sonnet-5 "done=1 blocked=0 attempts=1 replans=0" 2>&1)
rc26=$?
check "case26a: harness-record.sh fails closed (exit 1) when flock is unavailable" 1 "$rc26" "FLOCK_MISSING" "$out26"

after26="$(cat "$REC26")"
[ "$before26" = "$after26" ]
check "case26a: registry is NOT modified when the flock guard fires (fail-closed, no partial write)" 0 $? "" ""

# 26b (回帰防止): flock が到達可能な通常 PATH では既存動作 (成功して1行追記) が不変であること。
# この実行環境に flock が全く存在しない場合は spurious failure を避け skip する。
if command -v flock >/dev/null 2>&1; then
  REC26B="$WORK/rec26b.tsv"
  printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$REC26B"
  out26b=$(HARNESS_REGISTRY="$REC26B" bash "$RECORD" mission26b swarm-loop parallel claude-sonnet-5 "done=1 blocked=0 attempts=1 replans=0" 2>&1)
  rc26b=$?
  lines26b=$(wc -l <"$REC26B")
  [ "$rc26b" -eq 0 ] && [ "$lines26b" -eq 2 ]
  check "case26b (regression): with flock reachable on ambient PATH, record still succeeds unchanged" 0 $? "recorded: mission=mission26b" "$out26b"
else
  echo "SKIP: case26b - this host has no flock anywhere on PATH; cannot exercise the happy-path mirror"
fi

# ============================================================
# Case 16 (rev3): 存在ガード両欠落 — swarm-graph も swarm-loop も HARNESS_SKILLS_DIR に無い状態で
#                 並行 goal を渡す。(D) の規定は「swarm-loop 自身も無い場合はそのまま swarm-loop を
#                 返し rationale に警告」— 「使用不可と宣言した harness を推薦する」自己矛盾を防ぐ回帰テスト。
# ============================================================
NOBOTH_SKILLS="$WORK/noBoth-skills"
mkdir -p "$NOBOTH_SKILLS"
# swarm-loop も swarm-graph も意図的に欠落させる (mkdir しない)
SOUT=$(HARNESS_SKILLS_DIR="$NOBOTH_SKILLS" bash "$SELECT" "$GOAL_PARALLEL" "$REPO" 2>"$WORK/last_select_stderr.log"); SRC=$?
check "case16: select exits 0" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case16.json"
pyassert "case16: both harness SKILL.md missing -> harness=swarm-loop (no self-contradiction), rationale warns" "$WORK/case16.json" <<'PYEOF'
r = d["recommendation"]
assert r["harness"] == "swarm-loop", "expected swarm-loop even when both unavailable (no self-contradiction), got %r" % r["harness"]
assert len(r["rationale"]) > 0, "expected a warning rationale entry when no harness is available"
PYEOF

# ============================================================
# Case 17 (rev3): 実 git リポジトリでの profile 抽出 — `git ls-files | python3 - <<'EOF'` の
#                 stdin 競合 (パイプと heredoc が fd 0 を奪い合い python が heredoc をプログラム本体
#                 として読むため、パイプの読み手不在で SIGPIPE -> set -euo pipefail で exit 141・
#                 出力ゼロのクラッシュになりうる) の回帰テスト。非 git fixture だけではこの分岐が
#                 恒久的に隠れるため実 git リポジトリで確認する。
# ============================================================
GITREPO="$WORK/git-fixture-repo"
mkdir -p "$GITREPO"
(
  cd "$GITREPO" &&
  git init -q &&
  git config user.email "test@example.com" &&
  git config user.name "test" &&
  printf 'package main\n' >a.go &&
  printf '#!/bin/sh\necho hi\n' >b.sh &&
  git add a.go b.sh &&
  git commit -q -m fixture
) >/dev/null 2>&1
SOUT=$(bash "$SELECT" --profile-only "profile 抽出のテスト" "$GITREPO" 2>"$WORK/last_select_stderr.log"); SRC=$?
check "case17: select exits 0 on real git repo (no SIGPIPE/141 crash)" 0 "$SRC" "" ""
[ -n "$SOUT" ]
check "case17: output is non-empty" 0 $? "" ""
printf '%s' "$SOUT" >"$WORK/case17.json"
pyassert "case17: langs include extension-derived languages from git ls-files" "$WORK/case17.json" <<'PYEOF'
langs = d["profile"]["langs"]
assert "go" in langs, "expected 'go' in langs: %r" % langs
assert "sh" in langs, "expected 'sh' in langs: %r" % langs
PYEOF

# ============================================================
# Case 18 (impl-meta): 不正 UTF-8 registry → select の推薦経路がクラッシュしない
#                       (registry_matches=[] として続行し、rationale に registry-unreadable を記録)。
#                       graph-compile.sh の PARSE_ERROR 契約と同じ「実績が読めないだけで選択を
#                       止めない」fail-safe を harness-select.sh にも適用する回帰テスト。
# ============================================================
REG_BADUTF8="$WORK/registry-bad-utf8.tsv"
printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$REG_BADUTF8"
printf 'garbage-\xff\xfe-bytes-not-valid-utf8\n' >>"$REG_BADUTF8"
SOUT=$(HARNESS_REGISTRY="$REG_BADUTF8" bash "$SELECT" "$GOAL_PARALLEL" "$REPO" 2>"$WORK/last_select_stderr.log"); SRC=$?
check "case18: select exits 0 with unreadable (invalid utf-8) registry" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case18.json"
pyassert "case18: recommendation still produced, rationale records registry-unreadable" "$WORK/case18.json" <<'PYEOF'
r = d["recommendation"]
assert r["harness"] == "swarm-graph", "expected recommendation unaffected by unreadable registry, got %r" % r["harness"]
assert any("registry-unreadable" in x for x in r["rationale"]), "rationale missing registry-unreadable: %r" % r["rationale"]
PYEOF

# ============================================================
# Case 19 (impl-meta): 不正 UTF-8 plan → lint が生 traceback を漏らさず LINT_SCHEMA(exit 1) を返す
#                      (harness-lint.sh の plan 読み込みは既存 `except OSError` のみで
#                      UnicodeDecodeError が素通りする回帰の再現)。
# ============================================================
printf '{\n  "harness": "swarm-loop", "note": "\xff\xfe invalid utf8 bytes"\n}\n' >"$PLANDIR/c19-bad-utf8.json"
run_lint "$PLANDIR/c19-bad-utf8.json"
check "case19: lint exits 1 on invalid-UTF-8 plan (no crash)" 1 "$LRC" "" ""
case "$LOUT" in
  "LINT_SCHEMA: unreadable plan ("*) c19_prefix_ok=0 ;;
  *) c19_prefix_ok=1 ;;
esac
check "case19: stderr starts with 'LINT_SCHEMA: unreadable plan ('" 0 "$c19_prefix_ok" "" ""
if grep -qi 'Traceback' <<<"$LOUT"; then c19_tb=1; else c19_tb=0; fi
check "case19: stderr must not leak raw Python traceback" 0 "$c19_tb" "" ""

# ============================================================
# Case 20 (impl-meta): plan にディレクトリを渡す → 19 と同じ LINT_SCHEMA(exit 1) 形式
#                      (IsADirectoryError は既存 `except OSError` で捕捉済みだが、メッセージ形式を
#                      「LINT_SCHEMA: unreadable plan (...)」へ 19 と統一する契約の回帰)。
# ============================================================
mkdir -p "$PLANDIR/c20-is-a-directory"
run_lint "$PLANDIR/c20-is-a-directory"
check "case20: lint exits 1 when plan-path is a directory" 1 "$LRC" "" ""
case "$LOUT" in
  "LINT_SCHEMA: unreadable plan ("*) c20_prefix_ok=0 ;;
  *) c20_prefix_ok=1 ;;
esac
check "case20: directory-path stderr starts with 'LINT_SCHEMA: unreadable plan ('" 0 "$c20_prefix_ok" "" ""

# ============================================================
# Case 21 (impl-meta): 空 registry (ヘッダ行のみ) → total: 0 表示・exit 0
# ============================================================
REG_STATUS_EMPTY="$WORK/status-empty-registry.tsv"
printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$REG_STATUS_EMPTY"
TOUT=$(HARNESS_REGISTRY="$REG_STATUS_EMPTY" bash "$STATUS" 2>"$WORK/last_status_stderr.log"); TRC=$?
check "case21: harness-status.sh exits 0 on empty registry, shows total: 0" 0 "$TRC" "total: 0" "$TOUT"

# ============================================================
# Case 22 (impl-meta): 複数行の集計値 (harness 別・model-version 別件数)
# ============================================================
REG_STATUS_MULTI="$WORK/status-multi.tsv"
printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$REG_STATUS_MULTI"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-01" "s22-1" "swarm-loop"  "parallel"   "claude-sonnet-5" "done=2 blocked=1 attempts=3 replans=0" >>"$REG_STATUS_MULTI"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-02" "s22-2" "swarm-graph" "parallel"   "claude-sonnet-5" "done=1 blocked=2 attempts=3 replans=0" >>"$REG_STATUS_MULTI"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-03" "s22-3" "swarm-loop"  "sequential" "claude-fable-5"  "done=3 blocked=0 attempts=3 replans=0" >>"$REG_STATUS_MULTI"
TOUT=$(HARNESS_REGISTRY="$REG_STATUS_MULTI" bash "$STATUS" 2>"$WORK/last_status_stderr.log"); TRC=$?
check "case22a: harness-status.sh exits 0, total: 3" 0 "$TRC" "total: 3" "$TOUT"
check "case22b: harness breakdown swarm-loop: 2" 0 0 "swarm-loop: 2" "$TOUT"
check "case22c: harness breakdown swarm-graph: 1" 0 0 "swarm-graph: 1" "$TOUT"
check "case22d: model-version breakdown claude-sonnet-5: 2" 0 0 "claude-sonnet-5: 2" "$TOUT"
check "case22e: model-version breakdown claude-fable-5: 1" 0 0 "claude-fable-5: 1" "$TOUT"

# ============================================================
# Case 23 (impl-meta): 不正行 (列数不足・不正UTF-8) は skip され warning 表示・exit 0
# ============================================================
REG_STATUS_MALFORMED="$WORK/status-malformed.tsv"
printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$REG_STATUS_MALFORMED"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-01" "s23-1" "swarm-loop" "parallel" "claude-sonnet-5" "done=1 blocked=0 attempts=1 replans=0" >>"$REG_STATUS_MALFORMED"
printf 'too\tfew\tcolumns\n' >>"$REG_STATUS_MALFORMED"
printf 'garbage-\xff\xfe-bytes-not-utf8\n' >>"$REG_STATUS_MALFORMED"
TOUT=$(HARNESS_REGISTRY="$REG_STATUS_MALFORMED" bash "$STATUS" 2>"$WORK/last_status_stderr.log"); TRC=$?
check "case23a: harness-status.sh exits 0 with malformed+invalid-utf8 rows present, total: 1" 0 "$TRC" "total: 1" "$TOUT"
check "case23b: malformed (wrong column count) row produces a warning" 0 0 "skipped malformed line" "$TOUT"
check "case23c: invalid-utf-8 row produces a warning" 0 0 "invalid utf-8" "$TOUT"

# ============================================================
# Case 24 (impl-meta): profile-primary 指定時の同型失敗反復判定 (M4 EVOLVE-FEED の判定切り出し)
#                       2 回以上の blocked>done で REPEAT 表示、1 回では非表示
# ============================================================
REG_STATUS_REPEAT="$WORK/status-repeat.tsv"
printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$REG_STATUS_REPEAT"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-01" "s24-1" "swarm-graph" "parallel" "claude-sonnet-5" "done=1 blocked=3 attempts=4 replans=0" >>"$REG_STATUS_REPEAT"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-02" "s24-2" "swarm-graph" "parallel" "claude-sonnet-5" "done=1 blocked=2 attempts=3 replans=0" >>"$REG_STATUS_REPEAT"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-03" "s24-3" "swarm-graph" "parallel" "claude-sonnet-5" "done=5 blocked=1 attempts=6 replans=0" >>"$REG_STATUS_REPEAT"
TOUT=$(HARNESS_REGISTRY="$REG_STATUS_REPEAT" bash "$STATUS" "parallel" 2>"$WORK/last_status_stderr.log"); TRC=$?
check "case24a: primary=parallel with 2/3 blocked>done shows REPEAT" 0 "$TRC" "REPEAT" "$TOUT"

REG_STATUS_NOREPEAT="$WORK/status-norepeat.tsv"
printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$REG_STATUS_NOREPEAT"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-04" "s24b-1" "swarm-graph" "sequential" "claude-sonnet-5" "done=1 blocked=2 attempts=3 replans=0" >>"$REG_STATUS_NOREPEAT"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-05" "s24b-2" "swarm-graph" "sequential" "claude-sonnet-5" "done=5 blocked=1 attempts=6 replans=0" >>"$REG_STATUS_NOREPEAT"
TOUT=$(HARNESS_REGISTRY="$REG_STATUS_NOREPEAT" bash "$STATUS" "sequential" 2>"$WORK/last_status_stderr.log"); TRC=$?
check "case24b: primary=sequential with 1/2 blocked>done exits 0" 0 "$TRC" "" ""
if grep -q "REPEAT" <<<"$TOUT"; then c24b_repeat=1; else c24b_repeat=0; fi
check "case24b: REPEAT absent when only 1 blocked>done row" 0 "$c24b_repeat" "" ""

# ============================================================
# Case 25 (impl-meta rev2): TSV は行独立レコードなので registry 読み込みは all-or-nothing で握り
# 潰さない — 正常な blocked>done 過半 3 行 (5a と同じ swarm-graph/parallel fixture) に加え、
# 不正 UTF-8 の 1 行が混在しても (C) 降格は引き続き発火し (harness=swarm-loop)、かつ rationale に
# 降格根拠 (registry-downgrade:2/3) と行 skip の言及 (lines skipped) の両方が含まれる。
# (初版仕様の「registry_matches=[]」は不正行 1 行で正常行まで消え安全弁を沈黙無効化する仕様バグだった
# — reviewer の実環境再現で検出、rev2 で行単位 skip に改訂)
# ============================================================
REG_E="$WORK/registry-e.tsv"
printf '# date\tmission\tharness\tprofile\tmodel-version\toutcome\n' >"$REG_E"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-01" "rgE-1" "swarm-graph" "parallel" "claude-sonnet-5" "done=1 blocked=3 attempts=6 replans=1" >>"$REG_E"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-02" "rgE-2" "swarm-graph" "parallel" "claude-sonnet-5" "done=4 blocked=5 attempts=9 replans=0" >>"$REG_E"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "2026-07-03" "rgE-3" "swarm-graph" "parallel" "claude-sonnet-5" "done=5 blocked=1 attempts=6 replans=0" >>"$REG_E"
printf 'garbage-\xff\xfe-bytes-not-valid-utf8\n' >>"$REG_E"
SOUT=$(HARNESS_REGISTRY="$REG_E" bash "$SELECT" "$GOAL_PARALLEL" "$REPO" 2>"$WORK/last_select_stderr.log"); SRC=$?
check "case25: select exits 0 with 3 valid rows + 1 invalid-utf8 line mixed in registry" 0 "$SRC" "" ""
printf '%s' "$SOUT" >"$WORK/case25.json"
pyassert "case25: (C) downgrade still fires from the 3 valid rows despite 1 unreadable line, rationale mentions both" "$WORK/case25.json" <<'PYEOF'
r = d["recommendation"]
assert r["harness"] == "swarm-loop", "expected downgrade to swarm-loop despite 1 unreadable line, got %r" % r["harness"]
assert any("registry-downgrade:2/3" in x for x in r["rationale"]), "rationale missing registry-downgrade:2/3 (safety valve silently disabled by all-or-nothing read?): %r" % r["rationale"]
assert any("lines skipped" in x for x in r["rationale"]), "rationale missing lines-skipped mention for the unreadable line: %r" % r["rationale"]
PYEOF

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
