#!/usr/bin/env bash
#
# f2886q-apply.sh — venv/playwright bootstrap wrapper around f2886q-apply.py.
#
# python-playwright is heavy and not useful outside of this script, so we
# install it into an ephemeral venv under $TMPDIR rather than polluting
# the system Python or dotfiles' own tooling. The venv is reused across
# runs — a successful install leaves `.ok` behind — so only the first
# invocation pays the pip-install cost.
#
# Modes:
#   plan   — read-only state diff
#   apply  — enforce desired state
#
# Driven by:  make unifi/f2886q-plan   /  make unifi/f2886q-apply
#
set -euo pipefail

MODE="${1:?usage: $0 <plan|apply>}"
case "$MODE" in plan|apply) ;; *) echo "mode must be plan or apply" >&2; exit 2 ;; esac

HERE=$(cd "$(dirname "$0")" && pwd)
VENV="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-f2886q-venv"

if [ ! -f "$VENV/.ok" ]; then
    rm -rf "$VENV"
    python3 -m venv "$VENV"
    # Playwright is pinned loosely — any 1.x is fine. The ZTE UI selectors
    # the script walks are stable and don't depend on specific Playwright
    # API additions.
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet "playwright>=1.40,<2.0"
    touch "$VENV/.ok"
fi

exec "$VENV/bin/python" "$HERE/f2886q-apply.py" "$MODE"
