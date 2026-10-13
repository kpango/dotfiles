{
  lib,
  pkgs,
  settings,
  isDarwin,
  hostname,
  homeDirectory,
  username,
  ...
}:

# `nix-update` — rebuild and activate this host's nix-darwin configuration.
#
# This is deliberately not `sudo darwin-rebuild switch --flake …`, which is the
# command the upstream docs give. That form does not work here:
#
#   * darwin-rebuild refuses to run `switch` as anything but root
#     ("system activation must now be run as root" — it does not self-elevate),
#     so the flake evaluation happens as root too, and
#   * nix's git fetcher then refuses to open this repository, because it is owned
#     by the login user: "repository path is not owned by current user"
#     (libgit2 error 7).
#
# Registering the path in git's safe.directory does fix that — verified in both
# root's own config and /etc/gitconfig — but relying on it would mean the very
# first activation on a new machine cannot work, since whichever file holds the
# entry has to be put there before nix-darwin has ever run. Managing
# /etc/gitconfig declaratively also collides with writing it by hand during
# bootstrap.
#
# Splitting the work avoids the problem instead of papering over it: build as the
# user who owns the repository, then use root only for the two things that
# genuinely need it. Those two steps are exactly what `darwin-rebuild switch`
# does after building, so the semantics are unchanged — including registering the
# generation, which `activate` alone would skip, leaving rollbacks blind to it.

let
  flakeDir = "${homeDirectory}/${settings.dotfilesRelPath}/nix";

  # Determinate Nix owns the installation (nix.enable = false in
  # modules/darwin/system.nix), so nix lives in its default profile rather than
  # in the nix-darwin system path. Spelled out in full because the commands below
  # run under sudo, which does not inherit this PATH.
  nixBin = "/nix/var/nix/profiles/default/bin";

  nix-update = pkgs.writeShellApplication {
    name = "nix-update";
    text = ''
      flake=${lib.escapeShellArg flakeDir}
      host=${lib.escapeShellArg hostname}
      user=${lib.escapeShellArg username}
      home=${lib.escapeShellArg homeDirectory}

      echo "==> building darwinConfigurations.$host" >&2
      system=$(${nixBin}/nix build --no-link --print-out-paths \
        "$flake#darwinConfigurations.$host.system")

      echo "==> registering generation" >&2
      sudo ${nixBin}/nix-env -p /nix/var/nix/profiles/system --set "$system"

      echo "==> activating $system" >&2
      sudo "$system/sw/bin/darwin-rebuild" activate

      # Only reached once `activate` above has exited 0 (set -o errexit).
      # home-manager's backupFileExtension = "hm-bak" (flake.nix) leaves a
      # .hm-bak next to any pre-existing file it had to move aside; a
      # leftover .hm-bak from a prior activation then blocks the *next*
      # activation's own backup attempt ("Existing file ... would be
      # clobbered"). Scoped to exactly the paths home.file manages (read
      # back from the same evaluation, not a `find $HOME -name '*.hm-bak'`
      # sweep) so it can never touch a .hm-bak the user created themselves
      # outside home-manager's control.
      echo "==> pruning stale home-manager .hm-bak backups" >&2
      homeFiles=$(${nixBin}/nix eval --raw \
        "$flake#darwinConfigurations.$host.config.home-manager.users.$user.home.file" \
        --apply 'x: builtins.concatStringsSep "\n" (builtins.attrNames x)')
      while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        rel=''${rel#./}
        bak="$home/$rel.hm-bak"
        if [ -e "$bak" ]; then
          echo "    removing $bak" >&2
          rm -rf "$bak"
        fi
      done <<< "$homeFiles"
    '';
  };
in
{
  home.packages = lib.mkIf isDarwin [ nix-update ];
}
