#!/bin/sh
# wan-10g-80pct mission (2026-10-19) persistent sysctl tune
# tcp_mem is left at the kernel default (about 46407 61876 92814 pages on this 4GB box,
# from nr_free_buffer_pages()/16). The former "262144 524288 786432" (2GB pressure, 3GB
# hard limit) let local TCP grow past MemAvailable before memory pressure kicked in
# (CONTEXT Q47).
sysctl -w vm.swappiness=10
sysctl -w vm.vfs_cache_pressure=200
