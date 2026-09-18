{
  homeDirectory,
  settings,
  lib,
  pkgs,
  ...
}:

# AI-tool dotfile placement (~/.claude, ~/.pi/agent, ~/.agy, ~/.gemini,
# ~/.codex, ~/.prime/agent) is delegated to Makefile.d/install.mk's own
# claude/install, pi/install, agy/install, codex/install, and primeagent/install
# targets instead of re-declaring the same placements as home.file. See
# ADR-0002 (docs/adr/ADR-0002-dotfiles-placement-makefile-symlink-unification.md)
# and this directory's CONTEXT.md for the full rationale. In short: those Make
# targets already use `ln -sfvn` -- idempotent, no backup step -- which is
# exactly what home.file's backupFileExtension = "hm-bak" dance cannot offer.
# A pre-existing .hm-bak from an earlier activation permanently blocks the
# next activation's own backup attempt for the same path ("Existing file ...
# would be clobbered"), which is what originally broke `make nix/switch` here.
#
# This module previously reimplemented the same Makefile targets natively in
# Nix (home.file entries mirroring each `ln -sfvn` line). That parallel
# implementation is what actually drifted: `claude/install`'s builder swap to
# nixpkgs' current `buildGoNNNModule` naming aside, keeping two hand-written
# copies of ~350 file placements in sync was the real maintenance cost ADR-0002
# set out to remove.
{
  home.activation.dotfilesAgentToolsInstall = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ "$(id -u)" -eq 0 ]; then
      echo "dotfilesAgentToolsInstall: refusing to run as root (home-manager activation is expected to run as the target user)" >&2
      exit 1
    fi

    rootDir=${lib.escapeShellArg "${homeDirectory}/${settings.dotfilesRelPath}"}
    if [ ! -d "$rootDir" ]; then
      echo "dotfilesAgentToolsInstall: live checkout not found at $rootDir -- clone it there first" >&2
      exit 1
    fi

    # home-manager's activation environment does not include the profile's
    # own home.packages on PATH (chicken-and-egg: the new generation isn't
    # "live" until activation finishes) -- confirmed on-host, where a bare
    # `make` call here failed with "command not found" even though gnumake is
    # in shared.nix's home.packages. Resolve every nix-provided tool this
    # invocation (and everything install.mk shells out to: envsubst, jq) needs
    # by absolute store path instead, matching the same pattern
    # shared.nix's compileTmuxScripts already uses for pkgs.zsh. BSD coreutils
    # (ln/mkdir/find/cp/chmod) and sudo come from the ambient system PATH, same
    # as an interactive shell running `make claude/install` directly.
    export PATH=${lib.makeBinPath [ pkgs.gnumake pkgs.gettext pkgs.jq ]}:$PATH

    echo "==> make -C $rootDir claude/install pi/install agy/install codex/install primeagent/install" >&2
    $DRY_RUN_CMD make -C "$rootDir" \
      claude/install pi/install agy/install codex/install primeagent/install
  '';
}
