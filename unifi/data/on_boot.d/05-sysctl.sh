#!/bin/sh
# UDM Pro performance sysctl tuning
# Deploy: /data/on_boot.d/10-sysctl.sh (runs after each boot via unifi-os init)
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
sysctl -w net.core.rmem_default=16777216
sysctl -w net.core.wmem_default=16777216

# TCP Fast Open (client + server)
sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null || true

# Increase ARP cache for large LAN segments
sysctl -w net.ipv4.neigh.default.gc_thresh1=2048
sysctl -w net.ipv4.neigh.default.gc_thresh2=8192
sysctl -w net.ipv4.neigh.default.gc_thresh3=16384

echo "[10-sysctl] Applied UDM Pro performance sysctl"
