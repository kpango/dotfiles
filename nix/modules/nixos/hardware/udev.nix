{ lib, settings, ... }:

{
  environment.etc = {
    "libinput/local-overrides.quirks".text = ''
      [Touchpad touch override]
      MatchUdevType=touchpad
      MatchName=*Magic Trackpad 2
      AttrPressureRange=4:0
    '';
  };

  services.udev.extraHwdb = ''
    evdev:name:ThinkPad Extra Buttons:dmi:bvn*:bvr*:bd*:svnLENOVO*:pn*
     KEYBOARD_KEY_45=prog1
     KEYBOARD_KEY_49=prog2
  '';

  services.udev.extraRules = ''
    # ── I/O Scheduler rules (matches arch/udev/60-ioscheduler.rules) ──────
    # NVMe: use 'none' — NVMe hardware manages its own deep queue (NCQ/NVMe CQ).
    # Any host-side scheduler adds latency without benefit.
    ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
    ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/read_ahead_kb}="0"

    # SATA / eMMC SSD: mq-deadline gives bounded latency with good throughput.
    ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"

    # Rotational HDD: bfq provides fair bandwidth and low latency for mixed workloads.
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"

    # ── Persistent interface names (MACs from settings.nix) ───────────────
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${settings.network.interfaces.eth0}", NAME="eth0"
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${settings.network.interfaces.sfp0}", NAME="sfp0"
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${settings.network.interfaces.sfp1}", NAME="sfp1"

    # ── Input devices ─────────────────────────────────────────────────────
    KERNEL=="event*", NAME="input/%k", MODE="0660", GROUP="input"
    KERNEL=="uinput",                  GROUP="uinput", MODE="0660"
  '';
}
