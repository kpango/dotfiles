#!/bin/bash
#
# install.sh — post-install hook for /data/udm-service-tune.
# Masks idle fwupd.service and fwupd-refresh.timer (never runs apt purge).
#
set -euo pipefail

D=/data/udm-service-tune
chmod 0755 "$D/rollback.sh"

for u in fwupd-refresh.timer fwupd.service; do
    if systemctl is-active --quiet "$u"; then
        systemctl stop "$u"
    fi
    if [ "$(systemctl is-enabled "$u" 2>/dev/null || true)" != "masked" ]; then
        systemctl mask "$u" >/dev/null
    fi
done

echo "udm-service-tune: fwupd.service and fwupd-refresh.timer masked."
