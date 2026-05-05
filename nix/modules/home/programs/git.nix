{ settings, dotfilesPath, ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = settings.fullName;
        email = settings.email;
      };
      core.excludesfile = "${dotfilesPath}/.gitignore";
    };
    includes = [
      { path = "${dotfilesPath}/gitconfig"; }
    ];
  };
}
