#!/bin/bash
#
# install.sh — post-install hook for /data/udm-log-tune.
# Overrides earlyoom --dryrun report interval (-r 60 -> -r 3600) via systemd drop-in only.
#
set -euo pipefail

D=/data/udm-log-tune
chmod 0755 "$D/rollback.sh"

env_dst=/etc/default/earlyoom-udm-tune
dropin_dir=/etc/systemd/system/earlyoom.service.d
dropin_dst="$dropin_dir/99-udm-log-tune.conf"

changed=0
if ! cmp -s "$D/earlyoom-udm-tune" "$env_dst" 2>/dev/null; then
    install -m 0644 "$D/earlyoom-udm-tune" "$env_dst"
    changed=1
fi

mkdir -p "$dropin_dir"
if ! cmp -s "$D/99-udm-log-tune.conf" "$dropin_dst" 2>/dev/null; then
    install -m 0644 "$D/99-udm-log-tune.conf" "$dropin_dst"
    systemctl daemon-reload
    changed=1
fi

if [ "$changed" = 1 ] || ! pgrep -x earlyoom >/dev/null 2>&1 || ! ps -o args= -C earlyoom | grep -q -- '-r 3600'; then
    systemctl restart earlyoom.service
fi

systemctl is-active --quiet earlyoom.service \
    || { echo "FAIL: earlyoom.service not active" >&2; exit 1; }
systemctl is-active --quiet systemd-oomd.service \
    || { echo "FAIL: systemd-oomd.service not active" >&2; exit 1; }

ok=0
for _ in $(seq 1 10); do
    if ps -o args= -C earlyoom 2>/dev/null | grep -q -- '-r 3600'; then
        ok=1
        break
    fi
    sleep 0.2
done
[ "$ok" = 1 ] || { echo "FAIL: earlyoom did not pick up -r 3600" >&2; exit 1; }

echo "udm-log-tune: earlyoom drop-in active (-r 3600 --dryrun)."
