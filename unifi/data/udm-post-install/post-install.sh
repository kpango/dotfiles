#!/bin/bash
#
# post-install.sh — re-run every component's install hook on the UDM Pro
# (CONTEXT.md Q42). Single list shared by `make unifi/install`
# (scripts/unifi-install.sh, over ssh) and boot (on_boot.d/90-post-install.sh,
# detached via systemd-run), so a reboot ends in the same state as an install.
# Idempotent: hooks only rewrite units whose content differs. Add a new
# /data/<component>/install.sh to HOOKS.
#
# One failing hook does not stop the rest; it prints "[hook-fail] <hook> rc=<n>"
# and the script exits 1.
set -uo pipefail

HOOKS=(
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
  /data/udm-dfs-restore/install.sh
  /data/udm-mape-fallback/install.sh
  /data/clean-clients/install.sh
)

fail=0
for i in "${HOOKS[@]}"; do
  [ -x "$i" ] || continue
  echo "[post-install] $i"
  "$i" || { rc=$?; echo "[hook-fail] $i rc=$rc" >&2; fail=1; }
done

if [ -x /data/unifi-native-guard/guard.sh ]; then
  echo '[post-install] /data/unifi-native-guard/guard.sh units'
  /data/unifi-native-guard/guard.sh units || { rc=$?; echo "[hook-fail] guard.sh units rc=$rc" >&2; fail=1; }
fi

echo '[post-install] udm-boot.service (runs /data/on_boot.d/*.sh at boot)'
cmp -s /data/on_boot.d/udm-boot.service /etc/systemd/system/udm-boot.service \
  || cp /data/on_boot.d/udm-boot.service /etc/systemd/system/udm-boot.service
systemctl daemon-reload
echo '[post-install] systemctl daemon-reload done'
systemctl enable udm-boot.service || { echo '[hook-fail] systemctl enable udm-boot.service' >&2; fail=1; }

exit "$fail"
