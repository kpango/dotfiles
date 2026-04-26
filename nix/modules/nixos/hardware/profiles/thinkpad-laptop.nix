{ ... }:

{
  imports = [
    ./intel-laptop.nix
  ];

  boot.kernelParams = [
    "i915.enable_psr=0"
  ];

  # Thinkfan for ThinkPads
  services.thinkfan.enable = true;
}
