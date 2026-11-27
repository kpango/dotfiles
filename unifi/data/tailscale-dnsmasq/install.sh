#!/bin/bash
#
# install.sh — post-install hook for /data/tailscale-dnsmasq.
#
set -euo pipefail

D=/data/tailscale-dnsmasq
chmod 0755 "$D/ensure.sh"

changed=0
for u in "$D"/units/*; do
    dst=/etc/systemd/system/"$(basename "$u")"
    cmp -s "$u" "$dst" || { install -m 0644 "$u" "$dst"; changed=1; }
done
[ "$changed" = 1 ] && systemctl daemon-reload

systemctl enable --now tailscale-dnsmasq.path tailscale-dnsmasq.timer >/dev/null
systemctl is-active --quiet tailscale-dnsmasq.path \
    || { echo "FAIL: tailscale-dnsmasq.path not active" >&2; exit 1; }
systemctl is-active --quiet tailscale-dnsmasq.timer \
    || { echo "FAIL: tailscale-dnsmasq.timer not active" >&2; exit 1; }

"$D/ensure.sh"

echo "tailscale-dnsmasq: path+timer active, dnsmasq bound to tailscale0."
