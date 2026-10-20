#!/bin/bash
#
# udm-sla-tune.sh — rewrite UDAPI's sla/monitors state so UniFi UI's
# Overview > WAN detail panel shows NextDNS targets instead of the vendor
# defaults (ping.ui.com, 1.1.1.1, 8.8.8.8, www.microsoft.com, google.com).
#
# Scope split from udm-dpinger-hijack:
#
#   udm-dpinger-hijack  → rewrites the actual packets at the kernel
#                         (iptables OUTPUT nat + /etc/hosts). Independent
#                         of what UniFi UI shows.
#
#   udm-sla-tune (THIS) → rewrites the UDAPI state files that /stat/health
#                         reads from. Only affects what the UI DISPLAYS.
#                         No packet effect. The two layers are deliberately
#                         decoupled: packet hijack can keep working even
#                         if the display patch drifts (and vice versa).
#
# Why this script was partially retired on 2026-10-20 AM and then
# un-retired PM: the first revision patched sla/monitors in the state file
# and SIGHUP'd ubios-udapi-server to force a re-read. SIGHUP is a *full
# restart* that tears down Suricata/UTM/UBIOS ipsets for ~30 s — the
# UBIOS_policy_dst_dn_75 flush that happens inside that window drops
# strict Private DNS clients (Android {device}-21553f.dns.nextdns.io)
# and surfaces "Private DNS に接続できません". We removed SIGHUP and left
# the state patch, which worked for the display view (UDAPI's state file
# IS the display source — verified by diffing `/stat/health` uptime_stats
# vs the patched state file). Our 60 s timer keeps it converged across
# UDAPI's own occasional natural reconciles.
#
# Patches applied (all idempotent):
#
# A1) sla/monitors[].target  — one NextDNS IP per monitor, spread across
#       Global (G1/G2) and Account (A1/A2) anycast classes:
#
#         eth10-0   / ip6tnl2-0  →  45.90.28.0   (Global 1)
#         eth10-1   / ip6tnl2-1  →  45.90.28.74  (Account A1)
#         eth10-2   / ip6tnl2-2  →  45.90.30.74  (Account A2)
#         eth10-3   / ip6tnl2-3  →  45.90.30.0   (Global 2)
#         eth10-4   / ip6tnl2-4  →  45.90.28.74  (Account A1)
#         eth10-5   / ip6tnl2-5  →  45.90.30.74  (Account A2)
#         eth10-6   / ip6tnl2-6  →  45.90.28.0   (Global 1)
#
#       All v4. Account v6 (2a07:a8c0::21:553f / 2a07:a8c1::21:553f) is NOT
#       used as a target here: UDAPI's dpinger invocations bind the v4
#       interface src (-B 10.0.1.2 for eth10, -B 192.0.0.3 for ip6tnl2
#       inner), so a v6 target would fail to bind on respawn and the
#       monitor would go unhealthy. v6 lives in /etc/hosts (AAAA records
#       managed by udm-dpinger-hijack) as a defensive future-proof entry.
#
# A2) sla/monitors[].type = "icmp" + .domain = null for every monitor.
#       The vendor defaults have .type = "dns" / .domain = "ui.com" on
#       monitors -1 and -2, which drives dpinger to send actual DNS queries
#       (not ICMP echo) at the probe target. The user asked for all probes
#       to be ICMP — making it so in the UI DISPLAY is a one-field flip.
#       The actual dpinger process type is baked in at UDAPI config time
#       (not editable without SIGHUP) so until the next natural reconcile
#       the -1 / -2 dpingers keep sending DNS; udm-dpinger-hijack's
#       OUTPUT DNAT redirects them to NextDNS so the DNS traffic doesn't
#       leak either. Alignment of actual-type to displayed-type is paid
#       for on UDAPI's own schedule, not ours.
#
# A3) sla/policies.policies[].probes[].monitorHealthThreshold = 30 on
#       wfg-0 and wfg-1. UniFi defaults 50; 30 fails sooner on genuine
#       degradation (dpinger loss% threshold within an availability
#       window), which pairs well with the stricter wan_sla policy we
#       want for a dual-WAN NURO + BB.excite setup.
#
# B)  /run/resolv.conf.d/ip6tnl2 — UniFi ships `nameserver 1.1.1.1`
#       (Cloudflare) on the DS-Lite tunnel even when the WAN2 networkconf
#       has NextDNS set, so UDM itself leaks DNS queries whenever name
#       resolution flows via the tunnel. We rewrite it to NextDNS and
#       SIGHUP the per-tunnel dnsmasq (safe — only touches that dnsmasq
#       instance, nothing like the udapi-server cascade).
#
# Patches land in both /data/udapi-config/ubios-udapi-server/ubios-udapi-server.state
# AND the newest /data/udapi-config/udapi-net-cfg-*.json. UDAPI appears to
# use the net-cfg as its own source-of-truth when it regenerates the state
# file, so patching only one of the two lets the other drift it back on
# reconcile. Both.
#
# Idempotent. Run by udm-sla-tune.{service,timer} every 60 s and OnBoot.
# Also triggered by unifi-install.sh via udm-sla-tune/install.sh.
#
# Memory: udm-pro-dslite-aftr-manual, udm-pro-dot-nextdns-policy,
#         udm-pro-out-of-band-customizations.
#
set -uo pipefail

