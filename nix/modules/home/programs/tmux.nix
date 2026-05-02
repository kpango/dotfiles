{ isDarwin, dotfilesPath, ... }:

{
  programs.tmux = {
    enable = true;
    clock24 = true;
    mouse = true;
    extraConfig =
      let
        baseConfig = builtins.readFile ../../../../tmux.conf;
      in
      if isDarwin then
        builtins.replaceStrings
          [ "# set-environment -g PATH" ]
          [ "set-environment -g PATH" ]
          baseConfig
      else
        baseConfig;
  };
}
