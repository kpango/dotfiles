# CONTEXT — UDM Pro × NextDNS × Tailscale 一体構成

本 CONTEXT は 2026-10-14 の設計面談 (`/grill-interview`) で決着した 17 の判断と、
その背景となる不変条件・責務境界・却下代替案を集約する Living Invariants。

後続の自分 / 他 agent (vald-reviewer / code-reviewer / 新規 subagent) は、本ファイルを
読んでから UDM Pro / NextDNS / Tailscale 周辺の変更を提案・レビューすること。

---

## 1. ドメイン用語集 (Domain Glossary)

- **profile 21553f**: NextDNS プロファイル ID。この設定全体の center of gravity。dotfiles /
  UDM Pro / Tailscale admin UI の全エンドポイントで同一 ID を参照する。
- **strict Zero Leak**: 「DNS クエリは profile 21553f 以外に **絶対に流れない**」設計方針。
  Cloudflare / Google / Quad9 等の public resolver を active config から全撤去し、
  NextDNS 到達不能時は DNS を失敗させる (fail-closed) ことで達成する。
- **fail-closed**: NextDNS 側 (CLI, 直接 IPv6, DoT SNI) が到達不能になった時に DNS を
  **意図的に止める** 挙動。失敗が可視化され、気付かぬ profile バイパスより望ましいという
  判断に基づく。復旧動線は UDM Pro 側 `cron.d/nextdns-healthcheck` (5 分間隔) +
  systemd auto-restart。
- **add-mac / add-subnet=32,128**: UDM Pro の NextDNS CLI (`/data/nextdns.conf`) が
  上流 DoH リクエストに付加する EDNS オプション。LAN クライアントの MAC と /32 (IPv4) /
  /128 (IPv6) subnet 情報を NextDNS に渡し、Dashboard Logs 上で端末名別の可視性を得る。
- **direct IPv6 endpoint**: `2a07:a8c0::21:553f` / `2a07:a8c1::21:553f`。NextDNS の anycast
  アドレスに profile ID 21553f を埋め込んだ IPv6 destination。source IP に非依存で profile
  が特定される → dynamic WAN や外出先環境でも profile が維持される。
- **DoT SNI**: `45.90.28.0#21553f.dns.nextdns.io` 形式。IP に `#servername` を付与する
  systemd-resolved の DNS-over-TLS 書式。SNI ホスト名が profile 特定の役目を担うため
  source IP に非依存。
- **Linked IP (deprecated)**: `45.90.28.74 / 45.90.30.74` + `219.104.143.196` の組み合わせ。
  NextDNS が source IP を見て profile を特定する古い方式。WAN IP が動的 (DS-Lite /
  NURO CGNAT) のため本構成では採用しない。NextDNS API に削除手段なく、cosmetic 残置。
- **CPE-ID (`add-cpe-id=21553f`)**: dnsmasq が上流 DNS クエリに付加するプロファイル識別子。
  anycast endpoint 経由でも profile 特定が可能な第 3 の手段。

---

## 2. システム不変条件 (System Invariants)

### Inv-1 (必須): 全 DNS クエリは profile 21553f を通る

| 経路                          | profile 識別手段                                              | 定義ファイル                                                        |
| ----------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------- |
| UDM Pro 内部 (nextdns CLI)    | DoH URL (`https://dns.nextdns.io/21553f`)                     | `unifi/data/nextdns.conf`                                           |
| UDM Pro 配下 LAN (IPv4)       | gateway `10.0.x.1` → dnsmasq → nextdns CLI (`127.0.0.1:5342`) | UniFi networkconf (Auto)                                            |
| UDM Pro 配下 LAN (IPv6)       | direct `2a07:a8c0::21:553f` (profile 埋込)                    | UniFi networkconf (明示)                                            |
| Linux host (systemd-resolved) | DoT SNI `IP#21553f.dns.nextdns.io`                            | `nix/core/settings.nix`, `network/dns/resolved.conf`                |
| Linux host (NM-dnsmasq)       | anycast + `add-cpe-id=21553f`                                 | `nix/modules/nixos/network/dnsmasq.nix`, `network/dns/dnsmasq.conf` |
| Docker container              | direct `2a07:a8c0::21:553f`                                   | `dockers/daemon.json`                                               |
| 素の resolv.conf consumer     | direct `2a07:a8c0::21:553f`                                   | `network/dns/resolv.dnsmasq.conf`, `arch/resolv.conf`               |

