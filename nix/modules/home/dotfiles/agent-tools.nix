{
  homeDirectory,
  settings,
  lib,
  config,
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

    # home-manager's activation environment is far more minimal than an
    # interactive shell -- confirmed on-host in two rounds: neither
    # home.packages (make, go, git, zsh, gawk, gettext, jq -- everything
    # install.mk's targets and their prerequisites shell out to) nor even
    # /usr/bin, /bin were reliably on PATH ("make: command not found", then
    # "git"/"awk"/"zsh"/"go" all failing the same way one level deeper).
    # config.home.path is the same derivation home-manager itself builds to
    # put every home.packages entry on an interactive shell's PATH (see the
    # home-manager-path.drv this evaluates to); reuse it here instead of
    # hand-picking individual packages one failure at a time, and append the
    # standard system directories for anything not in home.packages (sudo,
    # in particular).
    export PATH="${config.home.path}/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

    # NIX_MANAGED=1 tells dotfiles/install (a prerequisite of every target
    # below) to skip DOTFILES_MAP destinations a home-manager module already
    # generates more richly than a plain symlink: programs.zsh's
    # .zshrc/.zshenv (zsh.nix), programs.git's .gitconfig (git.nix),
    # programs.tmux's .tmux.conf (tmux.nix), and darwin.nix's Nix-built
    # .gnupg/gpg-agent.conf on Darwin. Without this, dotfiles/install
    # silently replaces those with a plain live-repo symlink on every
    # `nix/switch`, and the *next* activation's checkLinkTargets refuses to
    # put home-manager's own version back (force = true doesn't help for
    # .zshrc/.zshenv specifically -- zsh.nix's own comment documents
    # home-manager keying those two paths as "./.zshrc" internally, which
    # never matches checkLinkTargets' normalized ".zshrc").
    echo "==> make -C $rootDir claude/install pi/install agy/install codex/install primeagent/install" >&2
    $DRY_RUN_CMD make -C "$rootDir" NIX_MANAGED=1 \
      claude/install pi/install agy/install codex/install primeagent/install
  '';
}
