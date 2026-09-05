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
