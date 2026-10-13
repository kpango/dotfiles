cat << 'EOF' > /tmp/udm-deep-trace.sh
#!/usr/bin/env bash
#
# udm-deep-trace.sh
# Ultra-Deep Diagnostic & Packet-Flow Tracing Script for UDM-Pro
#

set -u

TARGET="8.8.8.8"
TUNNEL_V4="192.0.0.2"
LAN_V4="10.0.0.1"
TUNNEL_PEER_V6="2404:8e00::feed:100"

echo "================================================================================"
echo " UDM-Pro Ultra-Deep Diagnostic Report - $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================================"

sec() {
    echo ""
    echo "================================================================================"
    echo ">>> $1"
    echo "================================================================================"
}

subsec() {
    echo ""
    echo "--- $1 ---"
}

# 1. 物理リンクおよび仮想インターフェースの詳細状態
sec "1. Detailed Interface Status & Interface Counters"
subsec "Link and Tunnel flags (ip -d link)"
ip -d link show eth8
ip -d link show eth10
ip -d link show ip6tnl1 2>&1 || echo "ip6tnl1 does not exist"

subsec "Interface Statistics & Dropped Packet Counters (ip -s link)"
ip -s link show eth8
ip -s link show ip6tnl1 2>&1 || true

subsec "IP Addresses with Flags (tentative, dadfailed, etc.)"
ip addr show dev eth8
ip addr show dev eth10
ip addr show dev ip6tnl1 2>&1 || true

# 2. IPv6 アンダーレイおよびネイバー・ルーティング詳細
sec "2. IPv6 Underlay, Neighbor Cache & Nexthop State"
subsec "IPv6 Neighbor Table (Full)"
ip -6 neigh show

subsec "Route get to Tunnel Peer (2404:8e00::feed:100)"
ip -6 route get "$TUNNEL_PEER_V6" 2>&1 || true

subsec "Route get from eth8 IPv6 to Peer"
ETH8_V6=$(ip -6 addr show dev eth8 scope global | grep inet6 | awk '{print $2}' | cut -d/ -f1 | head -n 1)
if [ -n "$ETH8_V6" ]; then
    ip -6 route get "$TUNNEL_PEER_V6" from "$ETH8_V6" 2>&1 || true
else
    echo "No global IPv6 found on eth8"
fi

subsec "All IPv6 Routes on eth8"
ip -6 route show dev eth8

# 3. ルーティングテーブルおよびポリシーの完全ダンプ
sec "3. Comprehensive Routing & Policy Dump"
subsec "IPv4 Rules (ip rule show)"
ip rule show

subsec "Table main (IPv4)"
ip route show table main

subsec "Table 201 (UniFi WAN / ip6tnl1)"
ip route show table 201 2>&1 || true

subsec "Table 202 (WAN2 / eth10)"
ip route show table 202 2>&1 || true

subsec "Kernel Route Resolution for 8.8.8.8 (Default, Tunnel IP, and LAN IP)"
echo -n "ip route get 8.8.8.8: "
ip route get 8.8.8.8 2>&1 || true
echo -n "ip route get 8.8.8.8 from $TUNNEL_V4: "
ip route get 8.8.8.8 from "$TUNNEL_V4" 2>&1 || true
echo -n "ip route get 8.8.8.8 from $LAN_V4: "
ip route get 8.8.8.8 from "$LAN_V4" 2>&1 || true

# 4. カーネル L3/L4 プロトコル統計 & パケットドロップカウンタ
sec "4. Kernel Network Drops & Error Counters"
subsec "Kernel SNMP IP/ICMP Error Statistics (netstat -s or /proc/net/snmp)"
if command -v netstat >/dev/null 2>&1; then
    netstat -s | grep -E -i 'drop|error|fail|unreach' | head -n 30
else
    cat /proc/net/snmp | head -n 10
fi

subsec "IPv6 SNMP Counters (/proc/net/snmp6)"
grep -E -i 'drop|outnoroutes|outerrors|fragok|inerrors' /proc/net/snmp6 || true

# 5. Netfilter / ファイアウォール詳細
sec "5. Firewall Inspection (Mangle, NAT, Raw, and Filters)"
subsec "Raw Table (PREROUTING / OUTPUT - Check for drops before routing)"
iptables -t raw -L -v -n 2>/dev/null || echo "raw table empty or unavailable"

subsec "NAT Table (POSTROUTING with packet counts)"
iptables -t nat -L POSTROUTING -v -n --line-numbers

subsec "Mangle Table (PREROUTING & FORWARD with marks)"
iptables -t mangle -L PREROUTING -v -n --line-numbers 2>/dev/null | head -n 30 || true
iptables -t mangle -L FORWARD -v -n --line-numbers 2>/dev/null | head -n 30 || true

subsec "Filter FORWARD Chain (Rules with actual drop/reject targets)"
iptables -L FORWARD -v -n --line-numbers | grep -E 'DROP|REJECT|UBIOS' | head -n 30 || true

# 6. リアルタイム・マルチインターフェース同時パケットトレース
sec "6. Live Simultaneous Multi-Interface Packet Capture"
echo "Starting simultaneous capture on ip6tnl1, eth8, and lo while sending 2 test pings..."

CAPTURE_LOG="/tmp/tcpdump_deep_capture.log"
rm -f "$CAPTURE_LOG"

# 1) ip6tnl1 (IPv4 ICMP)
timeout 3 tcpdump -nn -i ip6tnl1 icmp > /tmp/dump_ip6tnl1.log 2>&1 &
PID1=$!

# 2) eth8 (IPv6 proto 4 or ICMPv6)
timeout 3 tcpdump -nn -i eth8 '(ip6 and proto 4) or icmp6' > /tmp/dump_eth8.log 2>&1 &
PID2=$!

# 3) eth10 (IPv4 or IPv6 - Check if leaking to WAN2)
timeout 3 tcpdump -nn -i eth10 'host 8.8.8.8 or (ip6 and proto 4)' > /tmp/dump_eth10.log 2>&1 &
PID3=$!

sleep 0.5
echo "[Probe] Executing: ping -c 2 -W 1 -I $TUNNEL_V4 $TARGET"
ping -c 2 -W 1 -I "$TUNNEL_V4" "$TARGET" 2>&1 || true

wait $PID1 2>/dev/null || true
wait $PID2 2>/dev/null || true
wait $PID3 2>/dev/null || true

subsec "Captured on ip6tnl1 (Inner IPv4 ICMP)"
cat /tmp/dump_ip6tnl1.log
rm -f /tmp/dump_ip6tnl1.log

subsec "Captured on eth8 (Outer Encapsulated / ICMPv6)"
cat /tmp/dump_eth8.log
rm -f /tmp/dump_eth8.log

subsec "Captured on eth10 (Check for Wrong Interface Egress)"
cat /tmp/dump_eth10.log
rm -f /tmp/dump_eth10.log

# 7. DNS & ソケット状態
sec "7. DNS Resolver & Socket Bindings"
ps aux | grep '[d]nsmasq' || echo "No dnsmasq running"
echo ""
ss -tulpn | grep ':53 ' || echo "No listener on port 53"

echo "================================================================================"
echo " End of Ultra-Deep Diagnostic Report"
echo "================================================================================"
EOF

chmod +x /tmp/udm-deep-trace.sh
/tmp/udm-deep-trace.sh

