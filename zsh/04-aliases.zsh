if (($+commands[cpz])); then
	alias cp='cpz'
else
	alias cp='cp -r'
fi

if (($+commands[rmz])); then
	alias rm='rmz -f'
else
	alias rm='rm -rf'
fi

alias mv='mv -i'
alias mkdir='mkdir -p'
alias -g L='| less'

alias dl="\cd $HOME/Downloads"
alias dc="\cd $HOME/Documents"
alias ..='\cd ../' ...='\cd ../../' ....='\cd ../../../' .....='\cd ../../../../' ......='\cd ../../../../../'
alias ,,='\cd ../' ,,,='\cd ../../' ,,,,='\cd ../../../' ,,,,,='cd ../../../../' ,,,,,,='\cd ../../../../../'

alias :q=exit
alias :wq=exit

alias 600='chmod -R 600'
alias 644='chmod -R 644'
alias 655='chmod -R 655'
alias 755='chmod -R 755'
alias 777='chmod -R 777'

setopt no_global_rcs

zstyle ':zle:*' word-chars " /=;@:{},|"
zstyle ':zle:*' word-style unspecified
if (($+functions[zsh-defer])); then
	zsh-defer -p -r -c "autoload -Uz select-word-style && select-word-style default"
else
	autoload -Uz select-word-style
	select-word-style default
fi

case ${OSTYPE} in
linux*)
	if (($+commands[xsel])); then
		alias pbcopy="xsel --clipboard --input"
		alias pbpaste="xsel --clipboard --output"
	elif (($+commands[wl-copy])); then
		alias pbcopy="wl-copy"
		alias pbpaste="wl-paste"
	fi
	;;
esac

if (($+commands[rg])); then alias grep=rg; fi
if (($+commands[fd])); then alias find='fd'; fi
if (($+commands[dutree])); then alias du='dutree'; fi
if (($+commands[bat])); then alias cat='bat'; fi
if (($+commands[hyperfine])); then alias time='hyperfine'; fi
if (($+commands[procs])); then alias ps='procs'; fi

if (($+commands[btop])); then
	alias top='btop' htop='btop' btm='btop'
elif (($+commands[btm])); then
	alias top='btm' htop='btm' btop='btm'
elif (($+commands[htop])); then
	alias top='htop' btop='htop' btm='htop'
fi

if (($+commands[lsd])); then
	alias ks="lsd" l="lsd" ls='lsd'
	alias ll='lsd -l' la='lsd -aAlLh' lla='lsd -aAlLhi'
	alias tree='lsd --tree --total-size --human-readable' lg='lsd -aAlLh | rg'
elif (($+commands[erd])); then
	local erd_base='erd -H -d logical -I --level 1 --sort rsize -y inverted --dir-order first'
	local erd_la='erd -H -d logical -I -l --group --octal --time-format iso --sort rsize -y inverted --dir-order first --threads 32 --hidden --color force'
	alias ks="$erd_base" l="$erd_base" ll="$erd_base" ls="$erd_base"
	alias la="$erd_la --level 1"
	alias lla="$erd_la --no-git --level 2"
	alias tree="$erd_la --no-git"
	alias lg="$erd_la --level 1 | rg"
elif (($+commands[eza])); then
	alias ks="eza -G" l="eza -G" ls='eza -G'
	alias ll='eza -l' la='eza -aghHliS' lla='eza -aghHliSm' tree='eza -T' lg='eza -aghHliS | rg'
else
	case ${OSTYPE} in
	darwin*)
		alias ks="ls -G" l="ls -G" ls="ls -G"
		alias ll='ls -laG' la='ls -laG' lg='ls -aG | rg'
		;;
	linux*)
		alias ks="ls --color=auto" l="ls --color=auto" ls="ls --color=auto"
		alias ll='ls -la --color=auto' la='ls -la --color=auto' lg='ls -a --color=auto | rg'
		;;
	esac
fi

if (($+commands[fzf])); then
	if (($+commands[fzf-tmux])); then
		if (($+commands[fd])); then
			alias s='mkcd $(fd -a -H -t d . | fzf-tmux +m)'
			alias vf='hx $(fd -a -H -t f . | fzf-tmux +m)'
		fi
		if (($+commands[ghq])); then
			alias g='mkcd $(ghq root)/$(ghq list | fzf-tmux +m)'
		fi
	fi
fi

if (($+commands[tar])); then
	alias tarzip="\tar Jcvf"
	alias tarunzip="\tar Jxvf"
fi

if (($+commands[duf])); then alias df='\duf'; fi
if (($+commands[xdg-open])); then alias open=xdg-open; fi

if (($+functions[zsh-defer])); then
	if (($+commands[fastfetch])); then
		zsh-defer -p -r fastfetch
	elif (($+commands[neofetch])); then
		zsh-defer -p -r neofetch
	fi
else
	if (($+commands[fastfetch])); then
		fastfetch
	elif (($+commands[neofetch])); then
		neofetch
	fi
fi
mkcd() {
	if [[ -d $1 ]]; then
		\cd $1
	else
		printf "Confirm to Make Directory? $1 [y/N]: "
		if read -q; then
			echo
			\mkdir -p $1 && \cd $1
		fi
	fi
}
