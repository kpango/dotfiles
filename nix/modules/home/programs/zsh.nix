{ lib, settings, isDarwin, dotfilesPath, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    initContent = ''
      # Init Sheldon
      eval "$(sheldon source)"

      # Init Starship
      eval "$(starship init zsh)"

      # Source core monolithic zshrc script (bypassing Nix native strings to keep dotfiles source truth)
      source ${dotfilesPath}/zshrc
    '';

    shellAliases = lib.optionalAttrs isDarwin {
      colima-fast = settings.darwin.aliases.colima;
      nix-update = settings.darwin.aliases.nixUpdate;
    };
  };
}
