# unifi — UDM Pro ユーザーアセット (SSoT)

UniFi Dream Machine Pro (UniFi OS `6.0.19` / Debian 13 `trixie`, host `udm-pro.tailb8263.ts.net`, LAN `10.0.0.1`) 上の
**ユーザー作成アセット** (スクリプト / 設定 / systemd ユニット) の Single Source of Truth。

**スコープ外**: UniFi controller state (networkconf / setting / wlanconf / firewall-policies /
portforward 等) は UniFi Cloud が既にバックアップしているため dotfiles では shadow しない。
これらの JSON は WPA2 PSK / SSH 資格 / SSO / API token を平文で含むため、git に取り込むと
secret leak の原因になる (2026-10-14 事例、`CONTEXT.md` の §7 incident 参照)。
例外は `controller/` で、FW policy・Traffic Matching List・mDNS mode だけを**手書きの宣言**として
持ち、`unifictl` が API で適用する (ダンプはしない、`CONTEXT.md` Q25–Q31)。

`make unifi/install` で UDM Pro へ反映する（UDM Pro ローカル実行時は `/usr/bin/ubnt-device-info` を検出し `UDM=local`、外部端末からは `UDM=udmpro` 経由の `tar+ssh`）。`make unifi/pull` で現在の
UDM Pro `/data` と `/root` を dotfiles 側に取り込む (JSON ダンプは一切取らない)。

## レイアウト

| ディレクトリ    | UDM Pro 配置先     | 役割                                                                                                                                                                                                                                                                  |
| --------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `data/`         | `/data/`           | 永続スクリプト・設定・ネイティブ `systemd` ユニット (`nextdns.conf` / `nextdns-*` / `tailscale-unifi` `v3.3.11` / `tailscale-dnsmasq` / `tailscale-guard` / `udm-sysctl` / `udm-post-install` / `game-geo-bypass` / `unifi-native-guard` / `udm-*` / `clean-clients`) |
| `root/`         | `/root/`           | admin スクリプト (`update.sh` / `clean-clients.sh` / `debug.sh` 等)                                                                                                                                                                                                   |
| `etc-snapshot/` | — (参照のみ)       | `/etc/systemd/system/*.{service,timer,path}` と `/etc/cron.d/*` の生成後スナップショット。実際の `/etc/` 配置は `data/<component>/install.sh` と `data/on_boot.d/*.sh` が行うため、ここは**読み取り専用の参考**として追従する                                         |
| `controller/`   | — (controller API) | 秘密を含まない手書きの宣言。`firewall-policies.json` (USER_DEFINED の FW policy、zone 組ごとに配列の並び = 評価順)、`traffic-matching-lists.json`、`mdns.json`。zone / network / list は名前で書き、UUID は書かない                                                   |
| `unifictl/`     | — (ローカル実行)   | `controller/` を plan / apply する Go ツール (標準ライブラリのみ、`go run` で実行)                                                                                                                                                                                    |
| `scripts/`      | — (ローカル実行)   | `unifi-pull.sh` / `unifi-install.sh` / `unifi-diff.sh` 本体と、それらが共有する `_lib.sh` / `_data-allowlist.txt`                                                                                                                                                     |

## scripts/ 内訳

| ファイル              | 役割                                                                                                                                                                                                                                                                                                                                                                                                                     |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `_lib.sh`             | `UDM` / `REPO_ROOT` / `UNIFI_{DIR,SCRIPTS,DATA,ROOT}` の解決と `log` / `die` ヘルパ。3 スクリプトが共通で `. "$(dirname "$0")/_lib.sh"` で source する                                                                                                                                                                                                                                                                   |
| `_data-allowlist.txt` | `unifi-pull.sh` が `/data` 配下から tar に含めるパスの allowlist (`#` コメント・空行可)。vendor/service state (`/data/unifi/`, `/data/unifi-credential-server/`, `/data/udapi-config/` 等) は意図的に除外されている                                                                                                                                                                                                      |
| `unifi-pull.sh`       | SSH で `/data` と `/root` を tar+pipe で取り込み、`unifi/{data,root}/` を更新 (dest 不在時は `mkdir -p` で救済)                                                                                                                                                                                                                                                                                                          |
| `unifi-install.sh`    | 逆方向。tar push (local / ssh)、chmod で実行権復元、UDM 上の `/data/udm-post-install/post-install.sh` (各 `install.sh` と `guard.sh units`、`tailscale-{install,cert-renewal}`、`udm-post-install.service` を再配置、`systemctl daemon-reload`) を実行する。同じスクリプトを boot 時も `udm-post-install.service` が実行する (Q42/R2)。Hook 失敗は `[hook-fail] <path> rc=<n>` を stderr に出して exit 非 0 で可視化する |
| `unifi-diff.sh`       | md5sum ベースで `unifi/{data,root}/` と UDM Pro 実機を比較、drift を報告。`remote_dir` は `/data` または `/root` の literal 固定 (injection 防御)                                                                                                                                                                                                                                                                        |
| `unifi-status.sh`     | 読み取り専用 one-shot 診断: NextDNS CLI・Tailscale 状態・`tailscale0`・`/etc/resolv.conf`・`dnsmasq` 配線・`TS_ISOLATE`・systemd ユニット一覧                                                                                                                                                                                                                                                                            |
| `unifi-audit.sh`      | `udm-audit.sh` を実機 (local または `ssh "$UDM"`) で実行。読み取りのみで、unit・Tailscale R2/R3・DNS・IPv6・WAN SLA・iptables hook 本数などを 1 項目ずつ PASS/WARN/FAIL 表示し、FAIL 数を exit code で返す                                                                                                                                                                                                               |
| `unifi-logs.sh`       | `journalctl` (`nextdns`, `nextdns-*`, `tailscaled`, `tailscale-*`, `udm-post-install`, `udm-sysctl`) と `/var/log/nextdns-healthcheck.log`・`dmesg` を一息に tail。`LINES=N` で行数指定 (既定 50)                                                                                                                                                                                                                        |