STATE=/data/udapi-config/ubios-udapi-server/ubios-udapi-server.state
NETCFG_DIR=/data/udapi-config
RESOLV=/run/resolv.conf.d/ip6tnl2
LOCK=/run/udm-sla-tune.lock

NX_A1=45.90.28.74   # NextDNS Account A1 (profile 21553f)
NX_A2=45.90.30.74   # NextDNS Account A2 (profile 21553f)
NX_G1=45.90.28.0    # NextDNS Global anycast G1
NX_G2=45.90.30.0    # NextDNS Global anycast G2

WANT_THRESHOLD=30

log() { logger -t udm-sla-tune "$*"; }

exec 9>"$LOCK"
flock -n 9 || { log "another udm-sla-tune is running; skipping"; exit 0; }

# ============================================================================
# (A) sla/monitors + sla/policies patch — patches state file AND net-cfg.
# ============================================================================
STATE_CHANGED=0

patch_sla_file() {
    local path=$1
    [ -r "$path" ] || return 0
    [ -w "$path" ] || return 0

    # One jq pass that:
    #   - rewrites each sla/monitors[i].target to the mapped NextDNS IP
    #   - forces type = "icmp", domain = null
    #   - sets monitorHealthThreshold on both WAN failover group policies
    local tmp
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' RETURN

    if ! jq --arg a1 "$NX_A1" --arg a2 "$NX_A2" \
            --arg g1 "$NX_G1" --arg g2 "$NX_G2" \
            --argjson th "$WANT_THRESHOLD" '
        (. as $root
         | ($root
            | ."sla/monitors".monitors |= map(
                . as $m
                | .target = (
                    if   $m.id | endswith("-0") then $g1
                    elif $m.id | endswith("-1") then $a1
                    elif $m.id | endswith("-2") then $a2
                    elif $m.id | endswith("-3") then $g2
                    elif $m.id | endswith("-4") then $a1
                    elif $m.id | endswith("-5") then $a2
                    elif $m.id | endswith("-6") then $g1
                    else .target
                    end)
                | .type = "icmp"
                | .domain = null
              )
            | ."sla/policies".policies |= map(
                if (.id == "wfg-0" or .id == "wfg-1") then
                    .probes |= map(.monitorHealthThreshold = $th)
                else . end
              )
           )
        )
    ' "$path" > "$tmp"; then
        log "jq patch failed on $path; keeping original"
        return 1
    fi

    # Sanity: patched file must still parse and contain all expected ids.
    if ! jq -e '
        (."sla/monitors".monitors | map(.id)
            | contains(["eth10-0","eth10-1","eth10-2","eth10-3",
                        "eth10-4","eth10-5","eth10-6",
                        "ip6tnl2-0","ip6tnl2-1","ip6tnl2-2","ip6tnl2-3",
                        "ip6tnl2-4","ip6tnl2-5","ip6tnl2-6"])) and
        (."sla/policies".policies | map(.id) | contains(["wfg-0","wfg-1"]))
    ' "$tmp" >/dev/null 2>&1; then
        log "patched $path failed sanity check; keeping original"
        return 1
    fi

    if cmp -s "$tmp" "$path"; then
        return 0
    fi

    # Preserve ownership + mode of the original.
    install -m 0644 "$tmp" "$path"
    log "patched $path"
    if [ "$path" = "$STATE" ]; then
        STATE_CHANGED=1
    fi
}

