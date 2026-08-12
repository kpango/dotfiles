{
  isDarwin,
  dotfilesPath,
  pkgs,
  ...
}:

{
  programs.tmux = {
    enable = true;
    clock24 = true;
    mouse = true;
    plugins = with pkgs.tmuxPlugins; [
      cpu
      resurrect
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '15'
        '';
      }
    ];
    extraConfig =
      let
        # Lines managed by TPM (tmux plugin manager) in the plain-file tmux.conf,
        # stripped here because programs.tmux.plugins above installs the same
        # plugins declaratively instead.
        tpmLines = [
          "set -g @plugin 'tmux-plugins/tpm'\n"
          "set -g @plugin 'tmux-plugins/tmux-cpu'\n"
          "set -g @plugin 'tmux-plugins/tmux-resurrect'\n"
          "set -g @plugin 'tmux-plugins/tmux-continuum'\n"
          "set -g @continuum-restore 'on'\n"
          "set -g @continuum-save-interval '15'\n"
          "run '~/.tmux/plugins/tpm/tpm'\n"
        ];
        stripTPM = builtins.replaceStrings tpmLines (map (_: "") tpmLines);
        baseConfig = stripTPM (builtins.readFile "${dotfilesPath}/tmux.conf");
      in
      if isDarwin then
        builtins.replaceStrings [ "# set-environment -g PATH" ] [ "set-environment -g PATH" ] baseConfig
      else
        baseConfig;
  };
}
