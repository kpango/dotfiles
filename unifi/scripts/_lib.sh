#!/usr/bin/env bash
# _lib.sh — shared helpers for unifi/scripts/.
# Source this at the top of unifi-{pull,install,diff,status,audit,logs,update}.sh:
#   . "$(dirname "$0")/_lib.sh"
# Not meant to be executed on its own.

# Auto-detect local UDM Pro execution unless UDM is explicitly set.
if [ -z "${UDM:-}" ]; then
  if [ -x /usr/bin/ubnt-device-info ]; then
    UDM=local
  else
    UDM=udmpro
  fi
fi

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

# is_local — true when executing directly on the UDM Pro.
is_local() { [ "$UDM" = "local" ] || [ "$UDM" = "localhost" ]; }

# udm_clean_locale_args — build `-u` args for `env` so unsupported workstation
# locales (e.g. en_US.UTF-8, ja_JP.UTF-8) are not forwarded to UDM Pro via SendEnv.
_udm_locale_env_cmd() {
  local unset_args=(-u LANGUAGE) v
  for v in $(compgen -v LC_); do
    unset_args+=(-u "$v")
  done
  env "${unset_args[@]}" LANG=C.UTF-8 LC_ALL=C.UTF-8 "$@"
}

# udm_ssh ARGS... — invoke ssh without forwarding unsupported workstation locales.
udm_ssh() {
  _udm_locale_env_cmd ssh "$@"
}

# udm_local_bash CMD — invoke local bash -c with sanitized C.UTF-8 locale.
udm_local_bash() {
  _udm_locale_env_cmd bash -c "$*"
}

# udm_exec CMD — execute command on UDM Pro (local bash -c or ssh).
udm_exec() {
  if is_local; then
    udm_local_bash "$*"
  else
    udm_ssh "$UDM" "$@"
  fi
}

# udm_pipe_in CMD — pipe stdin into a command on UDM Pro.
udm_pipe_in() {
  if is_local; then
    udm_local_bash "$*"
  else
    udm_ssh "$UDM" "$@"
  fi
}

# udm_pipe_out CMD — stream stdout from a command on UDM Pro.
udm_pipe_out() {
  if is_local; then
    udm_local_bash "$*"
  else
    udm_ssh "$UDM" "$@"
  fi
}
