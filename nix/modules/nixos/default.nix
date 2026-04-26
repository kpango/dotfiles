{ ... }:

{
  imports = [
    ../../core/common.nix
    ./core
    ./desktop
    ./network
    ./hardware
    ./virtualization
  ];
}