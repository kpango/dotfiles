#!/usr/bin/env bash
# The repo-root AGENTS.md is the single project body (a regular file); CLAUDE.md and GEMINI.md must be
# symlinks to it (no copies that can drift).
# A tool that rewrites one of them as a regular file (e.g. `trail init`) is caught here.
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BODY_REL="AGENTS.md"
fails=0
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

[ -f "$ROOT/$BODY_REL" ] && [ ! -L "$ROOT/$BODY_REL" ] || fail "$BODY_REL must be a regular file"
body_real="$(readlink -f "$ROOT/$BODY_REL")"

for f in CLAUDE.md GEMINI.md; do
    if [ ! -L "$ROOT/$f" ]; then
        fail "$f must be a symlink to $BODY_REL (it is not a symlink)"
        continue
    fi
    [ "$(readlink -f "$ROOT/$f")" = "$body_real" ] || fail "$f resolves to $(readlink -f "$ROOT/$f"), want $body_real"
    # tracked as a symlink (mode 120000), not as a file copy
    if git -C "$ROOT" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
        mode="$(git -C "$ROOT" ls-files -s "$f" | cut -d' ' -f1)"
        [ "$mode" = "120000" ] || fail "$f is tracked with mode $mode, want 120000 (symlink)"
    fi
    [ "$fails" -eq 0 ] && echo "PASS: $f -> $BODY_REL"
done

grep -q 'one body, one root' "$ROOT/$BODY_REL" || fail "$BODY_REL lost its instruction-file topology note"

[ "$fails" -eq 0 ] || { echo "test-root-agent-files: $fails FAIL"; exit 1; }
echo "test-root-agent-files: 全テストPASS"
