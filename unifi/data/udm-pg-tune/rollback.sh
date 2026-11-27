#!/bin/bash
#
# rollback.sh — remove PostgreSQL 99-udm-emmc.conf drop-in and reload clusters.
#
set -euo pipefail

for c in apps main; do
    dst="/etc/postgresql/14/$c/conf.d/99-udm-emmc.conf"
    if [ -e "$dst" ]; then
        rm -f "$dst"
        pg_ctlcluster 14 "$c" reload
    fi
done

echo "udm-pg-tune: rolled back to cluster defaults and reloaded."
