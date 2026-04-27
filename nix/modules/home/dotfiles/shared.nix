{ settings, ... }:

{
  home.file = {
    ".config/atuin/config.toml".source = ../../../../atuin/config.toml;
    ".config/atuin/themes/zed_kpango.toml".source = ../../../../atuin/themes/zed_kpango.toml;
    ".config/ghostty/config".source = ../../../../ghostty.conf;
    ".config/ghostty/shaders".source = ../../../../ghostty/shaders;
    ".config/sheldon/plugins.toml".source = ../../../../sheldon.toml;
    ".config/starship.toml".source = ../../../../starship.toml;
    ".ssh/config".source = ../../../../sshconfig;
    ".editorconfig".source = ../../../../editorconfig;
    ".gemini/settings.json".source = ../../../../gemini/settings.json;
    ".gemini/policies/rules.toml".source = ../../../../gemini/policies/policy.toml;
    ".gitattributes".source = ../../../../gitattributes;
    ".gitconfig".source = ../../../../gitconfig;
    ".gitignore".source = ../../../../.gitignore;
    ".docker/daemon.json".source = ../../../../dockers/daemon.json;
    ".tmux.conf".source = ../../../../tmux.conf;
    ".tmux-kube".source = ../../../../tmux-kube;
    ".tmux.new-session".source = ../../../../tmux.new-session;
    "go/go.env".source = ../../../../go.env;
    ".config/helix/config.toml".source = ../../../../helix/config.toml;
    ".config/helix/languages.toml".source = ../../../../helix/languages.toml;
    ".config/helix/themes".source = ../../../../helix/themes;
  };
}