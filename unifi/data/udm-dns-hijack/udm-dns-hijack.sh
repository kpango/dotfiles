#!/bin/bash
#
# udm-dns-hijack.sh — transparent :53 DNAT to UDM dnsmasq, DoH :443 block,
# and defensive repopulation of UniFi's DoT allowlist ipset. All of them
# narrow their scope so that direct talk to the NextDNS 21553f profile is
# NEVER touched — only non-NextDNS traffic is rerouted or dropped.
#
# Background: Google Nest / Chromecast / many other embedded devices ignore
# the DHCP-provided DNS server and hardcode a fallback DNS (typically
# 8.8.8.8 / 8.8.4.4). This script transparently rewrites those hardcoded
# queries to the LAN gateway, where UDM dnsmasq forwards them to NextDNS.
# The device never notices; the leak is closed. Direct :53 to the real
# NextDNS anycast endpoints is explicitly exempted from DNAT so devices
# that *do* configure NextDNS correctly keep their native path.
#
# A second rule set blocks TCP+UDP:443 (UDP = DoH over HTTP/3) to the
# DNS-dedicated v4/v6 addresses of the major non-NextDNS DoH providers (dns.google,
# cloudflare-dns.com, doh.opendns.com, dns.quad9.net, doh.cleanbrowsing.org,
# dns.adguard.com). The providers' content services use different IPs so
# the block is scoped to DoH only.
#
# A third rule set keeps UniFi's own UBIOS_policy_dst_dn_75 ipset populated
# with the four NextDNS IPs. The UniFi "DoT: allow NextDNS 21553f" policy
# uses that ipset as its match-set; if it is ever flushed empty (e.g. a
# ubios-udapi-server restart with no matching dnsmasq lookup to repopulate
# it) the ACCEPT rule stops firing and strict Private DNS clients surface
# "Private DNS に接続できません" errors. This script re-seeds it when missing.
#
# Diff-before-mutate fast-path + atomic iptables-restore (--noflush --wait=30)
# eliminates steady-state nat table replacements, ipset swaps, flush-empty gaps,
# and preserves cumulative rule packet counters.
#
# Run by udm-dns-hijack.{service,timer} every 60s and OnBoot. Also triggered
# by unifi-install.sh via udm-dns-hijack/install.sh.
#
# Memory: udm-pro-dot-nextdns-policy, udm-pro-network-topology.
#
set -uo pipefail

log() { logger -t udm-dns-hijack "$*"; }

LOCK=/run/udm-dns-hijack.lock
exec 9>"$LOCK"
flock -n 9 || { log "another udm-dns-hijack is running; skipping"; exit 0; }

# -------- Config --------

# LAN interfaces to hijack. Format: "iface gateway_v4 gateway_v6_or_NONE".
# gateway_v6 "NONE" skips v6 DNAT for that VLAN (IoT has ipv6_interface_type
# "none" by design — see memory udm-pro-network-topology).
VLANS=(
    "br0 10.0.0.1  240d:f:fc4:29f1::1"
    "br2 10.0.10.1 NONE"
    "br3 10.0.3.1  240d:f:fc4:29f2::1"
)

# NextDNS anycast endpoints to EXEMPT from DNAT. A client that opts in to
# NextDNS directly (e.g. by configuring 45.90.28.0 as its resolver) should
# reach NextDNS unmodified; redirecting to UDM dnsmasq would double-forward
# through NextDNS CLI for no benefit.
NEXTDNS_V4=(
    45.90.28.0  45.90.30.0            # NextDNS Global anycast
)
NEXTDNS_V6=(
    2a07:a8c0::21:553f 2a07:a8c1::21:553f    # profile 21553f IPv6 endpoints
)

