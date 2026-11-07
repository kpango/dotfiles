#!/bin/sh
# UDM Pro performance sysctl tuning
# Deploy: /data/on_boot.d/05-sysctl.sh (run at boot by udm-boot.service in this directory)
# Note: /data/ persists across reboots; wiped only on factory reset / firmware reinstall.

set -e

# Conntrack: 65536 (default) is critically low for a gateway router.
# 1M entries @ ~288 bytes each ≈ 288MB — acceptable for 2GB+ RAM systems.
sysctl -w net.netfilter.nf_conntrack_max=1048576
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=3600
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=30

# BBR congestion control (available in 4.9+; UDM Pro runs 4.19)
if modprobe tcp_bbr 2>/dev/null; then
    sysctl -w net.ipv4.tcp_congestion_control=bbr
    sysctl -w net.core.default_qdisc=fq
else
    # fallback: fq_codel for active queue management (prevents bufferbloat)
    sysctl -w net.core.default_qdisc=fq_codel 2>/dev/null || true
fi

# Larger socket buffers for the WAN-facing TCP stack
sysctl -w net.core.rmem_max=134217728
sysctl -w net.core.wmem_max=134217728
# Keep the *_default at the kernel default (212992). A 16MB default applied to every
# socket, including dpinger's raw ICMP sockets that receive a copy of every ICMP packet
# and are never drained: 19 of them sat full at 16MB (301MB Recv-Q), which drove the UDM
# into swap thrashing and an OOM kill (2026-11-06). Apps that want more opt in up to *_max.
sysctl -w net.core.rmem_default=212992
sysctl -w net.core.wmem_default=212992

# TCP Fast Open (client + server)
sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null || true

# Increase ARP cache for large LAN segments
sysctl -w net.ipv4.neigh.default.gc_thresh1=2048
sysctl -w net.ipv4.neigh.default.gc_thresh2=8192
sysctl -w net.ipv4.neigh.default.gc_thresh3=16384

# WAN2 (eth8, MAP-E): udapi's WAN-Diag deletes the MAP-E CE /128 every ~3 min and udapi
# re-adds it within ms, but DAD then holds it tentative ~1.5s and ip6tnl2 drops every
# packet meanwhile ("Local address not yet configured!"). Skip DAD on this WAN link.
sysctl -w net.ipv6.conf.eth8.accept_dad=0 2>/dev/null || true

echo "[05-sysctl] Applied UDM Pro performance sysctl"
