#!/usr/bin/env bash
# unifi-status — one-shot diagnostic snapshot of the UDM Pro side state.
# Covers: nextdns CLI, Tailscale, user-added systemd units, firewall allowlists.
# Read-only; never mutates remote state. Used from `make unifi/status`.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

log status "UDM=$UDM — collecting"

ssh "$UDM" 'set -o pipefail
echo "=== nextdns CLI ==="
nextdns status 2>/dev/null || echo "(nextdns status unavailable)"
grep -E "^(profile|listen|cache-size|cache-max-age|max-ttl|report-client-info|bogus-priv|setup-router)\b" /data/nextdns.conf 2>/dev/null | sed "s/^/  /"
echo
echo "=== recent healthcheck restarts (last 5) ==="
tail -5 /var/log/nextdns-healthcheck.log 2>/dev/null | sed "s/^/  /" || echo "  (no healthcheck.log yet; failures have not fired)"
echo
echo "=== Tailscale ==="
tailscale status 2>&1 | head -4
echo
echo "=== dnsmasq upstream (:5342 → nextdns CLI expected) ==="
grep -E "^(server=127.0.0.1#|no-resolv|add-mac|add-subnet)" /run/dnsmasq.dhcp.conf.d/nextdns.conf 2>/dev/null | sed "s/^/  /"
echo
echo "=== user-added systemd units (active/failed only) ==="
systemctl list-units --no-pager --no-legend --state=active,failed \
  nextdns.service game-geo-bypass.timer tailscale-install.timer \
  unifi-native-guard-geoip-eth8.timer clean-clients.timer 2>/dev/null | sed "s/^/  /"
echo
echo "=== cron.d entries ==="
ls /etc/cron.d/nextdns-healthcheck 2>/dev/null && cat /etc/cron.d/nextdns-healthcheck | sed "s/^/  /" || echo "  (nextdns-healthcheck cron missing)"'
