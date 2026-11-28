#!/bin/bash
# bootstrap-packages.sh — idempotently ensure OS packages and core daemons
# (unifi-native-guard pins, nextdns CLI + unit + /etc/nextdns.conf, ndppd,
# sshpass, tailscale) are installed after a firmware update or factory reset.
set -euo pipefail

GUARD=/data/unifi-native-guard/guard.sh
PROTECTED=/data/unifi-native-guard/protected-packages.sh
NEXTDNS_UNIT=/etc/systemd/system/nextdns.service

if [ -x "$GUARD" ]; then
    "$GUARD" pins >/dev/null
fi

pkg_installed() {
    dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -qx 'install ok installed'
}

missing=()
command -v nextdns >/dev/null 2>&1 || [ -x /data/.nextdns-recover ] || pkg_installed nextdns || missing+=(nextdns)
command -v ndppd >/dev/null 2>&1 || pkg_installed ndppd || missing+=(ndppd)
command -v sshpass >/dev/null 2>&1 || pkg_installed sshpass || missing+=(sshpass)

if [ "${#missing[@]}" -gt 0 ]; then
    echo "[bootstrap] missing packages: ${missing[*]}"
    if [[ " ${missing[*]} " == *" nextdns "* ]]; then
        mkdir -p /usr/share/keyrings /etc/apt/sources.list.d
        if [ ! -s /usr/share/keyrings/nextdns.gpg ]; then
            curl -fsSL https://repo.nextdns.io/nextdns.gpg -o /usr/share/keyrings/nextdns.gpg
        fi
        cat > /etc/apt/sources.list.d/nextdns.list <<'EOF'
deb [signed-by=/usr/share/keyrings/nextdns.gpg] https://repo.nextdns.io/deb stable main
EOF
    fi

    UPDATE_OUTPUT=$(apt-get update 2>&1 || true)
    UNEXPECTED_FAILURES=$(printf '%s\n' "$UPDATE_OUTPUT" | grep -E 'Failed to fetch|^E: ' | grep -v -E 'apt-beta\.artifacts\.ui\.com|apt-release-candidate\.artifacts\.ui\.com' || true)
    if [ -n "$UNEXPECTED_FAILURES" ]; then
        printf '%s\n' "$UNEXPECTED_FAILURES" >&2
        exit 1
    fi

    if [ -x "$GUARD" ]; then
        "$GUARD" preflight
    fi

    SIM=$(DEBIAN_FRONTEND=noninteractive apt-get -s install --no-install-recommends "${missing[@]}")
    if [ -x "$PROTECTED" ]; then
        prot_regex=$("$PROTECTED" | awk '{print $1}' | paste -sd'|' -)
        if [ -n "$prot_regex" ] && printf '%s\n' "$SIM" | grep -E "^(Inst|Remv) ($prot_regex) " >/dev/null; then
            echo "[bootstrap] ABORT: apt-get install would touch Ubiquiti-protected package(s):" >&2
            printf '%s\n' "$SIM" | grep -E "^(Inst|Remv) ($prot_regex) " >&2
            exit 1
        fi
    fi

    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
    if [ -x "$GUARD" ]; then
        "$GUARD" verify
    fi
fi

# Recover /usr/bin/nextdns from /data/.nextdns-recover if wiped while /data remained.
if [ ! -x /usr/bin/nextdns ] && [ -x /data/.nextdns-recover ]; then
    cp -f /data/.nextdns-recover /usr/bin/nextdns
    chmod 0755 /usr/bin/nextdns
fi

if [ -f /data/nextdns.conf ]; then
    ln -sfn /data/nextdns.conf /etc/nextdns.conf
fi

DESIRED_UNIT=$(cat <<'UNIT'
[Unit]
Description=NextDNS DNS53 to DoH proxy.
Wants=nss-lookup.target network-online.target
After=nss-lookup.target network-online.target

[Service]
StartLimitInterval=5
StartLimitBurst=10
Environment=SERVICE_RUN_MODE=1
ExecStartPre=-/bin/cp -f /usr/bin/nextdns /data/.nextdns-recover
ExecStartPre=-/bin/cp -f /data/.nextdns-recover /usr/bin/nextdns
ExecStart=/usr/bin/nextdns run
RestartSec=120
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
UNIT
)

TMP_UNIT=$(mktemp)
trap 'rm -f "$TMP_UNIT"' EXIT
printf '%s\n' "$DESIRED_UNIT" > "$TMP_UNIT"
if [ ! -f "$NEXTDNS_UNIT" ] || ! cmp -s "$TMP_UNIT" "$NEXTDNS_UNIT"; then
    install -m 0644 "$TMP_UNIT" "$NEXTDNS_UNIT"
    systemctl daemon-reload
fi

if ! systemctl is-enabled --quiet nextdns.service 2>/dev/null; then
    systemctl enable nextdns.service >/dev/null
fi
if ! systemctl is-active --quiet nextdns.service 2>/dev/null; then
    systemctl start nextdns.service
fi

if ! command -v tailscale >/dev/null 2>&1 && [ -x /data/tailscale/manage.sh ]; then
    echo "[bootstrap] restoring tailscale via /data/tailscale/manage.sh on-boot"
    /data/tailscale/manage.sh on-boot
fi
