#!/bin/bash
#
# udm-verifier-enforcer.sh — hourly re-apply of the UniFi "usg" echo_server
# and dns_verification (replacing legacy 1.1.1.1 / 8.8.8.8 defaults with
# NextDNS Global Anycast 45.90.28.0 / 45.90.30.0), so a UI edit never leaves
# them off NextDNS for longer than ~1 h.
#
# The failover health probes themselves are configured through UniFi's
# official WAN SLA ("NextDNS", /v2/api/site/default/wan-slas, assigned to
# WAN1 and WAN2) and need no enforcement here. What WAN SLA does not
# control is the extra uptime-report monitor that UDAPI appends per WAN;
# its target comes from /rest/setting/usg echo_server.
#
# Fields re-applied on /rest/setting/usg:
#   echo_server      → 45.90.28.0 (NextDNS Global)
#   dns_verification → manual: 45.90.28.0 / 45.90.30.0 (no 1.1.1.1 / 8.8.8.8)
#
# API key is read from /data/unifi-api.key (or legacy /data/nextdns-client-names/api-key;
# provisioned at 0600 root). If the file is missing (fresh install before someone runs
#   pass show unifi-api | ssh udmpro 'install -m 600 /dev/stdin /data/unifi-api.key'
# ) the script logs and exits 0 — no retries, no failures that could
# gate the timer unit.
#
# Memory: udm-pro-out-of-band-customizations, udm-pro-dot-nextdns-policy.
#
set -uo pipefail

if [ -r /data/unifi-api.key ]; then
    API_KEY_FILE=/data/unifi-api.key
else
    API_KEY_FILE=/data/nextdns-client-names/api-key
fi
API_BASE=https://127.0.0.1/proxy/network/api/s/default
LOCK=/run/udm-verifier-enforcer.lock

NX_G1_V4=45.90.28.0   # NextDNS Global anycast primary
NX_G2_V4=45.90.30.0   # NextDNS Global anycast secondary

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

payload=$(cat <<EOF
{
  "echo_server": "$NX_G1_V4",
  "dns_verification": {
    "domain": "ui.com",
    "primary_dns_server": "$NX_G1_V4",
    "secondary_dns_server": "$NX_G2_V4",
    "setting_preference": "manual"
  }
}
EOF
)
code=$(put_json "$API_BASE/rest/setting/usg" "$payload")
log "PUT /rest/setting/usg → HTTP $code"
