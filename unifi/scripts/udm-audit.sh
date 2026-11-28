#!/bin/bash
# udm-audit.sh — read-only on-box audit of every out-of-band UDM Pro setting
# managed by this repo (unifi/data/*) plus Tailscale R2/R3 and controller-side
# values they depend on (WAN SLA, usg, networkconf, QoS, traffic routes).
# Prints PASS/WARN/FAIL per check and exits with the number of FAILs (0 = good).
#
# Runs ON the UDM (locally or streamed via ssh). Never mutates state.
# Uses /data/unifi-api.key (or legacy /data/nextdns-client-names/api-key) for
# optional controller API checks; skips API checks with WARN if not provisioned.
set -u
FAILS=0
WARNS=0
ok()   { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; WARNS=$((WARNS + 1)); }
ng()   { printf 'FAIL  %s\n' "$*"; FAILS=$((FAILS + 1)); }
chk()  { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else ng "$d"; fi; }

K=""
for kf in /data/unifi-api.key /data/nextdns-client-names/api-key; do
  if [ -r "$kf" ]; then
    K=$(tr -d '[:space:]' < "$kf")
    [ -n "$K" ] && break
  fi
done
api() { curl -ksS -H "X-API-KEY: $K" "https://127.0.0.1/proxy/network$1"; }

echo "== units"
for u in nextdns.service nextdns-dnsmasq-wire.path nextdns-client-names.timer nextdns-healthcheck.timer tailscaled.service tailscale-install.timer tailscale-cert-renewal.timer tailscale-dnsmasq.path tailscale-dnsmasq.timer tailscale-guard.timer udm-storage-tune.service udm-sysctl.service udm-sla-tune.path udm-sla-tune.timer udm-nuro-v6-pbr.path udm-nuro-v6-pbr.timer udm-dns-hijack.timer udm-dpinger-hijack.path udm-dpinger-hijack.timer udm-verifier-enforcer.timer udm-dfs-restore.timer udm-mape-fallback.timer clean-clients.timer game-geo-bypass.path game-geo-bypass.timer unifi-native-guard-geoip-eth8.timer ndppd.service; do
  chk "$u active+enabled" sh -c "systemctl is-active --quiet $u && systemctl is-enabled --quiet $u"
done
chk "udm-post-install.service enabled" systemctl is-enabled --quiet udm-post-install.service
for s in nextdns nextdns-dnsmasq-wire nextdns-client-names nextdns-healthcheck tailscale-install tailscale-cert-renewal tailscale-dnsmasq tailscale-guard udm-storage-tune udm-sysctl udm-sla-tune udm-nuro-v6-pbr udm-dns-hijack udm-dpinger-hijack udm-verifier-enforcer udm-dfs-restore udm-mape-fallback udm-post-install clean-clients game-geo-bypass; do
  chk "$s.service last run not failed" sh -c "! systemctl is-failed --quiet $s.service"
done
for legacy in udm-boot.service; do
  chk "legacy $legacy absent/inactive" sh -c "! systemctl is-active --quiet $legacy && [ ! -e /etc/systemd/system/$legacy ]"
done

