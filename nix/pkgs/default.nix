{
  pkgs ? import <nixpkgs> { },
}:

{
  # This directory is for custom packages that don't exist in nixpkgs.
  # You can build them with `nix build .#your-package-name`

  lumen = pkgs.callPackage ./lumen.nix { };
  prmt = pkgs.callPackage ./prmt.nix { };
}
