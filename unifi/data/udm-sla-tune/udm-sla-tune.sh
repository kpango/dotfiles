#!/bin/bash
#
# udm-sla-tune.sh — override UDM's per-WAN downstream dnsmasq resolver so
# every DNS query that originates from a WAN2-routed path stays inside the
# NextDNS 21553f profile.
#
# Scope was wider originally — the script also used to patch
# /data/udapi-config/ubios-udapi-server/ubios-udapi-server.state's
# sla/monitors[].target to swap the hardcoded ping.ui.com / 1.1.1.1 /
# 8.8.8.8 / google.com / www.microsoft.com default probes to NextDNS.
# That half was retired on 2026-10-20: without SIGHUP (which caused a
# WAN/WiFi cascade — see memory udm-pro-dot-nextdns-policy) UDAPI never
# re-reads the state file for sla/monitors, so the patch stuck on disk
# but never influenced the running dpinger processes. We verified by
# comparing patched state file vs `ps auxww` dpinger invocations vs
# UniFi API `uptime_stats` — the three disagreed. UniFi's own custom-
# SLA mechanism (config.wan_sla table + wan_sla UUID link in
# config.network_conf.dynamic_part) is defined in the Postgres schema
# but the WAN_SLA feature flag is not activated on 11.0.89, so direct
# INSERTs are ignored by UDAPI reconcile. The effective replacement is
# unifi/data/udm-dpinger-hijack (iptables OUTPUT DNAT catching the
# UDM-local probes to 1.1.1.1 / 8.8.8.8 before they leave the box).
#
# This script now has only one job:
#
#   /run/resolv.conf.d/ip6tnl2 — UniFi ships it with `nameserver 1.1.1.1`
#   (Cloudflare) even when the WAN2 networkconf has NextDNS set, so UDM
#   leaks DNS queries outside NextDNS whenever name resolution flows via
#   the DS-Lite tunnel. We rewrite it to NextDNS and SIGHUP only the
#   per-tunnel dnsmasq (not udapi-server) so the fix lands without the
#   restart cascade.
#
# Idempotent. Run by udm-sla-tune.{service,timer} every 60s and OnBoot.
# Also triggered by unifi-install.sh via udm-sla-tune/install.sh.
#
# Memory: udm-pro-dslite-aftr-manual, udm-pro-dot-nextdns-policy.
#
set -uo pipefail

RESOLV=/run/resolv.conf.d/ip6tnl2
LOCK=/run/udm-sla-tune.lock

# NextDNS endpoints. .74 encodes the Linked IP for profile 21553f; both
# resolve to Tokyo PoP (~3ms via NURO, ~6ms via BB.excite DS-Lite).
NX_A1=45.90.28.74   # profile 21553f, anycast A
NX_A2=45.90.30.74   # profile 21553f, anycast B

log() { logger -t udm-sla-tune "$*"; }

exec 9>"$LOCK"
flock -n 9 || { log "another udm-sla-tune is running; skipping"; exit 0; }

# ============================================================================
# /run/resolv.conf.d/ip6tnl2 drift repair
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

patch_resolv
