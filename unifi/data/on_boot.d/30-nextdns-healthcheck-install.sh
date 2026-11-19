#!/bin/sh
# Install healthcheck cron entry on every boot (survives firmware upgrades that wipe /etc).
set -eu
cat > /etc/cron.d/nextdns-healthcheck <<'CRON'
# nextdns healthcheck: probe DNS every 5 min, restart service on failure
MAILTO=""
*/5 * * * * root /data/nextdns-healthcheck.sh
CRON
chmod 644 /etc/cron.d/nextdns-healthcheck
