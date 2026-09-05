#!/usr/bin/env bash
# harness-registry.tsv の実績を人間可読に要約する (swarm-meta, loop-status.sh/graph-status.sh
# パターンの移植)。表示専用ツールであり判定の機械強制はしない (実行時の最終権威は dispatch 先
# ハーネスの hook)。M4 EVOLVE-FEED の「同一 profile-primary で同型の失敗が 2 回以上反復」判定を
# testable なスクリプトへ切り出したものが profile-primary 引数の Detail 節。
# usage: harness-status.sh [profile-primary]
#   registry: $(dirname "$0")/../harness-registry.tsv (env HARNESS_REGISTRY で上書き可)
# registry 不在/空/不正 UTF-8 行でもクラッシュしない (不正行はスキップし warning 表示)。
# exit は常に 0 固定 (harness-select.sh --profile-only と同じ「表示・情報のみ」契約)。
# python3 へは `cmd | python3 - <<heredoc` を使わない (パイプと heredoc が fd 0 を奪い合う既知バグ
# — harness-select.sh の langs_json 実装コメント参照)。registry パスを argv でファイル引数として渡す。
# 仕様: /tmp/a970d944-5c72-44e0-bf62-429e73ed60c4/swarm/specs/impl-meta-spec.md 「変更2」
# 「exit 0 固定」契約のため -e は意図的に外している (python3 の予期しない失敗があっても後続の
# `exit 0` まで実行を継続させる。表示専用ツールであり判定を機械強制しないという設計に従う)。
set -uo pipefail

# **重要**: `..` は cd の引数内で処理する（symlink越しの論理パスを保つため。詳細は
# harness-record.sh の同箇所コメント参照。pi-agent-consolidation-phase2 直後に実発生したバグの修正）。
registry_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
registry="${HARNESS_REGISTRY:-$registry_dir/harness-registry.tsv}"
primary_filter="${1:-}"

python3 - "$registry" "$primary_filter" <<'PYEOF'
import sys
import re
from collections import Counter, defaultdict

registry_path = sys.argv[1]
primary_filter = sys.argv[2]

warnings = []

# バイナリで読み、行ごとに個別デコードする (ファイル全体を一括 text open すると 1 行の不正
# UTF-8 で全体が読めなくなる — harness-select.sh/harness-lint.sh の「ファイル単位」fail-safe とは
# 異なり、本スクリプトは「行単位」で不正行だけをスキップし残りの集計を継続する契約)。
try:
    with open(registry_path, "rb") as f:
        raw_lines = f.readlines()
except FileNotFoundError:
    raw_lines = []
    warnings.append("registry not found: %s (treated as empty)" % registry_path)
except OSError as e:
    raw_lines = []
    warnings.append("cannot read registry: %s (treated as empty)" % e)

rows = []
for i, raw_line in enumerate(raw_lines, start=1):
    try:
        line = raw_line.decode("utf-8").rstrip("\r\n")
    except UnicodeDecodeError as e:
        warnings.append("skipped malformed line %d (invalid utf-8: %s)" % (i, e))
        continue
    if not line or line.startswith("#"):
        continue
    cols = line.split("\t")
    if len(cols) != 6:
        warnings.append("skipped malformed line %d (expected 6 tab-separated fields, got %d)" % (i, len(cols)))
        continue
    date, mission, harness, profile, model_version, outcome = cols
    rows.append({
        "date": date, "mission": mission, "harness": harness,
        "profile": profile, "model_version": model_version, "outcome": outcome,
    })


def blocked_gt_done(outcome):
    # harness-select.sh (C)registry降格判定と同じ抽出規則。パース不能なら None (分母から除外)。
    mo = re.search(r'blocked=(\d+)', outcome)
    do = re.search(r'done=(\d+)', outcome)
    if not mo or not do:
        return None
    return int(mo.group(1)) > int(do.group(1))


def blocked_majority_count(prows):
    parseable = 0
    blocked_majority = 0
    for r in prows:
        b = blocked_gt_done(r["outcome"])
        if b is None:
            continue
        parseable += 1
        if b:
            blocked_majority += 1
    return blocked_majority, parseable


print("## Harness Registry Summary")
print("  registry: %s" % registry_path)
print("  total: %d" % len(rows))
print()

print("## By harness")
harness_counts = Counter(r["harness"] for r in rows)
if harness_counts:
    for h in sorted(harness_counts):
        print("  %s: %d" % (h, harness_counts[h]))
else:
    print("  (none)")
print()

by_primary = defaultdict(list)
for r in rows:
    by_primary[r["profile"]].append(r)

print("## By profile-primary (outcome trend: blocked>done rows / parseable rows)")
if by_primary:
    for p in sorted(by_primary):
        blocked_majority, parseable = blocked_majority_count(by_primary[p])
        print("  %s: %d/%d blocked>done (total rows=%d)" % (p, blocked_majority, parseable, len(by_primary[p])))
else:
    print("  (none)")
print()

print("## By model-version")
mv_counts = Counter(r["model_version"] for r in rows)
if mv_counts:
    for mv in sorted(mv_counts):
        print("  %s: %d" % (mv, mv_counts[mv]))
else:
    print("  (none)")
print()

if primary_filter:
    print("## Detail: %s" % primary_filter)
    prows = by_primary.get(primary_filter, [])
    blocked_majority, parseable = blocked_majority_count(prows)
    print("  rows: %d" % len(prows))
    print("  blocked>done: %d/%d" % (blocked_majority, parseable))
    if blocked_majority >= 2:
        print("  REPEAT: same-type failure (blocked>done) repeated %d times (>=2, EVOLVE-FEED candidate)" % blocked_majority)
    print()

print("## Warnings")
if warnings:
    for w in warnings:
        print("  - %s" % w)
else:
    print("  (none)")
PYEOF

exit 0
