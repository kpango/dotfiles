#!/bin/bash
# ファームウェア更新後などに systemd ユニットを再配置する
set -euo pipefail

D=/data/game-geo-bypass
chmod 0755 "$D/apply.sh"

changed=0
for u in game-geo-bypass.service game-geo-bypass.timer game-geo-bypass.path; do
    src="$D/$u"
    dst="/etc/systemd/system/$u"
    cmp -s "$src" "$dst" || { install -m 0644 "$src" "$dst"; changed=1; }
done
[ "$changed" = 1 ] && systemctl daemon-reload

systemctl enable --now game-geo-bypass.path >/dev/null
systemctl is-active --quiet game-geo-bypass.path \
    || { echo "FAIL: game-geo-bypass.path not active" >&2; exit 1; }

systemctl enable --now game-geo-bypass.timer >/dev/null
systemctl is-active --quiet game-geo-bypass.timer \
    || { echo "FAIL: game-geo-bypass.timer not active" >&2; exit 1; }

systemctl start game-geo-bypass.service

echo "game-geo-bypass: timer active, WNS bypass rules applied."
