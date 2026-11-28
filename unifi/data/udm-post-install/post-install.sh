#!/bin/bash
#
# post-install.sh — re-run every component's install hook on the UDM Pro
# (CONTEXT.md Q42, R2/R3/R4 native systemd architecture).
# Single list shared by `make unifi/install` (scripts/unifi-install.sh) and
# boot (`udm-post-install.service`), so a reboot ends in the same state as an
# install. Idempotent: hooks only rewrite units whose content differs.
#
# One failing hook does not stop the rest; it prints "[hook-fail] <hook> rc=<n>"
# and the script exits 1.
set -uo pipefail

for _v in $(compgen -v LC_); do unset "$_v"; done
unset LANGUAGE _v
export LANG=C.UTF-8 LC_ALL=C.UTF-8

fail=0

if [ -x /data/unifi-native-guard/guard.sh ]; then
  echo '[post-install] /data/unifi-native-guard/guard.sh pins'
  /data/unifi-native-guard/guard.sh pins || { rc=$?; echo "[hook-fail] guard.sh pins rc=$rc" >&2; fail=1; }
fi

if [ -x /data/udm-post-install/bootstrap-packages.sh ]; then
  echo '[post-install] /data/udm-post-install/bootstrap-packages.sh'
  /data/udm-post-install/bootstrap-packages.sh || { rc=$?; echo "[hook-fail] bootstrap-packages.sh rc=$rc" >&2; fail=1; }
fi

HOOKS=(
  /data/udm-storage-tune/install.sh
  /data/udm-pg-tune/install.sh
  /data/udm-log-tune/install.sh
  /data/udm-zram-tune/install.sh
  /data/udm-service-tune/install.sh
  /data/udm-prio-tune/install.sh
  /data/udm-sysctl/install.sh
  /data/nextdns-client-names/install.sh
  /data/nextdns-dnsmasq-wire/install.sh
  /data/nextdns-healthcheck/install.sh
  /data/tailscale-dnsmasq/install.sh
  /data/tailscale-guard/install.sh
  /data/game-geo-bypass/install.sh
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

for i in "${HOOKS[@]}"; do
  [ -x "$i" ] || continue
  echo "[post-install] $i"
  "$i" || { rc=$?; echo "[hook-fail] $i rc=$rc" >&2; fail=1; }
done

if [ -x /data/unifi-native-guard/guard.sh ]; then
  echo '[post-install] /data/unifi-native-guard/guard.sh units'
  /data/unifi-native-guard/guard.sh units || { rc=$?; echo "[hook-fail] guard.sh units rc=$rc" >&2; fail=1; }
fi

# Sync Tailscale native systemd units without blocking on apt when active.
ts_changed=0
for u in tailscale-install.service tailscale-install.timer tailscale-cert-renewal.service tailscale-cert-renewal.timer; do
  src="/data/tailscale/$u"
  dst="/etc/systemd/system/$u"
  [ -f "$src" ] || continue
  if [ -L "$dst" ] || [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
    rm -f "$dst"
    install -m 0644 "$src" "$dst"
    ts_changed=1
  fi
done

# Self-unit: udm-post-install.service (replaces retired udm-boot.service)
self_src=/data/udm-post-install/units/udm-post-install.service
self_dst=/etc/systemd/system/udm-post-install.service
if [ -L "$self_dst" ] || [ ! -f "$self_dst" ] || ! cmp -s "$self_src" "$self_dst"; then
  rm -f "$self_dst"
  install -m 0644 "$self_src" "$self_dst"
  ts_changed=1
fi

# Idempotent cleanup of retired udm-boot & cron artifacts only.
legacy_removed=0
if [ -e /etc/systemd/system/udm-boot.service ] || [ -L /etc/systemd/system/udm-boot.service ]; then
  systemctl disable --now udm-boot.service 2>/dev/null || true
  rm -f /etc/systemd/system/udm-boot.service
  legacy_removed=1
fi
rm -f /etc/cron.d/nextdns-healthcheck /data/nextdns-healthcheck.sh
rm -rf /data/on_boot.d

if [ "$ts_changed" = 1 ] || [ "$legacy_removed" = 1 ]; then
  systemctl daemon-reload
  echo '[post-install] systemctl daemon-reload done'
fi

systemctl enable udm-post-install.service >/dev/null \
  || { echo '[hook-fail] systemctl enable udm-post-install.service' >&2; fail=1; }

if [ -f /etc/systemd/system/tailscale-install.service ]; then
  systemctl enable tailscale-install.service >/dev/null \
    || { echo '[hook-fail] systemctl enable tailscale-install.service' >&2; fail=1; }
fi
if [ -f /etc/systemd/system/tailscale-install.timer ]; then
  systemctl enable --now tailscale-install.timer >/dev/null \
    || { echo '[hook-fail] systemctl enable --now tailscale-install.timer' >&2; fail=1; }
fi
if [ -d /data/tailscale/certs ] && ls /data/tailscale/certs/*.crt >/dev/null 2>&1 && [ -f /etc/systemd/system/tailscale-cert-renewal.timer ]; then
  systemctl enable --now tailscale-cert-renewal.timer >/dev/null \
    || { echo '[hook-fail] systemctl enable --now tailscale-cert-renewal.timer' >&2; fail=1; }
fi
if ! systemctl is-active --quiet tailscaled.service && [ -f /etc/systemd/system/tailscale-install.service ]; then
  systemctl start --no-block tailscale-install.service \
    || { echo '[hook-fail] systemctl start --no-block tailscale-install.service' >&2; fail=1; }
fi

if [ "$fail" = 0 ]; then
  systemctl reset-failed udm-post-install.service 2>/dev/null || true
fi

exit "$fail"
