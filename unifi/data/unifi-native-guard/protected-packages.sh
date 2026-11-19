#!/bin/bash
# Print packages whose firmware (/mnt/.rofs) build is Ubiquiti-specific or deliberately
# held back by Ubiquiti (bullseye/bpo11 builds). Debian's versions of these break
# ubios-udapi-server (missing xtables extensions dpi*/dyn_random/geoip, zebra path, ...).
ADM=/mnt/.rofs/var/lib/dpkg
dpkg-query --admindir=$ADM -W -f='${Package} ${Version} ${Maintainer}\n' |
  awk '$2 ~ /ubnt|\+ui|-[0-9]+\+g[0-9a-f]{12}|deb11|bpo11/ || $0 ~ /[Uu]biquiti/ {print $1, $2}'
