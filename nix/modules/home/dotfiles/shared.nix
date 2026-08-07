{
  dotfilesPath,
  lib,
  pkgs,
  ...
}:

{
  home.file = {
    ".config/atuin/config.toml".source = "${dotfilesPath}/atuin/config.toml";
    ".config/atuin/themes/zed_kpango.toml".source = "${dotfilesPath}/atuin/themes/zed_kpango.toml";
    ".config/ghostty/config".source = "${dotfilesPath}/ghostty.conf";
    ".config/ghostty/shaders".source = "${dotfilesPath}/ghostty/shaders";
    # ghostty.conf sets `theme = zed_kpango`, which resolves against this
    # directory. Makefile.d/install.mk's DOTFILES_MAP already maps it; this was
    # the one dotfile pair (see ghostty-deployment plan) that never got its nix
    # counterpart, so a nix-only host would have shaders but a missing theme.
    ".config/ghostty/themes".source = "${dotfilesPath}/ghostty/themes";
    ".config/sheldon/plugins.toml".source = "${dotfilesPath}/sheldon.toml";
    ".ssh/config".source = "${dotfilesPath}/sshconfig";
    ".editorconfig".source = "${dotfilesPath}/editorconfig";
    ".gemini/settings.json".source = "${dotfilesPath}/gemini/settings.json";
    ".gemini/policies/rules.toml".source = "${dotfilesPath}/gemini/policies/policy.toml";
    ".gitattributes".source = "${dotfilesPath}/gitattributes";
    ".gitignore".source = "${dotfilesPath}/.gitignore";
    ".tmux.new-session".source = "${dotfilesPath}/tmux.new-session";
    "go/go.env".source = "${dotfilesPath}/go.env";
    ".config/helix/config.toml".source = "${dotfilesPath}/helix/config.toml";
    ".config/helix/languages.toml".source = "${dotfilesPath}/helix/languages.toml";
    ".config/helix/themes".source = "${dotfilesPath}/helix/themes";
    # ranger itself is already a shared package (packages/shared.nix); this was
    # only gated behind isLinux (modules/home/dotfiles/linux.nix) alongside
    # Wayland-only config, leaving darwin with the ranger binary but none of
    # its rc.conf/rifle.conf/commands.py. rifle.conf's rules are all guarded by
    # `has <program>`/`X` (X11 display) conditions, so the Linux-GUI-app rules
    # just don't match on darwin instead of breaking anything.
    ".config/ranger".source = "${dotfilesPath}/ranger";
  };

  # Tmux scripts live in tmux.conf.d/ and must be real copies in ~/.zcache so
  # zcompile can write .zwc alongside them (nix-store paths are read-only).
  # Mirrors the `make dotfiles/compile` step.
  home.activation.compileTmuxScripts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p "$HOME/.zcache"
    for pair in "kube:tmux-kube" "status-left:tmux-status-left" "short-path:tmux-short-path"; do
      src="''${pair%%:*}"
      dst="''${pair##*:}"
      # Delete before copying. Files in the nix store are mode r-xr-xr-x, and a
      # plain `cp` reproduces that mode, so the copy lands read-only and the next
      # activation fails with "cp: Permission denied" — this step worked exactly
      # once and broke every rebuild after it. Removing first is enough because
      # ~/.zcache itself is user-writable, and it also clears the stale .zwc so
      # zcompile below regenerates rather than failing to overwrite it.
      $DRY_RUN_CMD rm -f "$HOME/.zcache/$dst" "$HOME/.zcache/$dst.zwc"
      $DRY_RUN_CMD cp "${dotfilesPath}/tmux.conf.d/$src" "$HOME/.zcache/$dst"
      $DRY_RUN_CMD chmod 0755 "$HOME/.zcache/$dst"
    done
    $DRY_RUN_CMD ${pkgs.zsh}/bin/zsh -c '
      zcompile "$HOME/.zcache/tmux-kube"
      zcompile "$HOME/.zcache/tmux-status-left"
      zcompile "$HOME/.zcache/tmux-short-path"
    ' || true
  '';
}
