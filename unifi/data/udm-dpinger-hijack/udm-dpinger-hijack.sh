#!/bin/bash
#
# udm-dpinger-hijack.sh — keep UDM's informational dpinger probes off
# third-party hosts by redirecting them to NextDNS.
#
# The failover health probes are configured through UniFi's official WAN
# SLA ("NextDNS", /v2/api/site/default/wan-slas, assigned to WAN1 and
# WAN2), so they already target NextDNS. UDAPI still appends extra
# informational monitors per WAN that WAN SLA cannot change:
#
#   echo_server uptime monitor   -> 45.90.28.0 (set via usg by
#                                   udm-verifier-enforcer; nothing to do)
#   www.microsoft.com  (icmp)    -> redirected here
#   google.com         (icmp)    -> redirected here
#   1.1.1.1            (icmp)    -> redirected here
#
# UDAPI resolves those hostnames itself and bakes the resulting IPs into
# each dpinger's argv, so we scrape the IPs from the running dpinger
# processes and DNAT UDM-originated ICMP to them over to NextDNS A1. The
# scrape skips RFC1918 / loopback / link-local / 192.0.0.0/24 (DS-Lite
# inner) / 45.90.0.0/16 (already NextDNS).
#
# History: an /etc/hosts override for these hostnames (and static DNAT for
# 8.8.8.8 and :53) was removed on 2026-10-20. The hosts block leaked into
# /etc/hosts.dnsmasq (nextdns-client-names copies /etc/hosts there), which
# made the NextDNS CLI (use-hosts true) answer google.com with a NextDNS IP
# — a latent breakage for LAN clients — and UDAPI did not use it anyway.
#
# Idempotent — the UDM_DPINGER_HIJACK chain is flushed and rebuilt per run,
# OUTPUT hook is added only if missing. Run every 60s by the paired timer so
# UDAPI firewall rebuilds don't drop the chain for long.
#
set -uo pipefail

log() { logger -t udm-dpinger-hijack "$*"; }

LOCK=/run/udm-dpinger-hijack.lock
exec 9>"$LOCK"
flock -n 9 || { log "another udm-dpinger-hijack is running; skipping"; exit 0; }

NEXTDNS_A1_V4=45.90.28.74     # NextDNS profile 21553f, anycast A1
CHAIN=UDM_DPINGER_HIJACK
UDM_SRCS="10.0.1.2 192.0.0.3" # eth10 WAN address, ip6tnl2 inner address

# `-C` only answers "at least one"; drop extra copies so exactly one remains.
# Duplicates were left behind by an earlier -C that ran without -w and lost
# the xtables lock to UniFi, which made it look like the rule was missing.
dedupe() {  # dedupe <iptables|ip6tables> <table> <chain> <grep-pattern> <rule...>
    local ipt=$1 table=$2 chain=$3 pat=$4; shift 4
    while [ "$($ipt -w 30 -t "$table" -S "$chain" | grep -c -- "$pat")" -gt 1 ]; do
        $ipt -w 30 -t "$table" -D "$chain" "$@" || break
        log "removed duplicate $chain rule ($pat)"
    done
}

DYNAMIC_IPS=$(ps -o args= -C dpinger 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    | grep -vE '^(45\.90\.|10\.|127\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|169\.254\.|192\.0\.0\.)' \
    | sort -u)

iptables -w 30 -t nat -N "$CHAIN" 2>/dev/null || true
iptables -w 30 -t nat -F "$CHAIN"
for ip in $DYNAMIC_IPS; do
    iptables -w 30 -t nat -A "$CHAIN" -p icmp -d "$ip" -j DNAT --to-destination "$NEXTDNS_A1_V4"
done
iptables -w 30 -t nat -C OUTPUT -j "$CHAIN" 2>/dev/null \
    || { iptables -w 30 -t nat -I OUTPUT 1 -j "$CHAIN"; log "v4 OUTPUT hook added"; }
dedupe iptables nat OUTPUT "-j $CHAIN$" -j "$CHAIN"

# A dpinger that started pinging an IP before its rule existed keeps a
# conntrack entry that bypasses DNAT for as long as it keeps pinging. Drop
# only entries whose reply still comes from the original target
# (reply-src == dst means "never NATed"); NATed entries are left alone.
for ip in $DYNAMIC_IPS; do
    for src in $UDM_SRCS; do
        conntrack -D -p icmp -s "$src" -d "$ip" -r "$ip" >/dev/null 2>&1 \
            && log "dropped un-NATed conntrack $src -> $ip"
    done
done

exit 0
