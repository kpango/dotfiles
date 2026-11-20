#!/bin/bash
#
# udm-dfs-restore — put 5 GHz radios that a DFS radar hit moved off their
# configured channel back onto it (CONTEXT.md Q40).
#
# Why: the AP firmware's own nightly `syswrapper.sh dfs-reset` only looks at the
# first 5 GHz VAP (`list_first_vaps_ifs` returns after one match), so on an
# AP with two 5 GHz radios (UAP-XG) the second radio never comes back.
#
# What: compares the controller's configured channel (radio_table) with the
# live one (radio_table_stats) and restores every drifted radio. The timer
# runs it once a day at 05:00 JST so the restore never interrupts daytime use.
# Restoring = on the AP: `radartool chknol` (skip while the channel is in the
# NOL) then `iwconfig <vap> channel <cfg>` — the same as the firmware's
# dfs_reset. Only that radio pauses for the ~60 s CAC.
# --check also flags a drifted radio whose live span overlaps another AP's
# 5 GHz radio that it does not overlap by configuration (intentional
# overlaps are not reported as such).
#
# Usage: udm-dfs-restore.sh            restore every drifted radio (timer)
#        udm-dfs-restore.sh --check    read-only; print FAIL lines, exit = count
#
# The AP SSH password is read from the controller (mgmt x_ssh_password) on every
# run and handed to sshpass via the environment — never stored or put in argv.
set -euo pipefail

D=/data/udm-dfs-restore
KEY_FILE=/data/nextdns-client-names/api-key
MODE=${1:-run}
case "$MODE" in run|--check) ;; *) echo "usage: $0 [--check]" >&2; exit 64 ;; esac

log() { logger -t udm-dfs-restore "$*"; printf '%s\n' "$*"; }

K=$(cat "$KEY_FILE")
api() { curl -ksSf --max-time 20 -H "X-API-KEY: $K" "https://127.0.0.1/proxy/network$1"; }

# One line per drifted 5 GHz radio: "<collide> <ip> <radio> <cfg> <live> <name>".
# span = [lowest, highest] 20 MHz channel of the block a channel/width occupies
# (block edges counted from ch36; correct for JP/EU 36-144).
DEV=$(api /api/s/default/stat/device)
# While the Network app is (re)starting, the proxy answers 200 with an HTML
# page, and this jq 1.6 exits 0 on a parse error — so check the shape first.
jq -e '.data | type == "array"' <<<"$DEV" >/dev/null 2>&1 \
    || { log "controller API returned no device list (Network app not ready?)"; exit 1; }
DRIFT=$(jq -r '
  def span($ch; $ht): (($ht|tonumber) / 20 * 4) as $w
    | ($ch - (($ch - 36) % $w)) as $lo | [$lo, $lo + $w - 4];
  def ov($a; $b): $a[0] <= $b[1] and $b[0] <= $a[1];
  [ .data[] | select(.state == 1 and .radio_table) | . as $d
    | ($d.radio_table_stats // [] | map({(.name): .channel}) | add // {}) as $live
    | $d.radio_table[]
    | select(.radio == "na" and (.channel|tostring|test("^[1-9][0-9]*$")) and $live[.name] != null)
    | (.channel|tonumber) as $c | ($live[.name]|tonumber) as $l
    | {dev: $d.name, ip: $d.ip, radio: .name, cfg: $c, live: $l,
       cs: span($c; .ht), ls: span($l; .ht)} ]
  | . as $all
  | .[] | select(.cfg != .live) | . as $r
  | ([$all[] | select(.dev != $r.dev) | ov($r.ls; .ls) and (ov($r.cs; .cs) | not)] | any) as $col
  | "\($col) \($r.ip) \($r.radio) \($r.cfg) \($r.live) \($r.dev)"' <<<"$DEV")

if [ "$MODE" = --check ]; then
    n=0
    while read -r col ip radio cfg live name; do
        [ -n "$ip" ] || continue
        n=$((n + 1))
        printf 'FAIL  %s %s: configured ch%s, live ch%s%s\n' "$name" "$radio" "$cfg" "$live" \
            "$([ "$col" = true ] && echo ' — overlaps another AP outside the plan')"
    done <<<"$DRIFT"
    exit "$n"
fi

[ -n "$DRIFT" ] || exit 0

MGMT=$(api /api/s/default/get/setting/mgmt)
USER_=$(jq -r '.data[0].x_ssh_username // empty' <<<"$MGMT")
SSHPASS=$(jq -r '.data[0].x_ssh_password // empty' <<<"$MGMT")
[ -n "$USER_" ] && [ -n "$SSHPASS" ] || { log "mgmt ssh credentials not readable from controller"; exit 1; }
export SSHPASS

# Runs on the AP (busybox ash). Exit: 0 restored/already ok, 2 still in NOL, 3 no VAP.
REMOTE='ph=$1 ch=$2
vap=$(grep -v -e wips -e vwire -e apcl /var/run/${ph}_devnames | head -n 1)
[ -n "$vap" ] || exit 3
cur=$(iwlist "$vap" frequency | sed -n "s/.*(Channel \([0-9]*\)).*/\1/p")
[ "$cur" = "$ch" ] && exit 0
[ "$(radartool -i "$ph" chknol "$ch")" = false ] || exit 2
iwconfig "$vap" channel "$ch"'

FAILS=0
while read -r col ip radio cfg live name; do
    [ -n "$ip" ] || continue
    # Values come from the API; refuse anything that is not plainly shaped.
    if ! [[ $ip =~ ^[0-9]+(\.[0-9]+){3}$ && $radio =~ ^wifi[0-9]$ && $cfg =~ ^[0-9]+$ ]]; then
        log "$name: unexpected values ip=$ip radio=$radio cfg=$cfg — skipped"; FAILS=$((FAILS + 1)); continue
    fi
    rc=0
    sshpass -e ssh -n -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$D/known_hosts" -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no "$USER_@$ip" "set -- $radio $cfg; $REMOTE" || rc=$?
    case $rc in
        0) log "$name $radio: ch$live => ch$cfg restored (CAC ~60s; overlap=$col)" ;;
        2) log "$name $radio: ch$cfg still in NOL — next run" ;;
        *) log "$name $radio: restore to ch$cfg failed (rc=$rc)"; FAILS=$((FAILS + 1)) ;;
    esac
done <<<"$DRIFT"
exit "$FAILS"
