#!/bin/bash
# Run the same post-install hooks as `make unifi/install` on every boot
# (CONTEXT.md Q42). Detached with systemd-run: the hooks `systemctl start`
# other units, which must not hold up udm-boot.service. Output:
#   journalctl -u udm-post-install
set -euo pipefail
systemctl reset-failed udm-post-install.service 2>/dev/null || true
systemd-run --no-block --unit=udm-post-install /data/udm-post-install/post-install.sh
