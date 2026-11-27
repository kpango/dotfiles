#!/bin/bash
#
# install.sh — post-install hook for /data/udm-prio-tune.
# Applies Nice scheduling drop-ins for nextdns (-10), tailscaled (-5), and
# batch maintenance timers (Nice=10, best-effort priority 7), using live renice
# on running nextdns/tailscaled threads so there is 0 ms DNS/VPN outage.
#
set -euo pipefail

D=/data/udm-prio-tune
chmod 0755 "$D/rollback.sh"

changed=0
install_dropin() {
    local unit=$1 content=$2
    local dir="/etc/systemd/system/${unit}.d"
    local dst="$dir/99-udm-prio.conf"
    mkdir -p "$dir"
    if [ ! -f "$dst" ] || [ "$(cat "$dst")" != "$content" ]; then
        printf '%s\n' "$content" > "$dst"
        chmod 0644 "$dst"
        changed=1
    fi
}

install_dropin nextdns.service "[Service]
Nice=-10"

install_dropin tailscaled.service "[Service]
Nice=-5"

BATCH_CFG="[Service]
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7"

for u in udm-verifier-enforcer.service clean-clients.service udm-dfs-restore.service nextdns-client-names.service; do
    install_dropin "$u" "$BATCH_CFG"
done

[ "$changed" = 1 ] && systemctl daemon-reload

renice_service() {
    local unit=$1 target=$2
    local mpid tid cur
    mpid=$(systemctl show -p MainPID --value "$unit" 2>/dev/null || echo 0)
    [ "$mpid" -gt 1 ] 2>/dev/null || return 0
    while read -r tid cur; do
        [ -n "$tid" ] || continue
        [ "$cur" != "$target" ] && renice -n "$target" -p "$tid" >/dev/null 2>&1 || true
    done < <(ps -L -o tid=,ni= -p "$mpid" 2>/dev/null || true)
}

renice_service nextdns.service -10
renice_service tailscaled.service -5

echo "udm-prio-tune: drop-ins synced and live renice applied (nextdns=-10, tailscaled=-5)."
