{
  lib,
  settings,
  isDarwin,
  dotfilesPath,
  ...
}:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    initContent = ''
      # Source core monolithic zshrc script (bypassing Nix native strings to keep dotfiles source truth)
      # Sheldon is loaded with caching inside zsh/02-plugin.zsh
      source ${dotfilesPath}/zshrc
    '';

    # nix-update is not an alias: it is a real command built in
    # programs/nix-update.nix, because it has to build as this user and then
    # elevate for activation. An alias here would shadow it.
    shellAliases = lib.optionalAttrs isDarwin {
      colima-fast = settings.darwin.aliases.colima;
    };
  };
}
