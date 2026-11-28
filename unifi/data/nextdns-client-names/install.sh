#!/bin/bash
#
# install.sh — post-install hook for /data/nextdns-client-names.
#
set -euo pipefail

D=/data/nextdns-client-names
chmod 0755 "$D/sync.sh"

changed=0
for u in nextdns-client-names.service nextdns-client-names.timer; do
    src="$D/$u"
    dst="/etc/systemd/system/$u"
    cmp -s "$src" "$dst" || { install -m 0644 "$src" "$dst"; changed=1; }
done
[ "$changed" = 1 ] && systemctl daemon-reload

systemctl enable --now nextdns-client-names.timer >/dev/null
systemctl is-active --quiet nextdns-client-names.timer \
    || { echo "FAIL: nextdns-client-names.timer not active" >&2; exit 1; }

K=""
for kf in /data/unifi-api.key /data/nextdns-client-names/api-key; do
    if [ -s "$kf" ]; then
        K=$(tr -d '[:space:]' < "$kf")
        [ -n "$K" ] && break
    fi
done

if [ -z "$K" ]; then
    echo "nextdns-client-names: /data/unifi-api.key not provisioned — skipping initial sync."
elif curl -sfk -m 5 -H "X-API-KEY: $K" -H "Accept: application/json" https://127.0.0.1/proxy/network/integration/v1/sites | jq -er '.data[0].id' >/dev/null 2>&1; then
    systemctl start nextdns-client-names.service
    echo "nextdns-client-names: timer active, /etc/hosts.dnsmasq synced."
else
    echo "nextdns-client-names: timer active, UniFi API still starting (sync deferred to timer)."
fi
