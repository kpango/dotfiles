#!/usr/bin/env bash
# unifi-logs — tail the user-relevant logs on the UDM Pro (nextdns, healthcheck,
# tailscale) with a sensible default line count. Follow mode via LINES=0 is NOT
# supported — SSH over tar+ssh is enough stress, and journalctl -f would hang
# make targets. Used from `make unifi/logs`.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

LINES="${LINES:-50}"
log logs "UDM=$UDM — tailing last $LINES lines of each"

ssh "$UDM" "set +e
echo '=== nextdns.service (journalctl, last $LINES) ==='
journalctl -u nextdns --no-pager -n $LINES
echo
echo '=== nextdns-healthcheck.log ==='
tail -n $LINES /var/log/nextdns-healthcheck.log 2>/dev/null || echo '(no log file yet)'
echo
echo '=== tailscaled (journalctl, last $LINES) ==='
journalctl -u tailscaled --no-pager -n $LINES
echo
echo '=== dmesg | grep -i nextdns|tailscale|wan (last $LINES) ==='
dmesg -T 2>/dev/null | grep -iE 'nextdns|tailscale|wan' | tail -n $LINES || echo '(no matching dmesg lines)'"
