{ pkgs, lib, settings, ... }:

{
  # Weekly GC schedule for NixOS (systemd timer).  nix.gc.automatic and options
  # are set in core/common.nix; dates is NixOS-only (nix-darwin uses interval).
  nix.gc.dates = lib.mkDefault "weekly";

  # Time and Locale
  time = {
    timeZone = settings.timeZone;
    hardwareClockInLocalTime = settings.nix.hardwareClockInLocalTime;
  };
  i18n = {
    defaultLocale = settings.locale;
    supportedLocales = [ "en_US.UTF-8/UTF-8" "ja_JP.UTF-8/UTF-8" ];
  };

  # Core System Packages
  environment.systemPackages = with pkgs; [
    acpi
    autoconf
    automake
    binutils
    cryptsetup
    dmidecode
    dosfstools
    efibootmgr
    fakeroot
    fwupd
    iptables
    iputils
    lshw
    patchelf
    pciutils
    psmisc
    usbutils
    xfsprogs
  ];
}
