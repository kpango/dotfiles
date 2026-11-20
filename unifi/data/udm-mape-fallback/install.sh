#!/bin/bash
#
# install.sh — post-install hook for /data/udm-mape-fallback (CONTEXT.md Q41).
# Units live here because /etc/systemd/system is reset by firmware updates.
#
set -euo pipefail

D=/data/udm-mape-fallback

changed=0
for u in "$D"/units/*; do
    dst=/etc/systemd/system/"$(basename "$u")"
    cmp -s "$u" "$dst" || { install -m 0644 "$u" "$dst"; changed=1; }
done
[ "$changed" = 1 ] && systemctl daemon-reload

systemctl enable --now udm-mape-fallback.timer >/dev/null
systemctl is-active --quiet udm-mape-fallback.timer \
    || { echo "FAIL: udm-mape-fallback.timer not active" >&2; exit 1; }
# Run once now so the /etc/hosts pin (and a needed re-push) does not wait
# for the next 5-min tick after a firmware update wiped the units.
systemctl start udm-mape-fallback.service \
    || echo "WARN: udm-mape-fallback.service failed — see journalctl -t udm-mape-fallback" >&2

echo "udm-mape-fallback: 5-min timer active."
