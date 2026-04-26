{ pkgs, ... }:

{
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };
  environment.systemPackages = with pkgs; [
    vulkan-tools
  ];
}
