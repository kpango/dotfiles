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
  };

  # Tmux scripts live in tmux.conf.d/ and must be real copies in ~/.zcache so
  # zcompile can write .zwc alongside them (nix-store paths are read-only).
  # Mirrors the `make dotfiles/compile` step.
  home.activation.compileTmuxScripts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p "$HOME/.zcache"
    for pair in "kube:tmux-kube" "status-left:tmux-status-left" "short-path:tmux-short-path"; do
      src="''${pair%%:*}"
      dst="''${pair##*:}"
      $DRY_RUN_CMD cp "${dotfilesPath}/tmux.conf.d/$src" "$HOME/.zcache/$dst"
      $DRY_RUN_CMD chmod +x "$HOME/.zcache/$dst"
    done
    $DRY_RUN_CMD ${pkgs.zsh}/bin/zsh -c '
      zcompile "$HOME/.zcache/tmux-kube"
      zcompile "$HOME/.zcache/tmux-status-left"
      zcompile "$HOME/.zcache/tmux-short-path"
    ' || true
  '';
}
