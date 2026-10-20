#!/bin/sh
# wan-10g-80pct mission (2026-10-19) persistent sysctl tune
sysctl -w net.ipv4.tcp_mem="262144 524288 786432"
sysctl -w vm.swappiness=10
sysctl -w vm.vfs_cache_pressure=200
