{ ... }:

{
  imports = [
    ../intel.nix
  ];

  boot.kernelModules = [ "kvm-intel" ];

  boot.kernelParams = [
    "i915.enable_guc=3"
    "i915.enable_fbc=1"
    # Laptops use z3fold (lower memory overhead than zsmalloc, better for constrained RAM)
    "zswap.zpool=z3fold"
  ];

  # TLP for Laptops
  services.tlp.enable = true;
}