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
    # force = true: home.file's checkLinkTargets can't diff a pre-existing
    # *directory* target for sameness (it shells out to `cmp`, which errors
    # "Is a directory"), so on a host where Makefile.d/install.mk's
    # dotfiles/install already symlinked this directory in (mac/install runs
    # dotfiles/install before nix/setup), activation always refuses with
    # "would be clobbered" — even though both sides point at the identical
    # dotfiles-repo source. force sidesteps that dead-end.
    ".config/ghostty/shaders" = {
      source = "${dotfilesPath}/ghostty/shaders";
      force = true;
    };
    # ghostty.conf sets `theme = zed_kpango`, which resolves against this
    # directory. Makefile.d/install.mk's DOTFILES_MAP already maps it; this was
    # the one dotfile pair (see ghostty-deployment plan) that never got its nix
    # counterpart, so a nix-only host would have shaders but a missing theme.
    ".config/ghostty/themes" = {
      source = "${dotfilesPath}/ghostty/themes";
      force = true;
    };
    ".config/sheldon/plugins.toml".source = "${dotfilesPath}/sheldon.toml";
    # ~/.ssh/config is intentionally NOT managed here: it's a symlink into the
    # separate kpango/pass secrets repo (the real Host/IdentityFile config),
    # not this dotfiles-repo's sshconfig (a placeholder template). Managing it
    # here would force-overwrite real SSH config with the template (2026-08-22).
    ".editorconfig".source = "${dotfilesPath}/editorconfig";
    ".agy/settings.json".source = "${dotfilesPath}/agy/settings.json";
    ".agy/policies/rules.toml".source = "${dotfilesPath}/agy/policies/policy.toml";
    ".gitattributes".source = "${dotfilesPath}/gitattributes";
    ".gitignore".source = "${dotfilesPath}/.gitignore";
    ".tmux.new-session".source = "${dotfilesPath}/tmux.new-session";
    "go/go.env".source = "${dotfilesPath}/go.env";
    ".config/helix/config.toml".source = "${dotfilesPath}/helix/config.toml";
    ".config/helix/languages.toml".source = "${dotfilesPath}/helix/languages.toml";
    # force = true: same pre-existing-directory conflict as ghostty/shaders
    # and ghostty/themes above — see that comment.
    ".config/helix/themes" = {
      source = "${dotfilesPath}/helix/themes";
      force = true;
    };
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
