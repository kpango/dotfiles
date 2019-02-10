{ pkgs, ... }:
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
    #slock.enable = true;
    docker.enable =true
    tmux.enable = true;
    ssh.forwardX11 = false;
    ssh.startAgent = true;
  };
}