## /etc がどうやって同期されるか

- `/etc/systemd/system/udm-post-install.service` ← `/data/udm-post-install/post-install.sh` が
  自身のユニットと全フックを同期し、boot 時に同じ構成を再適用 (レガシー `udm-boot.service` / `on_boot.d` / cron は自動クリーンアップ)
- `/etc/systemd/system/nextdns-dnsmasq-wire.{path,service}`・`nextdns-client-names.{service,timer}`・`nextdns-healthcheck.{service,timer}` ←
  `nextdns` CLI (`:5342`) の dnsmasq 配線・クライアント名同期・ヘルスチェックをネイティブ `systemd` で維持
- `/etc/sysctl.d/99-udm-tune.conf`・`/etc/systemd/system/udm-sysctl.service` ← `/data/udm-sysctl/install.sh` が
  `udapi-server.service` 起動後にカーネルパラメータを適用
- `/etc/systemd/system/tailscale-dnsmasq.{service,path,timer}` ← `/data/tailscale-dnsmasq/install.sh` が
  `/run/dnsmasq.dhcp.conf.d/99-tailscale.conf` (`interface=tailscale0`, `no-dhcp-interface=tailscale0`) を維持し Split DNS を保護
- `/etc/systemd/system/tailscale-guard.{service,timer}` ← `/data/tailscale-guard/install.sh` が
  `TS_ISOLATE` チェーンで IoT (`br2` / `10.0.10.0/26`) と `tailscale0` を隔離
- `/etc/systemd/system/game-geo-bypass.{service,timer}` ← `/data/game-geo-bypass/install.sh` が
  自身のディレクトリ内の .service/.timer を /etc 配下にコピー → `systemctl daemon-reload`
- `/etc/systemd/system/unifi-native-guard-geoip-eth8.{service,timer,path}` ← 同じく
  `/data/unifi-native-guard/guard.sh units` が `units/` 配下から再配置
- `/etc/systemd/system/tailscale-install.{service,timer}`・`tailscale-cert-renewal.{service,timer}` ←
  `/data/tailscale/manage.sh` (`SierraSoftworks/tailscale-unifi` `v3.3.11`) および `post-install.sh` が設置
- `udm-{sla-tune,nuro-v6-pbr,dns-hijack,dpinger-hijack}` (60 秒毎)・`udm-verifier-enforcer` (1 時間毎)・
  `udm-dfs-restore` (毎日 05:00 JST)・`udm-mape-fallback` (5 分毎)・`clean-clients` (毎日 09:00 JST) の
  `.service`/`.timer` と `ndppd.service` ← 各 `/data/<component>/install.sh` が `units/` から配置 (`post-install.sh` の `HOOKS`)

したがって dotfiles 側は `/data/` のみを正本として扱い、`/etc/` は boot 時 or install.sh
実行時に自動再生成される。`etc-snapshot/` は「現状何が生成されているか」の読み取り専用
スナップショットで、デプロイ元ではない。

## Make ターゲット

