# Sheldon is loaded early in zshrc when zsh-defer is available; only load here as fallback
if (($+commands[sheldon])) && [[ -z "$ZSH_EXECUTION_STRING" ]] && ! (($+functions[zsh-defer])); then
	_zcache_eval sheldon 0 "sheldon source" \
		"${XDG_CONFIG_HOME:-$HOME/.config}/sheldon/plugins.toml"
fi

if (($+commands[direnv])); then
	if [[ -f "$ZCACHE_DIR/direnv.zsh" ]]; then
		if (($+functions[zsh-defer])); then zsh-defer -p -r source "$ZCACHE_DIR/direnv.zsh"; else source "$ZCACHE_DIR/direnv.zsh"; fi
	else
		_zcache_eval direnv 1 "direnv hook zsh" "$commands[direnv]"
	fi
fi
