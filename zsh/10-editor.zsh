if [ -z "$VIM" ]; then
	if (($+commands[hx])); then
		export VIM=${commands[hx]}
	elif (($+commands[nvim])); then
		export VIM=${commands[nvim]}
		if [[ ${OSTYPE} == "darwin"* ]]; then
			if [[ -f "$ZCACHE_DIR/nvim_runtime.zsh" ]]; then
				if (($+functions[zsh-defer])); then zsh-defer -p -r source "$ZCACHE_DIR/nvim_runtime.zsh"; else source "$ZCACHE_DIR/nvim_runtime.zsh"; fi
			else
				_zcache_eval nvim_runtime 1 'local rts=(/opt/homebrew/Cellar/neovim/*/share/nvim/runtime(N)); ((${#rts[@]} > 0)) && echo "export VIMRUNTIME=\"${rts[-1]}\""'
			fi
		elif [[ ${OSTYPE} == "linux"* ]] && [ -d /usr/share/nvim/runtime ]; then
			export VIMRUNTIME="/usr/share/nvim/runtime"
		fi
		export NVIM_HOME=$XDG_CONFIG_HOME/nvim
		export NVIM_LOG_FILE_PATH=$XDG_DATA_HOME/log
		export NVIM_TUI_ENABLE_TRUE_COLOR=1
		export NVIM_PYTHON_LOG_LEVEL=WARNING
		export NVIM_PYTHON_LOG_FILE=$NVIM_LOG_FILE_PATH/nvim.log
	elif (($+commands[vim])); then
		export VIM=${commands[vim]}
	else
		export VIM=${commands[vi]}
	fi
fi
export EDITOR=${EDITOR:-$VIM}
export VISUAL=${VISUAL:-$EDITOR}
export PAGER=${PAGER:-${commands[less]}}
export SUDO_EDITOR=${SUDO_EDITOR:-$EDITOR}

#ReactNative
export REACT_EDITOR=${REACT_EDITOR:-$EDITOR}

if (($+commands[hx])); then
	alias nvim="hx" vim="hx" vi="hx" bim="hx" cim="hx"
elif (($+commands[nvim])); then
	neovim() {
		local neovim="$commands[nvim]"
		if (($+commands[pass])); then
			if pass show neovim; then
				"$neovim" "$@"
			else
				echo "failed to open $@ due to the open ai api key load failure"
			fi
		else
			"$neovim" "$@"
		fi
	}
	alias nvim="neovim" vim="neovim" vi="neovim" bim="neovim" cim="neovim"
	alias nvup="nvim --headless -c 'UpdateRemotePlugins' -c 'PackerSync' -c 'PackerCompile'"
	nvim-init() {
		rm -rf "$XDG_CONFIG_HOME/gocode" \
			"$XDG_CONFIG_HOME/nvim/autoload" \
			"$XDG_CONFIG_HOME/nvim/ftplugin" \
			"$XDG_CONFIG_HOME/nvim/log" \
			"$XDG_CONFIG_HOME/nvim/pack" \
			"$HOME/.nvimlog" \
			"$HOME/.viminfo"
		nvup
	}
	alias nvinit="nvim-init"
	alias vake="$EDITOR Makefile"
	alias vback="cp $XDG_CONFIG_HOME/nvim/init.lua $XDG_CONFIG_HOME/nvim/init.lua.back"
	alias vedit="$EDITOR $XDG_CONFIG_HOME/nvim/"
	alias vocker="$EDITOR Dockerfile"
	alias vrest="cp $XDG_CONFIG_HOME/nvim/init.lua.back $XDG_CONFIG_HOME/nvim/init.lua"
else
	alias nvim="$EDITOR" vim="$EDITOR" vi="$EDITOR" bim="$EDITOR" cim="$EDITOR"
	alias vedit="$EDITOR $HOME/.vimrc"
fi

alias vspdchk="rm -rf /tmp/startup.log && $EDITOR --startuptime /tmp/startup.log +q && less /tmp/startup.log"
alias xedit="$EDITOR $HOME/.Xdefaults"
alias wedit="$EDITOR $XDG_CONFIG_HOME/sway/config"

if (($+commands[ranger])); then
	alias rng=ranger
fi

zedit() {
	if { [ -L "$HOME/.zshrc" ] || [ -f "/.dockerenv" ]; } && [ -f "$DOTFILES_DIR/zshrc" ]; then
		$EDITOR "$DOTFILES_DIR/zshrc"
	else
		$EDITOR "$HOME/.zshrc"
	fi
}

alias zsback="cp $HOME/.zshrc $HOME/.zshrc.back"
