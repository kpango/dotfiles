#!/bin/bash
#
# rollback-net.sh — restore default pfifo_fast qdiscs, XPS masks, and tailscale0 txqueuelen.
#
set -euo pipefail

sysctl -w net.core.default_qdisc=pfifo_fast >/dev/null
for dev in eth8 eth9 eth10 switch0; do
    ip link show "$dev" >/dev/null 2>&1 || continue
    if tc qdisc show dev "$dev" | grep -q '^qdisc mq '; then
        tc qdisc del dev "$dev" root 2>/dev/null || true
    fi
done

for dev in eth9 eth10 switch0; do
    for f in /sys/class/net/"$dev"/queues/tx-*/xps_cpus; do
        [ -w "$f" ] && echo 0 > "$f"
    done
done

for f in /sys/class/net/eth8/queues/tx-*/xps_cpus; do
    [ -w "$f" ] && echo f > "$f"
done

if ip link show tailscale0 >/dev/null 2>&1; then
    tc qdisc replace dev tailscale0 root pfifo_fast 2>/dev/null || true
    ip link set dev tailscale0 txqueuelen 500
fi

echo "udm-sysctl: rolled back fq_codel, xps_cpus, and tailscale0 txqueuelen."
