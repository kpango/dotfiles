#!/usr/bin/env zsh

INTERFACE=$1
STATUS=$2
BACKUP_IFACE=eth0

if [ "$INTERFACE" == "bond0" ]; then
	case "$STATUS" in
	up)
		nmcli dev set "$BACKUP_IFACE" autoconnect no 2>/dev/null || true
		nmcli dev disconnect "$BACKUP_IFACE" 2>/dev/null || true
		;;
	down)
		nmcli dev set "$BACKUP_IFACE" autoconnect yes 2>/dev/null || true
		nmcli dev connect "$BACKUP_IFACE" 2>/dev/null || true
		;;
	esac
fi
