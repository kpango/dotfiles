{
  pkgs ? import <nixpkgs> { },
}:

{
  # This directory is for custom packages that don't exist in nixpkgs.
  # You can build them with `nix build .#your-package-name`

  hunk = pkgs.callPackage ./hunk.nix { };
  prmt = pkgs.callPackage ./prmt.nix { };
}
