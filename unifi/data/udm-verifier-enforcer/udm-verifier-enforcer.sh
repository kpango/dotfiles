#!/bin/bash
#
# udm-verifier-enforcer.sh — re-apply NextDNS values to every UniFi API
# field related to WAN connectivity testing / probe targets. Runs hourly
# so a UI operation that reverts them never persists longer than ~1 h.
#
# Companion to udm-dpinger-hijack: that one DNATs the actual outbound
# dpinger packets to NextDNS. This script keeps the UniFi *configuration*
# honest at the API layer so (a) any field UniFi 11.0.89 silently drops
# today lands correctly if a future version activates the WAN_SLA feature
# flag, and (b) the informational monitor-3 (which /rest/setting/usg
# echo_server does drive) stays on NextDNS even after a UI edit.
#
# Fields re-applied:
#
# /rest/setting/usg:
#   echo_server                  → 45.90.28.0  (NextDNS Global anycast; drives
#                                  sla/monitors eth10-3 / ip6tnl2-3)
#   dns_verification.setting_preference → "manual"
#   dns_verification.primary_dns_server   → 45.90.28.74 (NextDNS A1)
#   dns_verification.secondary_dns_server → 45.90.30.74 (NextDNS A2)
#   dns_verification.domain      → "dns.nextdns.io"
#
# /rest/networkconf/<NURO_ID> and /<BBE_ID>:
#   wan_connectivity_test_target        → 45.90.28.74
#   wan_connectivity_test_targetv6      → 2a07:a8c0::21:553f
#   wan_connectivity_test_mode          → "custom"
#   wan_internet_connectivity_test      → "custom"
#   wan_ping_ip                         → 45.90.28.74
#   wan_ping_ipv6                       → 2a07:a8c0::21:553f
#
#   These six fields are *silently dropped* by UniFi Network 11.0.89 — the
#   PUT returns 200 OK but a re-GET shows them still null. Verified by
#   round-trip test 2026-10-20. We send them anyway because (i) they are
#   referenced in the UniFi JS bundle (WAN_SLA UI feature) and (ii) a UI
#   or firmware upgrade may activate the server-side route; shipping the
#   write defensively costs nothing and makes future rollout automatic.
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
NX_A1_V6=2a07:a8c0::21:553f

# WAN network_conf _id values (stable UUIDs; written once by UniFi on
# WAN creation and never regenerated).
NURO_ID=224daefb-4bd7-4a8a-8c4e-ba5ad2edc876
BBE_ID=718d4304-a385-48be-94e3-323f22570ef4

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

# ----------------------------------------------------------------------
# /rest/networkconf/<id> — defensive. These wan_connectivity_test_*
# fields silent-drop on 11.0.89 but ship them so future UniFi versions
# honor them without a dotfiles edit.
# ----------------------------------------------------------------------
NC_BODY=$(cat <<EOF
{
  "wan_connectivity_test_target": "$NX_A1_V4",
  "wan_connectivity_test_targetv6": "$NX_A1_V6",
  "wan_connectivity_test_mode": "custom",
  "wan_internet_connectivity_test": "custom",
  "wan_ping_ip": "$NX_A1_V4",
  "wan_ping_ipv6": "$NX_A1_V6"
}
EOF
)
for id in "$NURO_ID" "$BBE_ID"; do
    code=$(put_json "$API_BASE/rest/networkconf/$id" "$NC_BODY")
    log "PUT /rest/networkconf/$id → HTTP $code (fields may silent-drop on 11.0.89)"
done