echo "== Tailscale (R2 / R3)"
chk "kernel TUN /dev/net/tun present & tailscale0 UP" sh -c '[ -c /dev/net/tun ] && ip link show tailscale0 | grep -qE "UP|LOWER_UP"'
chk "no userspace-networking in /etc/default/tailscaled or tailscale-env" sh -c '! grep -q "userspace-networking" /etc/default/tailscaled /data/tailscale/tailscale-env'
chk "tailscale BackendState = Running" sh -c '[ "$(tailscale status --json | jq -r .BackendState)" = "Running" ]'
chk "tailscale prefs: SNAT=on, stateful-filtering=on, accept-dns=off, accept-routes=off" sh -c 'p=$(tailscale debug prefs 2>/dev/null) && printf "%s" "$p" | jq -e ".NoSNAT==false and .NoStatefulFiltering==false and .CorpDNS==false and .RouteAll==false"'
chk "/etc/resolv.conf = 127.0.0.1 (no 100.100.100.100)" sh -c 'grep -q "^nameserver 127.0.0.1$" /etc/resolv.conf && ! grep -q "100.100.100.100" /etc/resolv.conf'
chk "ip rule table 52 has no --accept-routes interference (no prio 5210..5250)" sh -c '! ip rule show | grep -qE "^52[1-5][0-9]:" && ! ip -6 rule show | grep -qE "^52[1-5][0-9]:"'
chk "99-tailscale.conf binds tailscale0 without DHCP" sh -c 'grep -q "^interface=tailscale0$" /run/dnsmasq.dhcp.conf.d/99-tailscale.conf && grep -q "^no-dhcp-interface=tailscale0$" /run/dnsmasq.dhcp.conf.d/99-tailscale.conf'
TS_V4=$(ip -4 -o addr show dev tailscale0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)
TS_V6=$(ip -6 -o addr show dev tailscale0 scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)
chk "dnsmasq Split DNS answers Dream-Machine-Pro over tailscale0 ($TS_V4)" sh -c '[ -n "'"$TS_V4"'" ] && [ -n "$(dig +short +time=2 +tries=1 @"'"$TS_V4"'" Dream-Machine-Pro 2>/dev/null)" ]'
chk "TS_ISOLATE v4 isolates br2 (10.0.10.0/26) from tailscale0 (hooked once)" sh -c '[ "$(iptables -w 30 -S FORWARD | grep -c -- "-j TS_ISOLATE$")" = 1 ] && iptables -w 30 -C TS_ISOLATE -i tailscale0 -o br2 -j DROP && iptables -w 30 -C TS_ISOLATE -i br2 -o tailscale0 -j DROP && iptables -w 30 -C TS_ISOLATE -i tailscale0 -d 10.0.10.0/26 -j DROP'
chk "TS_ISOLATE v6 isolates br2 from tailscale0 (hooked once)" sh -c '[ "$(ip6tables -w 30 -S FORWARD | grep -c -- "-j TS_ISOLATE$")" = 1 ] && ip6tables -w 30 -C TS_ISOLATE -i tailscale0 -o br2 -j DROP && ip6tables -w 30 -C TS_ISOLATE -i br2 -o tailscale0 -j DROP'
chk "TS_ISOLATE precedes UBIOS_FORWARD_JUMP (v4+v6)" bash -c 'for ipt in iptables ip6tables; do t=$($ipt -w 30 -S FORWARD | grep -v "^-P" | grep -n -- "-j TS_ISOLATE$" | head -1 | cut -d: -f1); u=$($ipt -w 30 -S FORWARD | grep -v "^-P" | grep -n -- "-j UBIOS_FORWARD_JUMP$" | head -1 | cut -d: -f1); [ -n "$t" ] && [ -n "$u" ] && [ "$t" -lt "$u" ] || exit 1; done'
TS_DNS_NAME=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//')
if [ -n "$TS_DNS_NAME" ] && openssl s_client -connect 127.0.0.1:443 -servername "$TS_DNS_NAME" </dev/null 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | grep -q "CN=$TS_DNS_NAME"; then
  ok "unifi-core TLS serves Tailscale cert for $TS_DNS_NAME"
else
  warn "unifi-core TLS not yet serving Tailscale cert for ${TS_DNS_NAME:-udm-pro}"
fi

