# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  imports = [
    <nixos-hardware/lenovo/thinkpad/x1>
    ./boot.nix
    ./environment.nix
    ./fonts.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./network.nix
    ./nix.nix
    ./nixpkg.nix
    ./programs.nix
    ./services.nix
    ./system.nix
    ./users.nix
    ./virtual.nix
  ];

  documentation.info.enable = true;
}
