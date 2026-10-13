#!/bin/sh
if [[ "${1:0:2}" = "en" ]]; then
    case "$2" in
        up)
            nmcli radio wifi off
            ;;
        down)
            nmcli radio wifi on
            ;;
    esac
fi