echo "== DNS / resolver"
chk "dnsmasq forwards to NextDNS CLI (nextdns.conf server=127.0.0.1#5342)" /data/nextdns-dnsmasq-wire/check.sh --check-only
chk "UniFi Native DoH (dnscrypt-proxy) disabled — NextDNS CLI owns DNS" sh -c '! pgrep -x dnscrypt-proxy >/dev/null 2>&1'
chk "/etc/hosts.dnsmasq provisioned for NextDNS client names" test -s /etc/hosts.dnsmasq
chk "LAN MagicDNS forwarder resolves udm-pro.tailb8263.ts.net -> $TS_V4" sh -c '[ -n "'"$TS_V4"'" ] && [ "$(dig +short +time=2 +tries=1 @10.0.0.1 udm-pro.tailb8263.ts.net 2>/dev/null | head -n1)" = "'"$TS_V4"'" ]'
chk "ip6tnl2 resolv = NextDNS Global anycast only" sh -c 'grep -q "^nameserver 45.90.28.0" /run/resolv.conf.d/ip6tnl2 && grep -q "^nameserver 45.90.30.0" /run/resolv.conf.d/ip6tnl2 && ! grep -qE "^nameserver (1\.1\.1\.1|8\.8|45\.90\.(28|30)\.74)" /run/resolv.conf.d/ip6tnl2'
chk "v4 :53 DNAT chain (8 rules incl. tailscale0 ! -d TS_V4) hooked once" sh -c '[ "$(iptables -w 30 -t nat -S UDM_DNS_HIJACK | grep -c DNAT)" = 8 ] && [ -n "'"$TS_V4"'" ] && iptables -w 30 -t nat -S UDM_DNS_HIJACK | grep -q -- "! -d '"$TS_V4"'/32 -i tailscale0" && [ "$(iptables -w 30 -t nat -S PREROUTING | grep -c -- "-j UDM_DNS_HIJACK$")" = 1 ]'
chk "v6 :53 DNAT chain (6 rules incl. tailscale0 ! -d TS_V6) hooked once" sh -c '[ "$(ip6tables -w 30 -t nat -S UDM_DNS_HIJACK | grep -c DNAT)" = 6 ] && [ -n "'"$TS_V6"'" ] && ip6tables -w 30 -t nat -S UDM_DNS_HIJACK | grep -q -- "! -d '"$TS_V6"'/128 -i tailscale0" && [ "$(ip6tables -w 30 -t nat -S PREROUTING | grep -c -- "-j UDM_DNS_HIJACK$")" = 1 ]'
chk "v4/v6 UDM-local OUTPUT :53 redirect (UDM_DNS_HIJACK_OUT) hooked once" bash -c '[ "$(iptables -w 30 -t nat -S UDM_DNS_HIJACK_OUT | grep -c "REDIRECT --to-ports 53")" = 2 ] && [ "$(iptables -w 30 -t nat -S OUTPUT | grep -c -- "-j UDM_DNS_HIJACK_OUT$")" = 1 ] && [ "$(ip6tables -w 30 -t nat -S UDM_DNS_HIJACK_OUT | grep -c "DNAT --to-destination \[2a07:a8c0::21:553f\]:53")" = 2 ] && [ "$(ip6tables -w 30 -t nat -S OUTPUT | grep -c -- "-j UDM_DNS_HIJACK_OUT$")" = 1 ]'
chk "UDM_NEXTDNS_V4 = 2 global anycast entries" sh -c '[ "$(ipset list UDM_NEXTDNS_V4 | grep -cE "^45\.90")" = 2 ]'
chk "UDM_NEXTDNS_V6 = 2 entries" sh -c '[ "$(ipset list UDM_NEXTDNS_V6 | grep -c "^2a07")" = 2 ]'
for p in "iptables UDM_DOH_BLOCK" "ip6tables UDM_DOH_BLOCK6"; do
  set -- $p
  for proto in tcp udp; do
    chk "DoH block $2: ipset 10 + $proto/443 FORWARD DROP once" sh -c '[ "$(ipset list "$2" | grep -cE "^[0-9a-f]+[.:]")" = 10 ] && [ "$($1 -w 30 -S FORWARD | grep -c -- "-p $3 .*--match-set $2 dst -j DROP")" = 1 ]' _ "$1" "$2" "$proto"
  done
