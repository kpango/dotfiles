#!/bin/bash
#
# udm-mape-fallback — keep WAN2 MAP-E (JPIX) up when the provisioning server
# is unreachable (CONTEXT.md Q41).
#
# Why: stock ubnt-hb46pp builds ip6tnl2 + MAP_E-POSTROUTING only from a fresh
# api.enabler.ne.jp fetch, resolved through eth8's DNS. That DNS is NextDNS
# (audit: "both WAN dns1/2 + v6 dns = NextDNS"), whose answer for the host never completes TLS; only the
# NGN DNS answer works. hb46pp keeps the tunnel when a later fetch fails, but
# after a reboot it has nothing, so WAN2 stayed down (2026-11-04).
#
# What (1 min after boot, then every 5 min):
#   always   pin api.enabler.ne.jp to the NGN DNS answer in /etc/hosts.
#   healthy  (tunnel has a remote and the SNAT chain exists): save the
#            parameters hb46pp last applied (/run/hb46pp/eth8.json) to $SAVED.
#   broken   (hb46pp still running for map_e_jpix, uptime > 5 min, saved CE
#            address still inside eth8's current /64): hand the saved
#            parameters to udapi the same way hb46pp does
#            (ubios-udapi-client internal /interfaces/hb46pp-update), then drop
#            un-NATed conntrack entries. A later successful fetch overwrites it.
#
# Usage: udm-mape-fallback.sh            (timer)
#        udm-mape-fallback.sh --check    read-only; exit 0 healthy, 1 broken
set -euo pipefail

D=/data/udm-mape-fallback
SAVED=$D/ip6tnl-parameters
IF=eth8
TUN=ip6tnl2
JSON=/run/hb46pp/$IF.json
# Provisioning host of map_e_jpix (hb46pp default TXT record).
PIN_HOSTS=api.enabler.ne.jp
MODE=${1:-run}
case "$MODE" in run|--check) ;; *) echo "usage: $0 [--check]" >&2; exit 64 ;; esac

log() { logger -t udm-mape-fallback "$*"; printf '%s\n' "$*"; }

# Capture first: with pipefail, grep -q exiting early would SIGPIPE the producer.
healthy() {
    local link nat
    link=$(ip -d link show "$TUN" 2>/dev/null) || return 1
    nat=$(iptables -w 30 -t nat -S MAP_E-POSTROUTING 2>/dev/null) || return 1
    grep -q ' remote [0-9a-f]*:' <<<"$link" && grep -q -- "-o $TUN .*-j SNAT" <<<"$nat"
}
# "CE -> BR, IPv4" for log lines.
summary() { awk -F'|' '{split($5, v, ":"); print $2 " -> " $3 ", " v[1]}' <<<"$1"; }

# hb46pp resolves through /run/resolv.conf.d/eth8, which is NextDNS-only, and
# NextDNS answers api.enabler.ne.jp with endpoints that never complete TLS.
# Pin the NGN DNS answer (the servers udapi lists as "# disabled") in a marked
# /etc/hosts block; hb46pp's resolver reads files before dns. Re-done every
# run because udapi rewrites /etc/hosts.
pin_hosts() {
    local ngn a block="" cur
    ngn=$(sed -n 's/^# disabled \([0-9a-f]*:[0-9a-f:]*\)$/\1/p;T;q' "/run/resolv.conf.d/$IF")
    [ -n "$ngn" ] || { log "no NGN DNS server in /run/resolv.conf.d/$IF — hosts pin skipped"; return 0; }
    for h in $PIN_HOSTS; do
        for a in $(dig +short +time=3 +tries=2 "@$ngn" AAAA "$h" | grep -E '^[0-9a-f:]+$' || true); do
            block+="$a $h"$'\n'
        done
    done
    [ -n "$block" ] || { log "NGN DNS $ngn gave no AAAA for $PIN_HOSTS — hosts pin kept as is"; return 0; }
    block=$(sort <<<"${block%$'\n'}")$'\n'   # DNS rotates the order
    cur=$(sed -n '/^# udm-mape-fallback begin$/,/^# udm-mape-fallback end$/p' /etc/hosts | sed '1d;$d')
    [ "$cur"$'\n' = "$block" ] && return 0
    { sed '/^# udm-mape-fallback begin$/,/^# udm-mape-fallback end$/d' /etc/hosts
      printf '# udm-mape-fallback begin\n%s# udm-mape-fallback end\n' "$block"; } > /etc/hosts.mape.tmp
    cat /etc/hosts.mape.tmp > /etc/hosts && rm -f /etc/hosts.mape.tmp
    log "pinned via NGN DNS: $(tr '\n' ' ' <<<"$block")"
}
[ "$MODE" = run ] && pin_hosts

if healthy; then
    [ "$MODE" = --check ] && exit 0
    p=$(jq -r '.ip6tnl_parameters // empty' "$JSON" 2>/dev/null || true)
    if [[ $p == map-e\|* ]] && ! [ "$p" = "$(cat "$SAVED" 2>/dev/null)" ]; then
        printf '%s\n' "$p" > "$SAVED.tmp" && mv "$SAVED.tmp" "$SAVED"
        log "saved MAP-E parameters: $(summary "$p")"
    fi
    exit 0
fi

[ "$MODE" = --check ] && { echo "$TUN has no MAP-E tunnel/SNAT"; exit 1; }

pgrep -f "^/bin/bash -s map_e_jpix $IF\$" >/dev/null \
    || { log "hb46pp not running for map_e_jpix on $IF (WAN2 not MAP-E?) — nothing to do"; exit 0; }
up=$(cut -d. -f1 /proc/uptime)
[ "$up" -ge 300 ] || { log "uptime ${up}s — leaving the first fetch to hb46pp"; exit 0; }
[ -s "$SAVED" ] || { log "$TUN down and no saved parameters"; exit 1; }

p=$(cat "$SAVED")
[[ $p =~ ^map-e\|[0-9a-f:]+\|[0-9a-f:]+\|\|[0-9.]+:[0-9,-]+$ ]] \
    || { log "saved parameters malformed — not applied"; exit 1; }
ce=$(cut -d'|' -f2 <<<"$p")
# The rule is only valid for the prefix it was issued for.
ADDRS=$(ip -6 -o addr show dev "$IF" scope global | awk '{print $4}' | cut -d/ -f1)
python3 - "$ce" $ADDRS <<'EOF' || { log "eth8 prefix no longer matches saved CE $ce — not applied"; exit 1; }
import ipaddress, sys
ce = ipaddress.IPv6Interface(sys.argv[1] + "/64").network
sys.exit(0 if any(a != sys.argv[1] and ipaddress.IPv6Address(a) in ce for a in sys.argv[2:]) else 1)
EOF

mkdir -p /run/hb46pp
jq -nc --arg i "$IF" --arg p "$p" \
    '{interface:$i, capability:"map_e_jpix", ip6tnl_parameters:$p, provisioning_data:{}}' > "$JSON"
ubios-udapi-client internal /interfaces/hb46pp-update "@$JSON" >/dev/null
sleep 10
conntrack -D -q 192.0.0.3 >/dev/null 2>&1 || true
if healthy; then
    log "hb46pp has no tunnel — applied saved MAP-E parameters ($(summary "$p"))"
else
    log "applied saved MAP-E parameters but $TUN is still not up"; exit 1
fi
