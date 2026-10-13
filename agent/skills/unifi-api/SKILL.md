---
name: unifi-api
description: Use when querying or configuring Ubiquiti UniFi network devices, sites, clients, WiFi, firewall, or statistics via local controller or cloud API. Covers authentication, endpoint selection, filtering, pagination, actions, and common operational recipes.
---

# UniFi Network API Reference (v10.4.57)

OpenAPI spec: `https://developer.ui.com/network/v10.4.57/openapi.json`
llms.txt: `https://developer.ui.com/network/v10.4.57/llms.txt`

## API Surfaces — Which to Use

| Surface                | Base URL                                                                         | Auth                            | When                                              |
| ---------------------- | -------------------------------------------------------------------------------- | ------------------------------- | ------------------------------------------------- |
| **Local Console**      | `https://{consoleIP}/proxy/network/integration`                                  | `X-API-KEY` header              | Local network access; kpango default (`10.0.0.1`) |
| **Cloud Connector**    | `https://api.ui.com/v1/connector/consoles/{consoleId}/proxy/network/integration` | `X-API-KEY` header              | Remote/VPN-less access via cloud                  |
| **Classic Controller** | `https://{consoleIP}/api/s/{site}`                                               | Session cookie + `X-Csrf-Token` | Older firmware; features not in Official v1       |

All local requests require `-k` (self-signed TLS).
API key generation: `unifi.ui.com` → Settings → API Keys.
Local key retrieval: `pass show unifi-api`.

## Authentication

```bash
KEY=$(pass show unifi-api)
BASE="https://10.0.0.1/proxy/network/integration/v1"
curl -sk -H "X-API-KEY: $KEY" -H "Accept: application/json" "$BASE/sites"
```

Classic Controller (when Official v1 lacks needed endpoint):

```bash
CTRL="https://10.0.0.1"
curl -sk -c /tmp/unifi_cookie -X POST "$CTRL/api/auth/login" \
  -H "Content-Type: application/json" -d '{"username":"ubnt","password":"ubnt"}'
CSRF=$(grep csrf /tmp/unifi_cookie | awk '{print $NF}')
curl -sk -b /tmp/unifi_cookie -H "X-Csrf-Token: $CSRF" "$CTRL/api/s/default/stat/device"
```

## Pagination & Filtering

All list endpoints share `?offset=N&limit=N&filter=...` query params.

Response envelope:

```json
{"offset": 0, "limit": 25, "count": 10, "totalCount": 42, "data": [...]}
```

Filter operators: `AND`, `OR`, `NOT` (compound expressions). Filter field names match response property names.

## Official v1 Endpoint Reference

All paths relative to `$BASE` (`/proxy/network/integration/v1`):

### Application & Sites

| Method | Path            | Description                |
| ------ | --------------- | -------------------------- |
| GET    | `/v1/info`      | Controller version, uptime |
| GET    | `/v1/sites`     | List all sites             |
| GET    | `/v1/countries` | Country list               |

### Devices

| Method | Path                                                                       | Description                                |
| ------ | -------------------------------------------------------------------------- | ------------------------------------------ |
| GET    | `/v1/pending-devices`                                                      | Devices awaiting adoption                  |
| GET    | `/v1/sites/{siteId}/devices`                                               | List adopted devices                       |
| POST   | `/v1/sites/{siteId}/devices`                                               | Adopt device                               |
| GET    | `/v1/sites/{siteId}/devices/{deviceId}`                                    | Device details (portTable, sysStats, etc.) |
| DELETE | `/v1/sites/{siteId}/devices/{deviceId}`                                    | Unadopt device                             |
| POST   | `/v1/sites/{siteId}/devices/{deviceId}/actions`                            | Device action (see below)                  |
| POST   | `/v1/sites/{siteId}/devices/{deviceId}/interfaces/ports/{portIdx}/actions` | Port action                                |
| GET    | `/v1/sites/{siteId}/devices/{deviceId}/statistics/latest`                  | Latest device stats                        |
| GET    | `/v1/sites/{siteId}/device-tags`                                           | List device tags                           |

**Device actions** (`action` field):

- `RESTART` — restart the device

**Port actions** (`action` field):

- `POWER_CYCLE` — PoE power cycle (useful for hung PoE devices)