done
chk "UBIOS DoT allowlist v4 has NextDNS DoT" sh -c 'ipset list UBIOS4policy_dst_dn_75 | grep -q 103.170.232.254 && ipset list UBIOS4policy_dst_dn_75 | grep -q 167.179.109.118'
chk "UBIOS DoT allowlist v6 has NextDNS DoT" sh -c 'ipset list UBIOS6policy_dst_dn_75 | grep -q 2a0b:4341:b02:166 && ipset list UBIOS6policy_dst_dn_75 | grep -q 2001:19f0:7001:5e19'

echo "== IPv6 / NURO"
chk "v6 PBR 30000 :29f1 -> 201.eth10" sh -c 'ip -6 rule show priority 30000 | grep -q "from 240d:f:fc4:29f1::/64 lookup 201.eth10"'
chk "v6 PBR 30001 :29f2 -> 201.eth10" sh -c 'ip -6 rule show priority 30001 | grep -q "from 240d:f:fc4:29f2::/64 lookup 201.eth10"'
chk "ndppd conf rules :29f1/:29f2 static" sh -c 'grep -q "rule 240d:f:fc4:29f1::/64 { static }" /etc/ndppd.conf && grep -q "rule 240d:f:fc4:29f2::/64 { static }" /etc/ndppd.conf'
chk "proxy_ndp eth10/all = 1" sh -c '[ "$(sysctl -n net.ipv6.conf.eth10.proxy_ndp)$(sysctl -n net.ipv6.conf.all.proxy_ndp)" = 11 ]'
chk "br0/br2/br3 v6 forwarding = 1" sh -c '[ "$(sysctl -n net.ipv6.conf.br0.forwarding)$(sysctl -n net.ipv6.conf.br2.forwarding)$(sysctl -n net.ipv6.conf.br3.forwarding)" = 111 ]'
chk "br0 has 240d:f:fc4:29f1::1/64" sh -c 'ip -6 addr show br0 | grep -q "240d:f:fc4:29f1::1/64"'
chk "br3 has 240d:f:fc4:29f2::1/64" sh -c 'ip -6 addr show br3 | grep -q "240d:f:fc4:29f2::1/64"'
chk "br2 (IoT) has no NURO v6" sh -c '! ip -6 addr show br2 | grep -q "240d:f:fc4"'
chk "eth10 has :29f0 address" sh -c 'ip -6 addr show eth10 | grep -q "240d:f:fc4:29f0:"'

echo "== WAN2 MAP-E (JPIX, since 2026-11-02)"
chk "ip6tnl2 remote = JPIX BR 2001:260:700:1::1:275" sh -c 'ip -d link show ip6tnl2 | grep -q "remote 2001:260:700:1::1:275"'
chk "MAP_E-POSTROUTING SNATs ip6tnl2 (tcp/udp/icmp)" sh -c 'r=$(iptables -w 30 -t nat -S MAP_E-POSTROUTING) || exit 1; for p in tcp udp icmp; do printf "%s\n" "$r" | grep -q -- "-o ip6tnl2 -p $p .*-j SNAT" || exit 1; done'
chk "no un-NATed conntrack (reply-dst 192.0.0.3)" sh -c '[ "$(conntrack -L -q 192.0.0.3 2>/dev/null | wc -l)" = 0 ]'
chk "eth8 accept_dad = 0 (CE re-add not held tentative, CONTEXT Q44)" sh -c '[ "$(cat /proc/sys/net/ipv6/conf/eth8/accept_dad)" = 0 ]'

