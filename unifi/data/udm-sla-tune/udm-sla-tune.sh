#!/bin/bash
#
# udm-sla-tune.sh — keep UDM's DS-Lite tunnel resolver on NextDNS.
#
# UniFi ships /run/resolv.conf.d/ip6tnl2 with `nameserver 1.1.1.1`
# (Cloudflare) even when the WAN2 networkconf has NextDNS set, so UDM
# itself leaks DNS queries whenever name resolution flows via the DS-Lite
# tunnel. We rewrite it to NextDNS and SIGHUP only the per-tunnel dnsmasq
# (scoped to that one process — not ubios-udapi-server).
#
# History: this script used to also patch sla/monitors + sla/policies in
# the UDAPI state file and SIGHUP ubios-udapi-server so the WAN health
# probes pointed at NextDNS. That is now done by UniFi's own WAN SLA
# feature (Settings > Internet > WAN SLA "WAN Requirement", assigned to WAN1 and
# WAN2 — API: /proxy/network/v2/api/site/default/wan-slas). The state
# patch was retired on 2026-10-20 because it would fight the
# controller-provisioned SLA monitors and needed a full udapi-server
# restart to take effect.
#
# Idempotent. Run by udm-sla-tune.{service,timer} every 60 s and OnBoot.
# Also triggered by unifi-install.sh via udm-sla-tune/install.sh.
#
# Memory: udm-pro-dslite-aftr-manual, udm-pro-out-of-band-customizations.
#
set -uo pipefail

RESOLV=/run/resolv.conf.d/ip6tnl2
LOCK=/run/udm-sla-tune.lock

NX_A1=45.90.28.74   # NextDNS Account A1 (profile 21553f)
NX_A2=45.90.30.74   # NextDNS Account A2 (profile 21553f)

log() { logger -t udm-sla-tune "$*"; }

exec 9>"$LOCK"
flock -n 9 || { log "another udm-sla-tune is running; skipping"; exit 0; }

[ -w "$(dirname "$RESOLV")" ] || exit 0  # /run not mounted yet

want=$(cat <<-EOF
	# Managed by udm-sla-tune.sh (dotfiles) — overrides udapi-server default
	# that pins ip6tnl2 to 1.1.1.1, which leaks DNS queries outside NextDNS.
	# static nameservers
	nameserver $NX_A1
	nameserver $NX_A2
	EOF
)

if [ -r "$RESOLV" ] && [ "$(cat "$RESOLV")" = "$want" ]; then
    exit 0
fi

log "resolv drift: $RESOLV not NextDNS; rewriting"
printf '%s\n' "$want" > "$RESOLV"

# Nudge the per-WAN dnsmasq instance so it re-reads immediately.
pid=$(pgrep -of "dnsmasq.*--resolv-file=$RESOLV" || true)
if [ -n "$pid" ]; then
    kill -HUP "$pid" && log "SIGHUP sent to dnsmasq-ip6tnl2 pid=$pid"
fi