patch_sla_file "$STATE"

# Patch EVERY net-cfg file so whichever hash UDAPI picks up on next cycle
# already carries our values. (UDAPI occasionally rotates between them.)
for nc in "$NETCFG_DIR"/udapi-net-cfg-*.json; do
    [ -f "$nc" ] && patch_sla_file "$nc"
done

# ============================================================================
# (B) /run/resolv.conf.d/ip6tnl2 drift repair.
# ============================================================================
patch_resolv() {
    [ -w "$(dirname "$RESOLV")" ] || return 0

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

    # Nudge the per-WAN dnsmasq instance only. Safe — scoped to one process.
    local pid
    pid=$(pgrep -of "dnsmasq.*--resolv-file=$RESOLV" || true)
    if [ -n "$pid" ]; then
        kill -HUP "$pid" && log "SIGHUP sent to dnsmasq-ip6tnl2 pid=$pid"
    fi
}

patch_resolv

# ============================================================================
# Conditional SIGHUP — only if the state file actually drifted.
# ============================================================================
# UDAPI serves /stat/health (what UniFi UI Overview displays) from its in-
# memory state, populated at startup / SIGHUP by re-reading the state file.
# A state-file edit without SIGHUP persists on disk but is invisible to the
# UI until something else triggers UDAPI to re-read.
#
# We only SIGHUP when STATE_CHANGED=1, i.e., this invocation actually
# rewrote $STATE because UDAPI had drifted it back to defaults (natural
# reconcile after a UniFi UI change, a firmware config write, etc.). In
# steady state the file matches our desired patch, no bytes change, no
# SIGHUP fires, no cascade. SIGHUP frequency ends up tied to UDAPI's own
# natural reconcile cadence — typically 0 or 1 per hour on this box.
#
# SIGHUP cost: UDAPI full-restart tears down Suricata, UTM/DPI, wan-
# failover, the UBIOS_policy_dst_dn_75 ipset etc. and plays them back
# over ~15–30 s. The DoT allowlist flush breaks strict Private DNS
# clients ("Private DNS に接続できません") during that window.
#
# Mitigation: before raising SIGHUP, force a dnsmasq resolution of the
# base NextDNS DoT domain (which repopulates UBIOS_policy_dst_dn_75 via
# dnsmasq's ipset= directive) and then re-run udm-dns-hijack right
# after so its defensive hardcoded re-seed lands within one second
# instead of waiting up to 60 s for the paired timer. Combined, the
# Private DNS window closes to a few seconds at most.
if [ "$STATE_CHANGED" = "1" ]; then
    log "state file was drifted; preparing UDAPI SIGHUP"

    # (1) Pre-populate UBIOS DoT ipset by making dnsmasq resolve the
    # NextDNS DoT base domain. The ipset= directive in dnsmasq config
    # auto-adds resolved addresses to UBIOS_policy_dst_dn_75.
    nslookup 21553f.dns.nextdns.io 127.0.0.1 >/dev/null 2>&1 || true

    # (2) SIGHUP.
    udapi_pid=$(pgrep -f "/usr/bin/ubios-udapi-server" | head -1 || true)
    if [ -n "$udapi_pid" ]; then
        kill -HUP "$udapi_pid" && log "SIGHUP sent to ubios-udapi-server pid=$udapi_pid"
    else
        log "could not find ubios-udapi-server PID; skipping SIGHUP"
    fi

    # (3) Immediately re-run udm-dns-hijack to hardcode-seed the ipset
    # before any strict Private DNS client probes it.
    [ -x /data/udm-dns-hijack/udm-dns-hijack.sh ] \
        && /data/udm-dns-hijack/udm-dns-hijack.sh >/dev/null 2>&1 || true
fi