echo "== memory (CONTEXT Q43)"
chk "net.core rmem/wmem_default = 212992" sh -c '[ "$(sysctl -n net.core.rmem_default)" = 212992 ] && [ "$(sysctl -n net.core.wmem_default)" = 212992 ]'
chk "raw socket Recv-Q total < 64MB (dpinger send sockets)" sh -c '[ "$(ss -anw 2>/dev/null | awk "NR>1{s+=\$2} END{print int(s/1048576)}")" -lt 64 ]'
chk "netlink Rmem total < 32MB (udapi-bridge unread route sockets, CONTEXT Q47)" sh -c '[ "$(awk "NR>1{s+=\$5} END{print int(s/1048576)}" /proc/net/netlink)" -lt 32 ]'
chk "tcp_mem high < 1GB (kernel default, CONTEXT Q47)" sh -c '[ "$(awk "{print \$3}" /proc/sys/net/ipv4/tcp_mem)" -lt 262144 ]'
chk "MemAvailable > 512MB" sh -c '[ "$(awk "/MemAvailable/{print int(\$2/1024)}" /proc/meminfo)" -gt 512 ]'
chk "stock dnsmasq.service not failed (CONTEXT Q48)" sh -c '! systemctl is-failed --quiet dnsmasq.service'
chk "MAP-E fallback has saved parameters (CONTEXT Q41)" test -s /data/udm-mape-fallback/ip6tnl-parameters
chk "api.enabler.ne.jp pinned to NGN DNS answer in /etc/hosts (CONTEXT Q41)" sh -c 'sed -n "/^# udm-mape-fallback begin$/,/^# udm-mape-fallback end$/p" /etc/hosts | grep -q " api.enabler.ne.jp$"'

echo "== OS & network tuning (CONTEXT Q49 / Q50)"
chk "/dev/boot queue scheduler=deadline, rotational=0" sh -c 'grep -q "\[deadline\]" /sys/block/boot/queue/scheduler && [ "$(cat /sys/block/boot/queue/rotational)" = 0 ]'
for p in 5434 5432; do
  chk "pg port $p: checkpoint=15min, wal_comp=on, fsync=on, fpw=on, jit=off" bash -c 'o=$(su - postgres -c "psql -p $1 -tAc \"SHOW checkpoint_timeout; SHOW wal_compression; SHOW fsync; SHOW full_page_writes; SHOW jit;\"" | tr "\n" " "); [ "$o" = "15min on on on off " ]' _ "$p"
done
chk "vm.page-cluster=0, vfs_cache_pressure=100, watermark_scale_factor=50" sh -c '[ "$(sysctl -n vm.page-cluster)" = 0 ] && [ "$(sysctl -n vm.vfs_cache_pressure)" = 100 ] && [ "$(sysctl -n vm.watermark_scale_factor)" = 50 ]'
chk "CPU priority: nextdns NI=-10 & tailscaled NI=-5" bash -c '[ "$(ps -o ni= -p "$(systemctl show -p MainPID --value nextdns.service)" | tr -d "[:space:]")" = "-10" ] && [ "$(ps -o ni= -p "$(systemctl show -p MainPID --value tailscaled.service)" | tr -d "[:space:]")" = "-5" ]'
for dev in eth8 eth9 eth10 switch0; do
  chk "$dev: fq_codel (limit 1024p) on 4 mq leaves" bash -c '[ "$(tc qdisc show dev "$1" | grep -c "^qdisc fq_codel .* limit 1024p ")" = 4 ]' _ "$dev"
  chk "$dev: 1:1 TX XPS (1 2 4 8)" bash -c '[ "$(cat /sys/class/net/"$1"/queues/tx-*/xps_cpus | tr "\n" " ")" = "1 2 4 8 " ]' _ "$dev"
