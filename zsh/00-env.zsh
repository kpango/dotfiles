fpath=("$DOTFILES_DIR/zfunc" $fpath)
autoload -Uz _zcache_eval

if [[ ${OSTYPE} == "darwin"* && -x /usr/libexec/path_helper ]]; then
	PATH=""
	[ -z "$_lazy_path_helper" ] && {
		_zcache_eval path_helper 0 "/usr/libexec/path_helper -s" /etc/paths /etc/paths.d
		_lazy_path_helper=1
	}
fi

export CHARSET=${CHARSET:-UTF-8} LESSCHARSET=${LESSCHARSET:-${CHARSET}} \
	XLANGCCUS=${XLANGCCUS:-en_US} XLANGCCJP=${XLANGCCJP:-ja_JP} \
	LANG=${LANG:-${XLANGCCUS}.${CHARSET}} LANGUAGE=${LANGUAGE:-${XLANGCCUS}:${XLANGCCJP}} \
	LC_ADDRESS=${LC_ADDRESS:-"${XLANGCCUS}.${CHARSET}"} LC_ALL=${LC_ALL:-${XLANGCCUS}.${CHARSET}} \
	LC_COLLATE=${LC_COLLATE:-"${XLANGCCUS}.${CHARSET}"} LC_CTYPE=${LC_CTYPE:-${CHARSET}} \
	LC_IDENTIFICATION=${LC_IDENTIFICATION:-"${XLANGCCUS}.${CHARSET}"} LC_MEASUREMENT=${LC_MEASUREMENT:-"${XLANGCCUS}.${CHARSET}"} \
	LC_MESSAGES=${LC_MESSAGES:-"${XLANGCCUS}.${CHARSET}"} LC_MONETARY=${LC_MONETARY:-"${XLANGCCUS}.${CHARSET}"} \
	LC_NAME=${LC_NAME:-"${XLANGCCUS}.${CHARSET}"} LC_NUMERIC=${LC_NUMERIC:-"${XLANGCCUS}.${CHARSET}"} \
	LC_PAPER=${LC_PAPER:-"${XLANGCCUS}.${CHARSET}"} LC_TELEPHONE=${LC_TELEPHONE:-"${XLANGCCUS}.${CHARSET}"} \
	LC_TIME=${LC_TIME:-${XLANGCCJP}.${CHARSET}} MANLANG=${MANLANG:-${XLANGCCJP}.${CHARSET}}

if [[ -z "$_ZSH_PATH_LOADED" || ${OSTYPE} == "darwin"* ]]; then
	export _ZSH_PATH_LOADED=1
	typeset -U path PATH

	CPUTYPE=${CPUTYPE:-$HOSTTYPE}
	if [[ ${OSTYPE} == "darwin"* ]] && [[ ${CPUTYPE} == "arm"* || ${CPUTYPE} == "aarch64"* ]]; then
		export PATH="/opt/homebrew/bin:$PATH"
	fi
	export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bun/bin:/usr/local/go/bin:/opt/local/bin:$GOBIN:$HOME/.local/bin:$CARGO_HOME/bin:$GCLOUD_PATH/bin:/usr/lib/docker/cli-plugins/:$PATH"

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

if [ -z "$TMUX" ]; then
	export TERM=${TERM:-"xterm-256color"}
else
	export TERM=${TERM:-"tmux-256color"}
fi

export SCOUT_DISABLE=${SCOUT_DISABLE:-1}


