#!/bin/sh
# nextdns-healthcheck — probe local DNS, restart NextDNS CLI (and dnsmasq if needed) on failure.
# fail-closed Zero Leak design relies on NextDNS CLI being up; this is the safety net.
set -eu
LOG=/var/log/nextdns-healthcheck.log
probe() { dig @127.0.0.1 nextdns.io +short +time=3 +tries=1 >/dev/null 2>&1; }
# dnsmasq は CLI を外れても NextDNS IP へ直接引けて probe が通るため、配線は別に見る (path unit の取りこぼし対策)
rc=0; /data/nextdns-dnsmasq-wire/check.sh || rc=$?
case $rc in
0) ;;
2) printf '%s dnsmasq → CLI wiring was missing — restarted nextdns\n' "$(date -u +%FT%TZ)" >> "$LOG"; exit 0 ;;
*) printf '%s FAIL — nextdns-dnsmasq-wire check rc=%s\n' "$(date -u +%FT%TZ)" "$rc" >> "$LOG" ;;
esac
if probe; then exit 0; fi
printf '%s FAIL — restarting nextdns\n' "$(date -u +%FT%TZ)" >> "$LOG"
systemctl restart nextdns
sleep 10
if probe; then exit 0; fi
printf '%s FAIL after nextdns restart — restarting dnsmasq\n' "$(date -u +%FT%TZ)" >> "$LOG"
systemctl restart dnsmasq