### Inv-2 (必須): fail-closed、FallbackDNS 空、public resolver 一切なし

- systemd-resolved: `services.resolved.settings.Resolve.FallbackDNS = ""` 明示 (NixOS の
  compiled-in default = Cloudflare/Google を無効化)
- dotfiles `network/dns/*.conf` から Cloudflare/Google/Quad9 全撤去
- UDM Pro DHCP 配布 DNS からも public resolver 全撤去
- `DNSOverTLS=yes` (strict), `DNSSEC=allow-downgrade`

### Inv-3 (必須): source IP 非依存の経路のみ

- WAN は動的 (BB.excite = DS-Lite CGNAT, NURO = NURO 機器 NAT) のため
  Linked IP `45.90.28.74` を active 配置に含めない
- 全経路は "profile 識別子 ∈ (dest IP / SNI / URL path / CPE-ID)" のいずれかで特定

### Inv-4 (必須): NextDNS CLI は interface binding なし (default-route 追従)

- `/data/nextdns.conf` の `listen localhost:53` のみ (bind interface 無し)
- WAN failover 時に default route が WAN1 (DS-Lite) → WAN2 (NURO) に切替わっても
  nextdns CLI の outbound DoH は追従する (socket 再接続時に新 default を使用)

### Inv-5 (必須): IoT VLAN は DNS 強制経路のみ

4 firewall policies が `aa310d5b-67a9-4774-b679-76852acd1ed1` (IoT) に対して active:

| ID         | 内容                               |
| ---------- | ---------------------------------- |
| `6514bc66` | BLOCK IoT → External TCP:853 (DoT) |
| `da102537` | BLOCK IoT → External UDP:853 (DoQ) |
| `ce1962da` | BLOCK IoT → (!10.0.10.1) TCP:53    |
| `52cfb2c4` | BLOCK IoT → (!10.0.10.1) UDP:53    |

IoT 機器が 8.8.8.8 等を硬コードしても遮断され、DHCP 配布の gateway `10.0.10.1` にフォールバック。
壊れる機器が発生したら allowlist (特定 IP 除外) で個別対応。

### Inv-6 (推奨): NextDNS allowlist に Tailscale インフラドメインを常駐

NextDNS blocklist が `api.tailscale.com` 等を誤爆するケースあり。以下を profile 21553f の
allowlist に登録済:

- `api.tailscale.com`
- `controlplane.tailscale.com`
- `login.tailscale.com`

### Inv-7 (推奨): nextdns-healthcheck による自動復旧

UDM Pro 上で以下が動作:

- `/data/nextdns-healthcheck.sh` (本体、5 分間隔で `dig @127.0.0.1 nextdns.io` probe、
  失敗時に `systemctl restart nextdns`、再失敗時に `systemctl restart dnsmasq`)
- `/data/on_boot.d/30-nextdns-healthcheck-install.sh` (boot 時に `/etc/cron.d/*` 再生成)
- `/etc/cron.d/nextdns-healthcheck` (cron entry、`*/5 * * * * root ...`)

### Inv-8 (推奨): Tailscale `autoApprovers` で route/exit node 自動承認

ACL (Access Controls) に以下が追加済:

```json
"autoApprovers": {
  "routes": {
    "10.0.0.0/24":  ["autogroup:admin"],
    "10.0.1.0/29":  ["autogroup:admin"],
    "10.0.3.0/26":  ["autogroup:admin"]
  },
  "exitNode": ["autogroup:admin"]
}
```

将来 LAN を追加した時の手動承認を省略する。`autogroup:admin` = kpango 単独の tailnet なので
other-user 誤 advertise のリスクなし。

