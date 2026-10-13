#!/bin/bash
# ファームウェア更新後などに systemd ユニットを再配置する
cp /data/game-geo-bypass/game-geo-bypass.{service,timer} /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now game-geo-bypass.timer
