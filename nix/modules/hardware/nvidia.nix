{ config, pkgs, lib, ... }:

{
  # ────────────────────────────────────────────────
  # NVIDIA proprietary driver configuration
  # Tested against: nvidia-beta 590.x (Arch: nvidia-beta-dkms)
  # NixOS equivalent: hardware.nvidia (uses nixpkgs nvidia packages)
  # ────────────────────────────────────────────────

  # Tell X/Wayland to use the nvidia driver
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Kernel modesetting (required for Wayland/GBM)
    modesetting.enable = true;

    # Use proprietary closed-source driver (not the open kernel module)
    open = false;

    # Include nvidia-settings GUI tool
    nvidiaSettings = true;

    # Power management: not needed on a desktop Threadripper workstation
    powerManagement.enable = false;
    powerManagement.finegrained = false;

    # Use the latest stable package (override to beta/specific version if needed)
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # NVIDIA container toolkit for Docker GPU passthrough
  hardware.nvidia-container-toolkit.enable = true;

  # Unload NVIDIA kernel modules cleanly before reboot/halt/poweroff.
  systemd.services.nvidia-unload = {
    description = "Unload NVIDIA kernel modules before shutdown";
    defaultDependencies = false;
    before = [ "reboot.target" "halt.target" "poweroff.target" ];
    after  = [ "graphical.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStop = pkgs.writeShellScript "nvidia-unload" ''
        modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia 2>/dev/null || true
      '';
    };
  };

  # nouveau must not load — belt-and-suspenders alongside boot.blacklistedKernelModules
  boot.blacklistedKernelModules = lib.mkAfter [ "nouveau" ];

  # CUDA toolkit available system-wide
  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
    nvtopPackages.nvidia
  ];

  # OpenGL / Vulkan
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      egl-wayland
      libvdpau-va-gl
    ];
  };
}
