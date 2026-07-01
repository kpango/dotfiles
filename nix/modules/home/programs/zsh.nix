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

    shellAliases = lib.optionalAttrs isDarwin {
      colima-fast = settings.darwin.aliases.colima;
      nix-update = settings.darwin.aliases.nixUpdate;
    };
  };
}
