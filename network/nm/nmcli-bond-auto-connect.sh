#!/bin/bash
# NetworkManager dispatcher: disable eth0 while bond0 is up
#
# Root causes fixed vs previous version:
#   1. zsh [ ] does not support == operator → always exited 1
#   2. Calling nmcli from within dispatcher deadlocks NM D-Bus (synchronous
#      invocation); systemd-run --no-block defers execution until NM is free

IFACE=$1
ACTION=$2
BACKUP=eth0

[ "$IFACE" != "bond0" ] && exit 0

case "$ACTION" in
  up)
    # Tell NM to stop managing eth0 entirely; transient (reverts on NM restart)
    systemd-run --no-block -- nmcli dev set "$BACKUP" managed no
    ;;
  down)
    # Restore NM management and bring eth0 up as fallback
    systemd-run --no-block -- \
      bash -c "nmcli dev set '$BACKUP' managed yes; sleep 0.5; nmcli dev connect '$BACKUP'"
    ;;
esac

exit 0
