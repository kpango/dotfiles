#!/bin/bash
#
# udm-dpinger-hijack.sh — rewrite UDM-local dpinger probes to NextDNS.
# All 14 default sla/monitors (7 per WAN) end up pointing at NextDNS, spread
# across three target classes: Global anycast, Account v4 (profile 21553f),
# and Account v6 (defensive AAAA records for any future v6 probe).
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
# Two layers of hijack combine to redirect every default probe to NextDNS:
#
# (A) /etc/hosts override — forces UDAPI's getaddrinfo() of the hardcoded
#     probe hostnames to return NextDNS IPs, so when UDAPI respawns dpinger
#     on reconcile the processes bake NextDNS addresses into their argv.
#
#       ping.ui.com         -> NextDNS Global 1 + 2 (45.90.28.0, 45.90.30.0)
#       www.microsoft.com   -> NextDNS Account A1 (45.90.28.74)
#       google.com          -> NextDNS Account A2 (45.90.30.74)
#       All three           -> NextDNS v6 (2a07:a8c0::21:553f /
#                                          2a07:a8c1::21:553f)
#
#     Scope note: /etc/hosts is read by libc getaddrinfo on this UDM, so
#     any UDM-local process resolving these three names (including dpinger
#     and anything else UniFi runs for its own purposes) sees the NextDNS
#     IP. Clients behind the gateway are unaffected — their DNS goes
#     through dnsmasq, which does not consult /etc/hosts for recursive
#     lookups. The three overridden hostnames have no other legitimate
#     UDM-local consumer we are aware of (verified: no UDM services or
#     cron jobs reference them on this box).
#
# (B) iptables OUTPUT nat (UDM_DPINGER_HIJACK chain) — rewrites any
#     already-resolved IP targets (sla/monitors eth10-{1,2,6} and
#     ip6tnl2-{1,2,6} have 1.1.1.1 / 8.8.8.8 as raw IPs in the UDAPI
#     defaults). Keeps the host-override and IP-override paths independent
#     so the five IP-targeted monitors are safe even if /etc/hosts is
#     wiped (firmware update, UDAPI regenerating the file, etc.).
#
#       1.1.1.1 UDP:53 -> NextDNS Account A1 (45.90.28.74)
#       8.8.8.8 UDP:53 -> NextDNS Account A2 (45.90.30.74)
#       1.1.1.1 ICMP   -> NextDNS Account A1
#       8.8.8.8 ICMP   -> NextDNS Account A2
#
# Combined coverage of the 14 default monitors:
#
#   id            type   original target     effective destination
#   ──────────────────────────────────────────────────────────────
#   eth10-0       icmp   ping.ui.com         NextDNS Global 1 / 2 (A)
#   eth10-1       dns    1.1.1.1             NextDNS Account A1   (B)*
#   eth10-2       dns    8.8.8.8             NextDNS Account A2   (B)*
#   eth10-3       icmp   ping.ui.com         NextDNS Global 1 / 2 (A)
#   eth10-4       icmp   www.microsoft.com   NextDNS Account A1   (A)
#   eth10-5       icmp   google.com          NextDNS Account A2   (A)
#   eth10-6       icmp   1.1.1.1             NextDNS Account A1   (B)
#   ip6tnl2-{0..6}  (same mapping, same NextDNS targets)
#
#   * -1 and -2 remain type=dns because dpinger's probe type is set in the
#     UDAPI config (not editable in this UniFi version). The query payload
#     stays "please resolve ui.com for me", but the recipient is NextDNS
#     (via iptables DNAT), not Cloudflare / Google. NextDNS responds to
#     those DNS queries normally so the probe stays healthy, and the leak
#     to third-party anycast is closed.
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
