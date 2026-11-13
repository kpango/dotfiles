#!/bin/bash
#
# install.sh — post-install hook for /data/udm-ndp-proxy.
#
# ndppd is the NDP Proxy Daemon that lets UDM answer IPv6 neighbor
# solicitations on eth10 (NURO WAN) for addresses that actually live on
# br0 (Default) and br3 (Media). This closes the IPv6 return-path hole
# left by F2886Q's lack of DHCPv6-PD: NURO's /56 is split manually and
# each LAN /64 is routed to UDM via NDP proxy. See memory
# udm-pro-nuro-v6-ndp-proxy for the full design.
#
# This installer places three files that /etc wipes (firmware updates,
# factory reset) would otherwise erase:
#   /etc/ndppd.conf                      — proxy rules
#   /etc/sysctl.d/99-ndp-proxy.conf      — kernel proxy_ndp + forwarding
#   /etc/systemd/system/ndppd.service    — daemon unit
#
set -euo pipefail

D=/data/udm-ndp-proxy

# ---- /etc/ndppd.conf ----
if ! cmp -s "$D/ndppd.conf" /etc/ndppd.conf; then
    install -m 0644 "$D/ndppd.conf" /etc/ndppd.conf
    ndppd_cfg_changed=1
else
    ndppd_cfg_changed=0
fi

# ---- /etc/sysctl.d/99-ndp-proxy.conf ----
if ! cmp -s "$D/99-ndp-proxy.conf" /etc/sysctl.d/99-ndp-proxy.conf; then
    install -m 0644 "$D/99-ndp-proxy.conf" /etc/sysctl.d/99-ndp-proxy.conf
    sysctl -p /etc/sysctl.d/99-ndp-proxy.conf >/dev/null
fi

# ---- /etc/systemd/system/ndppd.service ----
unit_changed=0
for u in "$D"/units/*; do
    dst=/etc/systemd/system/"$(basename "$u")"
    cmp -s "$u" "$dst" || { install -m 0644 "$u" "$dst"; unit_changed=1; }
done
[ "$unit_changed" = 1 ] && systemctl daemon-reload

systemctl enable --now ndppd.service >/dev/null
systemctl is-active --quiet ndppd.service \
    || { echo "FAIL: ndppd.service not active" >&2; exit 1; }

# If the config file changed, restart ndppd so it re-reads. It is a plain
# daemon and the restart gap is <1s — acceptable; drop-only brief gaps on
# NDP are no worse than normal link flap.
if [ "$ndppd_cfg_changed" = 1 ]; then
    systemctl restart ndppd.service
fi

echo "udm-ndp-proxy: ndppd running, sysctl applied, config matches dotfiles."
