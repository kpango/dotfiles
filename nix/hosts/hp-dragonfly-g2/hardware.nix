{ ... }:

{
  imports = [
    ../../modules/nixos/hardware/profiles/intel-laptop.nix
  ];

  # HP Dragonfly G2 specific kernels/tools
  boot.kernelModules = [ "pinctrl_tigerlake" ];

  boot.kernelParams = [
    "i915.enable_psr=1"
  ];

  boot.kernel.sysctl = {
    "dev.i915.perf_stream_paranoid" = 0;
  };
}