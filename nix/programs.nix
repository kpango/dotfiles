{
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs = {
    zsh = {
      enable = true;
      autosuggestions.enable = true;
      enableCompletion = true;
      syntaxHighlighting.enable = true;
    };
    tmux.enable = true;
    ssh = {
      forwardX11 = false;
      startAgent = true;
    };
    sway.enable = true;
    light.enable = true;
  };
}