done
chk "eth8: RX RPS stays f f f f (ip6tnl2 scatter)" sh -c '[ "$(cat /sys/class/net/eth8/queues/rx-*/rps_cpus | tr "\n" " ")" = "f f f f " ]'
chk "tailscale0: fq_codel (limit 1000p) & txqueuelen=1000" sh -c 'tc qdisc show dev tailscale0 | grep -q "^qdisc fq_codel .* root .* limit 1000p " && [ "$(cat /sys/class/net/tailscale0/tx_queue_len)" = 1000 ]'
chk "earlyoom drop-in (-r 3600 --dryrun) & systemd-oomd active" sh -c 'systemctl is-active --quiet systemd-oomd && ps -o args= -C earlyoom | grep -q -- "-r 3600" && ps -o args= -C earlyoom | grep -q -- "--dryrun"'
chk "zram0 next-boot COMP_ALGORITHM=zstd staged" sh -c 'grep -qx "COMP_ALGORITHM=zstd" /etc/default/ubnt-zram-swap'
chk "fwupd.service & fwupd-refresh.timer masked (not running)" sh -c '! pgrep -x fwupd >/dev/null 2>&1 && [ "$(systemctl is-enabled fwupd.service 2>/dev/null || true)" = "masked" ] && [ "$(systemctl is-enabled fwupd-refresh.timer 2>/dev/null || true)" = "masked" ]'
chk "unifi-native-guard pin covers iptables & frr" sh -c 'grep -qw iptables /etc/apt/preferences.d/30-unifi-native-protect && grep -qw frr /etc/apt/preferences.d/30-unifi-native-protect'

echo "== dpinger-hijack (display-only monitors)"
chk "UDM_DPINGER_HIJACK hooked once + has rules" sh -c '[ "$(iptables -w 30 -t nat -S OUTPUT | grep -c -- "-j UDM_DPINGER_HIJACK$")" = 1 ] && [ "$(iptables -w 30 -t nat -S UDM_DPINGER_HIJACK | grep -c DNAT)" -ge 1 ]'
chk "no probe-hostname override in /etc/hosts" sh -c '! grep -qE "BEGIN udm-dpinger-hijack|^[0-9a-f.:]+ +(ping\.ui\.com|google\.com|www\.microsoft\.com)( |$)" /etc/hosts'
chk "dnsmasq answers google.com with a non-NextDNS IP" sh -c 'a=$(dig +short +time=2 A google.com @10.0.0.1 | head -1); [ -n "$a" ] && ! echo "$a" | grep -q "^45\.90\."'
LEAK=$(conntrack -L -n 2>/dev/null | grep -E "src=(10\.0\.1\.2|192\.0\.0\.3) " | grep -E "dst=(1\.1\.1\.1|8\.8\.8\.8|23\.|142\.251\.|192\.178\.)" | grep -vE "src=45\.90\." | grep -c .)
[ "$LEAK" = 0 ] && ok "no UDM-local probe flow replying from non-NextDNS" || ng "UDM-local probe flows still answered by third party: $LEAK"

echo "== traffic routes (PBR)"
ST=/data/udapi-config/ubios-udapi-server/ubios-udapi-server.state
route_ok() {  # $1=v4 subnet  $2=pbr table
    local set
    set=$(for s in $(ipset list -n | grep -E '^UBIOS4trafficroute_net4_[0-9]+$'); do
        ipset list "$s" | grep -qx "$1" && echo "${s#UBIOS4}"; done)
    [ -n "$set" ] && jq -e --arg s "$set" --argjson t "$2" \
        '[.["firewall/pbr"].rules[] | select(.enabled and .source.sets[0]==$s) | .routingMode.pbrTable == $t] | (length > 0 and all)' "$ST"
}
chk "IoT 10.0.10.0/26 -> WAN2 (table 202)" route_ok 10.0.10.0/26 202
chk "Media 10.0.3.0/26 -> WAN1 (table 201)" route_ok 10.0.3.0/26 201
chk "Default 10.0.0.0/24 -> WAN1 (table 201)" route_ok 10.0.0.0/24 201

echo "== LAN IPv6 via NURO"
V6=$(conntrack -L -f ipv6 2>/dev/null | grep ESTABLISHED | grep -E 'src=240d:f:fc4:29f[12]:')
[ -n "$V6" ] && ok "LAN v6 flows established ($(echo "$V6" | grep -c .))" || warn "no established LAN v6 flows from :29f1/:29f2 right now"

echo "== QoS (tc)"
for w in eth10 eth8 ip6tnl2; do
  chk "$w: no htb root, no ingress redirect" bash -c 'o=$(tc qdisc show dev "$1") && [ -n "$o" ] && ! grep -q "^qdisc htb" <<<"$o" && ! tc filter show dev "$1" parent ffff: 2>/dev/null | grep -q mirred' _ "$w"
