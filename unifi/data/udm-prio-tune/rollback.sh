#!/bin/bash
#
# rollback.sh — remove CPU/IO priority drop-ins and restore nice 0 on live daemons.
#
set -euo pipefail

for u in nextdns.service tailscaled.service udm-verifier-enforcer.service clean-clients.service udm-dfs-restore.service nextdns-client-names.service; do
    rm -f "/etc/systemd/system/${u}.d/99-udm-prio.conf"
    rmdir "/etc/systemd/system/${u}.d" 2>/dev/null || true
done
systemctl daemon-reload

for u in nextdns.service tailscaled.service; do
    mpid=$(systemctl show -p MainPID --value "$u" 2>/dev/null || echo 0)
    [ "$mpid" -gt 1 ] 2>/dev/null || continue
    for tid in /proc/"$mpid"/task/*; do
        [ -d "$tid" ] || continue
        renice -n 0 -p "$(basename "$tid")" >/dev/null 2>&1 || true
    done
done

echo "udm-prio-tune: rolled back priority drop-ins and restored nice 0."
