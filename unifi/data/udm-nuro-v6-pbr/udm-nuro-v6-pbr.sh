#!/bin/bash
#
# udm-nuro-v6-pbr.sh — re-apply IPv6 source-based PBR for NURO sub-/64 LAN
# prefixes whenever udapi-server flushes the kernel rule table.
#
# Background: Default/Media VLAN clients hold NURO prefixes (:29f1::/64,
# :29f2::/64) that are sub-prefixes of our manual static prefix on F2886Q.
# Without a source-based rule, forwarded egress hits ip -6 rule 32000 (main)
# which has a default route via eth8 (BB.excite). BB.excite's upstream ISP
# BCP38-drops the mismatched NURO source — v6 Private DNS (DoT) from these
# devices then stalls, and Android Strict Private DNS surfaces this as a
# "no internet" / Wi-Fi join problem.
#
# udapi-server flushes ip -6 rules whenever it reconciles (UI change, WAN
# SLA commit, restart, boot), so a 60s timer re-adds the rules whenever they
# go missing. (Until 2026-10-20 udm-sla-tune.sh also SIGHUPed udapi-server.)
#
# Idempotent: if both expected rules are present, exits silently. Only when
# a rule is missing does it add it (and log once).
#
# Memory: udm-pro-nuro-v6-ndp-proxy (describes the full :29f1/:29f2 PBR +
# ndppd design this rule set belongs to).
#
set -uo pipefail

PRIO1=30000
PRIO2=30001
PFX1=240d:f:fc4:29f1::/64
PFX2=240d:f:fc4:29f2::/64
TABLE=201.eth10

log() { logger -t udm-nuro-v6-pbr "$*"; }

ensure() {
    local prio=$1 pfx=$2
    # ip -6 rule show by priority uniquely identifies our rule and avoids
    # grep-ing the whole table (noisy with UBIOS fwmark rules).
    if ip -6 rule show priority "$prio" | grep -q "from $pfx lookup $TABLE"; then
        return 0
    fi
    # Delete any stale entry at this priority before adding (defence against
    # a reused priority pointing somewhere unexpected).
    ip -6 rule del priority "$prio" 2>/dev/null || true
    if ip -6 rule add from "$pfx" lookup "$TABLE" priority "$prio"; then
        log "re-added rule prio=$prio from=$pfx lookup=$TABLE"
    else
        log "FAILED to add rule prio=$prio from=$pfx"
        return 1
    fi
}

rc=0
ensure "$PRIO1" "$PFX1" || rc=1
ensure "$PRIO2" "$PFX2" || rc=1
exit "$rc"
