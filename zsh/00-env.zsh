fpath=("$DOTFILES_DIR/zfunc" $fpath)
autoload -Uz _zcache_eval

if [[ ${OSTYPE} == "darwin"* && -x /usr/libexec/path_helper ]]; then
	PATH=""
	[ -z "$_lazy_path_helper" ] && {
		_zcache_eval path_helper 0 "/usr/libexec/path_helper -s" /etc/paths /etc/paths.d
		_lazy_path_helper=1
	}
fi

# Nix profiles — must come after the path_helper reset above, and must NOT sit
# inside the _ZSH_PATH_LOADED block further down.
#
# On darwin the `PATH=""` above discards everything /etc/zshenv exported, which
# is where nix-darwin puts its profiles; nix-darwin registers nothing in
# /etc/paths.d, so nothing comes back. And by the time this file is read,
# ~/.zcache/env.zsh has already set _ZSH_PATH_LOADED=1, so the block below is
# skipped entirely. The result was that every tool installed through nix — all
# ~650 of them, plus `nix` and `darwin-rebuild` themselves — was missing from
# PATH while the setup otherwise looked healthy.
#
# Listed in descending precedence and prepended in one step so this order is the
# order in PATH. Missing directories are skipped, so this is inert on hosts
# without nix. _apply_base_path's `typeset -U path PATH` (below) removes
# duplicates on repeated sourcing.
_nixpath=""
for _nixdir in \
	"$HOME/.nix-profile/bin" \
	"/etc/profiles/per-user/${USER:-$USERNAME}/bin" \
	"/run/current-system/sw/bin" \
	"/nix/var/nix/profiles/default/bin"; do
	[[ -d "$_nixdir" ]] && _nixpath="${_nixpath}${_nixdir}:"
done
[[ -n "$_nixpath" ]] && export PATH="${_nixpath}${PATH}"
unset _nixdir _nixpath

export CHARSET=${CHARSET:-UTF-8}
export LESSCHARSET=${LESSCHARSET:-${CHARSET}}
export XLANGCCUS=${XLANGCCUS:-en_US}
export XLANGCCJP=${XLANGCCJP:-ja_JP}

locale_us_default="${XLANGCCUS}.${CHARSET}"
locale_jp_default="${XLANGCCJP}.${CHARSET}"

for var in LANG LC_ALL LC_CTYPE; do
	eval "val=\$${var}"
	case "$val" in
	"" | . | ${CHARSET} | C | POSIX | US-ASCII | ANSI_X3.4-1968)
		export ${var}="$locale_us_default"
		;;
	esac
done

for var in LC_ADDRESS LC_COLLATE LC_IDENTIFICATION LC_MEASUREMENT LC_MESSAGES LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE; do
	eval "val=\$${var}"
	case "$val" in
	"" | . | ${CHARSET})
		export ${var}="$locale_us_default"
		;;
	esac
done

for var in LC_TIME MANLANG; do
	eval "val=\$${var}"
	case "$val" in
	"" | . | ${CHARSET})
		export ${var}="$locale_jp_default"
		;;
	esac
done

[[ -z "$LANGUAGE" ]] && export LANGUAGE="${XLANGCCUS}:${XLANGCCJP}"

# On darwin, _ZSH_PATH_LOADED may already be 1 by the time this file runs —
# either zshrc's early fallback or ~/.zcache/env.zsh (the _gen_env cache) sets
# it before combined.zsh is sourced. But the darwin branch at the top of this
# file always does `PATH=""` first (to let path_helper rebuild it), which
# discards whatever those earlier fallbacks put on PATH. Reusing the shared
# _ZSH_PATH_LOADED guard here would then see it already set and skip this
# block entirely, permanently dropping everything _base_path adds
# ($HOME/.local/bin, $HOME/.bun/bin, $GOBIN, $CARGO_HOME/bin, docker
# cli-plugins, etc.) for the rest of the session. A darwin-only guard ensures
# this block runs once after the PATH="" reset regardless of who set
# _ZSH_PATH_LOADED earlier. Non-darwin is unaffected — it keeps checking
# _ZSH_PATH_LOADED as before.
if [[ ${OSTYPE} == darwin* ]]; then
	_zsh_path_guard="$_ZSH_DARWIN_BASE_PATH_DONE"
else
	_zsh_path_guard="$_ZSH_PATH_LOADED"
fi

if [[ -z "$_zsh_path_guard" ]]; then
	# Deliberately NOT exported: an exported guard survives into every child
	# process (a new tmux pane, a nested `zsh`, an ssh session multiplexed
	# through the same tmux server) via normal fork/exec environment
	# inheritance. Each of those processes re-sources this file and hits its
	# own `PATH=""` reset, so each one independently needs this block to run
	# again — an inherited "already done" from a parent process's guard would
	# reproduce the exact bug this file works around, just one process
	# removed. Confirmed empirically: a plain `zsh -c` spawned from a shell
	# that had already exported this guard inherited it and skipped rebuild.
	[[ ${OSTYPE} == darwin* ]] && _ZSH_DARWIN_BASE_PATH_DONE=1
	# _ZSH_PATH_LOADED still gets set (and exported) on success either way:
	# other files (and later code in this one) key off it meaning "PATH base
	# construction is done in this process", not "which guard variable ran
	# it". Its own export-inheritance exposure is pre-existing/unchanged by
	# this fix — non-darwin never resets PATH after setting it, so an
	# inherited 1 there is correct, not stale.
	export _ZSH_PATH_LOADED=1
	# _apply_base_path (zfunc/) holds the typeset -g -U / _base_path / export
	# triplet — see its header for why -g is required here specifically (this
	# call site runs inside zsh-defer's anonymous-function task runner).
	autoload -Uz _apply_base_path
	_apply_base_path
fi
unset _zsh_path_guard

export SHELL=${SHELL:-${commands[zsh]}}
export USER=${USER:-$USERNAME}

export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.data}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-$HOME/.local/run}

if [[ ! -d "$XDG_RUNTIME_DIR" ]]; then
	mkdir -p "$XDG_RUNTIME_DIR"
	chmod 700 "$XDG_RUNTIME_DIR"
fi

if [ -z "$TMUX" ]; then
	export TERM=${TERM:-"xterm-256color"}
else
	export TERM=${TERM:-"tmux-256color"}
fi

export SCOUT_DISABLE=${SCOUT_DISABLE:-1}

# Bun binary lives at /usr/local/bin/bun (system-wide).  Without this, bun injects
# BUN_INSTALL=/usr/local at startup, causing AccessDenied when bun tries to write to
# that root-owned path as tempdir (e.g. claude-mem Stop hook via bun-runner.js).
# Unconditional: must be set before bun/claude starts so child processes inherit it.
export BUN_INSTALL="$HOME/.bun"
