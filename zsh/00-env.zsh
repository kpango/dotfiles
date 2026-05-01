fpath=("$DOTFILES_DIR/zfunc" $fpath)
autoload -Uz _zcache_eval

if [[ ${OSTYPE} == "darwin"* && -x /usr/libexec/path_helper ]]; then
	PATH=""
	[ -z "$_lazy_path_helper" ] && {
		_zcache_eval path_helper 0 "/usr/libexec/path_helper -s" /etc/paths /etc/paths.d
		_lazy_path_helper=1
	}
fi

export CHARSET=${CHARSET:-UTF-8}
export LESSCHARSET=${LESSCHARSET:-${CHARSET}}
export XLANGCCUS=${XLANGCCUS:-en_US}
export XLANGCCJP=${XLANGCCJP:-ja_JP}

locale_us_default="${XLANGCCUS}.${CHARSET}"
locale_jp_default="${XLANGCCJP}.${CHARSET}"

for var in LANG LC_ALL LC_CTYPE; do
	[[ -z "${(P)var}" || "${(P)var}" == (.|${CHARSET}|C|POSIX|US-ASCII|ANSI_X3.4-1968) ]] && export ${var}="$locale_us_default"
done

for var in LC_ADDRESS LC_COLLATE LC_IDENTIFICATION LC_MEASUREMENT LC_MESSAGES LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE; do
	[[ -z "${(P)var}" || "${(P)var}" == (.|${CHARSET}) ]] && export ${var}="$locale_us_default"
done

for var in LC_TIME MANLANG; do
	[[ -z "${(P)var}" || "${(P)var}" == (.|${CHARSET}) ]] && export ${var}="$locale_jp_default"
done

[[ -z "$LANGUAGE" ]] && export LANGUAGE="${XLANGCCUS}:${XLANGCCJP}"

if [[ -z "$_ZSH_PATH_LOADED" || ${OSTYPE} == "darwin"* ]]; then
	export _ZSH_PATH_LOADED=1
	typeset -U path PATH

	CPUTYPE=${CPUTYPE:-$HOSTTYPE}
	if [[ ${OSTYPE} == "darwin"* ]] && [[ ${CPUTYPE} == "arm"* || ${CPUTYPE} == "aarch64"* ]]; then
		export PATH="/opt/homebrew/bin:$PATH"
	fi
	export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bun/bin:/usr/local/go/bin:/opt/local/bin:${GOBIN:-$HOME/go/bin}:$HOME/.local/bin:${CARGO_HOME:-$HOME/.cargo}/bin:$GCLOUD_PATH/bin:/usr/lib/docker/cli-plugins/:$PATH"

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
