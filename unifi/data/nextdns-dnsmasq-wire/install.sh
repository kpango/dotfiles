#!/bin/sh
# ファームウェア更新後などに systemd ユニットを再配置する
set -eu
cp /data/nextdns-dnsmasq-wire/units/nextdns-dnsmasq-wire.path /data/nextdns-dnsmasq-wire/units/nextdns-dnsmasq-wire.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now nextdns-dnsmasq-wire.path
systemctl start nextdns-dnsmasq-wire.service