done

echo "== WAN SLA (local net-cfg / dpinger)"
NX='["45.90.28.0","45.90.28.74","45.90.30.0","45.90.30.74"]'
N=$(ls -t /data/udapi-config/udapi-net-cfg-*.json 2>/dev/null | head -1 || true)
if [ -n "$N" ]; then
  for w in eth10 ip6tnl2; do
    chk "net-cfg $w-0..3 = NextDNS ICMP" bash -c 'jq -e --arg w "$1" --argjson nx "$2" "[.\"sla/monitors\".monitors[] | select(.id|test(\"^\" + \$w + \"-[0-3]\$\")) | select(.type==\"icmp\") | .target] | sort == \$nx" "$3"' _ "$w" "$NX" "$N"
    chk "net-cfg $w-4..7 = NextDNS DNS" bash -c 'jq -e --arg w "$1" --argjson nx "$2" "[.\"sla/monitors\".monitors[] | select(.id|test(\"^\" + \$w + \"-[4-7]\$\")) | select(.type==\"dns\") | .target] | sort == \$nx" "$3"' _ "$w" "$NX" "$N"
  done
  chk "policies wfg-0/1 use only -0..7" bash -c 'jq -e "[.\"sla/policies\".policies[] | .probes[0].monitors | map(test(\"-[0-7]\$\")) | all] | all" "$1"' _ "$N"
fi
for w in eth10 ip6tnl2; do
  chk "running dpinger $w-0..3 on NextDNS" sh -c "[ \"\$(ps -o args= -C dpinger | grep -oE 'dpinger-$w-[0-3]-45\.90\.[0-9.]+ ' | sort -u | wc -l)\" = 4 ]"
done

