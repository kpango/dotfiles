#!/bin/sh
# NextDNS CLI (setup-router) は起動時に一度だけ /run/dnsmasq.dhcp.conf.d/nextdns.conf を書いて dnsmasq を
# kill する (router/ubios/setup.go)。udapi-server は設定変更のたびにこのディレクトリを再生成して nextdns.conf を
# 消すが CLI は書き直さないため、dnsmasq は resolv.conf.d/main の NextDNS IP へ平文 UDP で直接転送し、
# UDM 自身 (127.0.0.1 発、CLI が host 名 UDM-Pro を付ける) も LAN 端末も NextDNS 上で名前が付かなくなる。
# CLI を再起動すれば同じテンプレートで書き直される。
set -eu
CONF=/run/dnsmasq.dhcp.conf.d/nextdns.conf
grep -qs '^server=127\.0\.0\.1#5342$' "$CONF" && exit 0
logger -t nextdns-dnsmasq-wire "$CONF missing — restarting nextdns"
systemctl restart nextdns
