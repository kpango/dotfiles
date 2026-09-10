{ ... }:

{
  imports = [
    ../../modules/nixos/hardware/profiles/thinkpad-laptop.nix
  ];

  # ThinkPad X1 Carbon Gen 9 specific kernels/tools
  boot.kernelParams = [
    "i915.fastboot=1"
    "mem_sleep_default=s2idle"
    "psmouse.synaptics_intertouch=1"
  ];
}
