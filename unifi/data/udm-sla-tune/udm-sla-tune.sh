#!/bin/bash
#
# udm-sla-tune.sh — enforce NextDNS-only consistency across all drift surfaces
# that UniFi (ubios-udapi-server) regenerates for the WAN monitoring path.
#
# Background: UniFi 11.0.89 ships a dpinger DS-Lite DNS-probe bug ("Misformatted
# DNS reply") that marks the DS-Lite WAN bad on healthy links. Combined with the
# default monitorHealthThreshold=50, two simultaneous DNS flaps alone trip a
# failover event. UniFi also leaves /run/resolv.conf.d/ip6tnl2 pointing at the
# vendor-default 1.1.1.1 even when the WAN2 networkconf has NextDNS set, so UDM
# itself leaks DNS queries outside the NextDNS profile when routed via WAN2.
# On top of that, the default sla/monitors use ping.ui.com / www.microsoft.com /
# google.com / 1.1.1.1 / 8.8.8.8 as probe targets — all third-party endpoints
# that violate the "every DNS/health probe stays inside NextDNS" invariant.
#
# This script enforces three deviations from UniFi defaults, applied in order:
#
#   A) sla state tune (patch state file + SIGHUP udapi-server):
#       - every eth10-N and ip6tnl2-N (N = 0..6) monitor is set to the NextDNS
#         endpoint on the row below, with type=icmp (so no DNS parse bug ever
#         fires), rotating between two profile-linked IPs (profile 21553f) and
#         two NextDNS Global anycast IPs for path diversity:
#           N=0 -> 45.90.28.0   (NextDNS Global #1)
#           N=1 -> 45.90.28.74  (NextDNS profile 21553f #1)
#           N=2 -> 45.90.30.74  (NextDNS profile 21553f #2)
#           N=3 -> 45.90.30.0   (NextDNS Global #2)
#           N=4 -> 45.90.28.74  (profile #1 again, display-only coverage)
#           N=5 -> 45.90.30.74  (profile #2 again, display-only coverage)
#           N=6 -> 45.90.28.0   (Global #1 again)
#       - sla/policies wfg-0 (eth10)   monitorHealthThreshold 50 -> 30
#       - sla/policies wfg-1 (ip6tnl2) monitorHealthThreshold 50 -> 30
#
#   B) ip6tnl2 upstream dnsmasq resolv (patch + SIGHUP dnsmasq-ip6tnl2):
#       /run/resolv.conf.d/ip6tnl2  nameserver 1.1.1.1 -> NextDNS v4 (both)
#
# Both sections are idempotent and run independently: if (A) is already correct
# we skip udapi SIGHUP; if (B) is already correct we skip dnsmasq SIGHUP.
#
# Run by udm-sla-tune.{service,timer} every 60s and OnBoot. Also triggered by
# unifi-install.sh via udm-sla-tune/install.sh.
#
# Memory: udm-pro-dslite-aftr-manual, udm-pro-dot-nextdns-policy.
#
set -uo pipefail

STATE=/data/udapi-config/ubios-udapi-server/ubios-udapi-server.state
RESOLV=/run/resolv.conf.d/ip6tnl2
LOCK=/run/udm-sla-tune.lock

# NextDNS endpoints. .74 encodes the Linked IP for profile 21553f; .0 is the
# vanilla Global anycast endpoint. Both respond to ICMP, both are routed from
# JP via NextDNS's Tokyo PoP (~3ms via NURO, ~6ms via BB.excite DS-Lite).
NX_A1=45.90.28.74   # profile 21553f, anycast A
NX_A2=45.90.30.74   # profile 21553f, anycast B
NX_G1=45.90.28.0    # NextDNS Global, anycast A
NX_G2=45.90.30.0    # NextDNS Global, anycast B

# monitor-index -> desired target. Keep aligned with the header comment above.
declare -A WANT=(
    [0]=$NX_G1  [1]=$NX_A1  [2]=$NX_A2  [3]=$NX_G2
    [4]=$NX_A1  [5]=$NX_A2  [6]=$NX_G1
)

want_threshold=30

log() { logger -t udm-sla-tune "$*"; }

# Serialize concurrent timer+boot invocations so we don't SIGHUP twice.
exec 9>"$LOCK"
flock -n 9 || { log "another udm-sla-tune is running; skipping"; exit 0; }

