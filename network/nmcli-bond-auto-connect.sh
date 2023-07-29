#!/bin/bash

INTERFACE=$1
STATUS=$2

if [ "$INTERFACE" == "bond0" ]; then
    case "$STATUS" in
        up)
            nmcli dev set A autoconnect no
            nmcli dev disconnect A
            ;;
        down)
            nmcli dev set A autoconnect yes
            nmcli dev connect A
            ;;
    esac
fi
