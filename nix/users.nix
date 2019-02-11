{ pkgs, ... }:
{
  users.defaultUserShell = "/run/current-system/sw/bin/zsh";

  users.extraUsers.kpango = {
    description = "Yusuke Kato";
    extraGroups = [
      "adm"
      "audio"
      "cdrom"
      "disk"
      "docker"
      "networkmanager"
      "root"
      "systemd-journal"
      "users"
      "video"
      "wheel"
    ];
    createHome = true;
    home = "/home/kpango";
    isNormalUser = true;
    uid = 1000;
    shell = "/run/current-system/sw/bin/zsh";
  };
}