```bash
# Restart a device
curl -sk -H "X-API-KEY: $KEY" -X POST "$BASE/sites/$SITE/devices/$DEV_ID/actions" \
  -H "Content-Type: application/json" -d '{"action":"RESTART"}'

# PoE power cycle port 7
curl -sk -H "X-API-KEY: $KEY" \
  -X POST "$BASE/sites/$SITE/devices/$DEV_ID/interfaces/ports/7/actions" \
  -H "Content-Type: application/json" -d '{"action":"POWER_CYCLE"}'
```

### Clients

| Method | Path                                            | Description       |
| ------ | ----------------------------------------------- | ----------------- |
| GET    | `/v1/sites/{siteId}/clients`                    | Connected clients |
| GET    | `/v1/sites/{siteId}/clients/{clientId}`         | Client details    |
| POST   | `/v1/sites/{siteId}/clients/{clientId}/actions` | Client action     |

**Client actions** (`action` field):

- `AUTHORIZE_GUEST_ACCESS` — authorize hotspot guest
- `UNAUTHORIZE_GUEST_ACCESS` — revoke guest access

### Networks & WiFi

| Method         | Path                                                 | Description            |
| -------------- | ---------------------------------------------------- | ---------------------- |
| GET            | `/v1/sites/{siteId}/networks`                        | List networks (VLANs)  |
| POST           | `/v1/sites/{siteId}/networks`                        | Create network         |
| GET/PUT/DELETE | `/v1/sites/{siteId}/networks/{networkId}`            | Network CRUD           |
| GET            | `/v1/sites/{siteId}/networks/{networkId}/references` | What uses this network |
| GET            | `/v1/sites/{siteId}/wifi/broadcasts`                 | List SSIDs             |
| POST           | `/v1/sites/{siteId}/wifi/broadcasts`                 | Create SSID            |
| GET/PUT/DELETE | `/v1/sites/{siteId}/wifi/broadcasts/{id}`            | SSID CRUD              |
| GET            | `/v1/sites/{siteId}/wans`                            | WAN interfaces         |

### Firewall & ACL

| Method               | Path                                            | Description       |
| -------------------- | ----------------------------------------------- | ----------------- |
| GET/POST             | `/v1/sites/{siteId}/firewall/policies`          | Firewall policies |
| GET/PUT              | `/v1/sites/{siteId}/firewall/policies/ordering` | Policy order      |
| GET/PUT/PATCH/DELETE | `/v1/sites/{siteId}/firewall/policies/{id}`     | Policy CRUD       |
| GET/POST             | `/v1/sites/{siteId}/firewall/zones`             | Firewall zones    |
| GET/PUT/DELETE       | `/v1/sites/{siteId}/firewall/zones/{id}`        | Zone CRUD         |
| GET/POST             | `/v1/sites/{siteId}/acl-rules`                  | ACL rules         |
| GET/PUT/DELETE       | `/v1/sites/{siteId}/acl-rules/{id}`             | ACL CRUD          |
| GET/PUT              | `/v1/sites/{siteId}/acl-rules/ordering`         | ACL order         |

### DNS, Hotspot, VPN, Switching

| Method   | Path                                          | Description                          |
| -------- | --------------------------------------------- | ------------------------------------ |
| GET/POST | `/v1/sites/{siteId}/dns/policies`             | DNS policies                         |
| GET/POST | `/v1/sites/{siteId}/hotspot/vouchers`         | Hotspot vouchers                     |
| DELETE   | `/v1/sites/{siteId}/hotspot/vouchers`         | Bulk delete vouchers (`?filter=...`) |
| GET      | `/v1/sites/{siteId}/vpn/servers`              | VPN servers                          |
| GET      | `/v1/sites/{siteId}/vpn/site-to-site-tunnels` | S2S tunnels                          |
| GET      | `/v1/sites/{siteId}/switching/lags`           | LAGs                                 |
| GET      | `/v1/sites/{siteId}/switching/mc-lag-domains` | MC-LAG domains                       |
| GET      | `/v1/sites/{siteId}/switching/switch-stacks`  | Switch stacks                        |
| GET      | `/v1/sites/{siteId}/radius/profiles`          | RADIUS profiles                      |
| GET      | `/v1/sites/{siteId}/traffic-matching-lists`   | Traffic matching lists               |

### DPI (Deep Packet Inspection)

| Method | Path                   | Description    |
| ------ | ---------------------- | -------------- |
| GET    | `/v1/dpi/applications` | DPI app list   |
| GET    | `/v1/dpi/categories`   | DPI categories |

