#!/usr/bin/env bash
# graph-compile.sh — @fix_plan.md の "## Tasks" 節を JSON DAG へコンパイルする (swarm-graph)。
# usage: graph-compile.sh [--fit] [--stale <task-id>] [plan-path]
#   plan-path 省略時: $(git rev-parse --show-toplevel)/@fix_plan.md
#   (--show-toplevel はミッションworktree内から呼べばそのミッションworktree根を返す。呼び出し元
#    〈オーケストレーター〉がミッションworktreeルートから起動する責務を負う —
#    本スクリプト自身は渡された plan-path 引数をそのまま信頼する)
# 契約全文: claude/skills/swarm-graph の仕様書「graph-compile.sh 契約」参照。
set -euo pipefail

fit=false
stale_id=""
plan_path=""

while [ $# -gt 0 ]; do
  case "$1" in
    --fit)
      fit=true
      shift
      ;;
    --stale)
      stale_id="${2:?--stale requires a task-id}"
      shift 2
      ;;
    *)
      plan_path="$1"
      shift
      ;;
  esac
done

if [ -z "$plan_path" ]; then
  plan_path="$(git rev-parse --show-toplevel)/@fix_plan.md"
fi

exec python3 - "$plan_path" "$fit" "$stale_id" <<'PYEOF'
import sys
import re
import json
from collections import Counter

plan_path, fit_arg, stale_id = sys.argv[1], sys.argv[2], sys.argv[3]
fit = fit_arg == "true"

# status 語彙 (仕様書「graph-compile.sh 契約」)。未知の status はエラーにせず
# ready から除外し warnings に記録する (blocked 相当の扱い)。
KNOWN_STATUSES = {
    "pending", "in_progress", "done",
    "blocked(budget)", "blocked(design)", "blocked(spec)", "stale",
}

# "## Tasks" / "## Tasks (v2)" 等、"## Tasks" で始まる見出しのみを対象とする
# (word boundary: 直後が空白か行末。"## Tasksxyz" のような別見出しは対象外)。
TASKS_HEADING_RE = re.compile(r'^##\s+Tasks(\s|$)')
# 節の終端は次に現れる任意の "## " 見出し (### 等の深い見出しでは終端しない —
# "###" の 3 文字目は "#" であり \s にマッチしないため自然に除外される)。
ANY_HEADING_RE = re.compile(r'^##\s')


def emit(nodes, edges, metrics, ready, warnings, verdict, exit_code, stale_closure=None):
    out = {
        "nodes": nodes,
        "edges": edges,
        "metrics": metrics,
        "ready": ready,
        "warnings": warnings,
        "verdict": verdict,
    }
    # --stale 未指定時はキー自体を出力しない (仕様: "stale_closure（--stale 時のみ）")。
    if stale_closure is not None:
        out["stale_closure"] = stale_closure
    print(json.dumps(out))
    sys.exit(exit_code)


def parse_error(reason):
    # rev3 追加: plan が「存在するが読めない/解析不能」な場合の構造化応答。
    # 決定論的ツールとしての契約 (出力語彙の外に出ない) — 生の Python traceback は
    # 絶対に漏らさない。exit 7 は NO_TASKS(6, ファイル不在=新規ミッション扱い) と
    # 明確に区別する (「存在するが読めない」を新規ミッションと誤認しないため)。
    emit([], [], {"nodes": 0, "width": 0, "depth": 0, "critical_path": []},
         [], ["parse error: %s" % reason], "PARSE_ERROR", 7,
         stale_closure=([] if stale_id else None))


def read_plan_text(path):
    # FileNotFoundError のみ「有効な Tasks 節が無い」= NO_TASKS 相当として空文字列を
    # 返す (新規ミッション扱い、従来どおり)。それ以外の読み取り失敗 (不正 UTF-8・
    # plan-path がディレクトリ・権限エラー等の「存在するが読めない」状態) は
    # PARSE_ERROR として即座に構造化応答する。
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return ""
    except UnicodeDecodeError as e:
        parse_error("invalid UTF-8 while reading plan file %s (%s)" % (path, e))
    except IsADirectoryError:
        parse_error("plan-path is a directory, not a file: %s" % path)
    except PermissionError as e:
        parse_error("permission denied reading plan file %s (%s)" % (path, e))
    except OSError as e:
        parse_error("cannot read plan file %s (%s)" % (path, e))


