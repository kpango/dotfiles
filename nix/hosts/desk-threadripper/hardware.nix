{ pkgs, settings, dotfilesPath, ... }:

{
  imports = [
    ../../modules/nixos/hardware/profiles/nvidia-workstation.nix
  ];

  # Threadripper 3990X (64C/128T) & 256GB RAM optimizations
  boot.kernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "kvm-amd" ];
  
  boot.kernelParams = [
    "amd_iommu=on"
    "iommu=pt"
    # TR 3990X: amd_pstate driver lacks support; use legacy acpi-cpufreq.
    # CPU governor is set to 'performance' by the cpu-performance systemd service.
    "amd_pstate=disable"
    "idle=nomwait"
    "nvidia_drm.fbdev=1"
    "zswap.max_pool_percent=10"
    # Desktop uses zsmalloc (higher throughput than z3fold, suitable for ample RAM)
    "zswap.zpool=zsmalloc"
    "rd.driver.blacklist=nouveau"
    "transparent_hugepage=always"
    "rcu_nocbs=1-127"
    "rcu_nocb_poll"
  ];

  boot.kernel.sysctl = {
    # Aggressive VM tweaks for 256GB RAM
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_ratio" = 60;
    "vm.dirty_background_ratio" = 2;
  };

  hardware.nvidia = {
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = false; # Proprietary drivers recommended for RTX 20-series Turing
  };

  # Extra desktop packages
  environment.systemPackages = with pkgs; [
    vulkan-loader
    vulkan-validation-layers
  ];

  # NetworkManager bond0 system connections
  environment.etc = {
    "NetworkManager/system-connections/bond0.nmconnection" = {
      source = ../../../network/nm/desk/bond0.nmconnection;
      mode = settings.network.networkManager.connectionMode;
    };
    "NetworkManager/system-connections/eth0.nmconnection" = {
      source = ../../../network/nm/desk/eth0.nmconnection;
      mode = settings.network.networkManager.connectionMode;
    };
    "NetworkManager/system-connections/slave0.nmconnection" = {
      source = ../../../network/nm/desk/slave0.nmconnection;
      mode = settings.network.networkManager.connectionMode;
    };
    "NetworkManager/system-connections/slave1.nmconnection" = {
      source = ../../../network/nm/desk/slave1.nmconnection;
      mode = settings.network.networkManager.connectionMode;
    };
  };
}