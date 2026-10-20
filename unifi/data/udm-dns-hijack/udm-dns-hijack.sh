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
# A second rule set blocks TCP:443 to the ten DNS-dedicated IP addresses
# used by the major non-NextDNS DoH providers (dns.google,
# cloudflare-dns.com, doh.opendns.com, dns.quad9.net, doh.cleanbrowsing.org,
# dns.adguard.com). The providers' content services use different IPs so
# the block is scoped to DoH only.
#
# A third rule set keeps UniFi's own UBIOS_policy_dst_dn_75 ipset populated
# with the four NextDNS IPs. The UniFi "DoT: allow NextDNS 21553f" policy
# uses that ipset as its match-set; if it is ever flushed empty (e.g. a
# ubios-udapi-server restart with no matching dnsmasq lookup to repopulate
# it) the ACCEPT rule stops firing and strict Private DNS clients surface
# "Private DNS に接続できません" errors. This script re-seeds it every tick.
#
# Idempotent and ~1 ms transient — the :53 DNAT chain is flushed and rebuilt
# per run; the DoH ipset is atomically swapped. Clients retry DNS on first
# packet loss, so the gap is invisible in practice.
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
# NextDNS directly (e.g. by configuring 45.90.28.74 as its resolver) should
# reach NextDNS unmodified; redirecting to UDM dnsmasq would double-forward
# through the same NextDNS CLI for no benefit.
NEXTDNS_V4=(
    45.90.28.74 45.90.30.74          # profile 21553f linked IPs
    45.90.28.0  45.90.30.0            # NextDNS Global anycast
)
NEXTDNS_V6=(
    2a07:a8c0::21:553f 2a07:a8c1::21:553f    # profile 21553f IPv6 endpoints
)

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

CHAIN=UDM_DNS_HIJACK            # name reused in both nat tables (independent ns)
DOH_SET=UDM_DOH_BLOCK
NEXTDNS_SET_V4=UDM_NEXTDNS_V4
NEXTDNS_SET_V6=UDM_NEXTDNS_V6

# -------- NextDNS exemption ipsets (idempotent, atomic swap) --------
rebuild_set() {
    local family=$1 setname=$2
    shift 2
    local new="${setname}_new"
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
}

rebuild_set inet  "$NEXTDNS_SET_V4" "${NEXTDNS_V4[@]}"
rebuild_set inet6 "$NEXTDNS_SET_V6" "${NEXTDNS_V6[@]}"

# -------- :53 DNAT (v4) --------
iptables -t nat -N "$CHAIN" 2>/dev/null || true
iptables -t nat -F "$CHAIN"
for row in "${VLANS[@]}"; do
    read -r iface gw4 _ <<<"$row"
    for proto in udp tcp; do
        iptables -t nat -A "$CHAIN" -i "$iface" -p "$proto" --dport 53 \
            ! -d "$gw4" \
            -m set ! --match-set "$NEXTDNS_SET_V4" dst \
            -j DNAT --to-destination "$gw4:53"
    done
done
iptables -t nat -C PREROUTING -j "$CHAIN" 2>/dev/null \
    || { iptables -t nat -I PREROUTING 1 -j "$CHAIN"; log "v4 PREROUTING hook added"; }

# -------- :53 DNAT (v6) --------
ip6tables -t nat -N "$CHAIN" 2>/dev/null || true
ip6tables -t nat -F "$CHAIN"
for row in "${VLANS[@]}"; do
    read -r iface _ gw6 <<<"$row"
    [ "$gw6" = "NONE" ] && continue
    for proto in udp tcp; do
        ip6tables -t nat -A "$CHAIN" -i "$iface" -p "$proto" --dport 53 \
            ! -d "$gw6" \
            -m set ! --match-set "$NEXTDNS_SET_V6" dst \
            -j DNAT --to-destination "[$gw6]:53"
    done
done
ip6tables -t nat -C PREROUTING -j "$CHAIN" 2>/dev/null \
    || { ip6tables -t nat -I PREROUTING 1 -j "$CHAIN"; log "v6 PREROUTING hook added"; }

# -------- DoH :443 ipset (atomic swap) + FORWARD DROP --------
rebuild_set inet "$DOH_SET" "${DOH_IPS[@]}"
if ! iptables -C FORWARD -p tcp --dport 443 -m set --match-set "$DOH_SET" dst -j DROP 2>/dev/null; then
    iptables -I FORWARD 1 -p tcp --dport 443 -m set --match-set "$DOH_SET" dst -j DROP
    log "DoH FORWARD DROP rule added"
fi

# -------- Defensive UBIOS NextDNS DoT ipset repopulation --------
# UniFi's "DoT: allow NextDNS 21553f" firewall rule matches destinations
# in UBIOS_policy_dst_dn_75. That ipset is populated by dnsmasq *only when a
# client resolves the exact base domain* (21553f.dns.nextdns.io); device-
# specific Private DNS hostnames (pixel-21553f.dns.nextdns.io, etc.) do not
# trigger population. If a ubios-udapi-server restart flushes the ipset and
# no base-domain resolution happens afterward, the ALLOW rule stops firing,
# the subsequent "non-NextDNS :853 DROP" rule swallows every DoT attempt,
# and strict Private DNS clients surface "Private DNS に接続できません".
#
# This re-seed is a safety net. The primary fix lives in udm-sla-tune.sh
# (removed its SIGHUP, so UBIOS restarts no longer happen on our tick).
for s in UBIOS4policy_dst_dn_75; do
    ipset list -n "$s" >/dev/null 2>&1 || continue
    for ip in "${NEXTDNS_DOT_V4[@]}"; do
        ipset add "$s" "$ip" -exist
    done
done
for s in UBIOS6policy_dst_dn_75; do
    ipset list -n "$s" >/dev/null 2>&1 || continue
    for ip in "${NEXTDNS_DOT_V6[@]}"; do
        ipset add "$s" "$ip" -exist
    done
done
