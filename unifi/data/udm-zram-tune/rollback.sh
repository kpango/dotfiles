#!/bin/bash
#
# rollback.sh — remove /etc/default/ubnt-zram-swap override (reverts to lzo on next boot).
#
set -euo pipefail

rm -f /etc/default/ubnt-zram-swap
echo "udm-zram-tune: removed /etc/default/ubnt-zram-swap (default lzo applies next boot)."
