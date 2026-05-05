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
  # Git (system-level config)
  # ────────────────────────────────────────────────
  programs.git = {
    enable = true;
    config = {
      core = {
        autocrlf = false;
        editor = "hx";
        pager = "delta";
        fileMode = false;
        quotepath = false;
        precomposeunicode = true;
      };
      color.ui = "auto";
      push = {
        default = "tracking";
        autoSetupRemote = true;
      };
      pull = {
        rebase = true;
        ff = "only";
      };
      diff = {
        mnemonicprefix = true;
        patience = true;
        indentHeuristic = true;
        colorMoved = "default";
      };
      http.postBuffer = 524288000;
      help.autocorrect = 0;
      alias = {
        ad = "add";
        cam = "commit -a --amend";
        ci = "commit -a";
        cm = "commit";
        co = "checkout";
        ft = "fetch";
        rbm = "rebase main";
        sh = "show";
        so = "remote show origin";
        st = "status";
        stt = "status -uno -u";
        up = "pull --rebase";
        ba = "branch -a";
        bm = "branch --merged";
        bn = "branch --no-merged";
        br = "branch";
        la = "log --pretty=format:'%ad %h (%an): %s' --date=short";
        lp = "log -p";
      };
    };
  };

  # ────────────────────────────────────────────────
  # Starship prompt + Atuin history
  # ────────────────────────────────────────────────
  programs.starship.enable = true;
  programs.atuin.enable = true;

  # ────────────────────────────────────────────────
  # Core system packages — available to all users including root.
  # Developer tooling belongs in home-manager (modules/home/packages/).
  # Hardware-specific packages belong in the host's hardware module.
  # ────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    clang
    delta
    file
    git
    gnugrep
    gzip
    helix
    htop
    iproute2
    iptables
    gnumake
    nmap
    openssl
    patch
  ];
}
