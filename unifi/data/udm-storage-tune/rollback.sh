#!/bin/bash
#
# rollback.sh — restore /dev/boot default I/O queue (cfq, rotational=1) and remove udm-storage-tune.
#
set -euo pipefail

Q=/sys/block/boot/queue
if [ -w "$Q/scheduler" ] && grep -qw cfq "$Q/scheduler" 2>/dev/null; then
    echo cfq > "$Q/scheduler"
fi
if [ -w "$Q/rotational" ]; then
    echo 1 > "$Q/rotational"
fi

rm -f /etc/udev/rules.d/60-udm-boot-io.rules
udevadm control --reload-rules

if [ -e /etc/systemd/system/udm-storage-tune.service ]; then
    systemctl disable --now udm-storage-tune.service 2>/dev/null || true
    rm -f /etc/systemd/system/udm-storage-tune.service
    systemctl daemon-reload
fi

echo "udm-storage-tune: rolled back to cfq, rotational=1."
