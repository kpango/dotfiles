#!/bin/bash
#
# ensure.sh — keep dnsmasq-main bound to tailscale0 for Tailscale Split DNS.
#
# ubios-udapi-server regenerates /run/dnsmasq.dhcp.conf.d/ on config changes and
# runs dnsmasq-main with bind-to-device. Adding 99-tailscale.conf requires
# restarting dnsmasq-main (SIGTERM -> udapi-server watchdog respawns it), since
# SIGHUP does not re-read --conf-dir or bind new interfaces.
#
set -euo pipefail

CONF=/run/dnsmasq.dhcp.conf.d/99-tailscale.conf
CONF_TMP=/run/.99-tailscale.conf.tmp
MAIN_CONF=/run/dnsmasq.dns.conf.d/main.conf
CONF_DIR=/run/dnsmasq.dhcp.conf.d
TEST_DIR=/run/tailscale-dnsmasq.test
PID_FILE=/run/dnsmasq-main.pid
STATE_PID=/run/tailscale-dnsmasq.bound-pid
LOCK=/run/tailscale-dnsmasq.lock

log() { logger -t tailscale-dnsmasq "$*"; }

exec 9>"$LOCK"
flock -w 30 9 || { log "failed to acquire lock"; exit 1; }

ip link show tailscale0 >/dev/null 2>&1 || exit 0
TS_V4=$(ip -4 -o addr show dev tailscale0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)
TS_V6=$(ip -6 -o addr show dev tailscale0 scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)

mkdir -p "$CONF_DIR"

WANT=$'# Managed by tailscale-dnsmasq.service\ninterface=tailscale0\nno-dhcp-interface=tailscale0'

test_dnsmasq_cfg() {
    [ -r "$MAIN_CONF" ] || return 0
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"
    cp -a "$CONF_DIR"/. "$TEST_DIR"/ 2>/dev/null || true
    printf '%s\n' "$WANT" > "$TEST_DIR/99-tailscale.conf"
    if ! dnsmasq --test --conf-file="$MAIN_CONF" --conf-dir="$TEST_DIR/" >/dev/null 2>&1; then
        rm -rf "$TEST_DIR"
        log "ERROR: dnsmasq --test failed in staging dir $TEST_DIR; leaving $CONF untouched"
        return 1
    fi
    rm -rf "$TEST_DIR"
}

probe_dnsmasq_ts() {
    local ip ans
    [ -n "$TS_V4" ] && [ -n "$TS_V6" ] || return 1
    for ip in "$TS_V4" "$TS_V6"; do
        ans=$(dig +short +time=1 +tries=1 @"$ip" Dream-Machine-Pro 2>/dev/null || true)
        if [ -z "$ans" ]; then
            log "dnsmasq-main not answering on $ip:53"
            return 1
        fi
    done
    return 0
}

restart_dnsmasq_main() {
    local old_pid="" new_pid="" i
    rm -f "$STATE_PID"
    if [ -r "$PID_FILE" ]; then
        old_pid=$(cat "$PID_FILE" 2>/dev/null || true)
    fi
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        kill -TERM "$old_pid"
        log "sent SIGTERM to dnsmasq-main pid=$old_pid for tailscale0 rebind"
        for i in $(seq 1 20); do
            sleep 0.5
            new_pid=$(cat "$PID_FILE" 2>/dev/null || true)
            if [ -n "$new_pid" ] && [ "$new_pid" != "$old_pid" ] && kill -0 "$new_pid" 2>/dev/null; then
                log "dnsmasq-main respawned pid=$new_pid"
                sleep 0.2
                if probe_dnsmasq_ts; then
                    printf '%s\n' "$new_pid" > "$STATE_PID"
                    log "verified dnsmasq-main pid=$new_pid on v4=$TS_V4 and v6=$TS_V6"
                else
                    log "WARN: dnsmasq-main pid=$new_pid not ready on v4='${TS_V4:-none}' v6='${TS_V6:-none}'; will retry"
                fi
                return 0
            fi
        done
        log "WARN: timed out waiting for dnsmasq-main respawn"
    fi
}

need_write=0
if [ ! -f "$CONF" ] || [ "$(cat "$CONF" 2>/dev/null || true)" != "$WANT" ]; then
    need_write=1
fi

if [ "$need_write" = 1 ]; then
    test_dnsmasq_cfg
    printf '%s\n' "$WANT" > "$CONF_TMP"
    chmod 0644 "$CONF_TMP"
    mv -f "$CONF_TMP" "$CONF"
    restart_dnsmasq_main
    exit 0
fi

if [ -z "$TS_V4" ] || [ -z "$TS_V6" ]; then
    rm -f "$STATE_PID"
    log "tailscale0 missing address (v4='${TS_V4:-none}' v6='${TS_V6:-none}'); deferring STATE_PID"
    exit 0
fi

cur_pid=$(cat "$PID_FILE" 2>/dev/null || true)
bound_pid=$(cat "$STATE_PID" 2>/dev/null || true)

if [ -n "$cur_pid" ] && [ "$cur_pid" != "$bound_pid" ]; then
    test_dnsmasq_cfg
    if ! probe_dnsmasq_ts; then
        log "dnsmasq-main pid=$cur_pid failed dual-stack probe; restarting"
        restart_dnsmasq_main
        exit 0
    fi
    printf '%s\n' "$cur_pid" > "$STATE_PID"
fi
