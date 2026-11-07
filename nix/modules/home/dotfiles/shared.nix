{
  dotfilesPath,
  lib,
  pkgs,
  ...
}:

# atuin/ghostty/sheldon/editorconfig/agy/gitattributes/gitignore/helix and the
# rest of this module's former home.file entries were plain mirrors of repo
# files already covered by Makefile.d/install.mk's DOTFILES_MAP. They are now
# placed by Makefile.d/install.mk's dotfiles/install target instead (pulled in
# as a prerequisite of the install targets nix/modules/home/dotfiles/
# agent-tools.nix's home.activation calls) rather than re-declared here as a
# second, hand-synced copy — see this directory's CONTEXT.md.
#
# ~/.ssh/config remains intentionally NOT managed anywhere: it's a symlink
# into the separate kpango/pass secrets repo (the real Host/IdentityFile
# config), not this dotfiles-repo's sshconfig (a placeholder template).
{
  # Tmux scripts live in tmux.conf.d/ and must be real copies in ~/.zcache so
  # zcompile can write .zwc alongside them (nix-store paths are read-only).
  # Mirrors the `make dotfiles/compile` step.
  # Prefer cpz/rmz like zsh/04-aliases.zsh does. The activation PATH is empty
  # (home.emptyActivationPath, stateVersion >= 22.11), so look where
  # packages/shared.nix's installCargoBinTools installs them, and run after it
  # (which itself runs after writeBoundary).
  home.activation.compileTmuxScripts = lib.hm.dag.entryAfter [ "installCargoBinTools" ] ''
    cargoBin="''${CARGO_HOME:-$HOME/.cargo}/bin"
    # cpz refuses to overwrite without -f; rmz has no -r and is always recursive.
    if [ -x "$cargoBin/cpz" ]; then cpCmd=("$cargoBin/cpz" -f); else cpCmd=(cp -f); fi
    if [ -x "$cargoBin/rmz" ]; then rmCmd=("$cargoBin/rmz" -f); else rmCmd=(rm -f); fi
    $DRY_RUN_CMD mkdir -p "$HOME/.zcache"
    for pair in "kube:tmux-kube" "status-left:tmux-status-left" "short-path:tmux-short-path" "status-branch:tmux-status-branch"; do
      src="''${pair%%:*}"
      dst="''${pair##*:}"
      # Delete before copying. Files in the nix store are mode r-xr-xr-x, and a
      # plain `cp` reproduces that mode, so the copy lands read-only and the next
      # activation fails with "cp: Permission denied" — this step worked exactly
      # once and broke every rebuild after it. Removing first is enough because
      # ~/.zcache itself is user-writable, and it also clears the stale .zwc so
      # zcompile below regenerates rather than failing to overwrite it.
      $DRY_RUN_CMD "''${rmCmd[@]}" "$HOME/.zcache/$dst" "$HOME/.zcache/$dst.zwc"
      $DRY_RUN_CMD "''${cpCmd[@]}" "${dotfilesPath}/tmux.conf.d/$src" "$HOME/.zcache/$dst"
      $DRY_RUN_CMD chmod 0755 "$HOME/.zcache/$dst"
    done
    $DRY_RUN_CMD ${pkgs.zsh}/bin/zsh -c '
      zcompile "$HOME/.zcache/tmux-kube"
      zcompile "$HOME/.zcache/tmux-status-left"
      zcompile "$HOME/.zcache/tmux-short-path"
      zcompile "$HOME/.zcache/tmux-status-branch"
    ' || true
  '';
}