| ターゲット                    | 動作                                                                                                                                                                                                                    |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `make unifi/help`             | この表と同じ内容を inline コメントから抽出して表示                                                                                                                                                                      |
| `make unifi/pull`             | UDM Pro `/data` と `/root` の **スクリプト類のみ** を `unifi/{data,root}/` へ上書き取り込み (controller API JSON は取得しない)                                                                                          |
| `make unifi/install`          | `unifi/data/` を UDM Pro `/data/` に tar+ssh で push、`unifi/root/` を `/root/` に tar+ssh、各 `install.sh` を実行、`systemctl daemon-reload`                                                                           |
| `make unifi/diff`             | ローカル (`unifi/data`, `unifi/root`) と UDM Pro 実機の差分を md5sum ベースで表示                                                                                                                                       |
| `make unifi/dry-run`          | install の tar+ssh を実行せず何が送られるかプレビュー                                                                                                                                                                   |
| `make unifi/status`           | 読み取り専用の実機状態スナップショット (NextDNS CLI / Tailscale / dnsmasq / systemd)                                                                                                                                    |
| `make unifi/audit`            | 読み取り専用の設定監査。期待どおりの状態かを項目ごとに PASS/WARN/FAIL で表示し、FAIL があれば非 0 で終わる                                                                                                              |
| `make unifi/logs`             | 実機ログ (`nextdns`, `tailscaled`, `udm-post-install`, `udm-sysctl`, `dmesg`) を一息に tail。`LINES=N` で行数                                                                                                           |
| `make unifi/controller-plan`  | `controller/` と実機 controller の差分を表示 (読み取りのみ)。API キーは `pass show unifi-api`                                                                                                                           |
| `make unifi/controller-apply` | plan を表示し、`yes` 入力で適用 (`YES=1` で確認省略)。変更前の object は `$XDG_STATE_HOME/unifictl/backup/<ts>/` (repo 外, 0600)。mDNS の対象ネットワークは API で変えられないので、ずれていれば UI 手順を出して exit 3 |
| `make unifi/controller-test`  | `unifictl` の単体テスト (合成 fixture、controller に接続しない)                                                                                                                                                         |

変数: `UDM=<host>` で接続先を上書き (UDM Pro 上では自動 `local`、外部からは既定 `udmpro`)。`DRY_RUN=1` は `unifi/install` に対して
`unifi/dry-run` と同等 (CI などで直接呼ぶ場合用)。`LINES=N` で `unifi/logs` の行数 (既定 50)。
`UNIFI_HOST` / `UNIFI_SITE` で `unifictl` の接続先 (既定 `10.0.0.1` / `default`)。

`controller/` に新しい FW policy を足すときは、UI か API で作ったあとに宣言へ書き写し、
`make unifi/controller-plan` が `No changes` になることを確かめる。宣言から消しても実機の
policy は消えない (prune しない)。

## 絶対にコミットしないもの (secrets)

- `/data/tailscale/tailscaled.state` — Tailscale node private identity key
- `/data/tailscale/profile-data/`, `/data/tailscale/files/` — ユーザー個人証明書・authkey
- `/data/tailscale/dns-cache/`, `/data/tailscale/derpmap.cached.json` — runtime cache
- `/data/unifi-api.key`, `/data/clean-clients.key`, `~/.unifi_api_key`, `~/.ts_api_key` — API キー実体
  (dotfiles では `pass show unifi-api` / `pass show tailscale` / `pass show nextdns` 経由)
- UniFi controller API の JSON ダンプ全般 (`setting.json` / `wlanconf.json` / `networkconf.json`
  等) — WPA/SSH/SSO/API 秘密を平文で含むため、UniFi Cloud に任せる

## 既知の限界

- UDM Pro のファームウェアアップデートで `/etc/` と `/usr/` は wipe される。`/data/udm-post-install/post-install.sh` が
  `udm-post-install.service` として boot 時に `/etc/` 側を再構築する設計なので、install 後も自動復旧する
- `udm-post-install.service` および `tailscale-install.{service,timer}` 自体は `/etc/systemd/system/` に配置されるため、
  万一 `/etc` overlay ごと初期化された場合は `make unifi/install`（または `/data/udm-post-install/post-install.sh`）の再実行が必要
  (2026-10-16 の 6.0.13、2026-11-04 の 6.0.17 更新では `/etc` overlay は残った)
- `unifi-native-guard` は Ubiquiti 製パッケージを Debian trixie upgrade から保護する
  仕組み (詳細は `data/unifi-native-guard/guard.sh` ヘッダ参照)
- `game-geo-bypass` は Region Block の例外として Windows ゲーム機の WNS (Windows プッシュ通知、IN の Azure に解決される)
  を通過させる (詳細は `data/game-geo-bypass/apply.sh`)。UniFi 管理チェーン (`UBIOS_*`) には書き込まず、
  専用チェーン `GAME_GEOBYPASS` を FORWARD の GeoIP 判定より前に挿入して ACCEPT する。自前ルールには
  `-m comment` を付けない (udapi が未知の comment 付きルールを毎秒警告するため)
- 自前の iptables/ip6tables 呼び出しには必ず `-w 30` を付ける。付けないと UniFi が xtables lock を
  持っている間の `-C` が失敗し、hook が重複挿入される (`CONTEXT.md` Q35)
- WAN の failover probe は UniFi 公式の WAN SLA で NextDNS に向けている。WAN SLA で変えられない
  表示用 monitor だけを `udm-dpinger-hijack` が DNAT する。probe のホスト名を `/etc/hosts` に書かない
  (`/etc/hosts.dnsmasq` 経由で LAN 全体の名前解決が NextDNS IP に化ける、`CONTEXT.md` Q32–Q34)
