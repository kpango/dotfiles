{ versions, ... }:

{
  imports = [
    ./boot.nix
    ./system.nix
    ./security.nix
  ];

  system.stateVersion = versions.nixos;
}