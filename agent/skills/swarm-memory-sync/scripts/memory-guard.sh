#!/usr/bin/env bash
# Deterministic pre-write guard for swarm-memory-sync.
# supermemory.sh was retired in M1 (4-harness migration); search falls back to
# local Claude auto-memory (~/.claude/projects/*/memory/*.md) and Hermes memory
# (~/.hermes/memories/*.md) and prints structured JSON results.
#
# Usage:
#   memory-guard.sh [--] <keyword> [<keyword> ...]
#     Searches local Claude/Hermes memory files for matching lines and outputs
#     {"results": [...], "backend": "local-memory"}.
#   memory-guard.sh --ingest <file>
#   memory-guard.sh --status <id>
#     Returns retirement notice (exit 1): supermemory was retired in M1.
set -euo pipefail

usage() {
  echo "usage: memory-guard.sh [--] <keyword> [<keyword> ...]" >&2
  echo "       memory-guard.sh --ingest <file>" >&2
  echo "       memory-guard.sh --status <id>" >&2
}

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

case "$1" in
  --ingest|--status)
    echo "memory-guard.sh: supermemory was retired in M1; update native Claude auto-memory or Hermes memory directly" >&2
    exit 1
    ;;
  --record)
    echo "memory-guard.sh: --record has been removed" >&2
    exit 1
    ;;
  --)
    shift
    ;;
  -*)
    echo "memory-guard.sh: unknown option: $1" >&2
    usage
    exit 1
    ;;
  *)
    ;;
esac

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

python3 - "$@" <<'PY'
import glob
import json
import os
import sys

keywords = [k.lower() for k in sys.argv[1:] if k]
home = os.path.expanduser("~")
patterns = [
    os.path.join(home, ".claude", "projects", "*", "memory", "*.md"),
    os.path.join(home, ".hermes", "memories", "*.md"),
]
results = []
for pat in patterns:
    for path in sorted(glob.glob(pat)):
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        matches = [
            {"line": idx, "text": line.rstrip("\n")}
            for idx, line in enumerate(lines, 1)
            if any(kw in line.lower() for kw in keywords)
        ]
        if matches:
            results.append({"path": path, "matches": matches[:5]})
            if len(results) >= 10:
                break
    if len(results) >= 10:
        break

print(json.dumps({"results": results, "backend": "local-memory"}, ensure_ascii=False))
PY
