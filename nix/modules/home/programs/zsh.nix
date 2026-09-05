{
  dotfilesPath,
  ...
}:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # .zshenv (unlike .zshrc/initContent) is sourced for every zsh invocation, including
    # non-interactive `zsh -c` ones (Claude Code Bash tool, scripts) — dotfiles/zshenv relies
    # on this to export vars like GIT_COMMITTER_NAME/EMAIL there instead of zshrc. Without this,
    # dotfiles/zshenv is never sourced on darwin: home-manager's own generated .zshenv only
    # sources hm-session-vars.sh, so its content would otherwise be dead code on this platform.
    envExtra = ''
      source ${dotfilesPath}/zshenv
    '';

    initContent = ''
      # Source core monolithic zshrc script (bypassing Nix native strings to keep dotfiles source truth)
      # Sheldon is loaded with caching inside zsh/02-plugin.zsh
      source ${dotfilesPath}/zshrc
    '';

    # nix-update is not an alias: it is a real command built in
    # programs/nix-update.nix, because it has to build as this user and then
    # elevate for activation. An alias here would shadow it.
    #
    # colima-fast (colima start with VM sizing flags) was the only darwin shellAlias here;
    # removed along with colima itself (see packages/darwin.nix) — apple/container's
    # equivalent lifecycle is `container machine create`/`start`, wrapped as zsh functions
    # in zsh/20-docker.zsh instead of a single shellAlias.
  };

  # No `home.file."./.zshrc".force = true` here: home-manager's zsh module
  # keys these as "./.zshrc"/"./.zshenv" (dotDirRel defaults to "."), but
  # checkLinkTargets' generated forcedPaths array keeps that literal "./"
  # while the runtime target path it's compared against is normalized to
  # ".zshrc" — the two strings never match, so force is a silent no-op for
  # this specific key shape (confirmed by inspecting the built
  # check-link-targets.sh derivation, 2026-08-22). See mac/install's
  # MAC_PREP in Makefile.d/install.mk, which removes dotfiles/install's
  # pre-existing .zshrc/.zshenv symlinks before nix/setup runs instead.
}
