{
  versions,
  settings,
  username,
  ...
}:

{
  # Required by nix-darwin for user-scoped options (homebrew, defaults, etc.)
  system.primaryUser = username;

  # Nix itself is installed and managed by Determinate Nix (see `make nix/setup`),
  # which owns /etc/nix/nix.conf and its own launchd daemon. nix-darwin must not
  # also manage them — Determinate requires `nix.enable = false`.
  # https://docs.determinate.systems/guides/nix-darwin
  nix.enable = false;

  # nix-darwin enables this by default and then writes an *empty*
  # /etc/pam.d/sudo_local, because touchIdAuth, watchIdAuth and reattach are all
  # off here — `config.security.pam.services.sudo_local.text` evaluates to "".
  #
  # That empty write is not free: /etc/pam.d is a protected path (PAM is a
  # privilege-escalation surface), so creating the symlink fails with
  # "Operation not permitted" and aborts activation at the "setting up /etc"
  # step unless the invoking process holds Full Disk Access.
  #
  # Nothing is lost by turning it off. macOS ships no /etc/pam.d/sudo_local at
  # all, and while /etc/pam.d/sudo does `auth include sudo_local`, a missing
  # include is non-fatal — sudo works on this machine today with the file absent.
  # Enable this again (with touchIdAuth) only from a context that has Full Disk
  # Access.
  security.pam.services.sudo_local.enable = false;

  # Launchd daemon to raise file descriptor limits.
  # ProgramArguments[0] must be an absolute path: launchd execs it directly and
  # does not resolve names through PATH.
  launchd.daemons.limit-maxfiles = {
    serviceConfig = {
      Label = "limit.maxfiles";
      ProgramArguments = [
        "/bin/launchctl"
        "limit"
        "maxfiles"
        "${toString settings.system.fileDescriptorLimit}"
        "${toString settings.system.fileDescriptorLimit}"
      ];
      RunAtLoad = true;
      ServiceIPC = false;
    };
  };

  system.stateVersion = versions.darwin;
}
