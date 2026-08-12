{ ... }:

{
  imports = [ ./udev-ioscheduler.nix ];

  environment.etc = {
    "libinput/local-overrides.quirks".text = ''
      [Touchpad touch override]
      MatchUdevType=touchpad
      MatchName=*Magic Trackpad 2
      AttrPressureRange=4:0
    '';
  };

  services.udev.extraHwdb = ''
    evdev:name:ThinkPad Extra Buttons:dmi:bvn*:bvr*:bd*:svnLENOVO*:pn*
     KEYBOARD_KEY_45=prog1
     KEYBOARD_KEY_49=prog2
  '';

  services.udev.extraRules = ''
    # Input devices
    KERNEL=="event*", NAME="input/%k", MODE="0660", GROUP="input"
    KERNEL=="uinput",                  GROUP="uinput", MODE="0660"
  '';
}
