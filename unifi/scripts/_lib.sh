#!/usr/bin/env bash
# _lib.sh — shared helpers for unifi/scripts/.
# Source this at the top of unifi-{pull,install,diff}.sh:
#   . "$(dirname "$0")/_lib.sh"
# Not meant to be executed on its own.

# UDM Pro SSH destination (host alias from ~/.ssh/config; override via env).
UDM="${UDM:-udmpro}"

# Repository root. git first (works even inside a worktree), filesystem fallback
# second (for machines where the dotfiles tree is not a git checkout).
if ! REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
fi

# Directory layout — single source of truth for every script to point at.
UNIFI_DIR="$REPO_ROOT/unifi"
UNIFI_SCRIPTS="$UNIFI_DIR/scripts"
UNIFI_DATA="$UNIFI_DIR/data"
UNIFI_ROOT="$UNIFI_DIR/root"

# die MSG... — print to stderr and exit 1.
die() { printf '%s\n' "$*" >&2; exit 1; }

# log TAG MSG... — single structured log line that every script shares.
log() { local tag=$1; shift; printf '[%s] %s\n' "$tag" "$*"; }
