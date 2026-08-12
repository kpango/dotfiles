#!/usr/bin/env bash
# graph-status.sh — @fix_plan.md の graph ミッション状態を人間可読に要約する (swarm-graph)。
# usage: graph-status.sh [plan-path]
#   plan-path 省略時: $(git rev-parse --show-toplevel)/@fix_plan.md
# graph-compile.sh を同ディレクトリ解決 ($(dirname "$0")) で呼び出し、JSON を
# mission ヘッダ・status 別集計・ready フロンティア・in_progress/blocked/stale 詳細・
# width/depth/critical path・warnings の人間可読サマリーへ変換する。
# graph ミッションの状態確認は本スクリプトのみを使う — loop-status.sh は節スコープを
# 持たず、replan 後の複数 "## Tasks" 節を二重集計するため graph ミッションでは使用禁止。
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPILE="$SELF_DIR/graph-compile.sh"

plan_path="${1:-}"
if [ -z "$plan_path" ]; then
  plan_path="$(git rev-parse --show-toplevel)/@fix_plan.md"
fi

# compile が非 0 の場合は verdict とエラー内容をそのまま表示して同じ exit code で終了する。
set +e
json_out="$(bash "$COMPILE" "$plan_path")"
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  echo "$json_out"
  exit "$rc"
fi

mission_line="$(grep -m1 '^# @fix_plan.md' "$plan_path" 2>/dev/null || true)"
goal_line="$(grep -m1 '^- goal:' "$plan_path" 2>/dev/null || true)"
scale_line="$(grep -m1 '^- scale:' "$plan_path" 2>/dev/null || true)"
graph_managed_line="$(grep -m1 '^- graph-managed:' "$plan_path" 2>/dev/null || true)"

JSON="$json_out" \
MISSION_LINE="$mission_line" \
GOAL_LINE="$goal_line" \
SCALE_LINE="$scale_line" \
GRAPH_MANAGED_LINE="$graph_managed_line" \
python3 - <<'PYEOF'
import json
import os
from collections import Counter

d = json.loads(os.environ["JSON"])
nodes_by_id = {n["id"]: n for n in d["nodes"]}


def env_line(key):
    return os.environ.get(key, "").strip()


print(env_line("MISSION_LINE") or "# @fix_plan.md — mission: (不明。graph-managed 節が見当たらない)")
for key in ("GOAL_LINE", "SCALE_LINE", "GRAPH_MANAGED_LINE"):
    v = env_line(key)
    if v:
        print(v)
print()

counts = Counter(n["status"] for n in d["nodes"])
print("## Status")
for status in sorted(counts):
    print("  %s: %d" % (status, counts[status]))
print("  total: %d" % len(d["nodes"]))
print()

print("## Ready frontier")
if d["ready"]:
    for rid in d["ready"]:
        print("  - %s: %s" % (rid, nodes_by_id[rid]["summary"]))
else:
    print("  (none)")
print()

for label, statuses in (
    ("In progress", ("in_progress",)),
    ("Blocked", ("blocked(budget)", "blocked(design)", "blocked(spec)")),
    ("Stale", ("stale",)),
):
    matched = [n for n in d["nodes"] if n["status"] in statuses]
    print("## %s" % label)
    if matched:
        for n in matched:
            deps = ",".join(n["depends"]) if n["depends"] else "-"
            print("  - %s [%s] depends=%s: %s" % (n["id"], n["status"], deps, n["summary"]))
    else:
        print("  (none)")
    print()

m = d["metrics"]
print("## Graph metrics")
print("  nodes: %d  width: %d  depth: %d" % (m["nodes"], m["width"], m["depth"]))
print("  critical_path: %s" % (" -> ".join(m["critical_path"]) if m["critical_path"] else "(none)"))
print()

print("## Warnings")
if d["warnings"]:
    for w in d["warnings"]:
        print("  - %s" % w)
else:
    print("  (none)")
PYEOF
