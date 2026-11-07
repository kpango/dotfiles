{
  pkgs,
  lib,
  isDarwin,
  ...
}:

{
  home.packages = lib.mkIf isDarwin (
    with pkgs;
    [
      # NixOS gets atuin from programs.atuin.enable in modules/nixos/core/programs.nix.
      # Darwin has no equivalent, so without this the shell integration loaded by
      # sheldon (and the ATUIN_SESSION setup in zshrc) has no atuin binary to call.
      atuin
      # colima + docker (CLI) removed — apple/container replaces the whole container
      # backend, see modules/darwin/containerization.nix. The `container` CLI itself
      # comes from inputs.nix-apple-container, not nixpkgs.
      reattach-to-user-namespace
    ]
  );
  # cpz/rmz are installed for every host by installCargoBinTools in shared.nix.
}
