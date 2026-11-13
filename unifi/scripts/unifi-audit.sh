#!/usr/bin/env bash
# unifi-audit — read-only PASS/FAIL audit of the UDM Pro's out-of-band
# settings (systemd units, iptables/ipset, IPv6 PBR/ndppd, resolver) and the
# controller values they rely on (WAN SLA, usg, networkconf, QoS, traffic
# routes).
# Streams udm-audit.sh to the UDM over ssh; exits non-zero if any check fails.
# Used from `make unifi/audit`. The F2886Q ONU is not covered here — use
# `make unifi/f2886q-plan` for that.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

log audit "UDM=$UDM — running on-box checks"
ssh "$UDM" 'bash -s' < "$UNIFI_SCRIPTS/udm-audit.sh"
