#!/bin/bash
#
# udm-dpinger-hijack.sh — keep UDM's informational dpinger probes off
# third-party anycast by redirecting them to NextDNS.
#
# The failover health probes are configured through UniFi's official WAN
# SLA ("NextDNS", /v2/api/site/default/wan-slas, assigned to WAN1 and
# WAN2), so they already target NextDNS. UDAPI still appends extra
# informational monitors per WAN that WAN SLA cannot change:
#
#   echo_server uptime monitor   -> 45.90.28.0 (set via usg by
#                                   udm-verifier-enforcer; no hijack needed)
#   www.microsoft.com  (icmp)    -> hijacked here
#   google.com         (icmp)    -> hijacked here
#   1.1.1.1            (icmp)    -> hijacked here
#
# Layers:
#
# (A) /etc/hosts override — ping.ui.com / www.microsoft.com / google.com
#     resolve to NextDNS (plus defensive AAAA) for UDM-local libc lookups,
#     so a dpinger respawned after a fresh resolve targets NextDNS directly.
#     Clients behind the gateway are unaffected (dnsmasq does not use
#     /etc/hosts for recursion).
#
# (B) Static iptables OUTPUT DNAT (UDM_DPINGER_HIJACK) — UDM-originated
#     1.1.1.1 / 8.8.8.8 (UDP:53 and ICMP) -> NextDNS A1 / A2.
#
# (C) Dynamic DNAT — IPs scraped from running dpinger argv (UDAPI caches
#     resolved addresses there) -> NextDNS A1, until a re-resolve picks up
#     (A). RFC1918 / loopback / link-local / 192.0.0.0 / 45.90.0.0 skipped.
#
# Idempotent — the UDM_DPINGER_HIJACK chain is flushed and rebuilt per run,
# OUTPUT hook is added only if missing, /etc/hosts block is maintained via
# BEGIN/END marker lines (strip-and-reinsert each run so content drift is
# always re-converged in one place). Run every 60s by the paired timer so
# UDAPI firewall rebuilds don't drop the chain for long.
#
# Memory: udm-pro-network-topology, udm-pro-dot-nextdns-policy.
#
set -uo pipefail

log() { logger -t udm-dpinger-hijack "$*"; }

LOCK=/run/udm-dpinger-hijack.lock
exec 9>"$LOCK"
flock -n 9 || { log "another udm-dpinger-hijack is running; skipping"; exit 0; }

# -------- Config --------

# NextDNS anycast endpoints — three classes for diversity:
NEXTDNS_A1_V4=45.90.28.74     # Account v4 — profile 21553f, anycast A1
NEXTDNS_A2_V4=45.90.30.74     # Account v4 — profile 21553f, anycast A2
NEXTDNS_G1_V4=45.90.28.0      # Global anycast G1 (unprofiled)
NEXTDNS_G2_V4=45.90.30.0      # Global anycast G2 (unprofiled)
NEXTDNS_A1_V6=2a07:a8c0::21:553f    # Account v6 — profile 21553f
NEXTDNS_A2_V6=2a07:a8c1::21:553f    # Account v6 — profile 21553f, pair

# Hardcoded UniFi dpinger IP targets to rewrite via iptables.
CF_V4=1.1.1.1
GOOG_V4=8.8.8.8

CHAIN=UDM_DPINGER_HIJACK
HOSTS_FILE=/etc/hosts
MARK_BEGIN="# BEGIN udm-dpinger-hijack (dotfiles)"
MARK_END="# END udm-dpinger-hijack"

# ============================================================================
# (A) /etc/hosts override — hostname-based probes resolve to NextDNS.
# ============================================================================
maintain_hosts() {
    local tmp block
    tmp=$(mktemp)

    # Preserve everything outside our marker block.
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
        $0 == b { skip=1; next }
        $0 == e { skip=0; next }
        !skip
    ' "$HOSTS_FILE" > "$tmp"

    # Our desired block.
    block=$(cat <<-EOF
	$MARK_BEGIN
	# Managed by udm-dpinger-hijack.sh — redirect UDAPI's default dpinger
	# probe hostnames to NextDNS. Clients behind the gateway are not
	# affected (they use dnsmasq, which bypasses /etc/hosts for recursion).
	# NextDNS Global anycast — primary icmp (sla/monitors eth10-{0,3} / ip6tnl2-{0,3})
	$NEXTDNS_G1_V4 ping.ui.com
	$NEXTDNS_G2_V4 ping.ui.com
	# NextDNS Account v4 (profile 21553f) — icmp (sla/monitors eth10-4 / ip6tnl2-4)
	$NEXTDNS_A1_V4 www.microsoft.com
	# NextDNS Account v4 (profile 21553f) — icmp (sla/monitors eth10-5 / ip6tnl2-5)
	$NEXTDNS_A2_V4 google.com
	# NextDNS Account v6 (profile 21553f) — AAAA records for the same probe hostnames,
	# defensive: dpinger on this UDM is v4-only today, but any v6-capable future
	# probe path (e.g., UniFi adding v6 health checks) picks up NextDNS v6 directly.
	$NEXTDNS_A1_V6 ping.ui.com www.microsoft.com
	$NEXTDNS_A2_V6 google.com
	$MARK_END
	EOF
	)

    printf '\n%s\n' "$block" >> "$tmp"

    if ! cmp -s "$tmp" "$HOSTS_FILE"; then
        install -m 0644 "$tmp" "$HOSTS_FILE"
        log "/etc/hosts udm-dpinger-hijack block updated"
    fi
    rm -f "$tmp"
}

