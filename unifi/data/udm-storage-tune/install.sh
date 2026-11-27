#!/bin/bash
#
# install.sh — post-install hook for /data/udm-storage-tune.
#
set -euo pipefail

D=/data/udm-storage-tune
chmod 0755 "$D/apply.sh" "$D/rollback.sh"

udev_changed=0
rule_src="$D/60-udm-boot-io.rules"
rule_dst=/etc/udev/rules.d/60-udm-boot-io.rules
if ! cmp -s "$rule_src" "$rule_dst" 2>/dev/null; then
    install -m 0644 "$rule_src" "$rule_dst"
    udev_changed=1
fi
[ "$udev_changed" = 1 ] && udevadm control --reload-rules

unit_changed=0
for u in "$D"/units/*; do
    dst=/etc/systemd/system/"$(basename "$u")"
    cmp -s "$u" "$dst" 2>/dev/null || { install -m 0644 "$u" "$dst"; unit_changed=1; }
done
[ "$unit_changed" = 1 ] && systemctl daemon-reload

systemctl enable udm-storage-tune.service >/dev/null
systemctl restart udm-storage-tune.service
systemctl is-active --quiet udm-storage-tune.service \
    || { echo "FAIL: udm-storage-tune.service not active" >&2; exit 1; }

echo "udm-storage-tune: udev rule & service enabled, /dev/boot tuned (deadline, rotational=0)."
