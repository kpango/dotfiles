#!/bin/bash
#
# update.sh — UDM Pro システム保守スクリプト(旧 update-tailscale.sh をリニューアル)
# apt dist-upgrade によるシステム全体の最新化・UniFi/fwupdパッケージ更新・
# ファームウェア確認に加え、既知の障害パターンに対する事前/事後チェックを行う。
# 実行ログは /var/log/update.sh.log に記録される。
#

set -o pipefail

LOG_FILE="/var/log/update.sh.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== update.sh 開始: $(date -Iseconds) ====="

apt clean
echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/no-install-recommends
# 削除対象は apt 自身のキャッシュに限定する。旧版の /var/cache/* 一括削除は、起動時に
# nginx が作成する一時ディレクトリ(/var/cache/nginx/proxy_temp 等)まで消してしまい、
# nginx 再起動まで認証済み API/UI の大きな応答が
# 'mkdir() "/var/cache/nginx/proxy_temp/N" failed' で全て失敗(HTTP 000)していた
# (2026-09-25 確認)。debconf の設定DB(/var/cache/debconf)も巻き添えで消えていた。
rm -rf /var/lib/apt/lists/* /var/cache/apt/*

# nginx の一時ディレクトリ(nginx -V の *-temp-path)を所有者 nginx で保証する。
# 既に欠落している状態も、nginx を再起動せずにこの実行で修復される。
for d in client_temp proxy_temp fastcgi_temp uwsgi_temp scgi_temp; do
    install -d -o nginx -g nginx -m 700 "/var/cache/nginx/$d"
done

# 調査作業で残った診断用ダンプ(dpi-util --dpi-stats の出力等)を掃除する。
rm -f /tmp/dpi_stats_*.json


# 旧スクリプトの apt-key adv --refresh-keys / apt-key list ... del は削除。
# Debian trixie では apt-key コマンド自体が提供されておらず(command not found)、
# 常にエラーで終わる無意味な処理だった。鍵管理は各 *.list の signed-by 指定、または
# /etc/apt/trusted.gpg.d/ 配下の鍵ファイル(ubiquiti-archive-keyring.gpg 等)で
# 既に完結しており、apt-key による個別リフレッシュは不要。

# apt-beta.artifacts.ui.com / apt-release-candidate.artifacts.ui.com は
# Ubiquiti/JFrog側のサーバー証明書設定ミス(CN=*.jfrog.ioのままカスタムドメイン用の
# SANが未設定)により恒常的に403 Forbiddenを返す、クライアント側では解決不能な既知の
# 問題(BETAチャンネル運用を続ける限り発生し続ける)。この2ホスト由来の失敗のみ許容し、
# それ以外(Debian標準リポジトリ等)の取得失敗があれば処理を中止する。
UPDATE_OUTPUT=$(apt update -y 2>&1)
echo "$UPDATE_OUTPUT"
UNEXPECTED_FAILURES=$(echo "$UPDATE_OUTPUT" | grep -E 'Failed to fetch|^E: ' | grep -v -E 'apt-beta\.artifacts\.ui\.com|apt-release-candidate\.artifacts\.ui\.com')
if [ -n "$UNEXPECTED_FAILURES" ]; then
    echo "ERROR: 想定外のリポジトリ取得失敗を検出しました。以降の更新処理を中止します。" >&2
    echo "$UNEXPECTED_FAILURES" >&2
    exit 1
elif echo "$UPDATE_OUTPUT" | grep -qE 'apt-beta\.artifacts\.ui\.com|apt-release-candidate\.artifacts\.ui\.com'; then
    echo "NOTE: BETA/RCチャンネルの403 Forbiddenを検出しましたが、Ubiquiti/JFrog側の既知のサーバー証明書問題のため無視します。"
fi

# --- UniFi独自パッケージの保護 (unifi-native-guard) ---
# 背景: 2026-09-21 の apt dist-upgrade で Ubiquiti 独自ビルドの iptables/libxtables
# (dpi*/dyn_random/geoip 拡張)・frr(/usr/sbin/zebra)・dnsmasq 等が Debian 版に置換され、
# ubios-udapi-server の設定適用が毎回失敗・ロールバックした("Gateway Configuration
# Failed"、LAN の IPv4 断、ファイアウォール/GeoIP/WAN フェイルオーバー無効)。
# Debian 側と衝突する Ubiquiti パッケージだけを Debian オリジンから取得禁止に pin し、
# それ以外(libc・openssl・curl 等のセキュリティ更新)は従来通り最新に追従させる。
# pin はファームウェア層(/mnt/.rofs)から毎回生成するので、ファームウェア更新にも追従する。
GUARD=/data/unifi-native-guard/guard.sh
"$GUARD" pins
if ! "$GUARD" preflight; then
    echo "ERROR: dist-upgrade が Ubiquiti パッケージを置換/削除しようとしています。更新を中止します。" >&2
    exit 1
fi