# ============================================================================
# (A) sla/monitors + sla/policies state patch
# ============================================================================
patch_state() {
    [ -r "$STATE" ] || { log "state file missing: $STATE"; return 0; }

    # Build the per-monitor target map as a jq object so a single jq call does
    # the whole patch — cheaper than per-field loops and keeps the write atomic.
    local map
    map=$(jq -nc --arg a1 "$NX_A1" --arg a2 "$NX_A2" \
                 --arg g1 "$NX_G1" --arg g2 "$NX_G2" '
        {
            "eth10-0":   $g1, "eth10-1":   $a1, "eth10-2":   $a2, "eth10-3":   $g2,
            "eth10-4":   $a1, "eth10-5":   $a2, "eth10-6":   $g1,
            "ip6tnl2-0": $g1, "ip6tnl2-1": $a1, "ip6tnl2-2": $a2, "ip6tnl2-3": $g2,
            "ip6tnl2-4": $a1, "ip6tnl2-5": $a2, "ip6tnl2-6": $g1
        }
    ')

    # Check for drift. We treat any monitor whose target != desired OR whose
    # type != "icmp" as drifted, as well as wfg-0/wfg-1 threshold mismatches.
    local drifted
    drifted=$(jq -r --argjson map "$map" --argjson th "$want_threshold" '
        [
            (."sla/monitors".monitors[]? |
                select($map[.id]) |
                select(.target != $map[.id] or .type != "icmp") | .id),
            (."sla/policies".policies[]? |
                select(.id == "wfg-0" or .id == "wfg-1") |
                select(.probes[0].monitorHealthThreshold != $th) | .id)
        ] | join(",")
    ' "$STATE")

    [ -z "$drifted" ] && return 0

    log "state drift: $drifted"

    local tmp
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' RETURN

    if ! jq --argjson map "$map" --argjson th "$want_threshold" '
        ."sla/monitors".monitors |= map(
            if $map[.id] then
                .target = $map[.id] | .type = "icmp" | .domain = null
            else .
            end
        ) |
        ."sla/policies".policies |= map(
            if .id == "wfg-0" or .id == "wfg-1" then
                .probes |= map(.monitorHealthThreshold = $th)
            else .
            end
        )
    ' "$STATE" > "$tmp"; then
        log "state jq patch failed; keeping original"
        return 1
    fi

    # Sanity: patched file must parse and still contain all the identifiers
    # we expect to be governing. Guards against a jq regression or a truncated
    # write silently losing a monitor.
    local have_mon have_pol need
    have_mon=$(jq -c '."sla/monitors".monitors | map(.id)' "$tmp")
    have_pol=$(jq -c '."sla/policies".policies | map(.id)' "$tmp")
    need=$(jq -nc --argjson map "$map" '$map | keys')
    if ! jq -ne --argjson need "$need" --argjson have "$have_mon" \
                --argjson pol "$have_pol" '
        ($need - $have | length == 0) and
        ($pol | contains(["wfg-0", "wfg-1"]))
    ' >/dev/null; then
        log "patched state failed sanity check; keeping original"
        return 1
    fi

    cp "$STATE" "$STATE.pre-sla-tune" 2>/dev/null || true
    install -m 0644 "$tmp" "$STATE"
    log "state file patched"

    # SIGHUP intentionally omitted.
    #
    # ubios-udapi-server's SIGHUP handler is a *full restart*: it tears down
    # Suricata, UTM/DPI, wan-failover, redirector, arp-inspection and client
    # isolation, then re-plays the full state. The whole cycle takes ~30 s,
    # during which every per-domain ipset (including UBIOS_policy_dst_dn_75,
    # which allows DoT to NextDNS) is flushed and only re-populated when a
    # client happens to resolve the exact base domain again. Strict Private
    # DNS clients (Android "{device}-21553f.dns.nextdns.io", iOS equivalents)
    # fail during that window and surface "Private DNS に接続できません", and
    # several Android devices then churn DHCP waiting for the network to look
    # healthy again. The 2026-10-20 incident captured in the trajectory log
    # is exactly this.
    #
    # The state file edit is still worth doing: udapi-server will apply it
    # on the next natural reconcile (any UniFi UI change, boot, etc.). dpinger
    # will converge on the NextDNS targets then. The lag is acceptable; the
    # outage avoided is not.
}

# ============================================================================
# (B) /run/resolv.conf.d/ip6tnl2 drift repair
# ============================================================================
patch_resolv() {
    [ -w "$(dirname "$RESOLV")" ] || return 0  # /run not mounted yet, skip

    # Desired content. Keep the "static" header so a human reading the file
    # knows the override is intentional, not vendor-generated.
    local want
    want=$(cat <<-EOF
	# Managed by udm-sla-tune.sh (dotfiles) — overrides udapi-server default
	# that pins ip6tnl2 to 1.1.1.1, which leaks DNS queries outside NextDNS.
	# static nameservers
	nameserver $NX_A1
	nameserver $NX_A2
	EOF
	)

    if [ -r "$RESOLV" ] && [ "$(cat "$RESOLV")" = "$want" ]; then
        return 0
    fi

    log "resolv drift: $RESOLV not NextDNS; rewriting"
    printf '%s\n' "$want" > "$RESOLV"

    # Nudge the per-WAN dnsmasq instance so it re-reads immediately. Without
    # SIGHUP it waits until its next poll (~60s).
    local pid
    pid=$(pgrep -of "dnsmasq.*--resolv-file=$RESOLV" || true)
    if [ -n "$pid" ]; then
        kill -HUP "$pid" && log "SIGHUP sent to dnsmasq-ip6tnl2 pid=$pid"
    fi
}

patch_state
patch_resolv
