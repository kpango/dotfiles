#!/bin/bash
# UniFi で付けたクライアント名を NextDNS CLI に渡す。
# NextDNS CLI の UniFi 用名前取得 (discovery/ubios_linux.go) は MongoDB (localhost:27117/ace) を読むが、
# Network 11.0.83 以降は PostgreSQL へ移行しており何も返さない。代わりに CLI の hosts ソースが最優先で読む
# /etc/hosts.dnsmasq を生成する (CLI は最初に見つかった 1 ファイルしか読まないので /etc/hosts も含める)。
# 制約: CLI は DHCP リースから MAC で名前が引けるとそちらで上書きするため、ここで渡した名前が NextDNS に
# 出るのは DHCP ホスト名を名乗らない端末だけ。
set -euo pipefail
exec 9>/run/nextdns-client-names.lock; flock -n 9 || exit 0  # タイマーと手動実行の同時実行を防ぐ

DIR=/data/nextdns-client-names
OUT=/etc/hosts.dnsmasq
BASE=https://127.0.0.1/proxy/network/integration/v1
KEY=$(<"$DIR/api-key")  # Integration API key (git 管理外、mode 600)

api() { curl -sfk -m 15 -H "X-API-KEY: $KEY" -H "Accept: application/json" "$BASE$1"; }

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

site=$(api /sites | jq -er '.data[0].id')
clients=$(api "/sites/$site/clients?limit=200")
if [ "$(jq '.totalCount > .count' <<<"$clients")" = true ]; then
  echo "warn: client list truncated ($(jq -r '"\(.count)/\(.totalCount)"' <<<"$clients"))" >&2
fi
neigh6=$(ip -6 neigh show)

cat /etc/hosts >"$tmp"
jq -r '.data[] | select(.ipAddress != null and .name != null) | [.ipAddress, (.macAddress | ascii_downcase), .name] | @tsv' <<<"$clients" |
  while IFS=$'\t' read -r ip mac name; do
    # hosts の名前に使えない文字 (空白・' 等) を - に寄せる
    host=$(printf '%s' "$name" | tr -cs 'A-Za-z0-9-' '-' | sed 's/^-*//; s/-*$//')
    [ -n "$host" ] || continue
    printf '%s\t%s\n' "$ip" "$host"
    # IPv6 で問い合わせる端末向けに、同じ MAC の global アドレスも載せる
    awk -v m="lladdr $mac " 'index($0" ", m) && $1 !~ /^fe80/ {print $1}' <<<"$neigh6" |
      while read -r ip6; do printf '%s\t%s\n' "$ip6" "$host"; done
  done >>"$tmp"

cmp -s "$tmp" "$OUT" || install -m 644 "$tmp" "$OUT"
