#!/usr/bin/env bash
# harness-plan.json の着手前 best-effort スクリーニング (DGM の reward hacking 実証を受けた二重検証の
# 前段。実行時の最終権威は dispatch 先ハーネスの PostToolUse/Stop hook)。
# usage: harness-lint.sh <harness-plan.json>
#
# 多重違反時の優先順は 1 -> 4 -> 5 -> 2 -> 3 で固定 (スキーマ健全性が最優先、ヒューリスティックな
# WRITE_SCOPE は最後):
#   0 = PASS
#   1 = LINT_SCHEMA      (JSON 破損・必須キー欠落・harness/scale が列挙外・型不一致)
#   4 = BUDGET_BOUNDS    (task_max>5 / mission_max>20 / budget キーまたは下位キー欠落)
#   5 = ROUTING          (maker/fixer が sonnet 以外)
#   2 = VERIFIER_FLOOR   (checker!=opus / deterministic 空 / 検証省略表現)
#   3 = WRITE_SCOPE      (書き込み動詞と保護対象の隣接判定。完全性は保証しない)
# 仕様: /tmp/a970d944-5c72-44e0-bf62-429e73ed60c4/swarm/specs/sm-spec.md
set -euo pipefail

planfile="${1:?usage: harness-lint.sh <harness-plan.json>}"

