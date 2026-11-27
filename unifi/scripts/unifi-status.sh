#!/usr/bin/env bash
# unifi-status — one-shot diagnostic snapshot of the UDM Pro side state.
# Covers: NextDNS CLI, Tailscale, dnsmasq@tailscale0, TS_ISOLATE, native systemd units.
# Read-only; never mutates state. Used from `make unifi/status`.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

log status "UDM=$UDM — collecting"

udm_exec 'set -o pipefail
echo "=== NextDNS CLI ==="
nextdns status 2>/dev/null || echo "(nextdns status unavailable)"
grep -E "^(profile|listen|cache-size|cache-max-age|max-ttl|report-client-info|bogus-priv|setup-router|forwarder)\b" /data/nextdns.conf 2>/dev/null | sed "s/^/  /"
echo
echo "=== recent healthcheck restarts (last 5) ==="
tail -5 /var/log/nextdns-healthcheck.log 2>/dev/null | sed "s/^/  /" || echo "  (no healthcheck.log yet; failures have not fired)"
echo
echo "=== Tailscale ==="
tailscale status 2>&1 | head -12
echo
echo "=== tailscale0 interface ==="
ip addr show tailscale0 2>&1 | sed "s/^/  /"
echo
echo "=== /etc/resolv.conf ==="
cat /etc/resolv.conf 2>/dev/null | sed "s/^/  /"
echo
echo "=== dnsmasq NextDNS + tailscale0 binding ==="
grep -E "^(server=127.0.0.1#|no-resolv|add-mac|add-subnet)" /run/dnsmasq.dhcp.conf.d/nextdns.conf 2>/dev/null | sed "s/^/  /" || echo "  (nextdns.conf missing)"
cat /run/dnsmasq.dhcp.conf.d/99-tailscale.conf 2>/dev/null | sed "s/^/  /" || echo "  (99-tailscale.conf missing)"
ss -ulnp | grep ":53 " | sed "s/^/  /" || echo "  (no UDP :53 listener)"
echo
echo "=== UniFi Native DoH check (must be disabled) ==="
pgrep -xa dnscrypt-proxy 2>/dev/null | sed "s/^/  /" || echo "  (dnscrypt-proxy absent — expected)"
echo
echo "=== TS_ISOLATE (IoT br2 isolation) ==="
iptables -w 30 -S TS_ISOLATE 2>/dev/null | sed "s/^/  /" || echo "  (TS_ISOLATE missing)"
echo
echo "=== user-added systemd units (active/failed) ==="
systemctl list-units --no-pager --no-legend --state=active,failed \
  nextdns.service nextdns-dnsmasq-wire.path nextdns-client-names.timer nextdns-healthcheck.timer \
  tailscaled.service tailscale-install.timer tailscale-cert-renewal.timer \
  tailscale-dnsmasq.path tailscale-dnsmasq.timer tailscale-guard.timer \
  udm-sysctl.service udm-post-install.service \
  game-geo-bypass.timer unifi-native-guard-geoip-eth8.timer \
  udm-sla-tune.timer udm-nuro-v6-pbr.timer udm-dns-hijack.timer \
  udm-dpinger-hijack.timer udm-verifier-enforcer.timer udm-dfs-restore.timer \
  udm-mape-fallback.timer clean-clients.timer ndppd.service 2>/dev/null | sed "s/^/  /"'
