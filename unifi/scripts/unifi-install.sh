#!/usr/bin/env bash
# unifi-install — push dotfiles/unifi/{data,root}/ to UDM Pro via tar (local or ssh),
# bootstrap OS packages/hooks, and apply declarative controller state.
# Overwrite semantics: tar extraction replaces existing files. Idempotent per file content.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

DRY_RUN="${DRY_RUN:-0}"
SKIP_CONTROLLER="${SKIP_CONTROLLER:-0}"

log install "UDM=$UDM, DRY_RUN=$DRY_RUN, SKIP_CONTROLLER=$SKIP_CONTROLLER"

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

# push_dir LOCAL REMOTE — tar-pipe LOCAL into REMOTE on the UDM Pro.
push_dir() {
  local local_dir=$1 remote_dir=$2
  if [ "$DRY_RUN" = "1" ]; then
    log dry-run "would push $local_dir → $UDM:$remote_dir :"
    (cd "$local_dir" && find . -type f | sed 's|^\./|  |')
    return 0
  fi
  log push "$local_dir → $UDM:$remote_dir"
  (cd "$local_dir" && tar c .) | udm_pipe_in "tar x -C $remote_dir"
}

push_dir "$UNIFI_DATA" /data
push_dir "$UNIFI_ROOT" /root

api_key=$(resolve_api_key)

if [ "$DRY_RUN" = "1" ]; then
  if [ "$SKIP_CONTROLLER" != "1" ] && command -v go >/dev/null 2>&1 && [ -n "$api_key" ]; then
    UNIFI_API_KEY="$api_key" go run -C "$UNIFI_DIR/unifictl" . -dir "$UNIFI_DIR/controller" plan
  elif [ "$SKIP_CONTROLLER" != "1" ]; then
    log dry-run "UNIFI_API_KEY or go toolchain unavailable; skipping controller plan"
  fi
  log install "dry-run complete"
  exit 0
fi

# Normalise permissions: tar preserves local perms, but re-apply on the target
# in case anything was pushed with the wrong mode locally.
udm_exec 'find /data -maxdepth 4 -name "*.sh" -exec chmod +x {} \;
find /root -maxdepth 2 -name "*.sh" -exec chmod +x {} \;
chmod 644 /data/nextdns.conf 2>/dev/null || true'

# Ensure /data/unifi-api.key exists on the UDM before hooks / timers run.
if [ -n "$api_key" ]; then
  if ! udm_exec 'test -s /data/unifi-api.key'; then
    log install "restoring /data/unifi-api.key on $UDM"
    printf '%s\n' "$api_key" | udm_pipe_in 'umask 077 && cat > /data/unifi-api.key'
  fi
fi

# Bootstrap packages + post-install hooks + native systemd units + daemon-reload.
udm_exec /data/udm-post-install/post-install.sh

# Apply declarative UniFi controller state (zones, policies, TMLs, settings, devices).
if [ "$SKIP_CONTROLLER" != "1" ]; then
  if command -v go >/dev/null 2>&1; then
    [ -n "$api_key" ] || die "UNIFI_API_KEY could not be resolved (pass locked and missing from UDM)"
    log install "applying declarative controller config (unifictl)"
    UNIFI_API_KEY="$api_key" go run -C "$UNIFI_DIR/unifictl" . -dir "$UNIFI_DIR/controller" -yes apply
    log install "warming up dnsmasq DoT ipsets"
    udm_exec 'dig +short +time=3 @10.0.0.1 21553f.dns.nextdns.io A AAAA >/dev/null || true
dig +short +time=3 @10.0.3.1 kpango-pixel-21553f.dns.nextdns.io A AAAA >/dev/null || true'
  else
    log install "go toolchain unavailable; skipping controller apply"
  fi
fi

log install "done"
