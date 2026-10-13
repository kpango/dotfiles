#!/bin/sh
# nextdns-healthcheck — probe local DNS, restart NextDNS CLI (and dnsmasq if needed) on failure.
# fail-closed Zero Leak design relies on NextDNS CLI being up; this is the safety net.
set -eu
LOG=/var/log/nextdns-healthcheck.log
probe() { dig @127.0.0.1 nextdns.io +short +time=3 +tries=1 >/dev/null 2>&1; }
if probe; then exit 0; fi
printf '%s FAIL — restarting nextdns\n' "$(date -u +%FT%TZ)" >> "$LOG"
systemctl restart nextdns
sleep 10
if probe; then exit 0; fi
printf '%s FAIL after nextdns restart — restarting dnsmasq\n' "$(date -u +%FT%TZ)" >> "$LOG"
systemctl restart dnsmasq