## Error Response Schema

```json
{
  "code": "api.authentication.missing-credentials",
  "message": "Missing credentials",
  "requestId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "requestPath": "/v1/sites"
}
```

| HTTP    | Meaning                                       |
| ------- | --------------------------------------------- |
| 200/201 | OK                                            |
| 400     | Bad request / invalid body                    |
| 401     | Missing or invalid `X-API-KEY`                |
| 403     | Forbidden (insufficient scope)                |
| 404     | Resource not found                            |
| 429     | Rate limited — back off                       |
| 500     | Controller error (`requestId` for log lookup) |

## Common Recipes

### Bootstrap: site ID and device ID for Switch XG 10

```bash
KEY=$(pass show unifi-api)
BASE="https://10.0.0.1/proxy/network/integration/v1"

# Get site ID
SITE=$(curl -sk -H "X-API-KEY: $KEY" "$BASE/sites" | jq -r '.data[0].id')

# Find Switch XG 10 by name or MAC
DEV_ID=$(curl -sk -H "X-API-KEY: $KEY" "$BASE/sites/$SITE/devices" \
  | jq -r '.data[] | select(.name | test("XG")) | .id' | head -1)
```

### PoE usage per port on a switch

```bash
curl -sk -H "X-API-KEY: $KEY" "$BASE/sites/$SITE/devices/$DEV_ID" \
  | jq '.data.portTable[] | {port: .portIdx, name: .name, poe_power: .poe_power, poe_class: .poe_class}'
```

### Device stats (thermal, load, uptime)

```bash
curl -sk -H "X-API-KEY: $KEY" \
  "$BASE/sites/$SITE/devices/$DEV_ID/statistics/latest" | jq .
```

### List all connected clients with IP and hostname

```bash
curl -sk -H "X-API-KEY: $KEY" "$BASE/sites/$SITE/clients" \
  | jq '.data[] | {name: .name, ip: .ip, mac: .mac, vlan: .vlan}'
```

### Block client via Classic API (not in Official v1)

```bash
curl -sk -b /tmp/unifi_cookie -H "X-Csrf-Token: $CSRF" \
  -X POST "https://10.0.0.1/api/s/default/cmd/stamgr" \
  -H "Content-Type: application/json" \
  -d '{"cmd":"block-sta","mac":"aa:bb:cc:dd:ee:ff"}'
```

### Create hotspot voucher

```bash
curl -sk -H "X-API-KEY: $KEY" -X POST "$BASE/sites/$SITE/hotspot/vouchers" \
  -H "Content-Type: application/json" \
  -d '{"count":1,"expireDuration":60,"expireDurationUnit":"MINUTES"}'
```

## Classic API Supplement (features not in Official v1)

Base: `https://10.0.0.1/api/s/default`

| Path                      | Description                    |
| ------------------------- | ------------------------------ |
| `GET /stat/device`        | All devices (rich detail)      |
| `GET /stat/sta`           | Connected wireless clients     |
| `GET /stat/alluser`       | All clients incl. inactive     |
| `GET /stat/rogueap`       | Rogue/neighbor APs             |
| `GET /rest/wlanconf`      | WLAN (SSID) configurations     |
| `PUT /rest/wlanconf/{id}` | Update SSID                    |
| `GET /rest/networkconf`   | Network configs                |
| `POST /cmd/devmgr`        | Device mgmt (set-locate, etc.) |
| `POST /cmd/stamgr`        | Client mgmt (block, reconnect) |

## Notes

- `jq` required for all recipes.
- `-k` required for local controller with self-signed cert.
- Classic API cookie sessions expire; re-login on 401.
- Cloud Connector requires `consoleId` from `unifi.ui.com` — find it in the console URL.
- Pagination default limit varies by endpoint; always check `totalCount` vs `count`.

## SSH Access to the Console and Managed Devices

The console (UDM/UDM Pro/etc.) is commonly reached over Tailscale SSH when set up that way; a
Tailscale IP is dynamic — resolve it fresh via `tailscale status` rather than hardcoding a stale
one across sessions. Managed APs/switches often have no SSH key provisioned (password auth only)
— if your `~/.ssh/config` has host aliases for them, prefer those over raw IPs.

Credentials live in `pass` (exact entry names are per-deployment — check project memory for
which ones apply to your device):

