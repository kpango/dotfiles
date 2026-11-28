#!/bin/bash
#
# install.sh — post-install hook for /data/udm-sysctl.
#
set -euo pipefail

D=/data/udm-sysctl
chmod 0755 "$D/apply.sh" "$D/rollback-net.sh"

conf_changed=0
if ! cmp -s "$D/99-udm-tune.conf" /etc/sysctl.d/99-udm-tune.conf; then
    install -m 0644 "$D/99-udm-tune.conf" /etc/sysctl.d/99-udm-tune.conf
    conf_changed=1
fi

unit_changed=0
for u in "$D"/units/*; do
    dst=/etc/systemd/system/"$(basename "$u")"
    cmp -s "$u" "$dst" || { install -m 0644 "$u" "$dst"; unit_changed=1; }
done
[ "$unit_changed" = 1 ] && systemctl daemon-reload

systemctl enable udm-sysctl.service >/dev/null
systemctl restart udm-sysctl.service
systemctl is-active --quiet udm-sysctl.service \
    || { echo "FAIL: udm-sysctl.service not active" >&2; exit 1; }

echo "udm-sysctl: service enabled and sysctl applied."
