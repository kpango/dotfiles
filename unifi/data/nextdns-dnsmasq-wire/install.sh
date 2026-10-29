#!/bin/bash
#
# install.sh — post-install hook for /data/nextdns-dnsmasq-wire.
#
set -euo pipefail

D=/data/nextdns-dnsmasq-wire
chmod 0755 "$D/check.sh"

changed=0
for u in "$D"/units/*; do
    dst=/etc/systemd/system/"$(basename "$u")"
    cmp -s "$u" "$dst" || { install -m 0644 "$u" "$dst"; changed=1; }
done
[ "$changed" = 1 ] && systemctl daemon-reload

systemctl enable --now nextdns-dnsmasq-wire.path >/dev/null
systemctl is-active --quiet nextdns-dnsmasq-wire.path \
    || { echo "FAIL: nextdns-dnsmasq-wire.path not active" >&2; exit 1; }

systemctl start nextdns-dnsmasq-wire.service

echo "nextdns-dnsmasq-wire: path unit active, dnsmasq wired to NextDNS CLI."