- one entry typically holds the API key (see Authentication above)
- another typically holds the mgmt-account password, used for **both** SSH to the console's
  `root` account (often key-based there already) **and** password-auth SSH to AP/switch aliases

Never interpolate `pass show ...` directly into a remote SSH command string (`ssh host "$(pass
show x)..."`) — this can trip the harness's command-safety classifier and leaks the secret into
shell history/process args. For password-auth SSH to APs/switches, use a local `SSH_ASKPASS`
script instead of `sshpass` (often absent) or `expect` — use `mktemp` (not a fixed path) and set
permissions explicitly before anything can read it, to avoid a symlink-preplant/TOCTOU race on a
predictable `/tmp` filename:

```bash
ASKPASS=$(mktemp)
trap 'rm -f "$ASKPASS"' EXIT INT TERM
chmod 700 "$ASKPASS"
cat > "$ASKPASS" << 'EOF'
#!/bin/bash
pass show <your-mgmt-password-entry>
EOF
SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force \
  ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no <ap-alias> 'uptime' < /dev/null
```

## Package Safety — Never Let `apt upgrade` Touch UniFi-Native Packages

UniFi OS runs on a Debian (trixie) base with `/etc/apt/sources.list.d/ubiquiti.list` pointing at
Ubiquiti's own repo _alongside_ the standard Debian repos. Ubiquiti ships **custom builds** of
several packages (`iptables`/`libxtables12`/`libip4tc2`/`libip6tc2` with vendor iptables
extensions `dpi128`/`dyn_random`/`geoip`/`ubnt_mark`; `frr` for zebra/OSPF; `dnsmasq`, `openvpn`,
`ppp`, `keepalived`, `lldpd`, `miniupnpd`, `wireguard-tools`, `xl2tpd`,
`xtables-addons-common`, `iproute2`, and more) with **higher version numbers stamped on the
Debian side**. A plain `apt upgrade`/`apt dist-upgrade` — including one triggered incidentally
while installing an unrelated package — silently pulls the generic Debian build over the
Ubiquiti one wherever Debian's version compares higher, with two distinct failure modes observed
in production:

