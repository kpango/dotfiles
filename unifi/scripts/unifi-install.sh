#!/usr/bin/env bash
# unifi-install — push dotfiles/unifi/{data,root}/ to UDM Pro via tar+ssh (rsync-free).
# Overwrite semantics: tar extraction replaces existing files. Idempotent per file content.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

DRY_RUN="${DRY_RUN:-0}"

# Post-install hooks to re-run on every install so firmware-wiped /etc gets
# rebuilt. Each entry is a path on the UDM Pro and must be an executable file.
# Add new installers here when a new /data/<component>/install.sh is introduced.
POST_INSTALL_HOOKS=(
  /data/game-geo-bypass/install.sh
  /data/nextdns-client-names/install.sh
  /data/nextdns-dnsmasq-wire/install.sh
  /data/on_boot.d/30-nextdns-healthcheck-install.sh
  /data/udm-sla-tune/install.sh
  /data/udm-nuro-v6-pbr/install.sh
  /data/udm-dns-hijack/install.sh
  /data/udm-ndp-proxy/install.sh
  /data/udm-dpinger-hijack/install.sh
  /data/udm-verifier-enforcer/install.sh
  /data/clean-clients/install.sh
)
# guard.sh is special — it takes an "units" argument rather than being a bare
# installer, so it is handled by its own line further down.

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

# Post-install hooks + systemctl daemon-reload.
# Build a shell-safe literal list of hook paths with printf %q so entries with
# spaces or shell metacharacters cannot break the remote for-loop. Hook stderr
# and exit code are both captured so a silent failure stops being silent — the
# remote prints "[hook-fail] <path> rc=<n>" and the local shell exits non-zero
# if any hook failed, matching the user's expectation that "no output = success".
HOOK_LIST=$(printf ' %q' "${POST_INSTALL_HOOKS[@]}")
# shellcheck disable=SC2029  # hook list is intentionally expanded locally
ssh "$UDM" "fail=0
for i in $HOOK_LIST; do
  if [ -x \"\$i\" ]; then
    echo \"[post-install] \$i\"
    if ! \"\$i\"; then rc=\$?; echo \"[hook-fail] \$i rc=\$rc\" >&2; fail=1; fi
  fi
done
if [ -x /data/unifi-native-guard/guard.sh ]; then
  echo '[post-install] /data/unifi-native-guard/guard.sh units'
  if ! /data/unifi-native-guard/guard.sh units; then
    rc=\$?; echo \"[hook-fail] guard.sh units rc=\$rc\" >&2; fail=1
  fi
fi
echo '[post-install] udm-boot.service (runs /data/on_boot.d/*.sh at boot)'
cp /data/on_boot.d/udm-boot.service /etc/systemd/system/udm-boot.service
systemctl daemon-reload
echo '[post-install] systemctl daemon-reload done'
if ! systemctl enable udm-boot.service; then
  echo '[hook-fail] systemctl enable udm-boot.service' >&2; fail=1
fi
exit \$fail"

log install "done"
