#!/bin/bash
#
# apply.sh — configure /dev/boot flash I/O queue (rotational=0, scheduler=deadline).
# Never uses noop (prevents read starvation during PostgreSQL checkpoints).
#
set -euo pipefail

Q=/sys/block/boot/queue

if [ -w "$Q/rotational" ]; then
    cur_rot=$(cat "$Q/rotational" 2>/dev/null || echo "")
    if [ "$cur_rot" != "0" ]; then
        echo 0 > "$Q/rotational"
    fi
fi

if [ -w "$Q/scheduler" ]; then
    if grep -qw deadline "$Q/scheduler" 2>/dev/null; then
        if ! grep -q '\[deadline\]' "$Q/scheduler" 2>/dev/null; then
            echo deadline > "$Q/scheduler"
        fi
    fi
fi

logger -t udm-storage-tune "Applied /dev/boot I/O tune (rotational=0, scheduler=deadline)"