1. **ABI split, not a full downgrade**: the `iptables`/`iptables-restore` _binary_ and
   `libxtables.so.12` core library get replaced (new ABI) while individual extension `.so` files
   under `/usr/lib/aarch64-linux-gnu/xtables/` are left as the old vendor build (or vice versa,
   depending on which packages actually had matching Debian candidates) — the resulting **binary
   vs. extension-module ABI mismatch causes `iptables-restore` to SIGSEGV** on any ruleset that
   uses the affected extensions (TCPMSS, GeoIP), not merely fail cleanly. This is the direct
   mechanism behind a persistent "GatewayConfigurationError" (config apply crashes mid-write
   instead of committing) and silently-truncated GeoIP country lists (the crash cuts the rule
   list short partway through, which looks like a string-length limit but isn't one).
2. **Full package replacement**: `frr`/`libyang2` etc. get fully replaced, removing binaries
   (`/usr/sbin/zebra`) that udapi-server's config-apply pipeline depends on (OSPF), which trips
   the same GatewayConfigurationError rollback for unrelated reasons.

**Diagnose drift**: `dpkg -V <pkg>` (empty/`??5??????` output = files changed since install;
compare against `/var/lib/dpkg/info/<pkg>.md5sums`), `grep -B2 -A2 <pkg> /var/log/apt/history.log`
to date the replacement, `apt-cache policy <pkg>` to see whether the Ubiquiti-repo candidate is
still resolvable at all (it may not be, if Ubiquiti's own repo no longer serves an old version —
don't assume `apt-get install --reinstall` alone can restore the vendor build).

**Check for an already-maintained fix on the device before building a new one** — a prior
remediation may already exist as a small framework somewhere under `/data/` or
`/etc/apt/preferences.d/` that (a) pins the affected package set toward the vendor repo, (b)
preflight-checks `dist-upgrade` for would-be replacements before they happen, and (c) can restore
drifted files from the firmware's read-only lower layer (`/mnt/.rofs/...`), repackaging them for
`dpkg`. Check project memory for this device's specific path/tool name and run its own verify
step first before assuming a fresh repair is needed. Only recreate such a framework from scratch
if it's genuinely absent — and never duplicate it with an ad-hoc per-package `Pin-Priority: -10`
file, which starves `apt` of _any_ candidate for that package (including the vendor one) rather
than steering it toward the vendor repo.

## Non-Destructive Diagnostic Recipes

**Never** run a blanket `iptables -F`/`ip6tables -F` (any table) on this system to "reset" a
problem — NAT, fwmark-based policy routing, and Tailscale's own chains are all wired through the
same tables udapi-server manages, and flushing them independently of udapi-server's own state can
sever LAN routing/NAT until udapi-server rebuilds them (observed to cause a real outage). Before
touching a live ruleset, verify hypotheses non-destructively:

```bash
# Confirm a specific table's ruleset applies cleanly without touching the live kernel state
CHECK=$(mktemp)
iptables-save -t mangle > "$CHECK"
iptables-restore -w --counters --table mangle --noflush --test "$CHECK"
echo "exit: $?"   # 0 = would apply cleanly; 139 = SIGSEGV (see Package Safety above); 2 = parse error
rm -f "$CHECK"
```

**Diagnosing a stuck inform/API TCP handshake** (device shows stale `last_seen` in the
controller but ICMP/ARP to it work): check `conntrack -L | grep dport=8080` for entries stuck in
`SYN_RECV` — the controller's reply direction shows several retransmitted SYN-ACK packets that
never get ACKed back, indicating an L2-adjacent (not routing) hangup rather than a controller
software crash. Cross-check by fetching the same device's networkconf/device documents directly
via mongo (below) to rule out a config-level cause (e.g. a WAN network object with the `enabled`
field entirely absent — see "Direct MongoDB queries" below) before assuming it's purely transport-layer.

**Direct MongoDB queries** (when the local controller API itself is unresponsive/crashing —
`unifi-core`'s reverse proxy to the Java network app can wedge independently of udapi-server,
returning `HTTP:000`/`502`/`503` on `/proxy/network/*` while still answering `401` for
unauthenticated probes; a `systemctl restart unifi-core.service` often clears this, but get
explicit confirmation first — it has been observed to cascade into UniFi's own self-healing full
system reboot when the device's underlying state was already unhealthy, not the restart alone):

```bash
mongo --quiet --port 27117 --eval 'db.device.find({},{name:1,last_seen:1,_id:0}).toArray()' ace
mongo --quiet --port 27117 --eval 'db.networkconf.find({purpose:"wan"},{name:1,enabled:1,wan_type:1,_id:0}).toArray()' ace
```

The `ace` database backs the classic controller; `device`/`networkconf`/`power_supervisor` are
the collections most relevant to connectivity troubleshooting. A WAN `networkconf` document
missing its `enabled` field entirely (not `false` — _absent_) has been the root cause of a
persistent internal `mcad` error flood (`wan_man_get_primary(): UDAPI required field 'status' is
missing`, tens of thousands of log lines/hour) even while the interface itself forwards traffic
normally — fix via `PUT /proxy/network/api/s/default/rest/networkconf/{id}` (Classic REST API)
with the full existing document plus the single missing field, never a partial-document PUT.

## GeoIP: the DS-Lite Underlying-Interface Coverage Gap

On a DS-Lite WAN (`wan_type: dslite`), UniFi's own GeoIP enforcement only attaches to the
IPv4-in-IPv6 tunnel interface (`ip6tnl1`) — observed in production: native IPv6 traffic on the
tunnel's underlying physical WAN interface was passing normally while the tunnel interface's
`UBIOS_IN_GEOIP`/`UBIOS_OUT_GEOIP` chains showed the full configured country list applied. This
is a UniFi product gap, not a misconfiguration to "fix" through the UI. Verify on your own device
before assuming the gap applies: `ip6tables -L UBIOS_IN_GEOIP -n` (does it reference the physical
interface at all, vs. only being hooked into the DS-Lite tunnel's chains — check project memory
for which physical interface backs your DS-Lite WAN) and test actual reachability from a
GeoIP-blocked country's address over each path independently. The maintained workaround is a
standalone systemd path/timer unit scoped to that physical interface (path-triggered on
`udapi-net-cfg.json` changes) that mirrors the country list/direction into a **separate iptables
chain** that UniFi's own config-apply pipeline never touches — it must not reuse or write into
UniFi's own `UBIOS_IN_GEOIP`/`UBIOS_OUT_GEOIP` chains or `ipset`s, since udapi-server's own
reconciliation would then contend with it and could drop the supplemental rules on next apply.
