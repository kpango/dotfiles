#!/bin/bash
#
# install.sh — post-install hook for /data/nextdns-healthcheck (native systemd timer).
#
set -euo pipefail

D=/data/nextdns-healthcheck
chmod 0755 "$D/nextdns-healthcheck.sh"

changed=0
for u in "$D"/units/*; do
    dst=/etc/systemd/system/"$(basename "$u")"
    cmp -s "$u" "$dst" || { install -m 0644 "$u" "$dst"; changed=1; }
done
[ "$changed" = 1 ] && systemctl daemon-reload

rm -f /etc/cron.d/nextdns-healthcheck /data/nextdns-healthcheck.sh

systemctl enable --now nextdns-healthcheck.timer >/dev/null
systemctl is-active --quiet nextdns-healthcheck.timer \
    || { echo "FAIL: nextdns-healthcheck.timer not active" >&2; exit 1; }

echo "nextdns-healthcheck: timer active, legacy cron removed."
