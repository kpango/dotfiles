#!/bin/bash
#
# rollback.sh — remove earlyoom systemd drop-in override and restore default -r 60 interval.
#
set -euo pipefail

rm -f /etc/systemd/system/earlyoom.service.d/99-udm-log-tune.conf /etc/default/earlyoom-udm-tune
rmdir /etc/systemd/system/earlyoom.service.d 2>/dev/null || true
systemctl daemon-reload
systemctl restart earlyoom.service

echo "udm-log-tune: rolled back earlyoom to /etc/default/earlyoom (-r 60)."