---

## 3. 責務境界と入出力規約 (Boundary & Contracts)

### 3.1 コンポーネント別の責務

| 層                                           | 責務                                                                | 禁止                                               |
| -------------------------------------------- | ------------------------------------------------------------------- | -------------------------------------------------- |
| UDM Pro `/data/nextdns.conf`                 | profile 21553f の DoH 設定・CLI 稼働・add-mac/add-subnet 送信       | public resolver fallback 追加禁止                  |
| UDM Pro `/run/dnsmasq.*` (udapi-server 生成) | LAN DHCP → gateway DNS → nextdns CLI の経路確立                     | 直接編集禁止 (再生成される)                        |
| UniFi networkconf (API)                      | DHCP DNS 配布 (IPv4 Auto = gateway, IPv6 = NextDNS direct)          | public DNS 追加禁止                                |
| UniFi firewall-policies (API)                | IoT VLAN の DNS 経路強制 (Inv-5 の 4 policies)                      | 他 VLAN に拡張時は要 Grill 再面談                  |
| UniFi setting/doh                            | **off** (dnscrypt-proxy 停止、CLI 一本化)                           | state=custom に戻す場合は Grill 面談               |
| dotfiles `nix/core/settings.nix`             | NextDNS 定数の SSoT (profile ID / anycast / direct IPv6 / hostname) | public DNS 定数の復活禁止                          |
| dotfiles `network/dns/*.conf`                | 非 Nix Arch host 用の raw conf (`FallbackDNS=` 空、NextDNS only)    | 旧 Cloudflare/Quad9 の復活禁止                     |
| dotfiles `dockers/daemon.json`               | コンテナ DNS = Tailscale + NextDNS direct IPv6                      | public DNS の追加禁止                              |
| dotfiles `unifi/`                            | UDM Pro SSoT (data/root/etc-snapshot、backup は 2026-10-14 撤去)    | secrets (tailscaled.state / profile-data) 混入禁止 |
| UDM Pro `/data/nextdns-client-names/`        | UniFi クライアント名 → `/etc/hosts.dnsmasq` (5 分毎、Q19)           | `api-key` の git 取り込み禁止                      |
| UniFi Content Filtering                      | **off** (3 policy とも disabled、Q18)                               | 再有効化は NextDNS の端末識別を壊す (Q18 参照)     |

### 3.2 データフロー不変

```
LAN client (IPv4) ─DHCP で配布─▶ gateway 10.0.x.1
   └─▶ UDM Pro dnsmasq :53 (add-mac/add-subnet 付与)
      └─▶ nextdns CLI 127.0.0.1:5342
         └─▶ DoH https://dns.nextdns.io/21553f (over WAN1 default route)

LAN client (IPv6) ─DHCPv6/RA (dns auto = gateway 自身, Q20)─▶ UDM Pro dnsmasq :53
   └─▶ IPv4 と同じ経路 (add-mac/add-subnet → nextdns CLI → DoH)
   (2026-10-17 以前は 2a07:a8c0::21:553f を直接配布しており、IPv6 で問い合わせる端末は
    NextDNS 上で無名だった)

端末が自前で DoT する場合 (Android Private DNS 等) ─▶ NextDNS 直接 (UDM を通らない)
   └─▶ 端末識別はホスト名 `<端末名>-21553f.dns.nextdns.io` を端末側で設定した場合のみ

tailnet client ─MagicDNS 100.100.100.100─▶ Tailscale admin UI の NextDNS DoH
   (profile ID は Tailscale admin DNS で設定済、現状の DoH stamp は NextDNS-21553f)

systemd-resolved on host ─DoT─▶ 2a07:a8c0::#21553f.dns.nextdns.io  (SNI auth)
   └─▶ FallbackDNS 空 → 失敗時は fail-closed

dnsmasq (NetworkManager, host) ─anycast + add-cpe-id=21553f─▶ 2a07:a8c0::
   └─▶ NextDNS 側は CPE-ID から profile を特定

Docker container ─daemon.json dns:[]─▶ 100.100.100.100 (tailnet) /
                                       2a07:a8c0::21:553f (profile 直接)
```

