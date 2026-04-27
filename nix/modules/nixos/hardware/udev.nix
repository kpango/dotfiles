{ config, lib, settings, ... }:

let
  hasNvidia = builtins.elem "nvidia" config.services.xserver.videoDrivers;
in
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
    # 60-ioschedulers.rules
    ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*|nvme*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="kyber"
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
${lib.optionalString hasNvidia ''

    # 60-nvidia.rules
    ACTION=="add", DEVPATH=="/bus/pci/drivers/nvidia", RUN+="/usr/bin/nvidia-modprobe -c0 -m"
''}
    # 70-persistent-network.rules
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${settings.network.interfaces.eth0}", NAME="eth0"
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${settings.network.interfaces.sfp0}", NAME="sfp0"
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${settings.network.interfaces.sfp1}", NAME="sfp1"

    # Input rules
    KERNEL=="event*", NAME="input/%k", MODE="0660", GROUP="input"
    KERNEL=="uinput", GROUP="uinput", MODE="0660"
  '';
}