#!/bin/sh

if !(type wakeonlan > /dev/null 2>&1); then
    apt install wakeonlan
fi

wakeonlan -p 9 -i 10.0.0.255 f0:2f:74:d4:37:35
