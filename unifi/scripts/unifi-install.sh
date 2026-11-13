#!/usr/bin/env bash
# unifi-install — push dotfiles/unifi/{data,root}/ to UDM Pro via tar+ssh (rsync-free).
# Overwrite semantics: tar extraction replaces existing files. Idempotent per file content.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

DRY_RUN="${DRY_RUN:-0}"

log install "UDM=$UDM, DRY_RUN=$DRY_RUN"

# push_dir LOCAL REMOTE — tar-pipe LOCAL into REMOTE on the UDM Pro.
push_dir() {
  local local_dir=$1 remote_dir=$2
  if [ "$DRY_RUN" = "1" ]; then
    log dry-run "would push $local_dir → $UDM:$remote_dir :"
    (cd "$local_dir" && find . -type f | sed 's|^\./|  |')
    return 0
  fi
  log push "$local_dir → $UDM:$remote_dir"
  (cd "$local_dir" && tar c .) | ssh "$UDM" "tar x -C $remote_dir"
}

push_dir "$UNIFI_DATA" /data
push_dir "$UNIFI_ROOT" /root

if [ "$DRY_RUN" = "1" ]; then
  log install "dry-run complete"
  exit 0
fi

# Normalise permissions: tar preserves local perms, but re-apply on the remote
# in case anything was pushed with the wrong mode locally.
ssh "$UDM" 'find /data -maxdepth 4 -name "*.sh" -exec chmod +x {} \;
find /root -maxdepth 2 -name "*.sh" -exec chmod +x {} \;
chmod 644 /data/nextdns.conf 2>/dev/null || true'

# Post-install hooks + udm-boot.service + daemon-reload. The hook list lives
# on the UDM (data/udm-post-install/post-install.sh) so boot runs the same one
# (on_boot.d/90-post-install.sh, CONTEXT.md Q42). It prints
# "[hook-fail] <hook> rc=<n>" and exits non-zero if any hook failed.
ssh "$UDM" /data/udm-post-install/post-install.sh

log install "done"