### 3.3 エラー処理規約

- NextDNS 到達不能 → DNS 失敗 (fail-closed)。public resolver に逃がさない
- UDM Pro nextdns CLI 停止 → systemd auto-restart (RestartSec=120s) + cron healthcheck
  5 分間隔で `dig` probe + restart が二重の safety-net
- WAN1 停止 → UniFi 側 WAN failover が default route を書き換える → nextdns CLI の
  DoH outbound socket 再接続時に WAN2 経由になる (実機 failover テスト未実施、要注意)
- NextDNS が特定ドメインを誤爆 (例: Tailscale) → NextDNS allowlist 追加で解決。
  API key は `pass show nextdns`

---

## 4. 検討された選択肢と決定根拠 (Considered Options & Rationale)

| #       | テーマ                               | 決定                                                                                       | 却下した代替                                                     | 理由                                                                                                                                                                                                                                                                                 |
| ------- | ------------------------------------ | ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Q1      | dotfiles rollout 戦略                | B: 即 commit + Arch host 反映、NixOS rebuild は defer                                      | A (全機即 deploy) / C (deploy なし)                              | NixOS rebuild は長時間ビルド伴うため user 対面時間を取る                                                                                                                                                                                                                             |
| Q2      | Tailscale exit node 維持             | B: 現状維持 + 用途コメント                                                                 | A (削除) / C (有効化のみ記録)                                    | 削除より "念のため残置" のリスク低                                                                                                                                                                                                                                                   |
| Q3      | IoT DNS 強制                         | A: full lockdown (DoT 853 + DNS 53 bypass block、合計 4 policies)                          | B (DoT のみ) / C (skip) / D (段階的)                             | user 把握ベースで full lockdown を即適用、壊れる機器は allowlist 対応                                                                                                                                                                                                                |
| Q4      | Tailscale `autoApprovers`            | A: 全 LAN route + exit node を admin 自動承認                                              | B (手動継続) / C (route のみ)                                    | 現在の手動承認を次回繰り返さない、ACL 追記 1 ブロック                                                                                                                                                                                                                                |
| Q5      | UniFi WiFi SSID DNS inheritance 検査 | A: 検査実施 (結果: 3 SSID 全て VLAN から継承、override なし)                               | B (未確認) / C (意図的 override 容認)                            | 10 秒検査で leak path 排除確定                                                                                                                                                                                                                                                       |
| Q6      | nextdns CLI 停止検知                 | B: cron healthcheck (5 分間隔 dig + 自動 restart)                                          | A (systemd のみ) / C (通知付) / D (Prometheus)                   | fail-closed 設計の最小 safety-net、追加依存ゼロ                                                                                                                                                                                                                                      |
| Q7      | NextDNS Security blocks 有効化       | A + untrustedCertificates + freeHostingDomains + ddns 計 6 項目                            | B (低中FPまで) / C (現状維持) / D (full lockdown)                | user の使用パターンを尊重しつつ守備力追加                                                                                                                                                                                                                                            |
| Q8      | NextDNS log 保持                     | A: 現状維持 (90d / US / full logging)                                                      | B (EU 移動) / C (短縮) / D (24h+EU) / E (完全無効)               | Dashboard の端末別時系列分析を最優先                                                                                                                                                                                                                                                 |
| Q9      | NextDNS CLI 性能設定                 | D: `max-ttl 5m` + `cache-max-age 5m` (cache 二重化)                                        | A (現状 `max-ttl 5s`) / B (`max-ttl 5m` のみ) / C (TTL 制限解除) | upstream query 数を 60 倍削減 + cache で性能向上                                                                                                                                                                                                                                     |
| Q10     | NextDNS Parental Control             | A: 全 OFF 維持 (`blockBypass: true` のみ既存)                                              | B (safeSearch) / C (service blocks) / D (full lockdown)          | 単独 kpango 利用で制限不要                                                                                                                                                                                                                                                           |
| Q11     | NextDNS Block Page                   | A: 現状維持 (off)                                                                          | B (on)                                                           | HTTPS 全盛で block page は visible にならない                                                                                                                                                                                                                                        |
| Q12     | NextDNS Linked IP cleanup            | C3: 残置 + CONTEXT.md 注記 (API 削除手段なし)                                              | A (手動削除) / B (support request)                               | NextDNS API に unlink endpoint 不在、Dashboard web UI にも UI なし、cosmetic 問題のみで実害ゼロ                                                                                                                                                                                      |
| Q13     | Backup 永続化                        | A: dotfiles/unifi/ SSoT に移行 (user asset のみ、controller state は UniFi Cloud に任せる) | B (個人 persistent) / C (破棄) / D (UDM Pro 内保存)              | user 作成 script/config は git で、UniFi Cloud が shadow 済の controller state は dotfiles に含めない (2026-10-14 incident: controller JSON ダンプが WPA/SSH/SSO 秘密を平文で含み public GitHub に流出、`backup/` ディレクトリと `unifi-pull.sh` の API dump 機能を撤去して縮小した) |
| Q14     | Tailscale 他ノード key expiry        | 検査結果: 23/24 で既に無効化済、残 1 (lymJNQKRXYFWR) は Q15/Q16 で削除                     | —                                                                | 検査により action 不要と確定                                                                                                                                                                                                                                                         |
| Q15/Q16 | Tailscale offline ノード整理         | A: 1 年以上 offline + 不審 15 台一括削除                                                   | B (14 台) / C (1 台) / D (維持)                                  | tailnet admin UI 整理、戻ってきた際は再登録される                                                                                                                                                                                                                                    |
| Q18     | UniFi Content Filtering (2026-10-17) | 3 policy とも disabled。SafeSearch と成人向けブロックは NextDNS (`safeSearch: true`、category `porn`) へ移管 | 維持 / IoT のみ維持 | CF は LAN の :53 を coredns(127.0.0.1:1053) へ DNAT し、coredns → dnsmasq → nextdns の順に転送するため、dnsmasq/nextdns から見た送信元が全て 127.0.0.1 になり `add-mac`/`report-client-info` が無効化されていた (tcpdump で確認)。広告ブロックは NextDNS の blocklist が上位互換 |
| Q19     | UniFi クライアント名の NextDNS 連携  | `/data/nextdns-client-names/sync.sh` (5 分毎 timer) が Integration API から名前+IP(+同 MAC の IPv6) を取り `/etc/hosts.dnsmasq` を生成 | DHCP/mDNS 名のみ / 手書き hosts / `/usr/bin/mongo` シム | NextDNS CLI の UniFi 名取得は MongoDB 前提で Network 11.0.83+ (PostgreSQL) では無効。hosts ソースは IP で引かれ、DHCP リースに MAC 由来の名前がある端末はそちらが優先される (2026-10-17 時点 43 台中 17 台)。mongo シムは firmware 所有物を差し替えるため却下 |
| Q20     | LAN の IPv6 DNS 配布先               | 3 LAN とも `dhcpdv6_dns_auto: true` (UDM 自身) | 現状維持 (NextDNS 直接) / IoT 先行 | NextDNS 直接配布では IPv6 優先の端末が UDM を通らず無名になる。UDM が単一経路になるのは IPv4 で既に同じ |
| Q17     | Split DNS LAN domain                 | C: skip (現状維持、tailnet 内は MagicDNS で足りる)                                         | A (home.arpa 実装) / B (枠組みのみ) / D (不要判定)               | fix_plan 自体が条件付き保留、必要時 Option A で遅延展開可能                                                                                                                                                                                                                          |

