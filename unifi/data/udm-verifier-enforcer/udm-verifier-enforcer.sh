#!/bin/bash
#
# udm-verifier-enforcer.sh — hourly re-apply of the UniFi "usg" setting
# fields that drive UDAPI's uptime-report probe, so a UI edit never leaves
# it off NextDNS for longer than ~1 h.
#
# The failover health probes themselves are configured through UniFi's
# official WAN SLA ("NextDNS", /v2/api/site/default/wan-slas, assigned to
# WAN1 and WAN2) and need no enforcement here. What WAN SLA does not
# control is the extra uptime-report monitor that UDAPI appends per WAN;
# its target comes from /rest/setting/usg echo_server.
#
# Fields re-applied on /rest/setting/usg:
#   echo_server                           → 45.90.28.0  (NextDNS Global)
#   dns_verification.setting_preference   → "manual"
#   dns_verification.primary_dns_server   → 45.90.28.74 (NextDNS A1)
#   dns_verification.secondary_dns_server → 45.90.30.74 (NextDNS A2)
#   dns_verification.domain               → "dns.nextdns.io"
#
# (Until 2026-10-20 this also PUT wan_connectivity_test_* / wan_ping_* to
# /rest/networkconf; UniFi 11.0.89 silently drops those, so it was removed.)
#
# API key is read from /data/nextdns-client-names/api-key (shared with
# nextdns-client-names.service; already provisioned at 0600 root). If
# the file is missing (fresh install before someone runs
#   pass show unifi-api | ssh udmpro 'cat > /data/nextdns-client-names/api-key'
# ) the script logs and exits 0 — no retries, no failures that could
# gate the timer unit.
#
# Memory: udm-pro-out-of-band-customizations, udm-pro-dot-nextdns-policy.
#
set -uo pipefail

API_KEY_FILE=/data/nextdns-client-names/api-key
API_BASE=https://127.0.0.1/proxy/network/api/s/default
LOCK=/run/udm-verifier-enforcer.lock

# NextDNS endpoints — pair the Verifier primary/secondary with the two
# profile-linked anycast IPs so a NextDNS edge outage can't flap both.
NX_A1_V4=45.90.28.74
NX_A2_V4=45.90.30.74
NX_G1_V4=45.90.28.0

log() { logger -t udm-verifier-enforcer "$*"; }

exec 9>"$LOCK"
flock -n 9 || { log "another udm-verifier-enforcer is running; skipping"; exit 0; }

if [ ! -r "$API_KEY_FILE" ]; then
    log "api key missing ($API_KEY_FILE); re-provision via pass show unifi-api"
    exit 0
fi
API_KEY=$(head -1 "$API_KEY_FILE" | tr -d '[:space:]')
if [ -z "$API_KEY" ]; then
    log "api key file empty"
    exit 0
fi

# Simple PUT helper. curl -k because the UDM self-signed cert is scoped
# to the LAN hostname, not 127.0.0.1. --fail is intentionally omitted so
# a transient non-200 (e.g., UDAPI reload) is logged, not retried.
put_json() {
    local url=$1 body=$2
    local code
    code=$(curl -ksSo /dev/null -w "%{http_code}" \
                -X PUT \
                -H "X-API-KEY: $API_KEY" \
                -H "Content-Type: application/json" \
                -d "$body" "$url")
    echo "$code"
}

# ----------------------------------------------------------------------
# /rest/setting/usg — the echo_server field DOES land and drives
# sla/monitors eth10-3 / ip6tnl2-3 (uptime report). dns_verification
# fields are accepted at the API layer; whether UDAPI uses them in
# this version is unclear but setting them cleans up the API view.
# ----------------------------------------------------------------------
USG_BODY=$(cat <<EOF
{
  "echo_server": "$NX_G1_V4",
  "dns_verification": {
    "setting_preference": "manual",
    "primary_dns_server": "$NX_A1_V4",
    "secondary_dns_server": "$NX_A2_V4",
    "domain": "dns.nextdns.io"
  }
}
EOF
)
code=$(put_json "$API_BASE/rest/setting/usg" "$USG_BODY")
log "PUT /rest/setting/usg → HTTP $code"
