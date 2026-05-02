{ pkgs, settings, ... }:

{
  # Time and Locale
  time = {
    timeZone = settings.timeZone;
    hardwareClockInLocalTime = settings.nix.hardwareClockInLocalTime;
  };
  i18n.defaultLocale = settings.locale;

  # Nixpkgs Config
  nixpkgs.config = {
    allowUnfree = settings.nix.allowUnfree;
    allowBroken = settings.nix.allowBroken;
    allowUnfreeRedistributable = settings.nix.allowUnfreeRedistributable;
    pulseaudio = settings.nix.pulseaudio;
    chromium = settings.nix.chromium;
  };
  nixpkgs.overlays = [
    (self: super: {
      neovim = super.neovim.override {
        withPython3 = true;
        withRuby = true;
        vimAlias = true;
      };
    })
  ];

  # Core System Packages
  environment.systemPackages = with pkgs; [
    acpi
    atool
    autoconf
    automake
    binutils
    cryptsetup
    ctags
    dmidecode
    dosfstools
    efibootmgr
    fakeroot
    # flamegraph — package name varies by nixpkgs version; install via cargo if needed
    # flamegraph
    fwupd
    git-crypt
    hub
    iptables
    iputils
    libnm
    lshw
    nix-prefetch-git
    patchelf
    pciutils
    psmisc
    rxvt_unicode
    shellcheck
    tldr
    usbutils
    xbindkeys
    xclip
    xfsprogs
    xsel
    xwayland
  ];
}