---

## 5. 既知の制約と非目標 (Constraints & Non-Goals)

### 制約

- **NextDNS Linked IP `219.104.143.196` 削除不可**: v2 API に unlink endpoint 存在せず
  (DELETE/PATCH 試行全て 404 or 400、Dashboard web UI にも unlink UI 無し)。
  現在どの client も linked IP endpoint `45.90.28.74/.74` を叩いていないため実害ゼロで
  cosmetic 残置。将来 NextDNS 側で機能追加されたら再評価。
- **WAN failover 時の nextdns CLI 挙動 (未実機テスト)**: nextdns プロセスは `ip rule` の
  default route `201.ip6tnl1` (WAN1 DS-Lite) に乗る設計。WAN1 停止時に UniFi が default
  route を書き換えると TCP timeout 後に nextdns が再接続して WAN2 に切り替わる想定だが、
  実機 failover テスト未実施。問題が出たら `/data/nextdns-healthcheck.sh` 側で検知される。
  部分的な実地観測 (2026-10-16 23:25〜10-17 01:20): WAN1 の DS-Lite (IPv4) だけが落ち、IPv4 は
  WAN2 へ failover、eth8 の native IPv6 は生存していた間、nextdns は IPv6 の DoH endpoint
  (`[2a07:a8c1::]:443` 等) に接続したまま解決を継続し、healthcheck は一度も発火しなかった。
  WAN1 の IPv6 まで落ちるケースは依然未観測。