maintain_hosts

# ============================================================================
# (B) v4 OUTPUT DNAT — raw-IP probes (1.1.1.1 / 8.8.8.8) to NextDNS.
# ============================================================================
iptables -t nat -N "$CHAIN" 2>/dev/null || true
iptables -t nat -F "$CHAIN"

# DNS probes (sla/monitors eth10-1, eth10-2, ip6tnl2-1, ip6tnl2-2):
# dpinger fires UDP:53 queries to CF/Google. Rewrite to NextDNS A1/A2.
# The query payload stays "resolve ui.com"; NextDNS answers normally.
iptables -t nat -A "$CHAIN" -p udp -d "$CF_V4"   --dport 53 -j DNAT --to-destination "$NEXTDNS_A1_V4"
iptables -t nat -A "$CHAIN" -p udp -d "$GOOG_V4" --dport 53 -j DNAT --to-destination "$NEXTDNS_A2_V4"

# ICMP probes (sla/monitors eth10-6, ip6tnl2-6, and the resolved IPs of
# ping.ui.com before (A) takes effect for already-running dpinger processes).
iptables -t nat -A "$CHAIN" -p icmp -d "$CF_V4"   -j DNAT --to-destination "$NEXTDNS_A1_V4"
iptables -t nat -A "$CHAIN" -p icmp -d "$GOOG_V4" -j DNAT --to-destination "$NEXTDNS_A2_V4"

# (C) Dynamic DNAT — scrape IPs out of currently-running dpinger processes
# and DNAT them to NextDNS. UDAPI resolves hostname probes (ping.ui.com,
# www.microsoft.com, google.com) ONCE at reconcile and bakes the resolved
# IPs into dpinger argv; respawning a killed dpinger reuses the same
# cached IPs. (A) only takes effect after UDAPI itself re-reconciles AND
# re-resolves — which doesn't happen on every udm-verifier-enforcer PUT
# (UniFi skips reconcile when the PUT is a no-op). This block bridges the
# gap: whatever IPs the current dpingers are probing get redirected to
# NextDNS until a reconcile finally picks up /etc/hosts. Scope is tight —
# only extracted from dpinger argv, skips RFC1918 and the two IPs already
# covered above.
DYNAMIC_IPS=$(ps -o args= -C dpinger 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -u)
for ip in $DYNAMIC_IPS; do
    case "$ip" in
        45.90.*|10.*|127.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|169.254.*|192.0.0.*) continue ;;
        "$CF_V4"|"$GOOG_V4") continue ;;  # already handled above
    esac
    iptables -t nat -A "$CHAIN" -p icmp -d "$ip" -j DNAT --to-destination "$NEXTDNS_A1_V4"
done

# A dpinger that started pinging a freshly resolved IP before the rule
# above existed keeps a conntrack entry that bypasses DNAT for as long as
# it keeps pinging. Drop only entries whose reply still comes from the
# original target (reply-src == dst means "never NATed"); entries already
# rewritten to NextDNS are left alone, so steady state has no churn.
for ip in $DYNAMIC_IPS; do
    case "$ip" in
        45.90.*|10.*|127.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|169.254.*|192.0.0.*) continue ;;
    esac
    for src in 10.0.1.2 192.0.0.3; do
        conntrack -D -p icmp -s "$src" -d "$ip" -r "$ip" >/dev/null 2>&1 \
            && log "dropped un-NATed conntrack $src -> $ip"
    done
done

iptables -t nat -C OUTPUT -j "$CHAIN" 2>/dev/null \
    || { iptables -t nat -I OUTPUT 1 -j "$CHAIN"; log "v4 OUTPUT hook added"; }

# ============================================================================
# v6 OUTPUT DNAT — reserved empty chain for symmetry / future use.
# ============================================================================
ip6tables -t nat -N "$CHAIN" 2>/dev/null || true
ip6tables -t nat -F "$CHAIN"
# No v6 dpinger probes exist on this UDM today; (A) covers v6 defensively.
ip6tables -t nat -C OUTPUT -j "$CHAIN" 2>/dev/null \
    || { ip6tables -t nat -I OUTPUT 1 -j "$CHAIN"; log "v6 OUTPUT hook added"; }
