{ settings, ... }:

{
  services.k3s = {
    enable = settings.virtualisation.k3s.enable;
    role = settings.virtualisation.k3s.role;
    extraFlags = toString settings.virtualisation.k3s.extraFlags;
  };
}
