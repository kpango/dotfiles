#!/bin/bash
#
# apply.sh — isolate IoT VLAN (br2, 10.0.10.0/26) from tailscale0.
#
# Uses a dedicated TS_ISOLATE chain in filter FORWARD (NO -m comment, -w 30
# per CONTEXT.md Q35) so udapi-server firewall rebuilds never fail or drop it.
# Diff-before-mutate fast-path + atomic iptables-restore rebuild eliminates
# empty-chain race windows and unnecessary filter table replacements.
# Ensures TS_ISOLATE precedes UBIOS_FORWARD_JUMP in both iptables and ip6tables.
#
set -euo pipefail

CHAIN=TS_ISOLATE
IOT_IFACE=br2
IOT_CIDR=10.0.10.0/26
TS_IFACE=tailscale0
LOCK=/run/tailscale-guard.lock

log() { logger -t tailscale-guard "$*"; }

exec 9>"$LOCK"
flock -w 30 9 || { log "failed to acquire lock"; exit 1; }

dedupe() {
    local ipt=$1 table=$2 chain=$3 pat=$4; shift 4
    while [ "$($ipt -w 30 -t "$table" -S "$chain" | grep -c -- "$pat")" -gt 1 ]; do
        $ipt -w 30 -t "$table" -D "$chain" "$@" || break
        log "removed duplicate $ipt $chain rule ($pat)"
    done
}

sync_ts_isolate() {
    local ipt=$1 restore=$2 expected=$3
    local current
    current=$($ipt -w 30 -S "$CHAIN" 2>/dev/null || true)
    if [ "$current" = "$expected" ]; then
        return 0
    fi
    $restore --noflush --wait=30 <<EOF
*filter
:$CHAIN - [0:0]
-F $CHAIN
${expected#*-N $CHAIN
}
COMMIT
EOF
    log "rebuilt $ipt $CHAIN atomically"
}

ensure_forward_hook() {
    local ipt=$1
    local fwd count ts_pos ubios_pos
    fwd=$($ipt -w 30 -S FORWARD)
    count=$(printf '%s\n' "$fwd" | grep -c -- "-j $CHAIN$" || true)
    if [ "$count" = "1" ]; then
        ts_pos=$(printf '%s\n' "$fwd" | grep -v '^-P' | grep -n -- "-j $CHAIN$" | head -1 | cut -d: -f1 || true)
        ubios_pos=$(printf '%s\n' "$fwd" | grep -v '^-P' | grep -n -- "-j UBIOS_FORWARD_JUMP$" | head -1 | cut -d: -f1 || true)
        if [ -z "$ubios_pos" ] || { [ -n "$ts_pos" ] && [ "$ts_pos" -lt "$ubios_pos" ]; }; then
            return 0
        fi
    fi

    dedupe "$ipt" filter FORWARD "-j $CHAIN$" -j "$CHAIN"
    if ! $ipt -w 30 -C FORWARD -j "$CHAIN" 2>/dev/null; then
        $ipt -w 30 -I FORWARD 1 -j "$CHAIN"
        log "$ipt FORWARD hook added at pos 1"
        return 0
    fi
    ts_pos=$($ipt -w 30 -S FORWARD | grep -v '^-P' | grep -n -- "-j $CHAIN$" | head -1 | cut -d: -f1 || true)
    ubios_pos=$($ipt -w 30 -S FORWARD | grep -v '^-P' | grep -n -- "-j UBIOS_FORWARD_JUMP$" | head -1 | cut -d: -f1 || true)
    if [ -n "$ubios_pos" ] && [ -n "$ts_pos" ] && [ "$ts_pos" -ge "$ubios_pos" ]; then
        $ipt -w 30 -D FORWARD -j "$CHAIN"
        $ipt -w 30 -I FORWARD 1 -j "$CHAIN"
        log "$ipt FORWARD hook re-inserted at pos 1 (was pos=$ts_pos, UBIOS_FORWARD_JUMP pos=$ubios_pos)"
    fi
}

EXPECTED_V4=$(cat <<EOF
-N $CHAIN
-A $CHAIN -i $TS_IFACE -o $IOT_IFACE -j DROP
-A $CHAIN -i $IOT_IFACE -o $TS_IFACE -j DROP
-A $CHAIN -d $IOT_CIDR -i $TS_IFACE -j DROP
EOF
)

EXPECTED_V6=$(cat <<EOF
-N $CHAIN
-A $CHAIN -i $TS_IFACE -o $IOT_IFACE -j DROP
-A $CHAIN -i $IOT_IFACE -o $TS_IFACE -j DROP
EOF
)

sync_ts_isolate iptables iptables-restore "$EXPECTED_V4"
ensure_forward_hook iptables

sync_ts_isolate ip6tables ip6tables-restore "$EXPECTED_V6"
ensure_forward_hook ip6tables

# Ensure tailscale0 runs fq_codel and txqueuelen 1000 across tailscaled restarts without timer churn
if ip link show "$TS_IFACE" >/dev/null 2>&1; then
    if ! tc qdisc show dev "$TS_IFACE" | grep -q '^qdisc fq_codel .* root '; then
        modprobe sch_fq_codel 2>/dev/null || true
        tc qdisc replace dev "$TS_IFACE" root fq_codel limit 1000
        log "applied fq_codel (limit 1000) to $TS_IFACE"
    fi
    cur_qlen=$(tr -d '[:space:]' < "/sys/class/net/$TS_IFACE/tx_queue_len" 2>/dev/null || echo "")
    if [ "$cur_qlen" != "1000" ]; then
        ip link set dev "$TS_IFACE" txqueuelen 1000
        log "set $TS_IFACE txqueuelen 1000 (was ${cur_qlen:-unknown})"
    fi
fi
