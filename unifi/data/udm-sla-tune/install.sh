#!/bin/bash
#
# install.sh — post-install hook for /data/udm-sla-tune.
#
# Runs on the UDM Pro after unifi-install.sh has tar-pushed this directory,
# normalises execute bits, syncs the systemd units into /etc/systemd/system
# (firmware updates reset the overlay — same mechanism as unifi-native-guard),
# and enables the timer so the tune is enforced going forward.
#
set -euo pipefail

D=/data/udm-sla-tune
chmod 0755 "$D/udm-sla-tune.sh"

changed=0
for u in "$D"/units/*; do
    dst=/etc/systemd/system/"$(basename "$u")"
    cmp -s "$u" "$dst" || { install -m 0644 "$u" "$dst"; changed=1; }
done
[ "$changed" = 1 ] && systemctl daemon-reload

systemctl enable --now udm-sla-tune.timer >/dev/null
systemctl is-active --quiet udm-sla-tune.timer \
    || { echo "FAIL: udm-sla-tune.timer not active" >&2; exit 1; }

# Run once immediately so the tune applies without waiting for the next tick.
systemctl start udm-sla-tune.service

echo "udm-sla-tune: timer active, state patched if drifted."
