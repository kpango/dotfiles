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
# without nix. `typeset -U path PATH` removes duplicates on repeated sourcing.
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

if [[ -z "$_ZSH_PATH_LOADED" ]]; then
	export _ZSH_PATH_LOADED=1
	typeset -U path PATH

	# OS-common dirs vs macOS-only additions (Homebrew) live in _base_path, the
	# single source shared with _gen_env (env.zsh cache) and zshrc.
	autoload -Uz _base_path
	export PATH="$(_base_path):$PATH"

	if (($+commands[deno])); then
		export PATH="${commands[deno]:h}:$PATH"
	fi

	if [ -d "$HOME/.rd/bin" ]; then
		export PATH="$HOME/.rd/bin:$PATH"
	fi
fi

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