if [ -n "$K" ]; then
  echo "== Controller API checks"
  ENR=$(api /v2/api/site/default/wan/enriched-configuration)
  SLAID=$(printf %s "$ENR" | jq -r '.[] | select(.configuration.name=="NURO 10G") | .configuration.wan_sla // empty')
  SLA=$(api /v2/api/site/default/wan-slas)
  chk "NURO has a WAN SLA" test -n "$SLAID"
  chk "BB.excite uses the same WAN SLA" bash -c 'printf %s "$1" | jq -e --arg id "$2" "any(.[]; .configuration.wan_sla == \$id and (.configuration.name|startswith(\"BB.excite\")))"' _ "$ENR" "$SLAID"
  for t in ICMP DNS; do
    chk "WAN SLA $t monitors = 4 NextDNS targets" bash -c 'printf %s "$1" | jq -e --arg id "$2" --arg t "$3" --argjson nx "$4" ".[] | select(._id==\$id) | [.monitors[] | select(.type==\$t) | .target] | sort == \$nx"' _ "$SLA" "$SLAID" "$t" "$NX"
  done
  chk "WAN SLA has no non-NextDNS monitor" bash -c 'printf %s "$1" | jq -e --arg id "$2" ".[] | select(._id==\$id) | (.monitors|length) > 0 and all(.monitors[]; .target|startswith(\"45.90.\"))"' _ "$SLA" "$SLAID"
  H=$(api /api/s/default/stat/health)
  chk "UI health: both WANs alerting monitors = NextDNS ICMP/DNS" bash -c 'printf %s "$1" | jq -e "[.data[] | select(.subsystem==\"wan\") | .uptime_stats | to_entries[] | .value.alerting_monitors | map((.type==\"icmp\" or .type==\"dns\") and (.target|startswith(\"45.90.\"))) | all] | (length==2 and all)"' _ "$H"
  AVAIL_SUMMARY=$(printf %s "$H" | jq -r '[.data[] | select(.subsystem=="wan") | .uptime_stats | to_entries[] | "\(.key)=\(.value.availability)"] | join(" ")')
  UPTIME_S=$(awk '{print int($1)}' /proc/uptime)
  if printf %s "$H" | jq -e '[.data[] | select(.subsystem=="wan") | .uptime_stats | to_entries[] | .value.availability == 100] | (length==2 and all)' >/dev/null 2>&1; then
    ok "WAN1/WAN2 availability 100"
  elif [ "$UPTIME_S" -lt 86400 ] && printf %s "$H" | jq -e '[.data[] | select(.subsystem=="wan") | .uptime_stats | to_entries[] | .value.availability > 0] | (length==2 and all)' >/dev/null 2>&1; then
    warn "WAN1/WAN2 availability < 100 within 24h of reboot (uptime $((UPTIME_S/60))m; $AVAIL_SUMMARY)"
  else
    ng "WAN1/WAN2 availability 100 ($AVAIL_SUMMARY)"
  fi

  U=$(api /api/s/default/rest/setting/usg)
  chk "usg echo_server = 45.90.28.0" sh -c "echo '$U' | jq -e '.data[0].echo_server == \"45.90.28.0\"'"
  chk "usg dns_verification = manual NextDNS (no 1.1.1.1/8.8.8.8)" sh -c "echo '$U' | jq -e '.data[0].dns_verification.setting_preference == \"manual\" and .data[0].dns_verification.primary_dns_server == \"45.90.28.0\" and .data[0].dns_verification.secondary_dns_server == \"45.90.30.0\"'"
  NC=$(api /api/s/default/rest/networkconf)
  chk "both WAN dns1/2 + v6 dns = NextDNS" sh -c "echo '$NC' | jq -e '[.data[] | select(.purpose==\"wan\") | (.wan_dns1|startswith(\"45.90.\")) and (.wan_dns2|startswith(\"45.90.\")) and .wan_ipv6_dns1==\"2a07:a8c0::21:553f\" and .wan_ipv6_dns2==\"2a07:a8c1::21:553f\"] | (length==2 and all)'"
  chk "WAN2 wan_type = map-e,jpix" sh -c "echo '$NC' | jq -e '.data[] | select(.wan_networkgroup==\"WAN2\") | .wan_type==\"map-e,jpix\"'"
  chk "Default VLAN v6 static :29f1::1/64" sh -c "echo '$NC' | jq -e 'any(.data[]; .ipv6_interface_type==\"static\" and .ipv6_subnet==\"240d:f:fc4:29f1::1/64\")'"
  chk "Media VLAN v6 static :29f2::1/64" sh -c "echo '$NC' | jq -e 'any(.data[]; .ipv6_interface_type==\"static\" and .ipv6_subnet==\"240d:f:fc4:29f2::1/64\")'"
  chk "IoT VLAN v6 none" sh -c "echo '$NC' | jq -e 'any(.data[]; (.ip_subnet//\"\")==\"10.0.10.1/26\" and .ipv6_interface_type==\"none\")'"

  Q=$(api /v2/api/site/default/qos-rules)
  chk "QoS rules all disabled" bash -c 'printf %s "$1" | jq -e "all(.[]; .enabled==false)"' _ "$Q"

  WIFI=$(/data/udm-dfs-restore/udm-dfs-restore.sh --check 2>&1); rc=$?
  if [ "$rc" = 0 ]; then
    ok "all 5 GHz radios on their configured channel"
  else
    n=$(grep -c '^FAIL' <<<"$WIFI" || true)
    [ "$n" -gt 0 ] && printf '%s\n' "$WIFI" || ng "udm-dfs-restore --check failed (rc=$rc): $WIFI"
    FAILS=$((FAILS + n))
  fi
else
  warn "controller API checks skipped (/data/unifi-api.key not provisioned)"
fi

echo
printf 'audit summary: %d FAIL, %d WARN\n' "$FAILS" "$WARNS"
[ "$FAILS" = 0 ] && echo "audit: all checks passed" || echo "audit: $FAILS check(s) FAILED"
exit "$FAILS"
