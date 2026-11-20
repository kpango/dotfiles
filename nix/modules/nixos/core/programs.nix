{ pkgs, ... }:

{
  # ────────────────────────────────────────────────
  # Shell: zsh (system-wide default)
  # Plugin management (sheldon) + completion are handled at the user level.
  # ────────────────────────────────────────────────
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
    autosuggestions.enable = true;
    histSize = 1000000;
    shellInit = ''
      export EDITOR=hx
      export VISUAL=hx
      export PAGER=less
      export LESS="-R"
    '';
  };
  users.defaultUserShell = pkgs.zsh;

  # ────────────────────────────────────────────────
  # tmux
  # ────────────────────────────────────────────────
  programs.tmux = {
    enable = true;
    clock24 = true;
    historyLimit = 1000000;
    terminal = "tmux-256color";
    keyMode = "vi";
    aggressiveResize = true;
    extraConfig = ''
      set -g mouse on
      set -g base-index 1
      setw -g pane-base-index 1
      set -g automatic-rename on
      set -g automatic-rename-format '#{b:pane_current_path}'
      set-option -g set-titles on
      set -g focus-events on
      setw -g monitor-activity on
      setw -g visual-activity on
      setw -g alternate-screen on
      set -g status-keys vi

      bind c new-window -c '#{pane_current_path}'
      bind s split-window -v -c '#{pane_current_path}'
      bind v split-window -h -c '#{pane_current_path}'
      bind-key -r a setw synchronize-panes \; display "synchronize-panes #{?pane_synchronized,on,off}"
      bind-key -r C-j resize-pane -D 5
      bind-key -r C-k resize-pane -U 5
      bind-key -r C-h resize-pane -L 5
      bind-key -r C-l resize-pane -R 5

      set -g @plugin 'tmux-plugins/tpm'
      set -g @plugin 'tmux-plugins/tmux-cpu'
      set -g @cpu_interval 5
    '';
  };

  # ────────────────────────────────────────────────
  # Git: no system-level `programs.git` here. This module used to declare one
  # (/etc/gitconfig, core/color/push/pull/diff/http/help + an 18-entry alias
  # subset), but every real login user already gets the authoritative,
  # complete config through home-manager's `programs.git.includes` of
  # dotfiles/gitconfig (modules/home/programs/git.nix) — which wins by config
  # precedence regardless of what /etc/gitconfig says. The removed block had
  # already drifted: it carried only 18 of gitconfig's 40+ aliases, proving it
  # had not been kept in sync. If root ever needs its own git config, symlink
  # dotfiles/gitconfig for that account specifically rather than re-adding a
  # second copy here.
  # ────────────────────────────────────────────────

  # ────────────────────────────────────────────────
  # Atuin history
  # ────────────────────────────────────────────────
  programs.atuin.enable = true;

  # ────────────────────────────────────────────────
  # Core system packages — available to all users including root.
  # Developer tooling belongs in home-manager (modules/home/packages/); do not
  # re-add git/gitui/gzip/gnumake/nmap/patch/lumen/etc. here, they're already
  # in modules/home/packages/shared.nix for the actual login user. iptables is
  # in core/system.nix, not here — do not re-add it either.
  # This list is for what a root/rescue shell needs before any home-manager
  # profile is active.
  # Hardware-specific packages belong in the host's hardware module.
  # ────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    clang
    file
    gnugrep
    helix
    htop
    iproute2
    openssl
  ];
}
