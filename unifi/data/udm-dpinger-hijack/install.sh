#!/bin/sh
#
# Place systemd units for udm-dpinger-hijack and (re)start the timer.
# Idempotent: unit files are compared with cmp before overwrite; daemon-
# reload runs only when any unit changed.
#
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
SRC_UNITS="$HERE/units"
DST_UNITS=/etc/systemd/system

NEED_RELOAD=
for u in udm-dpinger-hijack.service udm-dpinger-hijack.timer; do
    if ! cmp -s "$SRC_UNITS/$u" "$DST_UNITS/$u" 2>/dev/null; then
        cp -f "$SRC_UNITS/$u" "$DST_UNITS/$u"
        echo "udm-dpinger-hijack: $u updated"
        NEED_RELOAD=1
    fi
done

[ -n "${NEED_RELOAD:-}" ] && systemctl daemon-reload

systemctl enable --now udm-dpinger-hijack.timer >/dev/null
systemctl start udm-dpinger-hijack.service || true

# Flush any stale conntrack entries that pre-date our DNAT chain. dpinger
# re-probes every few seconds and keeps the ICMP conntrack entry refreshed
# past its natural 30s timeout, so entries created before the chain existed
# will stay pinned (and bypass DNAT) indefinitely. One-shot flush here is
# surgical: scoped to UDM-local sources (eth10 wan ip + ip6tnl2 inner ip)
# and the two target IPs we actually DNAT. Clients behind the gateway are
# untouched — their :53 is already handled by udm-dns-hijack PREROUTING.
for src in 10.0.1.2 192.0.0.3; do
    for dst in 1.1.1.1 8.8.8.8; do
        conntrack -D -s "$src" -d "$dst" 2>/dev/null | tail -0 || true
    done
done

echo "udm-dpinger-hijack: installed and active"
