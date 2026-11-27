#!/bin/bash
# Region Block の例外: Windowsゲーム機 SFP+ 01/02 から WNS を名前解決した IP 宛てのみ素通し
# (WNS は IN = ブロック対象国の Azure に解決される。codefusion は IE の AWS で Region Block 対象外のため 2026-10-18 に除外)
# UniFi 管理下のチェーン(UBIOS_OUT_GEOIP)には書き込まない — udapi が "Found unexpected rule" を毎秒数件
# 出し続けるため(UniFi OS 6.0.13 で約 640 件/分)。代わりに専用チェーンを FORWARD の GeoIP 判定
# (UNG_GEOIP_ETH8_* / UBIOS_FORWARD_JUMP)より前に挿入し、一致した通信を ACCEPT する。
# ACCEPT した通信はそれ以降の UniFi ゾーンポリシーを通らない(ALIEN/TOR/IPS は先に評価済み)。
set -u
exec 9>/run/game-geo-bypass.lock; flock 9           # タイマーと手動実行の同時実行を防ぐ
PAIRS="10.0.3.22=00:1b:21:bd:94:e4 10.0.3.23=00:1b:21:bd:94:e6"  # kpango's Game Windows SFP+ 01 / 02
HOSTS="wns.notify.trafficmanager.net"
SET4=GAME_GEOBYPASS4; SET6=GAME_GEOBYPASS6; CHAIN=GAME_GEOBYPASS; TAG=game-geo-bypass; TTL=86400
STAMP=/run/game-geo-bypass.resolved
# ルールに -m comment を付けない: udapi は自分の知らない comment 付きルールをチェーンを問わず警告する

ipset list -n "$SET4" >/dev/null 2>&1 || ipset create -exist "$SET4" hash:ip family inet  timeout "$TTL"
ipset list -n "$SET6" >/dev/null 2>&1 || ipset create -exist "$SET6" hash:ip family inet6 timeout "$TTL"
# 名前解決は 1 時間に 1 回(ipset TTL は 24h)。タイマーの周期はルール再挿入のためだけに使う
if [ -z "$(find "$STAMP" -mmin -60 2>/dev/null)" ]; then
  for h in $HOSTS; do
    for ip in $(dig +short +time=2 +tries=1 A "$h" | grep -E '^[0-9.]+$'); do ipset add -exist "$SET4" "$ip" timeout "$TTL"; done
    for ip in $(dig +short +time=2 +tries=1 AAAA "$h" | grep -E '^[0-9a-fA-F:]+:[0-9a-fA-F:]*$'); do ipset add -exist "$SET6" "$ip" timeout "$TTL"; done
  done
  touch "$STAMP"
fi

# 旧方式の comment 付きルール(UBIOS_OUT_GEOIP への RETURN 挿入・初版の専用チェーン)を削除(存在時のみ)
cleanup_legacy() {
  local ipt=$1 c
  for c in UBIOS_OUT_GEOIP "$CHAIN"; do
    $ipt -w 30 -S "$c" 2>/dev/null | grep -q -- "--comment $TAG" || continue
    $ipt -w 30 -S "$c" 2>/dev/null | grep -- "--comment $TAG" | sed 's/^-A /-D /' |
      while read -r rule; do eval "$ipt -w 30 $rule"; done
  done
}

EXPECTED_V4="-N $CHAIN"
EXPECTED_V6="-N $CHAIN"
for pair in $PAIRS; do
  src=${pair%%=*}; mac=${pair#*=}
  EXPECTED_V4+="
-A $CHAIN -s ${src}/32 -m mac --mac-source $mac -m set --match-set $SET4 dst -j ACCEPT"
  EXPECTED_V6+="
-A $CHAIN -m mac --mac-source $mac -m set --match-set $SET6 dst -j ACCEPT"
done

sync_chain() {
  local ipt=$1 restore=$2 expected=$3
  local cur rules
  cur=$($ipt -w 30 -S "$CHAIN" 2>/dev/null || true)
  if [ "$cur" = "$expected" ]; then
    return 0
  fi
  cleanup_legacy "$ipt"
  rules=${expected#*-N $CHAIN
}
  $restore --noflush --wait=30 <<EOF
*filter
:$CHAIN - [0:0]
-F $CHAIN
$rules
COMMIT
EOF
}

# GeoIP 判定へのジャンプ(eth8 補完チェーン or UniFi のジャンプ)のうち最初のものの直前に挿入する
ensure_jump() {
  local ipt=$1 fwd count pos
  fwd=$($ipt -w 30 -S FORWARD 2>/dev/null || true)
  count=$(printf '%s\n' "$fwd" | grep -c -- "-j $CHAIN$" || true)
  if [ "$count" = "1" ]; then
    return 0
  fi
  if [ "$count" = "0" ]; then
    pos=$(printf '%s\n' "$fwd" | grep -v '^-P' | grep -nE -- '-j (UNG_GEOIP_ETH8_IN|UNG_GEOIP_ETH8_OUT|UBIOS_FORWARD_JUMP)$' | head -1 | cut -d: -f1)
    if [ -n "$pos" ]; then $ipt -w 30 -I FORWARD "$pos" -j "$CHAIN"; else $ipt -w 30 -A FORWARD -j "$CHAIN"; fi
  fi
}

sync_chain iptables  iptables-restore  "$EXPECTED_V4"
sync_chain ip6tables ip6tables-restore "$EXPECTED_V6"
ensure_jump iptables
ensure_jump ip6tables