- **IPv4 DHCP DNS を "完全に空" にできない**: UniFi dnsmasq は `dhcpd_dns_enabled: true`
  - 全エントリ空にしてもゲートウェイ IP を自動補完する (本 CONTEXT 作成時に実機確認)。
    IPv4 クライアントは `10.0.x.1` 経由で UDM Pro dnsmasq → nextdns CLI → NextDNS DoH を
    通る (結果として Zero Leak 不変は保たれている)。
- **UDM Pro の `/etc/` は firmware update で wipe される**: 本構成は `/data/on_boot.d/*.sh`
  と `/data/<component>/install.sh` が boot 時 or 手動実行で `/etc/` を再構築する。
  dotfiles 側は `/data/` を authoritative とし、`unifi/etc-snapshot/` は参照のみ。
  UniFi OS 自体は `/data/on_boot.d` を実行しないため、`make unifi/install` が配置する
  `udm-boot.service` がその実行を担う (2026-10-17 以前は実行されておらず sysctl が再起動で消えていた)。
  2026-10-16 の UniFi OS 6.0.13 更新では `/etc` overlay (upperdir `/mnt/.rwfs/data`) は残り、
  `/usr/bin/nextdns` と `/etc/apt/preferences.d/30-unifi-native-protect` だけが消えた
  (前者は nextdns.service の ExecStartPre が `/data/.nextdns-recover` から、後者は `update.sh` の
  `guard.sh pins` が復元)。
- **NixOS host の rebuild は本 commit 以降 user 手動**: `dotfiles/install` は Arch host で
  即反映されるが、NixOS host は user が `sudo nixos-rebuild switch --flake .#desk-threadripper`
  を実行するまで旧設定のまま。

### 非目標

- **UniFi controller state の shadow (`setting.json` / `wlanconf.json` / `networkconf.json` 等)**:
  UniFi Cloud が既に backup 済、かつこれらの JSON は WPA2 PSK / SSH credentials / SSO token /
  API token を平文で含むため、git に取り込むと secret leak の原因になる (下記 incident 参照)。
  `unifi/scripts/unifi-pull.sh` は user script 側のみ pull、controller API は一切叩かない。
- **Tailscale ACL 全面リファクタ**: 現在の ACL は wide-open (`acls:[{action:accept, users:["*"], ports:["*:*"]}]`)、
  単独 kpango tailnet 前提。他ユーザー共有が始まったら要再設計。
- **IoT 機器の allowlist (DNS redirect 例外)**: Q3 で lockdown 済、壊れる機器が実際に
  出てから個別対応 (事前の予防的 allowlist は作らない)。
- **NextDNS Parental Control の追加カテゴリ**: Q18 で `porn` + SafeSearch のみ移管 (Q10 を更新)。
  それ以上のカテゴリ/サービスブロックは family/guest WiFi 展開時に再検討。
- **LAN hostname (home.arpa / Split DNS)**: tailnet 内は MagicDNS で代替、必要時に Q17
  Option A で遅延展開。
