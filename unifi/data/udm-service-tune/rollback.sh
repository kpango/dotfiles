#!/bin/bash
#
# rollback.sh — unmask and re-start fwupd-refresh.timer and fwupd.service.
#
set -euo pipefail

systemctl unmask fwupd.service fwupd-refresh.timer >/dev/null
systemctl enable --now fwupd-refresh.timer >/dev/null

echo "udm-service-tune: unmasked fwupd.service and fwupd-refresh.timer."
