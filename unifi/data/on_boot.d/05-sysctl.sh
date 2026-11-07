#!/bin/sh
# UDM Pro performance sysctl tuning
# Deploy: /data/on_boot.d/05-sysctl.sh (run at boot by udm-boot.service in this directory)
# Note: /data/ persists across reboots; wiped only on factory reset / firmware reinstall.

set -e

# Conntrack: 65536 (default) is critically low for a gateway router.
# 1M entries @ ~288 bytes each ≈ 288MB — acceptable for 2GB+ RAM systems.
# Timeouts are not set here: udapi-server applies the controller's
# firewall/settings.conntrackTimeouts (tcpEstablished 7440 = RFC 5382, tcpTimeWait 120)
# over anything set at boot, and a shorter established timeout only cut idle TCP
# until udapi re-applied it (CONTEXT Q46).
sysctl -w net.netfilter.nf_conntrack_max=1048576

# BBR congestion control (available in 4.9+; UDM Pro runs 4.19)
if modprobe tcp_bbr 2>/dev/null; then
    sysctl -w net.ipv4.tcp_congestion_control=bbr
    sysctl -w net.core.default_qdisc=fq
else
    # fallback: fq_codel for active queue management (prevents bufferbloat)
    sysctl -w net.core.default_qdisc=fq_codel 2>/dev/null || true
fi

# rmem_max/wmem_max (128MB) and tcp_rmem/tcp_wmem are set by the firmware's own
# /etc/sysctl.d/10-sysctl-10g-tcp-udp-tune.conf (package udmpro-al324-base-files), so they
# are not repeated here (CONTEXT Q47).
# Keep the *_default at the kernel default (212992). A 16MB default applied to every
# socket, including dpinger's raw ICMP sockets that receive a copy of every ICMP packet
# and are never drained: 19 of them sat full at 16MB (301MB Recv-Q), which drove the UDM
# into swap thrashing and an OOM kill (2026-11-06). Apps that want more opt in up to *_max.
sysctl -w net.core.rmem_default=212992
sysctl -w net.core.wmem_default=212992

# TCP Fast Open (client + server)
sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null || true

# Neighbour table gc_thresh1-3 are left to UniFi: live values are 4096/131072/262144,
# larger than anything this script set, and they replace ours after boot (CONTEXT Q46).

# WAN2 (eth8, MAP-E): udapi's WAN-Diag deletes the MAP-E CE /128 every ~3 min and udapi
# re-adds it within ms, but DAD then holds it tentative ~1.5s and ip6tnl2 drops every
# packet meanwhile ("Local address not yet configured!"). Skip DAD on this WAN link.
sysctl -w net.ipv6.conf.eth8.accept_dad=0 2>/dev/null || true

echo "[05-sysctl] Applied UDM Pro performance sysctl"
