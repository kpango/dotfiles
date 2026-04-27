#!/usr/bin/env zsh

export ZCACHE_DIR="${ZCACHE_DIR:-$HOME/.zcache}"

if [[ -f "$ZCACHE_DIR/env.zsh" ]]; then
	source "$ZCACHE_DIR/env.zsh"
else
	[[ -d "$ZCACHE_DIR" ]] || mkdir -p "$ZCACHE_DIR"
	if [ -z "$CPUCORES" ]; then
		if (($+commands[nproc])); then
			export CPUCORES="$(nproc)"
		else
			export CPUCORES="$(getconf _NPROCESSORS_ONLN)"
		fi
	fi

	# Determine DOTFILES_DIR
	export GIT_USER=${GIT_USER:-kpango}
	if [ -z "$DOTFILES_DIR" ]; then
		DOTFILE_URL="github.com/$GIT_USER/dotfiles"
		if [ -d "$HOME/go/src/$DOTFILE_URL" ]; then
			export DOTFILES_DIR="$HOME/go/src/$DOTFILE_URL"
		elif [ -d "$HOME/ghq/$DOTFILE_URL" ]; then
			export DOTFILES_DIR="$HOME/ghq/$DOTFILE_URL"
		elif (($+commands[ghq])); then
			export DOTFILES_DIR="$(ghq root)/$DOTFILE_URL"
		else
			export DOTFILES_DIR="$HOME/dotfiles"
		fi
	fi

	fpath=("$DOTFILES_DIR/zfunc" $fpath)
	autoload -Uz _zcache_eval

	_gen_env() {
		echo "export CPUCORES=\"$CPUCORES\""
		echo "export GIT_USER=\"$GIT_USER\""
		echo "export DOTFILES_DIR=\"$DOTFILES_DIR\""
		if (($+commands[tmux])); then
			echo "export HAS_TMUX=1"
		fi
		if (($+commands[ghostty])); then
			echo "export TERMCMD=\"ghostty -e \$SHELL -c tmux -S /tmp/tmux.sock -q has-session && exec tmux -S /tmp/tmux.sock -2 attach-session -d || exec tmux -S /tmp/tmux.sock -2 new-session -n\$USER -s\$USER@\$HOST\""
		elif (($+commands[alacritty])); then
			echo "export TERMCMD=\"alacritty -e \$SHELL -c tmux -S /tmp/tmux.sock -q has-session && exec tmux -S /tmp/tmux.sock -2 attach-session -d || exec tmux -S /tmp/tmux.sock -2 new-session -n\$USER -s\$USER@\$HOST\""
		elif (($+commands[urxvtc])); then
			echo "export TERMCMD=\"urxvtc -e \$SHELL -c tmux -S /tmp/tmux.sock -q has-session && exec tmux -S /tmp/tmux.sock -2 attach-session -d || exec tmux -S /tmp/tmux.sock -2 new-session -n\$USER -s\$USER@\$HOST\""
		fi
	}
	_zcache_eval env 0 "_gen_env"
fi

if [[ -z "$functions[_zcache_eval]" ]]; then
	fpath=("$DOTFILES_DIR/zfunc" $fpath)
	autoload -Uz _zcache_eval
fi

local combined_cache="$ZCACHE_DIR/combined.zsh"
if [[ -f "$combined_cache" ]]; then
	source "$combined_cache"
else
	local zsh_deps=("$DOTFILES_DIR/zsh"/*.zsh(N))
	_zcache_eval combined 0 'cat "$DOTFILES_DIR/zsh"/*.zsh(N)' "${zsh_deps[@]}"
fi
