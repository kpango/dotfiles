#!/bin/bash
# Region Block の例外: Windowsゲーム機 SFP+ 01/02 から指定ホスト(wns / codefusion)を名前解決した IP 宛てのみ素通し
# UniFi 管理下のチェーン(UBIOS_OUT_GEOIP)には書き込まない — udapi が "Found unexpected rule" を毎秒数件
# 出し続けるため(UniFi OS 6.0.13 で約 640 件/分)。代わりに専用チェーンを FORWARD の GeoIP 判定
# (UNG_GEOIP_ETH8_* / UBIOS_FORWARD_JUMP)より前に挿入し、一致した通信を ACCEPT する。
# ACCEPT した通信はそれ以降の UniFi ゾーンポリシーを通らない(ALIEN/TOR/IPS は先に評価済み)。
set -u
exec 9>/run/game-geo-bypass.lock; flock 9           # タイマーと手動実行の同時実行を防ぐ
PAIRS="10.0.3.22=00:1b:21:bd:94:e4 10.0.3.23=00:1b:21:bd:94:e6"  # kpango's Game Windows SFP+ 01 / 02
HOSTS="wns.notify.trafficmanager.net support.codefusion.technology $(printf 'srv%02d.codefusion.technology ' $(seq 1 10))"
SET4=GAME_GEOBYPASS4; SET6=GAME_GEOBYPASS6; CHAIN=GAME_GEOBYPASS; TAG=game-geo-bypass; TTL=86400
# ルールに -m comment を付けない: udapi は自分の知らない comment 付きルールをチェーンを問わず警告する

ipset create -exist $SET4 hash:ip family inet  timeout $TTL
ipset create -exist $SET6 hash:ip family inet6 timeout $TTL
for h in $HOSTS; do
  for ip in $(dig +short +time=2 +tries=1 A "$h" | grep -E '^[0-9.]+$'); do ipset add -exist $SET4 "$ip" timeout $TTL; done
  for ip in $(dig +short +time=2 +tries=1 AAAA "$h" | grep -E '^[0-9a-fA-F:]+:[0-9a-fA-F:]*$'); do ipset add -exist $SET6 "$ip" timeout $TTL; done
done

# 旧方式の comment 付きルール(UBIOS_OUT_GEOIP への RETURN 挿入・初版の専用チェーン)を削除
for ipt in iptables ip6tables; do
  for c in UBIOS_OUT_GEOIP $CHAIN; do
    $ipt -w 30 -S $c 2>/dev/null | grep -- "--comment $TAG" | sed 's/^-A /-D /' |
      while read -r rule; do eval "$ipt -w 30 $rule"; done
  done
done

# -w: UniFi の xtables ロック保持中に -C が失敗して重複挿入されるのを防ぐ
ensure() { local ipt=$1; shift; $ipt -w 30 -C $CHAIN "$@" 2>/dev/null || $ipt -w 30 -A $CHAIN "$@"; }

# GeoIP 判定へのジャンプ(eth8 補完チェーン or UniFi のジャンプ)のうち最初のものの直前に挿入する
ensure_jump() {
  local ipt=$1 pos
  $ipt -w 30 -C FORWARD -j $CHAIN 2>/dev/null && return 0
  pos=$($ipt -w 30 -S FORWARD | grep -v '^-P' | grep -nE -- '-j (UNG_GEOIP_ETH8_IN|UNG_GEOIP_ETH8_OUT|UBIOS_FORWARD_JUMP)$' | head -1 | cut -d: -f1)
  if [ -n "$pos" ]; then $ipt -w 30 -I FORWARD "$pos" -j $CHAIN; else $ipt -w 30 -A FORWARD -j $CHAIN; fi
}

for ipt in iptables ip6tables; do
  $ipt -w 30 -N $CHAIN 2>/dev/null || true
done
for pair in $PAIRS; do
  src=${pair%%=*}; mac=${pair#*=}
  ensure iptables  -s "$src" -m mac --mac-source "$mac" -m set --match-set $SET4 dst -j ACCEPT
  ensure ip6tables           -m mac --mac-source "$mac" -m set --match-set $SET6 dst -j ACCEPT
done
ensure_jump iptables
ensure_jump ip6tables
