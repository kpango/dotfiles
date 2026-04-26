{ ... }:

{
  imports = [
    ../intel.nix
  ];

  boot.kernelModules = [ "kvm-intel" ];

  boot.kernelParams = [
    "i915.enable_guc=3"
    "i915.enable_fbc=1"
  ];

  # TLP for Laptops
  services.tlp.enable = true;
}