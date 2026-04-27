{ config, lib, settings, ... }:

let
  hasNvidia = builtins.elem "nvidia" config.services.xserver.videoDrivers;
in
{
  # OS Level Programs
  programs.ssh.startAgent = true;
  programs.sway.enable = true;
  programs.light.enable = true;

  environment.variables = lib.mkMerge [
    {
      GIT_EDITOR = lib.mkForce settings.desktop.editor;
      EDITOR = lib.mkForce settings.desktop.editor;
      LIBSEAT_BACKEND = "logind";
      GDK_BACKEND = "wayland";
      CLUTTER_BACKEND = "wayland";
      GDK_DISABLE = "gles-api,vulkan";
      GSK_RENDERER = "gl";
      KITTY_ENABLE_WAYLAND = "1";
      MOZ_ENABLE_WAYLAND = "1";
      MOZ_USE_XINPUT2 = "1";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      QT_AUTO_SCREEN_SCALE_FACTOR = "1";
      QT_QPA_PLATFORM = "wayland";
      SDL_VIDEODRIVER = "wayland";
      XDG_SESSION_TYPE = "wayland";
      XKB_DEFAULT_LAYOUT = settings.desktop.keyboard.layout;
      XKB_DEFAULT_OPTIONS = settings.desktop.keyboard.options;
      DefaultImModule = settings.desktop.imModule;
      GTK_IM_MODULE = settings.desktop.imModule;
      SDL_IM_MODULE = settings.desktop.imModule;
      QT_IM_MODULE = settings.desktop.imModule;
      XMODIFIER = "@im=${settings.desktop.imModule}";
      XMODIFIERS = "@im=${settings.desktop.imModule}";
    }
    (lib.mkIf hasNvidia {
      # NVIDIA Sway specific
      WLR_DRM_NO_ATOMIC = "1";
      WLR_NO_HARDWARE_CURSORS = "1";
      XWAYLAND_NO_GLAMOR = "1";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      __GL_GSYNC_ALLOWED = "0";
      __GL_VRR_ALLOWED = "0";
      LIBVA_DRIVER_NAME = "nvidia";
      GBM_BACKEND = "nvidia-drm";
    })
  ];
}