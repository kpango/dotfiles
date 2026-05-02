{ pkgs, lib, isDarwin, ... }:

{
  home.packages = lib.mkIf isDarwin (with pkgs; [
    colima
    docker
    nkf
    reattach-to-user-namespace
  ]);
}