echo "--- アップグレード可能なパッケージ一覧 ---"
apt list --upgradable 2>/dev/null

apt upgrade -y
apt dist-upgrade -y

# --- 既存パッケージ破損の事前修復 ---
# 半端な状態(half-installed等)のパッケージが残っていると、無関係な新規パッケージの
# インストール(fwupd等)まで依存関係エラーで巻き込まれて失敗するため先に解消する。
apt --fix-broken install -y

# unifi は 10-unsupport で pin 済み、unifi-base-ucore は UDM 用ではない別コントローラー
# (Debian nodejs を引き込む)のため導入しない。
apt-get install fwupd -y

# --- 更新後の検証: 置換された Ubiquiti パッケージをファームウェア層から自動復元 ---
if ! "$GUARD" verify; then
    echo "WARNING: unifi-native-guard verify に失敗しました。上記ログを確認してください。" >&2
fi

# --- eth8 (DS-Lite のネイティブ IPv6) への Region Blocking 適用ユニットの再登録 ---
# UniFi は DS-Lite の WAN として ip6tnl1 だけを GeoIP 対象にするため、eth8 経由の LAN IPv6 が
# 素通りになる。/data/unifi-native-guard/geoip-eth8.sh が CyberSecure の国リストに追従して
# 補完する。ユニットは /etc (overlay) にありファームウェア更新で消えるため、毎回確認する。
"$GUARD" units


# --- 主要ネットワークサービスの正常性検証 ---
# 背景: apt dist-upgrade由来の障害(上記overlay競合含む)は、ubios-udapi-server配下の
# dhcpServers/dnsForwarder/geoipFiltering/wifiman等を連鎖的にEmergency stopさせる
# ことがある。overlay修復だけでは既に停止済みのサービスは回復しないため、
# 直近のログを確認し、検出時のみ再起動を促す(自動再起動はDHCP等への影響が大きいため
# 行わず、警告に留める)。
verify_udapi_services_health() {
    local pid
    pid=$(pgrep -f 'ubios-udapi-server -c' | head -1)
    if [ -z "$pid" ]; then
        echo "WARNING: ubios-udapi-server プロセスが見つかりません。"
        return
    fi
    local emergency
    emergency=$(journalctl _PID="$pid" --no-pager --since '5 minutes ago' 2>/dev/null | grep -c 'Emergency stop')
    if [ "${emergency:-0}" -gt 0 ]; then
        echo "WARNING: udapi-server で ${emergency} 件の Emergency stop を検出しました。"
        journalctl _PID="$pid" --no-pager --since '5 minutes ago' 2>/dev/null | grep 'Emergency stop'
        echo "  -> 'systemctl restart udapi-server' による回復を検討してください。"
    else
        echo "udapi-server: 主要サービスに Emergency stop は検出されませんでした。"
    fi
}
verify_udapi_services_health


# 旧 autoremove -y を --purge 付きに変更し、不要パッケージの残存設定ファイルも
# 併せて除去する(容量確保・設定ファイルの孤児化防止)。
apt-get autoremove --purge -y
apt autoclean -y

sudo systemctl daemon-reload
sudo systemctl reload dbus.service
sudo systemctl restart fwupd.service

# --- fwupd: ファームウェア確認・更新 ---
# 背景: /usr/sbin/fwupdate はUbiquiti独自のプロプライエタリツール(単に<firmware file>を
# 引数に取るのみ)であり、fwupdパッケージが提供するfwupdmgrとは全くの別物。
# 旧スクリプトはfwupdmgrのサブコマンド構文(get-devices/refresh/get-updates等)を
# 誤ってfwupdateに対して呼び出しており、全て無効なオプションエラーで失敗していた。
# clear-history/clear-offlineに相当するfwupdmgrサブコマンドは存在しないため削除。
sudo fwupdmgr get-devices
sudo fwupdmgr refresh
sudo fwupdmgr get-updates
sudo fwupdmgr get-upgrades
sudo fwupdmgr update -y

# --- ログ・ディスク容量の保守(高速化・容量確保) ---
echo "--- systemd journal を7日以前分削除 ---"
journalctl --vacuum-time=7d

echo "--- ディスク使用率 ---"
df -h / /boot/firmware /data 2>/dev/null

BOOT_USAGE=$(df --output=pcent /boot/firmware 2>/dev/null | tail -1 | tr -dc '0-9')
if [ -n "$BOOT_USAGE" ] && [ "$BOOT_USAGE" -ge 90 ]; then
    echo "WARNING: /boot/firmware の使用率が ${BOOT_USAGE}% です。"
    echo "  多くの場合 rootfs.bkp (旧ファームウェアのロールバック用バックアップ)が主因です。"
    echo "  ロールバック手段を失うため自動削除は行いません。内容を確認の上、"
    echo "  不要と判断した場合のみ手動で削除してください: du -sh /boot/firmware/*"
fi

echo "===== update.sh 完了: $(date -Iseconds) ====="
