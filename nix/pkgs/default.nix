{ pkgs ? import <nixpkgs> { } }:

{
  # This directory is for custom packages that don't exist in nixpkgs.
  # You can build them with `nix build .#your-package-name`

  # Example:
  # my-script = pkgs.callPackage ./my-script.nix { };
}
