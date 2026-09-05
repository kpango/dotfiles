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

  # cpz/rmz (modern cp/rm replacements aliased in zsh/04-aliases.zsh) have no nixpkgs
  # package — dockers/rust.Dockerfile installs them via `cargo binstall`, so this
  # mirrors that at activation time instead. This is a deliberate exception to
  # preferring prebuilt nixpkgs binaries (see the Rust section of shared.nix): no
  # nixpkgs package exists, and re-implementing them as custom crates.io-fetching
  # derivations isn't worth it for two small tools. Uses nixpkgs' own cargo (not
  # rustup's rustup-managed one) so this doesn't depend on a default toolchain
  # being configured. Existing zsh guards fall back to plain cp -r/rm -rf, so a
  # failure here (e.g. offline) is non-fatal — it only means those two aliases
  # keep using the fallback until the next successful activation.
  home.activation.installCargoBinTools = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD env PATH="${pkgs.cargo-binstall}/bin:${pkgs.cargo}/bin:$PATH" \
        cargo binstall --no-confirm --quiet cpz rmz \
        || echo "installCargoBinTools: cpz/rmz install skipped (offline or binstall failed)" >&2
    ''
  );
}
