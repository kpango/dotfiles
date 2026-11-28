#!/bin/sh
#
# Install udm-verifier-enforcer units and start the hourly timer.
# Idempotent — units are only overwritten when content differs.
#
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
SRC_UNITS="$HERE/units"
DST_UNITS=/etc/systemd/system

NEED_RELOAD=
for u in udm-verifier-enforcer.service udm-verifier-enforcer.timer; do
    if ! cmp -s "$SRC_UNITS/$u" "$DST_UNITS/$u" 2>/dev/null; then
        cp -f "$SRC_UNITS/$u" "$DST_UNITS/$u"
        echo "udm-verifier-enforcer: $u updated"
        NEED_RELOAD=1
    fi
done

[ -n "${NEED_RELOAD:-}" ] && systemctl daemon-reload

systemctl enable --now udm-verifier-enforcer.timer >/dev/null
systemctl start udm-verifier-enforcer.service || true
echo "udm-verifier-enforcer: installed and active (hourly)"
