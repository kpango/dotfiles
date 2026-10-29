#!/bin/bash
#
# install.sh — post-install hook for /data/udm-dns-hijack.
#
set -euo pipefail

D=/data/udm-dns-hijack
chmod 0755 "$D/udm-dns-hijack.sh"

changed=0
for u in "$D"/units/*; do
    dst=/etc/systemd/system/"$(basename "$u")"
    cmp -s "$u" "$dst" || { install -m 0644 "$u" "$dst"; changed=1; }
done
[ "$changed" = 1 ] && systemctl daemon-reload

systemctl enable --now udm-dns-hijack.timer >/dev/null
systemctl is-active --quiet udm-dns-hijack.timer \
    || { echo "FAIL: udm-dns-hijack.timer not active" >&2; exit 1; }

systemctl start udm-dns-hijack.service

echo "udm-dns-hijack: timer active, :53 DNAT + DoH block applied."
