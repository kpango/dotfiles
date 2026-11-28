#!/bin/bash
#
# install.sh — post-install hook for /data/udm-zram-tune.
# Configures zram0 to use zstd on future boots via /etc/default/ubnt-zram-swap.
# NEVER runs swapoff or restarts ubnt-zram-swap.service on a live system.
#
set -euo pipefail

D=/data/udm-zram-tune
chmod 0755 "$D/rollback.sh"

grep -qw zstd /sys/block/zram0/comp_algorithm \
    || { echo "FAIL: kernel zram0 does not support zstd" >&2; exit 1; }

dst=/etc/default/ubnt-zram-swap
if ! cmp -s "$D/ubnt-zram-swap" "$dst" 2>/dev/null; then
    install -m 0644 "$D/ubnt-zram-swap" "$dst"
fi

echo "udm-zram-tune: /etc/default/ubnt-zram-swap set (COMP_ALGORITHM=zstd, next boot)."
