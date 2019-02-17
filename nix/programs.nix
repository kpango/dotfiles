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
    # sway-beta = {
    #   enable = true;
    #   extraPackages = with pkgs; [
    #     swayidle # used for controlling idle timeouts and triggers (screen locking, etc)
    #     swaylock # used for locking Wayland sessions

    #     waybar        # polybar-alike
    #     i3status-rust # simpler bar written in Rust

    #     grim     # screen image capture
    #     slurp    # screen are selection tool
    #     mako     # notification daemon
    #     wlstream # screen recorder
    #     oguri    # animated background utility
    #     kanshi   # dynamic display configuration helper
    #     redshift-wayland # patched to work with wayland gamma protocol
    #   ];
    # };
    sway.enable = true;
    light.enable = true;
  };
}
