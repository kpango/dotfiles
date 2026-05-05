{ pkgs, lib, ... }:

let
  # Python script that maps TX queue N → CPU N (XPS), wrapping at 128 cores.
  xpsScript = pkgs.writeText "xps-setup.py" ''
    import os, sys
    iface = sys.argv[1]
    base  = f"/sys/class/net/{iface}/queues"
    tx_queues = sorted([q for q in os.listdir(base) if q.startswith("tx-")],
                       key=lambda x: int(x.split("-")[1]))
    for i, q in enumerate(tx_queues):
        cpu = i % 128
        words = [0, 0, 0, 0]
        words[cpu // 32] = 1 << (cpu % 32)
        mask = ",".join(f"{words[3-j]:08x}" for j in range(4))
        p = f"{base}/{q}/xps_cpus"
        try:
            with open(p, "w") as f:
                f.write(mask)
        except OSError as e:
            print(f"xps: {p}: {e}", file=sys.stderr)
  '';

  # Per-interface tuning script (same logic as /etc/NetworkManager/dispatcher.d/99-coalesce-x710)
  tuneIface = pkgs.writeShellScript "x710-tune-iface" ''
    set -euo pipefail
    IFACE="$1"

    # 1. Threaded NAPI — reduces interrupt latency under heavy RX load
    echo 1 > /sys/class/net/"$IFACE"/threaded || true

    # 2. Ethtool ring buffers
    ${pkgs.ethtool}/bin/ethtool -G "$IFACE" rx 8160 tx 8160 || true

    # 3. Ethtool offloads
    ${pkgs.ethtool}/bin/ethtool -K "$IFACE" \
      hw-tc-offload on \
      tx-tcp-segmentation on \
      tx-tcp6-segmentation on \
      rx-gro-list on \
      rx-udp-gro-forwarding on || true

    # 4. Coalescing: i40e rejects adaptive-* changes together with usecs;
    #    disable adaptive first, set usecs, then re-enable.
    ${pkgs.ethtool}/bin/ethtool -C "$IFACE" adaptive-rx off adaptive-tx off \
      rx-usecs 100 tx-usecs 100 || true
    ${pkgs.ethtool}/bin/ethtool -C "$IFACE" adaptive-rx on adaptive-tx on || true

    # 5. Replace root qdisc with mq so fq children inherit the correct quantum
    #    for MTU 9000 (quantum ~ 18028 bytes, not the default 3028 for 1500-MTU).
    ${pkgs.iproute2}/bin/tc qdisc replace dev "$IFACE" root mq || true

    # 6. RFS + RPS: steer received flows to the socket-owning CPU
    FLOW_CNT=512
    ALL_CPUS="ffffffff,ffffffff,ffffffff,ffffffff"
    for queue_dir in /sys/class/net/"$IFACE"/queues/rx-*; do
      [ -d "$queue_dir" ] || continue
      echo "$ALL_CPUS" > "$queue_dir/rps_cpus"  || true
      echo "$FLOW_CNT"  > "$queue_dir/rps_flow_cnt" || true
    done

    # 7. XPS: map TX queue N → CPU N for cache-local transmit
    ${pkgs.python3}/bin/python3 ${xpsScript} "$IFACE" || true
  '';

in
{
  # ────────────────────────────────────────────────
  # sfp0 tuning service
  # ────────────────────────────────────────────────
  systemd.services."x710-tune-sfp0" = {
    description = "X710 NIC tuning for sfp0 (Intel i40e)";
    documentation = [ "https://www.kernel.org/doc/html/latest/networking/scaling.html" ];

    # Trigger when the sfp0 network device appears in sysfs
    bindsTo = [ "sys-subsystem-net-devices-sfp0.device" ];
    after = [ "sys-subsystem-net-devices-sfp0.device" "network-pre.target" ];
    wantedBy = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${tuneIface} sfp0";
      # Retry once on failure (driver may not be fully initialised)
      Restart = "on-failure";
      RestartSec = "2s";
    };
  };

  # ────────────────────────────────────────────────
  # sfp1 tuning service
  # ────────────────────────────────────────────────
  systemd.services."x710-tune-sfp1" = {
    description = "X710 NIC tuning for sfp1 (Intel i40e)";
    documentation = [ "https://www.kernel.org/doc/html/latest/networking/scaling.html" ];

    bindsTo = [ "sys-subsystem-net-devices-sfp1.device" ];
    after = [ "sys-subsystem-net-devices-sfp1.device" "network-pre.target" ];
    wantedBy = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${tuneIface} sfp1";
      Restart = "on-failure";
      RestartSec = "2s";
    };
  };

  # Pull in ethtool, iproute2, python3 at system level so the scripts work
  environment.systemPackages = with pkgs; [ ethtool iproute2 python3 ];
}
