#!/bin/bash
#
# install.sh — post-install hook for /data/udm-pg-tune.
# Installs PostgreSQL drop-ins to reduce eMMC write amplification and reloads (never restarts).
#
set -euo pipefail

D=/data/udm-pg-tune
SRC="$D/99-udm-emmc.conf"
chmod 0755 "$D/rollback.sh"

declare -A PORTS=([apps]=5434 [main]=5432)

for c in apps main; do
    dir="/etc/postgresql/14/$c/conf.d"
    [ -d "$dir" ] || continue
    dst="$dir/99-udm-emmc.conf"
    if ! cmp -s "$SRC" "$dst" 2>/dev/null; then
        install -m 0644 -o postgres -g postgres "$SRC" "$dst"
        pg_ctlcluster 14 "$c" reload
    fi
    port=${PORTS[$c]}
    ct=$(su - postgres -c "psql -p $port -tAc 'SHOW checkpoint_timeout;'" 2>/dev/null || echo "")
    wc=$(su - postgres -c "psql -p $port -tAc 'SHOW wal_compression;'" 2>/dev/null || echo "")
    jt=$(su - postgres -c "psql -p $port -tAc 'SHOW jit;'" 2>/dev/null || echo "")
    if [ "$ct" != "15min" ] || [ "$wc" != "on" ] || [ "$jt" != "off" ]; then
        echo "FAIL: postgresql@14-$c settings mismatch (checkpoint_timeout=$ct, wal_compression=$wc, jit=$jt)" >&2
        exit 1
    fi
done

echo "udm-pg-tune: 99-udm-emmc.conf installed & reloaded (checkpoint_timeout=15min, wal_compression=on, jit=off)."
