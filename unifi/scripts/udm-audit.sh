#!/bin/bash
# udm-audit.sh — read-only on-box audit of every out-of-band UDM Pro setting
# managed by this repo (unifi/data/*) plus the controller-side values they
# depend on (WAN SLA, usg, networkconf, traffic routes). Prints one PASS/FAIL
# line per check and exits with the number of failures (0 = all good).
#
# Runs ON the UDM: streamed by unifi-audit.sh as `ssh udmpro bash -s`.
# Never mutates state. Needs /data/nextdns-client-names/api-key for the
# controller API checks.
set -u
FAILS=0
ok()  { printf 'PASS  %s\n' "$*"; }
ng()  { printf 'FAIL  %s\n' "$*"; FAILS=$((FAILS + 1)); }
chk() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else ng "$d"; fi; }

K=$(cat /data/nextdns-client-names/api-key 2>/dev/null) || { ng "api key /data/nextdns-client-names/api-key missing"; exit "$FAILS"; }
api() { curl -ksS -H "X-API-KEY: $K" "https://127.0.0.1/proxy/network$1"; }

echo "== units"
for u in udm-sla-tune.timer udm-nuro-v6-pbr.timer udm-dns-hijack.timer udm-dpinger-hijack.timer udm-verifier-enforcer.timer clean-clients.timer ndppd.service; do
  chk "$u active+enabled" sh -c "systemctl is-active --quiet $u && systemctl is-enabled --quiet $u"
done
for s in udm-sla-tune udm-nuro-v6-pbr udm-dns-hijack udm-dpinger-hijack udm-verifier-enforcer clean-clients; do
  chk "$s.service last run not failed" sh -c "! systemctl is-failed --quiet $s.service"
done

echo "== DNS / resolver"
chk "ip6tnl2 resolv = NextDNS only" sh -c 'grep -q "^nameserver 45.90.28.74" /run/resolv.conf.d/ip6tnl2 && grep -q "^nameserver 45.90.30.74" /run/resolv.conf.d/ip6tnl2 && ! grep -qE "^nameserver (1\.1\.1\.1|8\.8)" /run/resolv.conf.d/ip6tnl2'
chk "v4 :53 DNAT chain (6 rules) hooked once" sh -c '[ "$(iptables -w 30 -t nat -S UDM_DNS_HIJACK | grep -c DNAT)" = 6 ] && [ "$(iptables -w 30 -t nat -S PREROUTING | grep -c -- "-j UDM_DNS_HIJACK$")" = 1 ]'
chk "v6 :53 DNAT chain (4 rules) hooked once" sh -c '[ "$(ip6tables -w 30 -t nat -S UDM_DNS_HIJACK | grep -c DNAT)" = 4 ] && [ "$(ip6tables -w 30 -t nat -S PREROUTING | grep -c -- "-j UDM_DNS_HIJACK$")" = 1 ]'
chk "UDM_NEXTDNS_V4 = 4 entries" sh -c '[ "$(ipset list UDM_NEXTDNS_V4 | grep -cE "^45\.90")" = 4 ]'
chk "UDM_NEXTDNS_V6 = 2 entries" sh -c '[ "$(ipset list UDM_NEXTDNS_V6 | grep -c "^2a07")" = 2 ]'
chk "DoH block ipset 10 + FORWARD DROP once" sh -c '[ "$(ipset list UDM_DOH_BLOCK | grep -cE "^[0-9]")" = 10 ] && [ "$(iptables -w 30 -S FORWARD | grep -c -- "--match-set UDM_DOH_BLOCK dst -j DROP")" = 1 ]'
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

echo "== WAN2 DS-Lite"
chk "ip6tnl2 remote = 2404:8e00::feed:101" sh -c 'ip -d link show ip6tnl2 | grep -q "remote 2404:8e00::feed:101"'

echo "== WAN SLA (official)"
SLA=$(api /v2/api/site/default/wan-slas)
chk "wan-slas has NextDNS w/ 4 ICMP NextDNS targets" sh -c "echo '$SLA' | jq -e '.[] | select(.name==\"NextDNS\") | [.monitors[] | select(.type==\"ICMP\") | .target] | sort == [\"45.90.28.0\",\"45.90.28.74\",\"45.90.30.0\",\"45.90.30.74\"]'"
SLAID=$(echo "$SLA" | jq -r '.[] | select(.name=="NextDNS") | ._id')
ENR=$(api /v2/api/site/default/wan/enriched-configuration)
chk "NURO wan_sla = NextDNS" sh -c "echo '$ENR' | jq -e '.[] | select(.configuration.name==\"NURO 10G\") | .configuration.wan_sla == \"$SLAID\"'"
chk "BB.excite wan_sla = NextDNS" sh -c "echo '$ENR' | jq -e '.[] | select(.configuration.wan_sla == \"$SLAID\" and (.configuration.name|startswith(\"BB.excite\")))'"
N=$(ls -t /data/udapi-config/udapi-net-cfg-*.json | head -1)
for w in eth10 ip6tnl2; do
  chk "net-cfg $w-0..3 = NextDNS ICMP" sh -c "jq -e '[.\"sla/monitors\".monitors[] | select(.id|test(\"^$w-[0-3]\$\")) | select(.type==\"icmp\") | .target] | sort == [\"45.90.28.0\",\"45.90.28.74\",\"45.90.30.0\",\"45.90.30.74\"]' $N"