def compile_graph(text):
    lines = text.splitlines()

    heading_indices = [i for i, l in enumerate(lines) if TASKS_HEADING_RE.match(l)]

    no_tasks_metrics = {"nodes": 0, "width": 0, "depth": 0, "critical_path": []}

    if not heading_indices:
        emit([], [], no_tasks_metrics, [], [], "NO_TASKS", 6,
             stale_closure=([] if stale_id else None))

    # 最後に出現する "## Tasks" 節のみを有効版とする。範囲はその見出し行の直後から
    # 次の "## " 見出し行 (または EOF) まで。範囲外の "|" 行は一切ノード化しない。
    last_idx = heading_indices[-1]
    end_idx = len(lines)
    for j in range(last_idx + 1, len(lines)):
        if ANY_HEADING_RE.match(lines[j]):
            end_idx = j
            break

    section_lines = lines[last_idx + 1:end_idx]

    def split_row(stripped_line):
        inner = stripped_line.strip("|")
        return [c.strip() for c in inner.split("|")]

    def is_separator(cells):
        return bool(cells) and all(c != "" and set(c) <= set("-: ") for c in cells)

    rows = []
    # rev3 追加: セル数が 8 でない行 (summary 等に未エスケープ "|" を含む場合に
    # 発生) は truncate/padding せずノード化から完全に除外し、warnings に記録する。
    # 静かな列ずれで depends/status/domain がずれて bogus MISSING_DEP 等に化けるのを防ぐ。
    malformed = []  # [(ncells, line-prefix40), ...]
    for raw_line in section_lines:
        stripped = raw_line.strip()
        if not stripped.startswith("|"):
            continue
        cells = split_row(stripped)
        if is_separator(cells):
            continue
        if cells and cells[0].strip().lower() == "task-id":
            continue
        if len(cells) != 8:
            malformed.append((len(cells), stripped[:40]))
            continue
        rows.append(cells)

    malformed_warnings = [
        "malformed row (ncells=%d): %s" % (n, s) for n, s in malformed
    ]

    if not rows:
        emit([], [], no_tasks_metrics, [], malformed_warnings, "NO_TASKS", 6,
             stale_closure=([] if stale_id else None))

    nodes = {}
    order_ids = []
    for cells in rows:
        task_id, summary, depends_raw, _worktree, status, _attempts, domain, note = cells
        depends = [d.strip() for d in depends_raw.split(",")]
        depends = [d for d in depends if d and d != "-"]
        if task_id not in nodes:
            order_ids.append(task_id)
        nodes[task_id] = {
            "summary": summary,
            "status": status,
            "depends": depends,
            "domain": domain,
            "note": note,
        }

    # MISSING_DEP: depends が既知ノードに存在しない参照を持つ場合。
    missing_flag = any(
        dep not in nodes
        for tid in order_ids
        for dep in nodes[tid]["depends"]
    )

    # depends グラフ (a -> b は "b が a に depends") の順方向隣接。存在しない dep への
    # 辺は張らない (MISSING_DEP は別途検出済みであり、循環検出をここで誤爆させない)。
    children = {tid: [] for tid in order_ids}
    indeg = {tid: 0 for tid in order_ids}
    for tid in order_ids:
        for dep in nodes[tid]["depends"]:
            if dep in nodes:
                indeg[tid] += 1
                children[dep].append(tid)

    # Kahn 法をラウンド単位で処理する: ラウンド番号がそのままレベル
    # (= ルートからの最長経路長) になる。全ノードを処理し切れなければ循環。
    remaining = set(order_ids)
    levels = {}
    round_no = 0
    while remaining:
        zero = sorted(i for i in remaining if indeg[i] == 0)
        if not zero:
            break
        for i in zero:
            levels[i] = round_no
            remaining.discard(i)
            for c in children[i]:
                indeg[c] -= 1
        round_no += 1

    cycle_flag = len(levels) != len(order_ids)

    # VERIFIER_FLOOR: note の空白区切りトークンに "verify:skip" が完全一致するノードは
    # domain が docs-wiring の場合のみ許可 (部分一致トークンはマッチしない)。
    verifier_violations = [
        tid for tid in order_ids
        if "verify:skip" in nodes[tid]["note"].split() and nodes[tid]["domain"] != "docs-wiring"
    ]
    verifier_flag = len(verifier_violations) > 0

    if cycle_flag:
        # 循環時は正しいレベルが定義できないため、メトリクスは意味を持たせず 0 埋めする。
        metrics = {"nodes": len(order_ids), "width": 0, "depth": 0, "critical_path": []}
    else:
        level_counts = Counter(levels.values())
        width = max(level_counts.values()) if levels else 0
        depth = (max(levels.values()) + 1) if levels else 0
        max_level = max(levels.values()) if levels else 0
        at_max = sorted(i for i in order_ids if levels.get(i) == max_level)
        critical_path = []
        if at_max:
            # 決定的選択: 最長レベルのノードのうち id 辞書順で最小のものを終点にし、
            # 各ステップで「レベルが 1 つ下の depends」のうち id 辞書順最小を選んで遡る。
            cur = at_max[0]
            critical_path = [cur]
            cur_level = max_level
            while cur_level > 0:
                candidates = sorted(
                    d for d in nodes[cur]["depends"]
                    if d in nodes and levels.get(d) == cur_level - 1
                )
                if not candidates:
                    break
                nxt = candidates[0]
                critical_path.append(nxt)
                cur = nxt
                cur_level -= 1
            critical_path.reverse()
        metrics = {"nodes": len(order_ids), "width": width, "depth": depth, "critical_path": critical_path}

    edges = []
    for tid in order_ids:
        for dep in nodes[tid]["depends"]:
            if dep in nodes:
                edges.append([dep, tid])

    warnings = []
    for tid in order_ids:
        st = nodes[tid]["status"]
        if st not in KNOWN_STATUSES:
            warnings.append("unknown status '%s' on %s" % (st, tid))
    warnings.extend(malformed_warnings)

    ready = []
    for tid in order_ids:
        st = nodes[tid]["status"]
        if st not in ("pending", "stale"):
            continue
        deps_done = all(
            nodes[d]["status"] == "done"
            for d in nodes[tid]["depends"]
            if d in nodes
        )
        if deps_done:
            ready.append(tid)

    stale_closure = None
    if stale_id:
        stale_closure = []
        if stale_id in nodes:
            visited = set()
            stack = list(children.get(stale_id, []))
            while stack:
                cur = stack.pop()
                if cur in visited:
                    continue
                visited.add(cur)
                stack.extend(children.get(cur, []))
            stale_closure = sorted(i for i in visited if nodes[i]["status"] == "done")

    node_list = [
        {
            "id": tid,
            "summary": nodes[tid]["summary"],
            "status": nodes[tid]["status"],
            "depends": nodes[tid]["depends"],
            "domain": nodes[tid]["domain"],
            "note": nodes[tid]["note"],
        }
        for tid in order_ids
    ]

    # 判定優先順 (複数該当時は先勝ち): PARSE_ERROR (例外時に既に emit 済み) ->
    # NO_TASKS (既に上で処理済み) -> CYCLE -> MISSING_DEP -> VERIFIER_FLOOR ->
    # (--fit 時のみ) UNFIT_FALLBACK_LOOP -> OK。
    if cycle_flag:
        emit(node_list, edges, metrics, ready, warnings, "CYCLE", 3, stale_closure=stale_closure)
    if missing_flag:
        emit(node_list, edges, metrics, ready, warnings, "MISSING_DEP", 4, stale_closure=stale_closure)
    if verifier_flag:
        emit(node_list, edges, metrics, ready, warnings, "VERIFIER_FLOOR", 5, stale_closure=stale_closure)
    if fit and (len(order_ids) <= 2 or metrics["width"] == 1):
        emit(node_list, edges, metrics, ready, warnings, "UNFIT_FALLBACK_LOOP", 2, stale_closure=stale_closure)

    emit(node_list, edges, metrics, ready, warnings, "OK", 0, stale_closure=stale_closure)


# rev3 追加: 入力読取〜JSON emit 全体を防御的 try/except で囲む。emit() の
# sys.exit() は意図した制御フロー (SystemExit は BaseException 直下で Exception
# を継承しないため except Exception には捕捉されず、正常に伝播する)。それ以外の
# 未知の例外は全て PARSE_ERROR (exit 7) の構造化 JSON へ変換し、生 traceback を
# 一切標準出力へ漏らさない。
try:
    plan_text = read_plan_text(plan_path)
    compile_graph(plan_text)
except SystemExit:
    raise
except Exception as e:
    parse_error("%s: %s" % (type(e).__name__, e))
PYEOF
