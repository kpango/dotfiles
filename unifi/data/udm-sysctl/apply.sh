#!/bin/bash
#
# apply.sh — apply UDM Pro performance, qdisc (fq_codel), and sysctl tuning after udapi-server.
#
set -euo pipefail

modprobe sch_fq_codel 2>/dev/null || true
sysctl -e --system >/dev/null

apply_fq_codel_mq() {
    local dev q nq maj
    for dev in switch0 eth8 eth10 eth9; do
        ip link show "$dev" >/dev/null 2>&1 || continue
        tc qdisc show dev "$dev" | grep -q '^qdisc mq ' || continue
        if tc qdisc show dev "$dev" | grep -q '^qdisc mq 0: root'; then
            tc qdisc replace dev "$dev" root handle 1: mq
        fi
        maj=$(tc qdisc show dev "$dev" | awk '/^qdisc mq /{print $3; exit}')
        [ -n "$maj" ] || continue
        nq=$(find "/sys/class/net/$dev/queues" -maxdepth 1 -type d -name 'tx-*' | wc -l)
        [ "$nq" -gt 0 ] || continue
        for q in $(seq 1 "$nq"); do
            if ! tc qdisc show dev "$dev" | grep -q "^qdisc fq_codel .* parent ${maj}${q} .* limit 1024p "; then
                tc qdisc replace dev "$dev" parent "${maj}${q}" fq_codel limit 1024
            fi
        done
    done
}

apply_tx_xps() {
    local dev q f mask cur
    for dev in eth8 eth9 eth10 switch0; do
        ip link show "$dev" >/dev/null 2>&1 || continue
        for q in 0 1 2 3; do
            f="/sys/class/net/$dev/queues/tx-$q/xps_cpus"
            [ -w "$f" ] || continue
            mask=$(printf '%x' $((1 << q)))
            cur=$(tr -d '[:space:]' < "$f" 2>/dev/null || echo "")
            if [ "$cur" != "$mask" ]; then
                echo "$mask" > "$f"
            fi
        done
    done
}

apply_fq_codel_mq
apply_tx_xps

logger -t udm-sysctl "Applied UDM Pro sysctl, fq_codel mq leaf, and 1:1 TX XPS tuning"
