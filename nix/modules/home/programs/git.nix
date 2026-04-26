{ settings, dotfilesPath, ... }:

{
  programs.git = {
    enable = true;
    userName = settings.fullName;
    userEmail = settings.email;

    extraConfig = {
      core = {
        excludesfile = "${dotfilesPath}/.gitignore";
      };
    };

    includes = [
      {
        path = "${dotfilesPath}/gitconfig";
      }
    ];
  };
}