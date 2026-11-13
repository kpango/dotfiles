#!/usr/bin/env bash
# unifi-pull — refresh dotfiles/unifi/{data,root}/ from the live UDM Pro.
# Scope: user-authored assets only (/data/* scripts/configs + /root/ admin scripts).
# UniFi controller state (networkconf/setting/wlanconf/firewall-policies/...) is
# backed up by UniFi Cloud and intentionally not shadowed here — those dumps carry
# WPA2 PSK, SSH credentials, SSO/API tokens as plain-text fields and tracking them
# in git puts secrets at risk (2026-10-14 incident).
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

ALLOWLIST="$UNIFI_SCRIPTS/_data-allowlist.txt"
[ -r "$ALLOWLIST" ] || die "allowlist not readable: $ALLOWLIST"

# Comment-stripped, blank-stripped paths from the allowlist, joined into
# a single space-separated argv for the remote tar command.
mapfile -t DATA_PATHS < <(grep -vE '^\s*(#|$)' "$ALLOWLIST")
(( ${#DATA_PATHS[@]} > 0 )) || die "allowlist is empty: $ALLOWLIST"

# Guard against a missing destination tree: tar x -C <dir> fails loudly if <dir>
# does not exist, and after a fresh clone that is a real possibility.
mkdir -p "$UNIFI_DATA" "$UNIFI_ROOT"

log pull "UDM=$UDM → $UNIFI_DATA and $UNIFI_ROOT"

# /data allowlist pull.
# shellcheck disable=SC2029  # paths intentionally expanded locally
ssh "$UDM" "cd /data && tar c ${DATA_PATHS[*]} 2>/dev/null" | tar x -C "$UNIFI_DATA"

# /root admin scripts (denylist for dotfiles / ssh / pass / gnupg / history).
ROOT_EXCLUDES=(
  .bash_history .cache .claude .claude.json .config .gnupg .ssh .local
  .password-store .netrc pass .dbshell .history_frr .lesshst .wget-hsts
  .profile .bashrc .vimrc
)
EXCLUDE_ARGS=()
for e in "${ROOT_EXCLUDES[@]}"; do EXCLUDE_ARGS+=(--exclude="./$e"); done
# shellcheck disable=SC2029
ssh "$UDM" "cd /root && tar c ${EXCLUDE_ARGS[*]} ." | tar x -C "$UNIFI_ROOT"

log pull "done — review 'git diff unifi/' before committing"
