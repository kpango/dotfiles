#!/usr/bin/env bash
# unifi-update — run the UDM Pro maintenance scripts in /root, in order:
#   update.sh → clean-clients.sh → restart-tailscale.sh → debug.sh
# Stops at the first failure. Used from `make unifi/update`; it runs what is
# already on the UDM, so push first with `make unifi/install` if unifi/root/ changed.
#
# When executed remotely over Tailscale SSH, restart-tailscale.sh is started
# detached (systemd-run) and this script waits for SSH to come back.
# When executed locally on the UDM Pro (UDM=local), it runs directly.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

run() {  # run SCRIPT — run /root/SCRIPT on the UDM, streaming its output
  log update "$1"
  udm_exec "bash /root/$1" || die "[update] /root/$1 failed (rc=$?) — stopping"
}

run update.sh
run clean-clients.sh

if is_local; then
  run restart-tailscale.sh
  udm_exec 'tailscale status --self --peers=false' || die "[update] tailscale check failed"
else
  log update "restart-tailscale.sh (detached; SSH over Tailscale may drop)"
  udm_ssh "$UDM" 'systemd-run --quiet --unit=udm-restart-tailscale --collect \
    bash /root/restart-tailscale.sh' || die "[update] could not start restart-tailscale.sh"
  sleep 5
  for i in $(seq 1 24); do
    udm_ssh -o ConnectTimeout=5 "$UDM" true 2>/dev/null && break
    [ "$i" = 24 ] && die "[update] $UDM not reachable 2 min after restart-tailscale.sh"
    sleep 5
  done
  udm_ssh "$UDM" 'journalctl -u udm-restart-tailscale --no-pager -o cat -n 20; tailscale status --self --peers=false' \
    || die "[update] tailscale check failed"
fi

run debug.sh
log update "done"
