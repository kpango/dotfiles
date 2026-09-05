#!/usr/bin/env bash
# 決定論プロファイル抽出 + ハーネス推薦 (LLM 不使用)。
# usage: harness-select.sh [--profile-only] "<goal text>" [repo-root]
#   repo-root 省略時: git rev-parse --show-toplevel (失敗時 PWD)
#
# 推薦は 2 段階・独立 (混在させない):
#   (A) lenses 決定 = 常に加算的 (risk -> code-reviewer, secret/認証 -> +security-audit)
#   (B) harness 決定 = 上から評価し最初に真になった規則で確定
#   (C) registry 降格 = (B) が swarm-graph の場合のみ、過去の blocked>done 過半で swarm-loop へ降格
#   (D) 存在ガード = 決定 harness の SKILL.md が無ければ swarm-loop へ降格
#
# --profile-only: profile のみ出力 (recommendation を含まない)。exit は常に 0
#   (推薦は情報。強制は harness-lint と dispatch 先 hook が担う)。
# 仕様: /tmp/a970d944-5c72-44e0-bf62-429e73ed60c4/swarm/specs/sm-spec.md
set -euo pipefail

profile_only=false
if [ "${1:-}" = "--profile-only" ]; then
  profile_only=true
  shift
fi

goal="${1:?usage: harness-select.sh [--profile-only] \"<goal text>\" [repo-root]}"
repo_root="${2:-}"
if [ -z "$repo_root" ]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# 2026-09-04、harness-record.shの同箇所コメント参照: claude/pi/agy個別のharness-registry.tsvを
# agent/skills/swarm-meta/harness-registry.tsvへ統合したことに伴い、旧来の「logical cd(symlinkを
# 辿らない)で呼び出し元エコシステムディレクトリを意図的に保つ」設計を、常に単一の正典を指す
# `readlink -f`ベースの物理解決方式へ変更した。readlinkを`dirname`へ直接ネストさせず独立した
# statementにする理由はself-improve-check.shと同じ(ネストするとreadlink失敗をset -eが検知
# できず、無言でcwd依存の誤ったパスへフォールバックしてしまう)。
resolved_self="$(readlink -f "${BASH_SOURCE[0]}")"
registry_dir="$(dirname "$(dirname "$resolved_self")")"
registry="${HARNESS_REGISTRY:-$registry_dir/harness-registry.tsv}"
skills_dir="${HARNESS_SKILLS_DIR:-$HOME/.claude/skills}"

# 言語 mix: git ls-files の拡張子集計。git 外なら空配列。
# 注意: `git ls-files | python3 - <<EOF` は書いてはならない — パイプ(fd 0)と heredoc(fd 0)が
# 同じ標準入力を奪い合い、python3 が heredoc をプログラム本体として読むためパイプの読み手が
# 不在になる。実 git リポジトリでは SIGPIPE -> set -euo pipefail で exit 141・出力ゼロのまま
# クラッシュする (test-harness-guard.sh case17 の回帰対象)。heredoc は mktemp した一時ファイルへ
# 書き出し、標準入力はパイプ専用に空けておく。
langs_json="[]"
if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  langs_script="$(mktemp)"
  cat >"$langs_script" <<'PYEOF'
import sys, json, os
exts = {}
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    _, ext = os.path.splitext(line)
    if not ext:
        continue
    ext = ext[1:]
    exts[ext] = exts.get(ext, 0) + 1
langs = sorted(exts.keys(), key=lambda e: -exts[e])
print(json.dumps(langs))
PYEOF
  langs_json=$(git -C "$repo_root" ls-files 2>/dev/null | python3 "$langs_script")
  rm -f "$langs_script"
fi

# goal / registry / skills_dir を python へ引数として渡し、profile + recommendation を組み立てる。
# LLM を使わず決定論的な語彙一致・正規表現だけで判定する契約 (sm-spec.md 「harness-select.sh 契約」)。
python3 - "$goal" "$registry" "$skills_dir" "$profile_only" "$langs_json" <<'PYEOF'
import sys, json, re, os

goal = sys.argv[1]
registry_path = sys.argv[2]
skills_dir = sys.argv[3]
profile_only = sys.argv[4] == "true"
langs = json.loads(sys.argv[5])

goal_lower = goal.lower()

PARALLEL_WORDS = ["並行", "並列", "複数", "全域", "全体", "一括", "監査", "audit", "横断", "swarm"]
SEQUENTIAL_WORDS = ["順に", "手順", "逐次", "段階的", "一つずつ", "1ファイル", "リネーム", "typo"]
RISK_WORDS = ["マージ", "merge", "deploy", "リリース", "本番", "production", "hook",
              "削除", "破壊", "migration", "secret", "認証"]
SECRET_WORDS = ["secret", "認証"]

def count_hits(words):
    n = 0
    for w in words:
        if w.lower() in goal_lower:
            n += 1
    return n

parallel_n = count_hits(PARALLEL_WORDS)
sequential_n = count_hits(SEQUENTIAL_WORDS)
risk_n = count_hits(RISK_WORDS)
secret_hit = count_hits(SECRET_WORDS) > 0

if parallel_n > sequential_n:
    primary = "parallel"
elif sequential_n > parallel_n:
    primary = "sequential"
else:
    primary = "neutral"

