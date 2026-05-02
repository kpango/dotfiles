{ username, versions, homeDirectory, ... }:

{
  imports = [
    ./shared.nix
    ./linux.nix
    ./darwin.nix
  ];

  home = {
    username = "${username}";
    homeDirectory = homeDirectory;
    stateVersion = versions.homeManager;
  };
}
