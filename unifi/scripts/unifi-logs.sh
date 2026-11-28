#!/usr/bin/env bash
# unifi-logs — tail the user-relevant logs on the UDM Pro (nextdns,
# tailscaled, tailscale-install, tailscale-cert-renewal, tailscale-dnsmasq,
# tailscale-guard, udm-post-install, udm-sysctl, dmesg) with a sensible default line count.
# Used from `make unifi/logs`.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

LINES="${LINES:-50}"
log logs "UDM=$UDM — tailing last $LINES lines of each"

udm_exec "set +e
for unit in nextdns nextdns-dnsmasq-wire nextdns-healthcheck nextdns-client-names tailscaled tailscale-install tailscale-cert-renewal tailscale-dnsmasq tailscale-guard udm-post-install udm-sysctl; do
  echo \"=== \$unit (journalctl, last $LINES) ===\"
  journalctl -u \"\$unit\" --no-pager -n $LINES
  echo
done
echo '=== /var/log/nextdns-healthcheck.log ==='
tail -n $LINES /var/log/nextdns-healthcheck.log 2>/dev/null || echo '(empty/absent)'
echo
echo '=== dmesg | grep -i tailscale|wan|ip6tnl2 (last $LINES) ==='
dmesg -T 2>/dev/null | grep -iE 'tailscale|wan|ip6tnl2' | tail -n $LINES || echo '(no matching dmesg lines)'"
