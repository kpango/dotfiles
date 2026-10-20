#!/bin/bash
#
# udm-dpinger-hijack.sh — rewrite UDM-local dpinger probes to NextDNS.
#
# Background: UniFi Network Application 11.0.89 spawns 14 dpinger processes
# (7 per WAN) with hardcoded probe targets — ping.ui.com, 1.1.1.1 (dns+icmp),
# 8.8.8.8 (dns), google.com, www.microsoft.com. The sla/policies feature
# that would let the user override these (config.wan_sla + the WAN_SLA UI
# flag) is defined in the schema but not activated on this version: the
# UniFi API drops wan_connectivity_test_* fields silently, /rest/wan-sla*
# endpoints return InvalidObject/404, and direct Postgres INSERTs into
# config.wan_sla are ignored by UDAPI reconcile (verified 2026-10-20).
#
# The only path that actually works is UDM-local DNAT in the OUTPUT nat
# chain: when the kernel sees UDM originating a packet to 1.1.1.1 or 8.8.8.8
# (UDP:53 or ICMP), rewrite the destination to NextDNS before routing. The
# dpinger processes don't notice — they continue to think they're probing
# the hardcoded targets, but the actual packets reach NextDNS, so no
# third-party anycast ever learns our WAN addresses or RTT patterns from
# our health-check traffic. Monitors eth10-{0,1,2,6} and ip6tnl2-{0,1,2,6}
# (five of the seven per WAN, including all three that sla/policies uses
# for the failover decision) are covered.
#
# Monitors -4 (www.microsoft.com) and -5 (google.com) are left as-is: they
# resolve to Microsoft/Google content IPs (not DNS endpoints) that are too
# broad to DNAT safely, and they're informational — sla/policies does not
# use them for health decisions. Their leak is one ICMP packet per 10s per
# WAN, a trade-off we accept to avoid blanket-redirecting anything named
# www.microsoft.com or google.com from UDM-local processes.
#
# Idempotent — the UDM_DPINGER_HIJACK chain is flushed and rebuilt per run,
# OUTPUT hook is added only if missing. Run every 60s by the paired timer
# so UDAPI firewall rebuilds don't drop the chain for long.
#
# Memory: udm-pro-network-topology, udm-pro-dot-nextdns-policy.
#
set -uo pipefail

log() { logger -t udm-dpinger-hijack "$*"; }

LOCK=/run/udm-dpinger-hijack.lock
exec 9>"$LOCK"
flock -n 9 || { log "another udm-dpinger-hijack is running; skipping"; exit 0; }

# -------- Config --------

# NextDNS anycast endpoints — spread icmp vs dns across A1/A2 so a single
# NextDNS edge outage can't fail both health probes simultaneously.
NEXTDNS_A1_V4=45.90.28.74     # NextDNS profile 21553f, anycast A1
NEXTDNS_A2_V4=45.90.30.74     # NextDNS profile 21553f, anycast A2
NEXTDNS_G1_V4=45.90.28.0      # NextDNS Global anycast G1 (unprofiled)
NEXTDNS_A1_V6=2a07:a8c0::21:553f
NEXTDNS_A2_V6=2a07:a8c1::21:553f

# Hardcoded UniFi dpinger targets to rewrite. These are the IPs the UDAPI
# built-in SLA defaults aim at (we verified by inspecting running `ps aux`
# dpinger invocations and /data/udapi-config/udapi-net-cfg-*.json).
CF_V4=1.1.1.1
GOOG_V4=8.8.8.8

CHAIN=UDM_DPINGER_HIJACK

# -------- v4 OUTPUT DNAT (hijack UDM-local probes to NextDNS) --------

iptables -t nat -N "$CHAIN" 2>/dev/null || true
iptables -t nat -F "$CHAIN"

# DNS probes (sla/monitors eth10-1, eth10-2, ip6tnl2-1, ip6tnl2-2): dpinger
# fires UDP:53 queries to CF/Google. Rewrite to NextDNS A1/A2. We keep
# the Cloudflare/Google split by rewriting 1.1.1.1→A1 and 8.8.8.8→A2 so
# the two DNS probes continue to hit two independent anycast backends.
iptables -t nat -A "$CHAIN" -p udp -d "$CF_V4"   --dport 53 -j DNAT --to-destination "$NEXTDNS_A1_V4"
iptables -t nat -A "$CHAIN" -p udp -d "$GOOG_V4" --dport 53 -j DNAT --to-destination "$NEXTDNS_A2_V4"

# ICMP probes (sla/monitors eth10-0, eth10-3, eth10-6, ip6tnl2-0, -3, -6):
# dpinger pings the hostnames ping.ui.com / 1.1.1.1 (resolved to CF/Google
# anycast). Since ping.ui.com resolves to 1.1.1.1 and 8.8.8.8 (verified via
# `getent hosts ping.ui.com`), these ICMP probes also go to 1.1.1.1/8.8.8.8.
# A single ICMP DNAT per target covers all of them.
iptables -t nat -A "$CHAIN" -p icmp -d "$CF_V4"   -j DNAT --to-destination "$NEXTDNS_A1_V4"
iptables -t nat -A "$CHAIN" -p icmp -d "$GOOG_V4" -j DNAT --to-destination "$NEXTDNS_A2_V4"

iptables -t nat -C OUTPUT -j "$CHAIN" 2>/dev/null \
    || { iptables -t nat -I OUTPUT 1 -j "$CHAIN"; log "v4 OUTPUT hook added"; }

# -------- v6 OUTPUT DNAT --------
# UDM has no stable v6 UniFi default probe hostnames beyond ip6tnl2-* which
# we already v4-rewrite via the tunnel's inner v4 encap. Reserve an empty
# v6 chain for symmetry / future use so a later edit here is a one-liner.

ip6tables -t nat -N "$CHAIN" 2>/dev/null || true
ip6tables -t nat -F "$CHAIN"
# Example (uncomment if UniFi ever adds a v6 DNS probe to a known public IP):
# ip6tables -t nat -A "$CHAIN" -p udp -d 2606:4700:4700::1111 --dport 53 \
#     -j DNAT --to-destination "[$NEXTDNS_A1_V6]"
ip6tables -t nat -C OUTPUT -j "$CHAIN" 2>/dev/null \
    || { ip6tables -t nat -I OUTPUT 1 -j "$CHAIN"; log "v6 OUTPUT hook added"; }
