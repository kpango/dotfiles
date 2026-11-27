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

"$D/sync.sh"

echo "nextdns-client-names: timer active, /etc/hosts.dnsmasq synced."
