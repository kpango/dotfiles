{ versions, ... }:

{
  imports = [
    ./boot.nix
    ./system.nix
    ./security.nix
    ./programs.nix
  ];

  system.stateVersion = versions.nixos;
}
