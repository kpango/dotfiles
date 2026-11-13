#!/bin/bash
# ファームウェア更新後などに systemd ユニットを再配置する
cp /data/nextdns-client-names/nextdns-client-names.{service,timer} /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now nextdns-client-names.timer
