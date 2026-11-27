{ ... }:

{
  services.udev.extraRules = ''
    # NVMe: no host-side scheduler — NVMe hardware manages its own deep queue.
    ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
    ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/read_ahead_kb}="0"

    # SATA / eMMC SSD: mq-deadline — bounded latency with good throughput.
    ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"

    # Rotational HDD: bfq — fair bandwidth and low latency for mixed workloads.
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
  '';
}
