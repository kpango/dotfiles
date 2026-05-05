{ dotfilesPath, ... }:

{
  home.file = {
    ".config/atuin/config.toml".source = "${dotfilesPath}/atuin/config.toml";
    ".config/atuin/themes/zed_kpango.toml".source = "${dotfilesPath}/atuin/themes/zed_kpango.toml";
    ".config/ghostty/config".source = "${dotfilesPath}/ghostty.conf";
    ".config/ghostty/shaders".source = "${dotfilesPath}/ghostty/shaders";
    ".config/sheldon/plugins.toml".source = "${dotfilesPath}/sheldon.toml";
    ".config/starship.toml".source = "${dotfilesPath}/starship.toml";
    ".ssh/config".source = "${dotfilesPath}/sshconfig";
    ".editorconfig".source = "${dotfilesPath}/editorconfig";
    ".gemini/settings.json".source = "${dotfilesPath}/gemini/settings.json";
    ".gemini/policies/rules.toml".source = "${dotfilesPath}/gemini/policies/policy.toml";
    ".gitattributes".source = "${dotfilesPath}/gitattributes";
    ".gitignore".source = "${dotfilesPath}/.gitignore";
    ".tmux-kube".source = "${dotfilesPath}/tmux-kube";
    ".tmux.new-session".source = "${dotfilesPath}/tmux.new-session";
    "go/go.env".source = "${dotfilesPath}/go.env";
    ".config/helix/config.toml".source = "${dotfilesPath}/helix/config.toml";
    ".config/helix/languages.toml".source = "${dotfilesPath}/helix/languages.toml";
    ".config/helix/themes".source = "${dotfilesPath}/helix/themes";
  };
}