done
chk "policies wfg-0/1 use only -0..3" sh -c "jq -e '[.\"sla/policies\".policies[] | .probes[0].monitors | map(test(\"-[0-3]\$\")) | all] | all' $N"
for w in eth10 ip6tnl2; do
  chk "running dpinger $w-0..3 on NextDNS" sh -c "[ \"\$(ps -o args= -C dpinger | grep -oE 'dpinger-$w-[0-3]-45\.90\.[0-9.]+ ' | sort -u | wc -l)\" = 4 ]"
done
H=$(api /api/s/default/stat/health)
chk "UI health: both WANs alerting monitors = NextDNS ICMP" sh -c "echo '$H' | jq -e '[.data[] | select(.subsystem==\"wan\") | .uptime_stats | to_entries[] | .value.alerting_monitors | map(.type==\"icmp\" and (.target|startswith(\"45.90.\"))) | all] | (length==2 and all)'"
chk "WAN1/WAN2 availability 100" sh -c "echo '$H' | jq -e '[.data[] | select(.subsystem==\"wan\") | .uptime_stats | to_entries[] | .value.availability == 100] | all'"

echo "== usg / networkconf"
U=$(api /api/s/default/rest/setting/usg)
chk "usg echo_server = 45.90.28.0" sh -c "echo '$U' | jq -e '.data[0].echo_server == \"45.90.28.0\"'"
NC=$(api /api/s/default/rest/networkconf)
chk "both WAN dns1/2 + v6 dns = NextDNS" sh -c "echo '$NC' | jq -e '[.data[] | select(.purpose==\"wan\") | .wan_dns1==\"45.90.28.74\" and .wan_dns2==\"45.90.30.74\" and .wan_ipv6_dns1==\"2a07:a8c0::21:553f\" and .wan_ipv6_dns2==\"2a07:a8c1::21:553f\"] | (length==2 and all)'"
chk "WAN2 AFTR manual feed:101" sh -c "echo '$NC' | jq -e '.data[] | select(.wan_networkgroup==\"WAN2\") | .wan_dslite_remote_host==\"2404:8e00::feed:101\" and .wan_dslite_remote_host_auto==false'"
chk "Default VLAN v6 static :29f1::1/64" sh -c "echo '$NC' | jq -e 'any(.data[]; .ipv6_interface_type==\"static\" and .ipv6_subnet==\"240d:f:fc4:29f1::1/64\")'"
chk "Media VLAN v6 static :29f2::1/64" sh -c "echo '$NC' | jq -e 'any(.data[]; .ipv6_interface_type==\"static\" and .ipv6_subnet==\"240d:f:fc4:29f2::1/64\")'"
chk "IoT VLAN v6 none" sh -c "echo '$NC' | jq -e 'any(.data[]; (.ip_subnet//\"\")==\"10.0.10.1/26\" and .ipv6_interface_type==\"none\")'"

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
[ -n "$V6" ] && ok "LAN v6 flows established ($(echo "$V6" | grep -c .))" || ng "no established LAN v6 flows from :29f1/:29f2"

echo "== dpinger-hijack (display-only monitors)"
chk "UDM_DPINGER_HIJACK hooked once + has rules" sh -c '[ "$(iptables -w 30 -t nat -S OUTPUT | grep -c -- "-j UDM_DPINGER_HIJACK$")" = 1 ] && [ "$(iptables -w 30 -t nat -S UDM_DPINGER_HIJACK | grep -c DNAT)" -ge 1 ]'
chk "no probe-hostname override in /etc/hosts or hosts.dnsmasq" sh -c '! grep -qE "BEGIN udm-dpinger-hijack|^[0-9a-f.:]+ +(ping\.ui\.com|google\.com|www\.microsoft\.com)( |$)" /etc/hosts /etc/hosts.dnsmasq'
chk "NextDNS CLI answers google.com with a non-NextDNS IP" sh -c 'a=$(dig +short +time=2 A google.com @127.0.0.1 -p 5342 | head -1); [ -n "$a" ] && ! echo "$a" | grep -q "^45\.90\."'
LEAK=$(conntrack -L -n 2>/dev/null | grep -E "src=(10\.0\.1\.2|192\.0\.0\.3) " | grep -E "dst=(1\.1\.1\.1|8\.8\.8\.8|23\.|142\.251\.|192\.178\.)" | grep -vE "src=45\.90\." | grep -c .)
[ "$LEAK" = 0 ] && ok "no UDM-local probe flow replying from non-NextDNS" || ng "UDM-local probe flows still answered by third party: $LEAK"

echo
[ "$FAILS" = 0 ] && echo "audit: all checks passed" || echo "audit: $FAILS check(s) FAILED"
exit "$FAILS"