# Tailscale exit-node traffic (UDM advertises 0.0.0.0/0 and ::/0).
# Split DNS queries explicitly addressed to UDM's tailscale0 IPs are exempted
# (! -d $TS_V4 / ! -d $TS_V6) so they hit UDM dnsmasq directly; rogue :53
# queries from exit-node clients (e.g. hardcoded 8.8.8.8:53) are DNATed to
# UDM's tailscale0 listener -> dnsmasq -> NextDNS CLI :5342.
TS_IFACE=tailscale0
TS_V4=$(ip -4 -o addr show dev "$TS_IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)
TS_V6=$(ip -6 -o addr show dev "$TS_IFACE" scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)

# NextDNS DoT endpoints — the IPs that dns.nextdns.io resolves to for the
# profile 21553f host. These feed UniFi's own UBIOS_policy_dst_dn_75 ipset
# (used by the "DoT: allow NextDNS 21553f" firewall rule), guaranteeing the
# ALLOW matches even when udapi-server restarts flush the ipset and no
# client happens to resolve the base domain to re-populate it.
NEXTDNS_DOT_V4=(103.170.232.254 167.179.109.118)
NEXTDNS_DOT_V6=(2a0b:4341:b02:166:5054:ff:fe53:ab1 2001:19f0:7001:5e19:5400:2ff:fec8:7b5a)

# DoH server IP addresses to block on :443. These are DNS-dedicated anycast
# endpoints; blocking :443 to them does not affect the providers' content
# hosting on separate IP ranges (e.g. google.com and youtube.com do not
# resolve to 8.8.8.8). Keep this list conservative — adding a general-
# purpose Cloudflare content IP would break every site behind it.
DOH_IPS=(
    8.8.8.8 8.8.4.4                                 # dns.google
    1.1.1.1 1.0.0.1                                 # cloudflare-dns.com (primary pair only)
    9.9.9.9 149.112.112.112                         # dns.quad9.net
    208.67.222.222 208.67.220.220                   # doh.opendns.com
    94.140.14.14 94.140.15.15                       # dns.adguard.com
)
DOH_IPS_V6=(
    2001:4860:4860::8888 2001:4860:4860::8844       # dns.google
    2606:4700:4700::1111 2606:4700:4700::1001       # cloudflare-dns.com
    2620:fe::fe 2620:fe::9                          # dns.quad9.net
    2620:119:35::35 2620:119:53::53                 # doh.opendns.com
    2a10:50c0::ad1:ff 2a10:50c0::ad2:ff             # dns.adguard.com
)

CHAIN=UDM_DNS_HIJACK            # name reused in both nat tables (independent ns)
OUT_CHAIN=UDM_DNS_HIJACK_OUT    # UDM-local OUTPUT :53 redirect to local dnsmasq/NextDNS CLI
DOH_SET=UDM_DOH_BLOCK
DOH_SET_V6=UDM_DOH_BLOCK6
NEXTDNS_SET_V4=UDM_NEXTDNS_V4
NEXTDNS_SET_V6=UDM_NEXTDNS_V6

# -------- NextDNS / DoH ipsets (diff-first, atomic swap on drift) --------
rebuild_set() {
    local family=$1 setname=$2
    shift 2
    local expected current new="${setname}_new"
    expected=$(printf '%s\n' "$@" | sort)
    if current=$(ipset list "$setname" 2>/dev/null); then
        current=$(printf '%s\n' "$current" | awk '/^Members:/{f=1;next} f && NF{print $1}' | sort)
        if [ "$current" = "$expected" ]; then
            return 0
        fi
    fi

    ipset create "$new" "hash:ip" family "$family" -exist
    ipset flush "$new"
    for ip in "$@"; do
        ipset add "$new" "$ip"
    done
    if ipset list -n "$setname" >/dev/null 2>&1; then
        ipset swap "$new" "$setname"
        ipset destroy "$new"
    else
        ipset rename "$new" "$setname"
    fi
    log "rebuilt ipset $setname"
}

sync_nat_chain() {
    local ipt=$1 restore=$2 chain=$3 rules=$4
    local expected current
    expected="-N $chain
$rules"
    current=$($ipt -w 30 -t nat -S "$chain" 2>/dev/null || true)
    if [ "$current" = "$expected" ]; then
        return 0
    fi
    $restore --noflush --wait=30 <<EOF
*nat
:$chain - [0:0]
-F $chain
$rules
COMMIT
EOF
    log "rebuilt $ipt nat $chain"
}

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

ensure_jump_once() {  # ensure_jump_once <ipt> <table> <chain> <pat> <log_msg> <rule...>
    local ipt=$1 table=$2 chain=$3 pat=$4 msg=$5; shift 5
    local dump count
    dump=$($ipt -w 30 -t "$table" -S "$chain" 2>/dev/null || true)
    count=$(printf '%s\n' "$dump" | grep -c -- "$pat" || true)
    if [ "$count" = "1" ]; then
        return 0
    fi
    if [ "$count" = "0" ]; then
        $ipt -w 30 -t "$table" -I "$chain" 1 "$@"
        log "$msg"
        return 0
    fi
    dedupe "$ipt" "$table" "$chain" "$pat" "$@"
}

rebuild_set inet  "$NEXTDNS_SET_V4" "${NEXTDNS_V4[@]}"
rebuild_set inet6 "$NEXTDNS_SET_V6" "${NEXTDNS_V6[@]}"

# -------- :53 DNAT (v4) --------
V4_RULES=""
for row in "${VLANS[@]}"; do
    read -r iface gw4 _ <<<"$row"
    for proto in udp tcp; do
        V4_RULES+="-A $CHAIN ! -d ${gw4}/32 -i $iface -p $proto -m $proto --dport 53 -m set ! --match-set $NEXTDNS_SET_V4 dst -j DNAT --to-destination $gw4:53
"
    done
done
if [ -n "$TS_V4" ]; then
    for proto in udp tcp; do
        V4_RULES+="-A $CHAIN ! -d ${TS_V4}/32 -i $TS_IFACE -p $proto -m $proto --dport 53 -m set ! --match-set $NEXTDNS_SET_V4 dst -j DNAT --to-destination $TS_V4:53
"
    done
fi
sync_nat_chain iptables iptables-restore "$CHAIN" "${V4_RULES%$'\n'}"
ensure_jump_once iptables nat PREROUTING "-j $CHAIN$" "v4 PREROUTING hook added" -j "$CHAIN"

# -------- :53 DNAT (v6) --------
V6_RULES=""
for row in "${VLANS[@]}"; do
    read -r iface _ gw6 <<<"$row"
    [ "$gw6" = "NONE" ] && continue
    for proto in udp tcp; do
        V6_RULES+="-A $CHAIN ! -d ${gw6}/128 -i $iface -p $proto -m $proto --dport 53 -m set ! --match-set $NEXTDNS_SET_V6 dst -j DNAT --to-destination [$gw6]:53
"
    done
done
if [ -n "$TS_V6" ]; then
    for proto in udp tcp; do
        V6_RULES+="-A $CHAIN ! -d ${TS_V6}/128 -i $TS_IFACE -p $proto -m $proto --dport 53 -m set ! --match-set $NEXTDNS_SET_V6 dst -j DNAT --to-destination [$TS_V6]:53
"
    done
fi
sync_nat_chain ip6tables ip6tables-restore "$CHAIN" "${V6_RULES%$'\n'}"
ensure_jump_once ip6tables nat PREROUTING "-j $CHAIN$" "v6 PREROUTING hook added" -j "$CHAIN"

# -------- DoH :443 ipsets (diff-first, atomic swap) + FORWARD DROP --------
# udp too: DoH over HTTP/3 (QUIC) to the same IPs bypassed a tcp-only DROP.
rebuild_set inet  "$DOH_SET"    "${DOH_IPS[@]}"
rebuild_set inet6 "$DOH_SET_V6" "${DOH_IPS_V6[@]}"
for pair in "iptables $DOH_SET" "ip6tables $DOH_SET_V6"; do
    read -r ipt set <<<"$pair"
    fwd_dump=$($ipt -w 30 -S FORWARD 2>/dev/null || true)
    for proto in tcp udp; do
        pat="-p $proto .*--match-set $set dst -j DROP"
        count=$(printf '%s\n' "$fwd_dump" | grep -c -- "$pat" || true)
        if [ "$count" = "1" ]; then
            continue
        elif [ "$count" = "0" ]; then
            $ipt -w 30 -I FORWARD 1 -p "$proto" --dport 443 -m set --match-set "$set" dst -j DROP
            log "DoH FORWARD DROP rule added ($ipt $proto)"
        else
            dedupe "$ipt" filter FORWARD "$pat" -p "$proto" --dport 443 -m set --match-set "$set" dst -j DROP
        fi
    done
done

# -------- UDM-local OUTPUT :53 redirect (blocks 1.1.1.1/8.8.8.8/etc. from UDM itself) --------
# IPv6 DNATs directly to NextDNS profile 21553f ([2a07:a8c0::21:553f]:53) because
# local dnsmasq/REDIRECT over lo drops global-src -> ::1 / lo packets due to bind-to-device.
OUT_V4_RULES=""
for proto in udp tcp; do
    OUT_V4_RULES+="-A $OUT_CHAIN -p $proto -m $proto --dport 53 -m set --match-set $DOH_SET dst -j REDIRECT --to-ports 53
"
done
sync_nat_chain iptables iptables-restore "$OUT_CHAIN" "${OUT_V4_RULES%$'\n'}"
ensure_jump_once iptables nat OUTPUT "-j $OUT_CHAIN$" "iptables OUTPUT hook added ($OUT_CHAIN)" -j "$OUT_CHAIN"

OUT_V6_RULES=""
for proto in udp tcp; do
    OUT_V6_RULES+="-A $OUT_CHAIN -p $proto -m $proto --dport 53 -m set --match-set $DOH_SET_V6 dst -j DNAT --to-destination [2a07:a8c0::21:553f]:53
"
done
sync_nat_chain ip6tables ip6tables-restore "$OUT_CHAIN" "${OUT_V6_RULES%$'\n'}"
ensure_jump_once ip6tables nat OUTPUT "-j $OUT_CHAIN$" "ip6tables OUTPUT hook added ($OUT_CHAIN)" -j "$OUT_CHAIN"

# -------- Defensive UBIOS NextDNS DoT ipset repopulation --------
for s in UBIOS4policy_dst_dn_75; do
    cur=$(ipset list "$s" 2>/dev/null) || continue
    for ip in "${NEXTDNS_DOT_V4[@]}"; do
        printf '%s\n' "$cur" | grep -qx -- "$ip" || ipset add "$s" "$ip" -exist
    done
done
for s in UBIOS6policy_dst_dn_75; do
    cur=$(ipset list "$s" 2>/dev/null) || continue
    for ip in "${NEXTDNS_DOT_V6[@]}"; do
        printf '%s\n' "$cur" | grep -qx -- "$ip" || ipset add "$s" "$ip" -exist
    done
done