# 規模ヒント: 「数値+(ファイル|タスク|箇所)」パターンから推定タスク数 est_tasks (無ければ null)
est_tasks = None
m = re.search(r'(\d+)\s*(?:ファイル|タスク|箇所)', goal)
if m:
    est_tasks = int(m.group(1))

profile = {
    "signals": {
        "parallel": parallel_n,
        "sequential": sequential_n,
        "risk": risk_n,
        "primary": primary,
    },
    "est_tasks": est_tasks,
    "langs": langs,
}

if profile_only:
    print(json.dumps({"profile": profile}))
    sys.exit(0)

# --- registry 照会: profile.signals.primary が一致する過去行を registry_matches として返す ---
# fail-safe: registry が読めない/デコード不能でもクラッシュしない (graph-compile.sh の PARSE_ERROR
# 契約と同じ「実績が読めないだけで選択を止めない」原則)。TSV は行独立レコードであり、all-or-nothing で
# 握り潰すと不正行 1 行が (C) registry 降格の安全弁を沈黙無効化してしまう (rev2 で実再現・修正)。
# harness-status.sh と同じパターンでバイナリ読込→行単位デコードし、不正行のみ skip してパース可能な
# 行は registry_matches へ引き続き積む。
registry_matches = []
registry_unreadable_reason = None
registry_skipped_lines = 0
if os.path.isfile(registry_path):
    try:
        with open(registry_path, "rb") as f:
            raw_lines = f.readlines()
    except OSError as e:
        raw_lines = []
        registry_unreadable_reason = "%s" % e
    for raw_line in raw_lines:
        try:
            line = raw_line.decode("utf-8").rstrip("\n")
        except UnicodeDecodeError:
            registry_skipped_lines += 1
            continue
        if not line or line.startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) != 6:
            continue
        date, mission, harness, row_profile, model_version, outcome = cols
        if row_profile != primary:
            continue
        registry_matches.append({
            "date": date, "mission": mission, "harness": harness,
            "profile": row_profile, "model_version": model_version,
            "outcome": outcome,
        })

# --- (A) lenses 決定: 常に加算的、(B) に影響しない ---
lenses = []
if risk_n > 0:
    lenses.append("code-reviewer")
    if secret_hit:
        lenses.append("security-audit")

rationale = []
# ファイル自体が開けない場合のみ registry_matches=[] (上のループで空のまま) + 生の理由を記録する。
# 個別行のデコード失敗はファイル読み取り自体は成功しているため、この分岐とは独立に skip 件数を記録する。
if registry_unreadable_reason is not None:
    rationale.append("registry-unreadable: %s" % registry_unreadable_reason)
elif registry_skipped_lines > 0:
    rationale.append("registry-unreadable: %d lines skipped (decode errors)" % registry_skipped_lines)

# --- (B) harness 決定: 上から評価し最初に真になった規則で確定 ---
if sequential_n > parallel_n or (est_tasks is not None and est_tasks <= 2):
    harness = "swarm-loop"
    if sequential_n > parallel_n:
        rationale.append("rule1: sequential signal (%d) > parallel signal (%d)" % (sequential_n, parallel_n))
    if est_tasks is not None and est_tasks <= 2:
        rationale.append("rule1: est_tasks=%d <= 2" % est_tasks)
elif parallel_n > sequential_n and (est_tasks is None or est_tasks >= 3):
    harness = "swarm-graph"
    rationale.append("rule2: parallel signal (%d) > sequential signal (%d), est_tasks=%r" % (parallel_n, sequential_n, est_tasks))
else:
    harness = "swarm-loop"
    rationale.append("rule3: conservative default (Endure>Excel>Evolve)")

# --- (C) registry 降格 (降格のみ・昇格なし。harness=swarm-graph の場合のみ対象) ---
if harness == "swarm-graph":
    graph_rows = [r for r in registry_matches if r["harness"] == "swarm-graph"]
    parseable = 0
    blocked_majority = 0
    for r in graph_rows:
        mo = re.search(r'blocked=(\d+)', r["outcome"])
        do = re.search(r'done=(\d+)', r["outcome"])
        if not mo or not do:
            continue
        parseable += 1
        if int(mo.group(1)) > int(do.group(1)):
            blocked_majority += 1
    if parseable > 0 and blocked_majority * 2 > parseable:
        harness = "swarm-loop"
        rationale.append("registry-downgrade:%d/%d" % (blocked_majority, parseable))

# --- (D) 存在ガード (最終) ---
def skill_exists(name):
    return os.path.isfile(os.path.join(skills_dir, name, "SKILL.md"))

if not skill_exists(harness):
    unavailable = harness
    harness = "swarm-loop"
    if unavailable != "swarm-loop" and skill_exists("swarm-loop"):
        rationale.append("harness-unavailable:%s" % unavailable)
    else:
        rationale.append("harness-unavailable:%s (swarm-loop also unavailable, no other option)" % unavailable)

recommendation = {
    "harness": harness,
    "scale": "mission",
    "lenses": lenses,
    "budget": {"task_max": 5, "mission_max": 20},
    "rationale": rationale,
}

out = {
    "profile": profile,
    "recommendation": recommendation,
    "registry_matches": registry_matches,
}
print(json.dumps(out))
PYEOF
