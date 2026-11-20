#!/bin/bash
#
# geoip-eth8.sh — apply CyberSecure Region Blocking to eth8 (native IPv6 of the DS-Lite WAN)
#
# Background: with a DS-Lite WAN, UniFi registers only ip6tnl1 (IPv4-in-IPv6 tunnel) as the
# WAN interface, so services.geoipFiltering.interfaces never contains eth8 and native IPv6
# of every LAN (prefix delegated via eth8) bypasses Region Blocking.
#
# This mirrors UniFi's UBIOS_IN_GEOIP / UBIOS_OUT_GEOIP semantics for eth8 in chains of its
# own. It reads the country list/action/direction that the controller pushes to udapi
# (i.e. what is configured in the CyberSecure UI) and never references UniFi-owned chains
# or ipsets, so udapi-server can rebuild its firewall freely (a referenced chain/ipset
# would make its iptables-restore fail -> "Gateway Configuration Failed").
#
# Idempotent; run by unifi-native-guard-geoip-eth8.{timer,path}.
#
set -uo pipefail

IFACE=eth8
CFG=/data/udapi-config/udapi-net-cfg.json
IN=UNG_GEOIP_ETH8_IN
OUT=UNG_GEOIP_ETH8_OUT
STATE=/run/unifi-native-guard-geoip-eth8.state
IPT="ip6tables -w 10"

log() { logger -t geoip-eth8 "$*"; }

remove_all() {
    for spec in "INPUT -i $IFACE -j $IN" "FORWARD -i $IFACE -j $IN" "FORWARD -o $IFACE -j $OUT"; do
        while $IPT -C $spec 2>/dev/null; do $IPT -D $spec; done
    done
    for c in $IN $OUT; do $IPT -F $c 2>/dev/null; $IPT -X $c 2>/dev/null; done
    rm -f "$STATE"
}

[ -r "$CFG" ] || exit 0
read -r enabled action direction countries < <(jq -r '
    .services.geoipFiltering // {} |
    "\(.enabled // false) \(.action // "block") \(.direction // "both") \((.countryList // []) | join(","))"' "$CFG")

if [ "$enabled" != "true" ] || [ -z "$countries" ]; then
    [ -e "$STATE" ] && { remove_all; log "Region Blocking disabled; removed $IFACE rules"; }
    exit 0
fi

case "$direction" in
    *in*|*ingress*) do_in=1; do_out=0 ;;
    *out*|*egress*) do_in=0; do_out=1 ;;
    *)              do_in=1; do_out=1 ;;
esac
# "block" = drop listed countries; anything else (allow-list mode) = drop all others
neg=""; [ "$action" = "block" ] || neg="!"

desired="$action $direction $countries"
chains_ok=1
for c in $IN $OUT; do $IPT -S $c >/dev/null 2>&1 || chains_ok=0; done

build_chain() {  # $1 chain, $2 --source-country|--destination-country, $3 log prefix, $4 enabled?
    $IPT -N "$1" 2>/dev/null || $IPT -F "$1"
    if [ "$4" = 1 ]; then
        $IPT -A "$1" -m state --state RELATED,ESTABLISHED -j RETURN
        $IPT -A "$1" -m geoip $neg "$2" "$countries" -m state --state NEW \
            -m limit --limit 50/sec --limit-burst 100 \
            -j NFLOG --nflog-prefix "[$3] DESCR=\"drop action\"" --nflog-group 2 --nflog-threshold 16
        $IPT -A "$1" -m geoip $neg "$2" "$countries" -j DROP
    fi
    $IPT -A "$1" -j RETURN
}

if [ $chains_ok = 0 ] || [ "$(cat "$STATE" 2>/dev/null)" != "$desired" ]; then
    build_chain $IN  --source-country      UBIOS_IN_GEOIP_ETH8  $do_in  &&
    build_chain $OUT --destination-country UBIOS_OUT_GEOIP_ETH8 $do_out &&
        { echo "$desired" > "$STATE"; log "applied: action=$action direction=$direction countries=$(echo "$countries" | tr ',' '\n' | wc -l)"; }
fi

# jump right before UniFi's own jump chain (same precedence as UniFi's GeoIP: after TOR/IPS/tailscale)
ensure_jump() {  # $1 chain, $2 anchor, rest = match
    local chain=$1 anchor=$2; shift 2
    $IPT -C "$chain" "$@" 2>/dev/null && return 0
    local pos
    pos=$($IPT -S "$chain" | grep -v '^-P' | grep -n -- "-j $anchor\$" | head -1 | cut -d: -f1)
    if [ -n "$pos" ]; then $IPT -I "$chain" "$pos" "$@"; else $IPT -A "$chain" "$@"; fi
    log "inserted $chain $*"
}
ensure_jump INPUT   UBIOS_INPUT_JUMP   -i $IFACE -j $IN
ensure_jump FORWARD UBIOS_FORWARD_JUMP -i $IFACE -j $IN
ensure_jump FORWARD UBIOS_FORWARD_JUMP -o $IFACE -j $OUT
