#!/bin/bash
#
# udm-dpinger-hijack.sh — keep UDM's informational dpinger probes off
# third-party hosts by redirecting them to NextDNS.
#
# Diff-before-mutate fast-path + atomic iptables-restore (--noflush --wait=30)
# skips nat rebuilds and conntrack -D forks when DYNAMIC_IPS and OUTPUT hook
# have zero drift, while preserving full Q33 conntrack cleanup on any change.
#
set -uo pipefail

log() { logger -t udm-dpinger-hijack "$*"; }

LOCK=/run/udm-dpinger-hijack.lock
exec 9>"$LOCK"
flock -n 9 || { log "another udm-dpinger-hijack is running; skipping"; exit 0; }

NEXTDNS_A1_V4=45.90.28.0      # NextDNS Global anycast A1
CHAIN=UDM_DPINGER_HIJACK
UDM_SRCS="10.0.1.2 192.0.0.3" # eth10 WAN address, ip6tnl2 inner address

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

RULES=""
for ip in $DYNAMIC_IPS; do
    RULES+="-A $CHAIN -d ${ip}/32 -p icmp -j DNAT --to-destination $NEXTDNS_A1_V4
"
done
RULES="${RULES%$'\n'}"
EXPECTED="-N $CHAIN"
[ -n "$RULES" ] && EXPECTED="$EXPECTED
$RULES"

cur_chain=$(iptables -w 30 -t nat -S "$CHAIN" 2>/dev/null || true)
out_dump=$(iptables -w 30 -t nat -S OUTPUT 2>/dev/null || true)
hook_count=$(printf '%s\n' "$out_dump" | grep -c -- "-j $CHAIN$" || true)

if [ "$cur_chain" = "$EXPECTED" ] && [ "$hook_count" = "1" ]; then
    exit 0
fi

if [ "$cur_chain" != "$EXPECTED" ]; then
    iptables-restore --noflush --wait=30 <<EOF
*nat
:$CHAIN - [0:0]
-F $CHAIN
$RULES
COMMIT
EOF
    log "rebuilt nat $CHAIN"
fi

if [ "$hook_count" = "0" ]; then
    iptables -w 30 -t nat -I OUTPUT 1 -j "$CHAIN"
    log "v4 OUTPUT hook added"
elif [ "$hook_count" != "1" ]; then
    dedupe iptables nat OUTPUT "-j $CHAIN$" -j "$CHAIN"
fi

for ip in $DYNAMIC_IPS; do
    for src in $UDM_SRCS; do
        conntrack -D -p icmp -s "$src" -d "$ip" -r "$ip" >/dev/null 2>&1 \
            && log "dropped un-NATed conntrack $src -> $ip"
    done
done

exit 0
