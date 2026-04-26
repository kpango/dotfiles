if [ -z "$VIM" ]; then
	if (($+commands[hx])); then
		export VIM=${commands[hx]}
	elif (($+commands[nvim])); then
		export VIM=${commands[nvim]}
		case ${OSTYPE} in
		darwin*)
			if [ -d /opt/homebrew/Cellar/neovim/*/share/nvim/runtime ]; then
				export VIMRUNTIME="/opt/homebrew/Cellar/neovim/*/share/nvim/runtime"
			fi
			;;
		linux*)
			if [ -d /usr/share/nvim/runtime ]; then
				export VIMRUNTIME="/usr/share/nvim/runtime"
			fi
			;;
		esac
		export NVIM_HOME=$XDG_CONFIG_HOME/nvim
		export NVIM_LOG_FILE_PATH=$XDG_DATA_HOME/log
		export NVIM_TUI_ENABLE_TRUE_COLOR=1
		export NVIM_PYTHON_LOG_LEVEL=WARNING
		export NVIM_PYTHON_LOG_FILE=$NVIM_LOG_FILE_PATH/nvim.log
	elif (($+commands[vim])); then
		export VIM=${commands[vim]}
		case ${OSTYPE} in
		darwin*)
			if [ -d /opt/homebrew/Cellar/neovim/*/share/nvim/runtime ]; then
				export VIMRUNTIME="/opt/homebrew/Cellar/neovim/*/share/nvim/runtime"
			fi
			;;
		linux*)
			if [ -d /usr/share/nvim/runtime ]; then
				export VIMRUNTIME="/usr/share/nvim/runtime"
			fi
			;;
		esac
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
	alias nvim=hx
	alias vim=hx
	alias vi=hx
	alias bim=hx
	alias cim=hx
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
	alias nvim=neovim
	alias vim=neovim
	alias vi=neovim
	alias bim=neovim
	alias cim=neovim
	alias nvup="nvim --headless -c 'UpdateRemotePlugins' -c 'PackerSync' -c 'PackerCompile'"
	nvim-init() {
		rm -rf "$HOME/.config/gocode"
		rm -rf "$HOME/.config/nvim/autoload"
		rm -rf "$HOME/.config/nvim/ftplugin"
		rm -rf "$HOME/.config/nvim/log"
		rm -rf "$HOME/.config/nvim/pack"
		nvup
		rm "$HOME/.nvimlog"
		rm "$HOME/.viminfo"
	}
	alias nvinit="nvim-init"
	alias vake="nvim Makefile"
	alias vback="cp $HOME/.config/nvim/init.lua $HOME/.config/nvim/init.lua.back"
	alias vedit="nvim $HOME/.config/nvim/"
	alias vocker="nvim Dockerfile"
	alias vrestore="cp $HOME/.config/nvim/init.lua.back $HOME/.config/nvim/init.lua"
	alias vspdchk="rm -rf /tmp/starup.log && nvim --startuptime /tmp/startup.log +q && less /tmp/startup.log"
	alias wedit="nvim $HOME/.config/sway/config"
	alias xedit="nvim $HOME/.Xdefaults"
else
	alias vedit="$EDITOR $HOME/.vimrc"
	alias vi="$EDITOR"
	alias vim="$EDITOR"
	alias bim="$EDITOR"
	alias cim="$EDITOR"
	alias vspdchk="rm -rf /tmp/starup.log && $EDITOR --startuptime /tmp/startup.log +q && less /tmp/startup.log"
	alias xedit="$EDITOR $HOME/.Xdefaults"
	alias wedit="$EDITOR $HOME/.config/sway/config"
fi

if (($+commands[ranger])); then
	alias rng=ranger
fi

if { [ -L "$HOME/.zshrc" ] || [ -f "/.dockerenv" ]; } && [ -f "$DOTFILES_DIR/zshrc" ]; then
	alias zedit="$EDITOR $DOTFILES_DIR/zshrc"
else
	alias zedit="$EDITOR $HOME/.zshrc"
fi

alias zsback="cp $HOME/.zshrc $HOME/.zshrc.back"
