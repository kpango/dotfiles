#!/usr/bin/env bash
# unifi-audit — read-only PASS/FAIL audit of the UDM Pro's out-of-band
# settings (systemd units, Tailscale R2/R3, iptables/ipset, IPv6 PBR/ndppd,
# resolver) and the controller values they rely on (WAN SLA, usg, networkconf,
# QoS, traffic routes).
# Runs udm-audit.sh locally or over ssh; exits non-zero if any check fails.
# Used from `make unifi/audit`. The F2886Q ONU is not covered here — use
# `make unifi/f2886q-plan` for that.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

log audit "UDM=$UDM — running on-box checks"
if is_local; then
  udm_local_bash "bash $(printf %q "$UNIFI_SCRIPTS/udm-audit.sh")"
else
  udm_ssh "$UDM" 'bash -s' < "$UNIFI_SCRIPTS/udm-audit.sh"
fi
