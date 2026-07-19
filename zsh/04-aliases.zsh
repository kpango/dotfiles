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
	if (($+commands[wl-copy])); then
		alias pbcopy="wl-copy"
		alias pbpaste="wl-paste"
	elif (($+commands[xclip])); then
		alias pbcopy="xclip -i -selection clipboard"
		alias pbpaste="xclip -o -selection clipboard"
	elif (($+commands[xsel])); then
		alias pbcopy="xsel --clipboard --input"
		alias pbpaste="xsel --clipboard --output"
	fi
	;;
esac

if (($+commands[rg])); then alias grep=rg; fi
if (($+commands[fd])); then alias find='fd'; fi
if (($+commands[dutree])); then alias du='dutree'; fi
if (($+commands[bat])); then alias cat='bat'; fi
if (($+commands[hyperfine])); then alias time='hyperfine'; fi
if (($+commands[procs])); then alias ps='procs'; fi
if (($+commands[gitui])); then alias tig=gitui; fi

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

alias s='mkcd $(fd -a -H -t d . | fzf --tmux center)'
alias vf='hx $(fd -a -H -t f . | fzf --tmux center)'
g() {
	local dir
	dir=$(
		{
			(($+commands[ghq])) && ghq list -p
			(($+commands[zoxide])) && zoxide query --list 2>/dev/null
		} | sort -u | fzf --tmux center
	)
	[[ -n "$dir" ]] && mkcd "$dir"
}

zsync_state() {
	emulate -L zsh
	local verbose=0
	[[ "$1" == "-v" || "$1" == "--verbose" ]] && verbose=1

	printf 'Initializing dotfiles state refresh...\n'

	if [[ -n "$TMUX" ]] && (($+commands[tmux])); then
		if ((verbose)); then printf '  -> Synchronizing Tmux environment...\n'; fi
		local _env_var _env_val
		while IFS='=' read -r _env_var _env_val; do
			if [[ -n "$_env_var" && -n "$_env_val" ]]; then
				export "$_env_var=$_env_val"
			fi
		done < <(tmux show-environment -s 2>/dev/null)
		if [[ -n "$SSH_AUTH_SOCK" && "$SSH_AUTH_SOCK" != "$HOME/.ssh/rc_auth_sock" ]]; then
			ln -sfvn "$SSH_AUTH_SOCK" "$HOME/.ssh/rc_auth_sock"
			export SSH_AUTH_SOCK="$HOME/.ssh/rc_auth_sock"
		fi
		tmux refresh-client &>/dev/null
	fi
	if (($+commands[gpg-connect-agent])); then
		if ((verbose)); then printf '  -> Refreshing GPG-Agent TTY...\n'; fi
		export GPG_TTY="${TTY:-$(tty)}"
		[[ -n "$TMUX" ]] && export PINENTRY_USER_DATA="TMUX=$TMUX"
		gpg-connect-agent updatestartuptty /bye &>/dev/null || {
			gpgconf --kill gpg-agent
			gpg-connect-agent updatestartuptty /bye &>/dev/null
		}
	fi
	if (($+commands[atuin])); then
		if ((verbose)); then printf '  -> Verifying Atuin daemon state...\n'; fi
		rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/atuin/history.db-lock" 2>/dev/null
		fc -RI 2>/dev/null
	fi
	if ((verbose)); then printf '  -> Sweeping container & infrastructure subsystems...\n'; fi
	if [[ -S /var/run/docker.sock && ! -w /var/run/docker.sock ]]; then
		sudo chown -R "${USER:-$(id -un)}:${GID:-$(id -gn)}" /var/run/docker.sock 2>/dev/null
	fi
	local -a zombie_pids
	zombie_pids=($(pgrep -f "kubectl port-forward" 2>/dev/null) $(pgrep -f "docker exec" 2>/dev/null))

	if ((${#zombie_pids} > 0)); then
		if ((verbose)); then printf '     * Reclaiming %d detached proxy/exec processes...\n' ${#zombie_pids}; fi
		kill -9 "${zombie_pids[@]}" 2>/dev/null
	fi
	if (($+commands[herdr])); then
		export HERDR_SESSION="${USER:-$USERNAME}-${HOST:-$HOSTNAME}"
		rm -f "/tmp/herdr-${HERDR_SESSION:?}.sock" 2>/dev/null
	fi
	local _tmpdir="${TMPDIR:-${XDG_RUNTIME_DIR:-/tmp}}"
	if [[ -d "$_tmpdir" ]]; then
		rm -rf "$_tmpdir"/fzf-* 2>/dev/null
		rm -rf "$_tmpdir"/.pin-* 2>/dev/null
	fi

	printf 'Dotfiles runtime state synchronized successfully.\n'
}
alias fix-state=zsync_state

if (($+commands[tar])); then
	alias tarzip="\tar Jcvf"
	alias tarunzip="\tar Jxvf"
fi

if (($+commands[duf])); then alias df='\duf'; fi
if (($+commands[xdg-open])); then alias open=xdg-open; fi
if (($+commands[claude])); then alias claude='GITHUB_PERSONAL_ACCESS_TOKEN=$(pass show github.api.ro.token) bun run --bun claude'; fi

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
