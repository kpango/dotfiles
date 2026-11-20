#!/bin/bash
#
# install.sh — post-install hook for /data/udm-nuro-v6-pbr.
#
# Normalises execute bits, syncs the systemd units into /etc/systemd/system
# (firmware updates reset the overlay), and enables the timer. Also retires
# the pre-dotfiles /etc/systemd/system/udm-v6-source-pbr.service that this
# component replaces.
#
set -euo pipefail

D=/data/udm-nuro-v6-pbr
chmod 0755 "$D/udm-nuro-v6-pbr.sh"

# Retire the ad-hoc predecessor from the earlier interactive session, if it
# is still installed. Idempotent — ignore if missing.
if systemctl list-unit-files udm-v6-source-pbr.service >/dev/null 2>&1; then
    systemctl disable --now udm-v6-source-pbr.service 2>/dev/null || true
    rm -f /etc/systemd/system/udm-v6-source-pbr.service
    systemctl daemon-reload
fi

changed=0
for u in "$D"/units/*; do
    dst=/etc/systemd/system/"$(basename "$u")"
    cmp -s "$u" "$dst" || { install -m 0644 "$u" "$dst"; changed=1; }
done
[ "$changed" = 1 ] && systemctl daemon-reload

systemctl enable --now udm-nuro-v6-pbr.timer >/dev/null
systemctl is-active --quiet udm-nuro-v6-pbr.timer \
    || { echo "FAIL: udm-nuro-v6-pbr.timer not active" >&2; exit 1; }

# Run once immediately so the rules are present without waiting for the tick.
systemctl start udm-nuro-v6-pbr.service

echo "udm-nuro-v6-pbr: timer active, ip -6 rules re-applied if missing."
