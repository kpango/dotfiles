#!/bin/bash
#
# install.sh — post-install hook for /data/clean-clients.
#
# Places the systemd units that run /root/clean-clients.sh (pushed from
# unifi/root/) daily at 09:00 JST to forget stale ghost clients. Units live
# here because /etc/systemd/system is reset by firmware updates.
#
set -euo pipefail

D=/data/clean-clients

changed=0
for u in "$D"/units/*; do
    dst=/etc/systemd/system/"$(basename "$u")"
    cmp -s "$u" "$dst" || { install -m 0644 "$u" "$dst"; changed=1; }
done
[ "$changed" = 1 ] && systemctl daemon-reload

systemctl enable --now clean-clients.timer >/dev/null
systemctl is-active --quiet clean-clients.timer \
    || { echo "FAIL: clean-clients.timer not active" >&2; exit 1; }

echo "clean-clients: daily timer active."
