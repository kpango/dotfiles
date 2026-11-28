# Sheldon is loaded early in zshrc when zsh-defer is available; only load here as fallback
if (($+commands[sheldon])) && [[ -z "$ZSH_EXECUTION_STRING" ]] && ! (($+functions[zsh-defer])); then
	_zcache_eval sheldon 0 "sheldon source" \
		"${XDG_CONFIG_HOME:-$HOME/.config}/sheldon/plugins.toml"
fi

if (($+commands[direnv])); then
	_direnv_hook_fast() {
		[[ -n $DIRENV_DIR ]] && { eval "$("$commands[direnv]" export zsh)"; return; }
		local d=$PWD
		while [[ -n $d ]]; do
			if [[ -f "$d/.envrc" || -f "$d/.env" ]]; then
				eval "$("$commands[direnv]" export zsh)"
				return
			fi
			[[ $d == / || ( -n ${HOME:-} && $d == $HOME ) ]] && break
			d=${d:h}
		done
	}
	if [[ -f "$ZCACHE_DIR/direnv.zsh" && ! "$commands[direnv]" -nt "$ZCACHE_DIR/direnv.zsh" ]]; then
		source "$ZCACHE_DIR/direnv.zsh"
	else
		_zcache_eval direnv 0 "direnv hook zsh" "$commands[direnv]"
	fi
	_direnv_hook() { _direnv_hook_fast }
fi

