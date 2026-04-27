export ZSH_AUTOSUGGEST_USE_ASYNC=1
export ZSH_AUTOSUGGEST_MANUAL_REBIND=1

bindkey -e

if (($+commands[sheldon])); then
	if [[ -f "$ZCACHE_DIR/sheldon.zsh" ]]; then
		source "$ZCACHE_DIR/sheldon.zsh"
	else
		_zcache_eval sheldon 0 "sheldon source" "$HOME/.config/sheldon/plugins.toml"
	fi
fi

if (($+commands[direnv])); then
	if [[ -f "$ZCACHE_DIR/direnv.zsh" ]]; then
		zsh-defer -p -r source "$ZCACHE_DIR/direnv.zsh"
	else
		_zcache_eval direnv 1 "direnv hook zsh" "$commands[direnv]"
	fi
fi
