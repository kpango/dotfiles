#!/usr/bin/env bash
# unifi-sync — single-command post-update UDM Pro convergence & verification:
#   1. Auto-fallback SSH (udmpro -> UDM_FALLBACK) if Tailscale isn't up yet after firmware update
#   2. Full idempotent deploy (`unifi-install.sh`)
#   3. Tailscale recovery convergence (waits for tailscale0 v4 IP if newly started, then re-wires hooks)
#   4. Optional maintenance (`WITH_UPDATE=1`) / ONU sync (`WITH_ONU=1`)
#   5. 3-stage completion verification: unifi-diff (0 drift), unifictl plan (0 diff), unifi-audit (0 FAIL)
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

UDM_FALLBACK="${UDM_FALLBACK:-root@10.0.0.1}"
WITH_UPDATE="${WITH_UPDATE:-0}"
SKIP_CONTROLLER="${SKIP_CONTROLLER:-0}"
WITH_ONU="${WITH_ONU:-0}"

resolve_api_key() {
  if [ -n "${UNIFI_API_KEY:-}" ]; then
    printf '%s' "$UNIFI_API_KEY"
    return 0
  fi
  local k=""
  if command -v pass >/dev/null 2>&1; then
    k=$(timeout 5 pass show unifi-api </dev/null 2>/dev/null || true)
  fi
  if [ -z "$k" ]; then
    k=$(udm_exec 'cat /data/unifi-api.key 2>/dev/null || cat /data/nextdns-client-names/api-key 2>/dev/null || cat /data/clean-clients.key 2>/dev/null' || true)
  fi
  printf '%s' "$k"
}

ORIG_UDM="$UDM"
USED_FALLBACK=0

# Stage 1: Reachability & auto-fallback (e.g. Tailscale wiped by UniFi OS update)
if ! is_local; then
  if ! udm_ssh -o ConnectTimeout=5 -o BatchMode=yes "$UDM" true 2>/dev/null; then
    if [ "$UDM" != "$UDM_FALLBACK" ] && udm_ssh -o ConnectTimeout=5 -o BatchMode=yes "$UDM_FALLBACK" true 2>/dev/null; then
      log sync "primary host '$UDM' unreachable; falling back to '$UDM_FALLBACK'"
      UDM="$UDM_FALLBACK"
      USED_FALLBACK=1
    else
      die "[sync] neither '$UDM' nor fallback '$UDM_FALLBACK' is reachable over SSH"
    fi
  fi
fi

# Wait for UniFi Network Controller API readiness after firmware update reboot
if [ "$SKIP_CONTROLLER" != 1 ]; then
  if ! udm_exec 'test ! -s /data/unifi-api.key || curl -sfk -m 5 -H "X-API-KEY: $(tr -d "[:space:]" < /data/unifi-api.key)" -H "Accept: application/json" https://127.0.0.1/proxy/network/integration/v1/sites | jq -er ".data[0].id" >/dev/null 2>&1'; then
    log sync "waiting up to 120s for UniFi Network API readiness"
    api_ready=0
    for _ in $(seq 1 24); do
      if udm_exec 'curl -sfk -m 5 -H "X-API-KEY: $(tr -d "[:space:]" < /data/unifi-api.key)" -H "Accept: application/json" https://127.0.0.1/proxy/network/integration/v1/sites | jq -er ".data[0].id" >/dev/null 2>&1'; then
        api_ready=1
        break
      fi
      sleep 5
    done
    [ "$api_ready" = 1 ] || die "[sync] UniFi Network API not ready within 120s"
  fi
fi

# Stage 2: Full deploy (/data, /root, apt pins, bootstrap packages, systemd hooks, controller apply)
log sync "stage 2/5: deploying dotfiles + hooks + controller config (UDM=$UDM)"
UDM="$UDM" SKIP_CONTROLLER="$SKIP_CONTROLLER" "$UNIFI_SCRIPTS/unifi-install.sh"

# Stage 3: Tailscale recovery convergence (only waits/re-wires if tailscale0 wasn't ready during post-install)
log sync "stage 3/5: verifying tailscale0 convergence"
if ! udm_exec 'ip -4 -o addr show dev tailscale0 2>/dev/null | grep -q .' 2>/dev/null; then
  log sync "tailscale0 IPv4 not up yet; waiting up to 60s for tailscale-install.service"
  ts_ready=0
  for _ in $(seq 1 12); do
    if udm_exec 'ip -4 -o addr show dev tailscale0 2>/dev/null | grep -q .' 2>/dev/null; then
      ts_ready=1
      break
    fi
    sleep 5
  done
  [ "$ts_ready" = 1 ] || die "[sync] tailscale0 did not obtain an IPv4 address within 60s"
  udm_exec 'systemctl start tailscale-dnsmasq.service tailscale-guard.service udm-dns-hijack.service && /data/udm-prio-tune/install.sh'
fi

if [ "$USED_FALLBACK" = 1 ] && [ "$ORIG_UDM" != "$UDM" ]; then
  if udm_ssh -o ConnectTimeout=5 -o BatchMode=yes "$ORIG_UDM" true 2>/dev/null; then
    log sync "primary host '$ORIG_UDM' recovered; switching verification target back"
    UDM="$ORIG_UDM"
  fi
fi

# Stage 4: Optional maintenance & ONU sync
if [ "$WITH_UPDATE" = 1 ]; then
  log sync "stage 4/5: running unifi-update (WITH_UPDATE=1)"
  UDM="$UDM" "$UNIFI_SCRIPTS/unifi-update.sh"
fi
if [ "$WITH_ONU" = 1 ]; then
  log sync "stage 4/5: applying F2886Q ONU state (WITH_ONU=1)"
  "$UNIFI_SCRIPTS/f2886q-apply.sh" apply
fi

# Stage 5: 3-stage completion verification gates
log sync "stage 5/5: gate 1 — md5 diff check"
UDM="$UDM" "$UNIFI_SCRIPTS/unifi-diff.sh"

if [ "$SKIP_CONTROLLER" != 1 ] && command -v go >/dev/null 2>&1; then
  log sync "stage 5/5: gate 2 — controller plan drift check"
  api_key=$(resolve_api_key)
  [ -n "$api_key" ] || die "[sync] UNIFI_API_KEY could not be resolved for controller plan check"
  plan_out=$(UNIFI_API_KEY="$api_key" go run -C "$UNIFI_DIR/unifictl" . -dir "$UNIFI_DIR/controller" plan)
  printf '%s\n' "$plan_out"
  if ! printf '%s\n' "$plan_out" | grep -qxF 'No changes. The controller matches unifi/controller/.'; then
    die "[sync] controller drift remains after install"
  fi
fi

log sync "stage 5/5: gate 3 — on-box & controller audit"
UDM="$UDM" "$UNIFI_SCRIPTS/unifi-audit.sh"

log sync "complete: deployed, 0 file drift, 0 controller drift, audit PASS (UDM=$UDM)"