- **Mongo 直編集での UniFi config 変更**: controller API で代替可能なため使わない
  (controller cache 整合性のため)。
- **本番 kubectl/helm 操作**: security-gate hook が別途ブロック。本 CONTEXT の対象外。

---

## 7. Incident log

### 2026-10-14 — UniFi controller JSON dump leak + remediation

- **何が起きた**: 2026-10-14 UTC の `feat(unifi)` commit (旧 SHA `ea21b2a1`、本 CONTEXT 更新時点
  では history-rewrite 済) で `unifi/backup/<ts>/unifi-api/` 配下に `setting.json` /
  `wlanconf.json` / `networkconf.json` の生ダンプが入り、kpango/dotfiles (public GitHub mirror)
  に push された。これらは UniFi Controller が返す `x_passphrase` (WPA2 PSK) / `x_ssh_password` /
  `x_sso_token` / `x_api_token` / `x_private_key` / `x_mesh_psk` / `x_element_psk` 等を平文で
  含んでいた。
- **検知**: user 指示による `grep -rE '"(x_passphrase|x_password|...)":"'` スキャン。
  18 unique literal の leak を確認。
- **現場対応 (本セッション内で完了)**:
  1. working tree の 3 ファイルを `unifi/scripts/redact-json.sh` (jq ベースの key-pattern walker)
     で redact
  2. `git-filter-repo --replace-text` で全 branch の全 blob を対象に 17 literal を `<redacted>`
     に置換
  3. force-push 準備 (hook security-gate が block するため user 手動実行)
  4. `unifi/scripts/unifi-pull.sh` から controller API dump 機構を削除、`unifi/backup/` ディレクトリ
     撤去
  5. `unifi/.gitignore` に `backup/` と `*.raw.json` 追加して再発防止
- **残対応 (user 側必須、具体値は意図的に非掲載)**:
  - 全 WPA2 PSK の rotation (`kpango-home` / `kpango-game` / `kpango-iot` の 3 SSID)
  - UDM Pro device SSH password rotation
  - UniFi SSO token 失効 (全セッション logout → 再ログイン)
  - UniFi `x_api_token` 失効と再発行 (Settings → Control Plane → Integrations)
  - WireGuard `x_private_key` の該当 tunnel 再生成 (使用箇所要調査)
  - Mesh/Element radio key は controller が再 adopt で自動再生成されるので手動 rotation 不要
  - GitHub Support への cached blob purge request (強く推奨)
- **再発防止構造**:
  - `unifi/` 自体の scope を user script 側に限定 (controller state は UniFi Cloud に委譲)
  - `unifi-pull.sh` から controller API 呼び出しを削除、ARG として controller endpoint を
    一切受け付けない設計
  - `unifi/.gitignore` の `backup/` block で accidental 再生成を block
  - `unifi/scripts/redact-json.sh` は撤去 (API dump 自体を扱わないため)

---

## 6. 参考: 本 CONTEXT 生成時点の環境値

- 日付: 2026-10-14
- UDM Pro: UniFi OS 6.0.12, host `UDM-Pro`, LAN `10.0.0.1`, tailnet `100.118.109.67`
- WAN1: BB.excite 10G (DS-Lite via Transix, 現 egress IPv4 `130.62.15.41`, IPv6 `2409:12:d2a0:800:...`)
- WAN2: NURO 10G (`10.0.1.2/24` via NURO 機器, IPv6 `240d:f:fc4:2900:...`)
- VLANs: Default (`10.0.0.0/24`), IoT (`10.0.10.0/26`), Media (`10.0.3.0/26`), NURO (`vlan 50`, UNMANAGED)
- Tailnet: `tailb8263.ts.net`, 9 nodes (本整理後)
- NextDNS: profile `21553f` (public ID、プライバシー上の懸念なし。この構成全体の center of gravity)
- Commits: `9bf0049f` (dns strict Zero Leak), `a4f38cac` (NM nmconnection fix), `ea21b2a1` (unifi SSoT)
