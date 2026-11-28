#!/bin/bash
#
# install.sh — post-install hook for /data/tailscale-guard.
#
set -euo pipefail

D=/data/tailscale-guard
chmod 0755 "$D/apply.sh"

changed=0
for u in "$D"/units/*; do
    dst=/etc/systemd/system/"$(basename "$u")"
    cmp -s "$u" "$dst" || { install -m 0644 "$u" "$dst"; changed=1; }
done
[ "$changed" = 1 ] && systemctl daemon-reload

systemctl enable --now tailscale-guard.timer >/dev/null
systemctl is-active --quiet tailscale-guard.timer \
    || { echo "FAIL: tailscale-guard.timer not active" >&2; exit 1; }

systemctl start tailscale-guard.service

echo "tailscale-guard: timer active, br2/10.0.10.0/26 isolated from tailscale0."
