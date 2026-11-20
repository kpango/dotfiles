#!/bin/bash
#
# install.sh — post-install hook for /data/udm-dfs-restore (CONTEXT.md Q40).
# Units live here because /etc/systemd/system is reset by firmware updates.
#
set -euo pipefail

D=/data/udm-dfs-restore

changed=0
for u in "$D"/units/*; do
    dst=/etc/systemd/system/"$(basename "$u")"
    cmp -s "$u" "$dst" || { install -m 0644 "$u" "$dst"; changed=1; }
done
[ "$changed" = 1 ] && systemctl daemon-reload

systemctl enable --now udm-dfs-restore.timer >/dev/null
systemctl is-active --quiet udm-dfs-restore.timer \
    || { echo "FAIL: udm-dfs-restore.timer not active" >&2; exit 1; }

echo "udm-dfs-restore: daily 05:00 timer active."
