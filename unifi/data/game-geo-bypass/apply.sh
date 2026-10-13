#!/bin/bash
# Region Block (UBIOS_OUT_GEOIP) の例外: Windowsゲーム機 SFP+ 01/02 のみ
#  - アイルランド(IE)宛ては丸ごと素通し (codefusion.technology は AWS eu-west-1)
#  - それ以外は指定ホスト(wns 等)を名前解決した IP のみ素通し
# UniFi の UI ポリシーは GeoIP チェーンより後に評価されるため、iptables で直接 RETURN を挿入する。
set -u
exec 9>/run/game-geo-bypass.lock; flock 9           # タイマーと手動実行の同時実行を防ぐ
MACS="00:1b:21:bd:94:e4 00:1b:21:bd:94:e6"          # kpango's Game Windows SFP+ 01 / 02
V4_SRCS="10.0.3.22 10.0.3.23"
ALLOW_COUNTRIES="IE"
HOSTS="wns.notify.trafficmanager.net support.codefusion.technology $(printf 'srv%02d.codefusion.technology ' $(seq 1 10))"
SET4=GAME_GEOBYPASS4; SET6=GAME_GEOBYPASS6; CHAIN=UBIOS_OUT_GEOIP; TAG=game-geo-bypass; TTL=86400

ipset create -exist $SET4 hash:ip family inet  timeout $TTL
ipset create -exist $SET6 hash:ip family inet6 timeout $TTL
for h in $HOSTS; do
  for ip in $(dig +short +time=2 +tries=1 A "$h" | grep -E '^[0-9.]+$'); do ipset add -exist $SET4 "$ip" timeout $TTL; done
  for ip in $(dig +short +time=2 +tries=1 AAAA "$h" | grep -E '^[0-9a-fA-F:]+:[0-9a-fA-F:]*$'); do ipset add -exist $SET6 "$ip" timeout $TTL; done
done

# -w: UniFi の xtables ロック保持中に -C が失敗して重複挿入されるのを防ぐ
ensure() { local ipt=$1; shift; $ipt -w 30 -C $CHAIN "$@" 2>/dev/null || $ipt -w 30 -I $CHAIN 1 "$@"; }

for mac in $MACS; do
  for src in $V4_SRCS; do
    ensure iptables -s "$src" -m mac --mac-source "$mac" -m set --match-set $SET4 dst -m comment --comment $TAG -j RETURN
    ensure iptables -s "$src" -m mac --mac-source "$mac" -m geoip --destination-country $ALLOW_COUNTRIES -m comment --comment $TAG -j RETURN
  done
  ensure ip6tables -m mac --mac-source "$mac" -m set --match-set $SET6 dst -m comment --comment $TAG -j RETURN
  ensure ip6tables -m mac --mac-source "$mac" -m geoip --destination-country $ALLOW_COUNTRIES -m comment --comment $TAG -j RETURN
done
