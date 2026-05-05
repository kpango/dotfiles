{ pkgs, lib, isDarwin, ... }:

{
  home.packages = lib.mkIf isDarwin (with pkgs; [
    colima
    docker
    reattach-to-user-namespace
  ]);
}