# 判定は python 側で一括して行い、単一の "<exit-code>\t<reason>" 行を stdout へ返す。
# bash 側は exit code の反映と reason の stderr 出力のみを担当する (シェル側での JSON パースを
# 避け、優先順位判定を 1 箇所に閉じ込めるため)。
result=$(python3 - "$planfile" <<'PYEOF'
import json, re, sys

planfile = sys.argv[1]

def fail(code, reason):
    print("%d\t%s" % (code, reason))
    sys.exit(0)

try:
    with open(planfile, "r", encoding="utf-8") as f:
        raw = f.read()
except (OSError, UnicodeDecodeError) as e:
    # graph-compile.sh の PARSE_ERROR と同じ「生 traceback を漏らさない」原則。不正 UTF-8
    # (UnicodeDecodeError は OSError のサブクラスではないため個別に捕捉が必要) ・ディレクトリ・
    # 権限エラー等、読めない理由を問わず単一の LINT_SCHEMA(exit 1) メッセージへ集約する。
    fail(1, "LINT_SCHEMA: unreadable plan (%s)" % e)

try:
    plan = json.loads(raw)
except json.JSONDecodeError as e:
    fail(1, "LINT_SCHEMA: malformed JSON: %s" % e)

if not isinstance(plan, dict):
    fail(1, "LINT_SCHEMA: plan root is not an object")

# --- 1: LINT_SCHEMA ---
if "harness" not in plan or plan["harness"] not in ("swarm-loop", "swarm-graph"):
    fail(1, "LINT_SCHEMA: harness missing or out of enum (swarm-loop|swarm-graph): %r" % plan.get("harness"))
if "scale" not in plan or plan["scale"] not in ("quick", "interactive", "mission"):
    fail(1, "LINT_SCHEMA: scale missing or out of enum (quick|interactive|mission): %r" % plan.get("scale"))
if "verification" not in plan or not isinstance(plan["verification"], dict):
    fail(1, "LINT_SCHEMA: verification key missing or not an object")
verification = plan["verification"]
if "checker" not in verification or not isinstance(verification["checker"], str):
    fail(1, "LINT_SCHEMA: verification.checker missing or not a string")
if "deterministic" not in verification or not isinstance(verification["deterministic"], list):
    fail(1, "LINT_SCHEMA: verification.deterministic missing or not an array")
if "lenses" not in verification or not isinstance(verification["lenses"], list):
    fail(1, "LINT_SCHEMA: verification.lenses missing or not an array")
if "routing" not in plan or not isinstance(plan["routing"], dict):
    fail(1, "LINT_SCHEMA: routing key missing or not an object")
routing = plan["routing"]
if "maker" not in routing or not isinstance(routing["maker"], str):
    fail(1, "LINT_SCHEMA: routing.maker missing or not a string")
if "fixer" not in routing or not isinstance(routing["fixer"], str):
    fail(1, "LINT_SCHEMA: routing.fixer missing or not a string")
if "steps" not in plan or not isinstance(plan["steps"], list):
    fail(1, "LINT_SCHEMA: steps missing or not an array")

# --- 4: BUDGET_BOUNDS (budget キー/下位キー欠落も含む) ---
budget = plan.get("budget")
if not isinstance(budget, dict):
    fail(4, "BUDGET_BOUNDS: budget key missing or not an object")
task_max = budget.get("task_max")
mission_max = budget.get("mission_max")
if not isinstance(task_max, int) or isinstance(task_max, bool):
    fail(4, "BUDGET_BOUNDS: budget.task_max missing or not an integer")
if not isinstance(mission_max, int) or isinstance(mission_max, bool):
    fail(4, "BUDGET_BOUNDS: budget.mission_max missing or not an integer")
if task_max > 5:
    fail(4, "BUDGET_BOUNDS: budget.task_max=%d > 5" % task_max)
if mission_max > 20:
    fail(4, "BUDGET_BOUNDS: budget.mission_max=%d > 20" % mission_max)

# --- 5: ROUTING (fable 消費はスポット判断層に集約するため sonnet 固定) ---
if routing["maker"] != "sonnet":
    fail(5, "ROUTING: routing.maker=%r is not sonnet" % routing["maker"])
if routing["fixer"] != "sonnet":
    fail(5, "ROUTING: routing.fixer=%r is not sonnet" % routing["fixer"])

# --- 2: VERIFIER_FLOOR (誤検知よりも floor 防衛を優先する意図を契約に明記) ---
if verification["checker"] != "opus":
    fail(2, "VERIFIER_FLOOR: verification.checker=%r is not opus" % verification["checker"])
if len(verification["deterministic"]) == 0:
    fail(2, "VERIFIER_FLOOR: verification.deterministic is empty")

SKIP_PHRASES = ["skip checker", "checkerなし", "検証省略", "verify:skip"]
steps = plan["steps"]
lenses = verification["lenses"]
for idx, step in enumerate(steps):
    if not isinstance(step, str):
        continue
    for phrase in SKIP_PHRASES:
        if phrase in step:
            fail(2, "VERIFIER_FLOOR: step %d contains skip phrase '%s'" % (idx, phrase))
for lens in lenses:
    if not isinstance(lens, str):
        continue
    for phrase in SKIP_PHRASES:
        if phrase in lens:
            fail(2, "VERIFIER_FLOOR: lenses contains skip phrase '%s'" % phrase)

# --- 3: WRITE_SCOPE (書き込み動詞と保護対象の隣接判定。単なる Read・共起なしのリダイレクトは除外) ---
# agent/hooks/claude/ は agent-hooks-and-pi-agents-unification ミッション(2026-09-03)で
# claude/hooks/*.sh の一部(security-gate.sh 等 decide.py 委譲 shim 計7件)が実体移動した先。
# write-scope-lib.sh の write_scope_is_protected() と同じ理由で追加(パスのセグメント順が逆の
# ため claude/hooks/ 側のパターンには一致しない)。同ミッションで agy/hooks/*.sh・
# pi/extensions/*.ts も同様に agent/hooks/{agy,pi}/ へ実体移動しており、Phase 4.5敵対的レビュー
# (security-adversarial-reviewer)の指摘により claude 分と対称に追加する。
PROTECTED = r'(?:claude/hooks/|agent/hooks/claude/|agent/hooks/agy/|agent/hooks/pi/|budget-guard|verify\.sh|SWARM\.md|SWARM_REFERENCES\.md|SKILL\.md|swarm-fable-gate|swarm-stop-verify|swarm-post-edit-lint)'
# (a) sed -i の引数列に保護 token を含む
re_sed = re.compile(r'sed\s+-i[^\n]*' + PROTECTED)
# (b) リダイレクト/tee の書き込み先が保護 token を含む場合のみ
re_redirect = re.compile(r'(^|[\s;&|])(>>?|tee)\s+[^\s]*' + PROTECTED)
# (c) tool 呼び出し形式の引数部に保護 token を含む場合のみ
re_toolcall = re.compile(r'(?:Edit|Write|MultiEdit)\([^\n)]*' + PROTECTED)

for idx, step in enumerate(steps):
    if not isinstance(step, str):
        continue
    if re_sed.search(step):
        fail(3, "WRITE_SCOPE: step %d writes to protected path via sed -i: %s" % (idx, step))
    if re_redirect.search(step):
        fail(3, "WRITE_SCOPE: step %d writes to protected path via redirect/tee: %s" % (idx, step))
    if re_toolcall.search(step):
        fail(3, "WRITE_SCOPE: step %d writes to protected path via tool-call args: %s" % (idx, step))

print("0\tPASS")
PYEOF
)

code="${result%%$'\t'*}"
reason="${result#*$'\t'}"
if [ "$code" != "0" ]; then
  echo "$reason" >&2
fi
exit "$code"
