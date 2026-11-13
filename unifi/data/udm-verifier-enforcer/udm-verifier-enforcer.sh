#!/bin/bash
#
# udm-verifier-enforcer.sh — hourly re-apply of the UniFi "usg" echo_server,
# which drives UDAPI's uptime-report probe, so a UI edit never leaves it off
# NextDNS for longer than ~1 h.
#
# The failover health probes themselves are configured through UniFi's
# official WAN SLA ("NextDNS", /v2/api/site/default/wan-slas, assigned to
# WAN1 and WAN2) and need no enforcement here. What WAN SLA does not
# control is the extra uptime-report monitor that UDAPI appends per WAN;
# its target comes from /rest/setting/usg echo_server.
#
# Field re-applied on /rest/setting/usg:
#   echo_server → 45.90.28.0 (NextDNS Global)
#
# (Until 2026-10-20 this also set usg dns_verification — unused once the
# WAN SLA replaced the DNS-type probes — and PUT wan_connectivity_test_* /
# wan_ping_* to /rest/networkconf, which UniFi 11.0.89 silently drops.)
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

NX_G1_V4=45.90.28.0   # NextDNS Global anycast

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

code=$(put_json "$API_BASE/rest/setting/usg" "{\"echo_server\": \"$NX_G1_V4\"}")
log "PUT /rest/setting/usg → HTTP $code"
