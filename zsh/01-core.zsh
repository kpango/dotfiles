if [ -x /usr/libexec/path_helper ]; then
	PATH=""
	[ -z "$_lazy_path_helper" ] && {
		local path_cache="$HOME/.path_helper_cache.zsh"
		if [[ ! -f "$path_cache" || /etc/paths -nt "$path_cache" || /etc/paths.d -nt "$path_cache" ]]; then
			/usr/libexec/path_helper -s >"$path_cache"
		fi
		source "$path_cache"
		_lazy_path_helper=1
	}
fi
# environment var
export CHARSET=${CHARSET:-UTF-8}
export LESSCHARSET=${LESSCHARSET:-${CHARSET}}
export XLANGCCUS=${XLANGCCUS:-en_US}
export XLANGCCJP=${XLANGCCJP:-ja_JP}
export LANG=${LANG:-${XLANGCCUS}.${CHARSET}}
export LANGUAGE=${LANGUAGE:-${XLANGCCUS}:${XLANGCCJP}}
export LC_ADDRESS=${LC_ADDRESS:-"${XLANGCCUS}.${CHARSET}"}
export LC_ALL=${LC_ALL:-${XLANGCCUS}.${CHARSET}}
export LC_COLLATE=${LC_COLLATE:-"${XLANGCCUS}.${CHARSET}"}
export LC_CTYPE=${LC_CTYPE:-${CHARSET}}
export LC_IDENTIFICATION=${LC_IDENTIFICATION:-"${XLANGCCUS}.${CHARSET}"}
export LC_MEASUREMENT=${LC_MEASUREMENT:-"${XLANGCCUS}.${CHARSET}"}
export LC_MESSAGES=${LC_MESSAGES:-"${XLANGCCUS}.${CHARSET}"}
export LC_MONETARY=${LC_MONETARY:-"${XLANGCCUS}.${CHARSET}"}
export LC_NAME=${LC_NAME:-"${XLANGCCUS}.${CHARSET}"}
export LC_NUMERIC=${LC_NUMERIC:-"${XLANGCCUS}.${CHARSET}"}
export LC_PAPER=${LC_PAPER:-"${XLANGCCUS}.${CHARSET}"}
export LC_TELEPHONE=${LC_TELEPHONE:-"${XLANGCCUS}.${CHARSET}"}
export LC_TIME=${LC_TIME:-${XLANGCCJP}.${CHARSET}}
export MANLANG=${MANLANG:-${XLANGCCJP}.${CHARSET}}
if [ -z "$_ZSH_PATH_LOADED" ]; then
	export _ZSH_PATH_LOADED=1
	if [[ ${OSTYPE} == "darwin"* && ${CPUTYPE} == "arm"* ]]; then
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
if (($+commands[sheldon])); then
	[ -z "$_lazy_sheldon" ] && {
		sheldon_cache="$HOME/.sheldon_cache.zsh"
		if [[ ! -f "$sheldon_cache" || "$HOME/.config/sheldon/plugins.toml" -nt "$sheldon_cache" ]]; then
			sheldon source >"$sheldon_cache"
		fi
		source "$sheldon_cache"
		_lazy_sheldon=1
	}
fi
# ヒストリの設定
HISTFILE=$HOME/.zsh_history
HISTSIZE=1000000
SAVEHIST=1000000
setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt hist_ignore_all_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt hist_save_no_dups
LISTMAX=1000
WORDCHARS="$WORDCHARS|:"
# export PROMPT_COMMAND='hcmd=$(history 1); hcmd="${hcmd# *[0-9]*  }"; if [[ ${hcmd%% *} == "cd" ]]; then pwd=$OLDPWD; else pwd=$PWD; fi; hcmd=$(echo -e "cd $pwd && $hcmd"); history -s "$hcmd"'
########################################
# 補完
# 補完機能を有効にする

zstyle ':completion:*' format '%B%d%b'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' ignore-parents parent pwd ..
zstyle ':completion:*' keep-prefix
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' menu select
zstyle ':completion:*' squeeze-slashes true
zstyle ':completion:*' verbose yes
zstyle ':completion:*:(nano|vim|nvim|vi|emacs|e):*' ignored-patterns '*.(wav|mp3|flac|ogg|mp4|avi|mkv|webm|iso|dmg|so|o|a|bin|exe|dll|pcap|7z|zip|tar|gz|bz2|rar|deb|pkg|gzip|pdf|mobi|epub|png|jpeg|jpg|gif)'
zstyle ':completion:*:(rm|kill|diff):*' ignore-line other
zstyle ':completion:*:*:*:*:*' menu select
zstyle ':completion:*:*:-subscript-:*' tag-order indexes parameters
zstyle ':completion:*:*:cd:*' tag-order local-directories directory-stack path-directories
zstyle ':completion:*:*:cd:*:directory-stack' menu yes select
zstyle ':completion:*:-tilde-:*' group-order 'named-directories' 'path-directories' 'expand'
zstyle ':completion:*:corrections' format ' %F{green}-- %d (errors: %e) --%f'
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
# zstyle ':completion:*:default' list-prompt '%S%M matches%s'
zstyle ':completion:*:default' menu select=1
zstyle ':completion:*:descriptions' format ' %F{yellow}-- %d --%f'
# zstyle ':completion:*:functions' ignored-patterns '(_*|pre(cmd|exec)|prompt_*)'
zstyle ':completion:*:history-words' list false
zstyle ':completion:*:history-words' menu yes
zstyle ':completion:*:history-words' remove-all-dups yes
zstyle ':completion:*:history-words' stop yes
zstyle ':completion:*:manuals' separate-sections true
zstyle ':completion:*:manuals.(^1*)' insert-sections true
zstyle ':completion:*:matches' group 'yes'
zstyle ':completion:*:messages' format ' %F{purple} -- %d --%f'
zstyle ':completion:*:options' auto-description '%d'
zstyle ':completion:*:options' description 'yes'
zstyle ':completion:*:processes' command 'ps x -o pid, s, args'
zstyle ':completion:*:rm:*' file-patterns '*:all-files'
zstyle ':completion:*:sudo:*' command-path /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin /usr/X11R6/bin
zstyle ':completion:*:warnings' format ' %F{red}-- no matches found --%f'
zstyle ':completion::complete:*' cache-path "${ZDOTDIR:-${HOME}}/.zcompcache"
zstyle ':completion::complete:*' use-cache on
# zstyle ':zsh-kubectl-prompt:' separator ' | ns: '
# zstyle ':zsh-kubectl-prompt:' preprompt 'ctx: '
# zstyle ':zsh-kubectl-prompt:' postprompt ''
########################################
# vcs_info
# autoload -Uz vcs_info
# autoload -Uz add-zsh-hook
#
# zstyle ':vcs_info:*' formats '(%s)-[%b]'
# zstyle ':vcs_info:*' actionformats '%F{red}(%s)-[%b|%a]%f'

precmd() {
	if [ ! -z $TMUX ]; then
		tmux refresh-client -S
	fi
}
# _update_vcs_info_msg() {
# 	vcs_info
# 	# RPROMPT="%F{046}${vcs_info_msg_0_} %F{102}[%D{%Y-%m-%d %H:%M:%S}]"
# 	# RPROMPT="%F{green}${vcs_info_msg_0_} %{$fg[blue]%}($ZSH_KUBECTL_PROMPT)%{$reset_color%} %F{gray}[%D{%Y-%m-%d %H:%M:%S}]"
# }
# add-zsh-hook precmd _update_vcs_info_msg
########################################
# オプション
setopt auto_cd         # ディレクトリ名だけでcdする
setopt auto_list       # 補完候補を一覧表示
setopt auto_menu       # 補完候補が複数あるときに自動的に一覧表示する
setopt auto_param_keys # カッコの対応などを自動的に補完
setopt auto_param_slash
setopt auto_pushd # cd したら自動的にpushdする
setopt correct
setopt extended_glob
setopt ignore_eof
setopt interactive_comments # '#' 以降をコメントとして扱う
setopt list_packed          # 補完候補を詰めて表示
setopt list_types           # 補完候補一覧でファイルの種別をマーク表示
setopt magic_equal_subst    # = の後はパス名として補完する
setopt no_beep              # beep を無効にする
setopt no_flow_control      # フローコントロールを無効にする
setopt noautoremoveslash    # 最後のスラッシュを自動的に削除しない
setopt nonomatch
setopt notify            # バックグラウンドジョブの状態変化を即時報告
setopt print_eight_bit   # 日本語ファイル名を表示可能にする
setopt prompt_subst      # プロンプト定義内で変数置換やコマンド置換を扱う
setopt pushd_ignore_dups # 重複したディレクトリを追加しない
# ^R で履歴検索をするときに * でワイルドカードを使用出来るようにする
bindkey -e
select-history() {
	BUFFER=$(history -n -r 1 |
		awk 'length($0) > 2' |
		rg -v "^...$" |
		rg -v "^....$" |
		rg -v "^.....$" |
		rg -v "^......$" |
		rg -v "^exit$" |
		uniq -u |
		fzf-tmux --no-sort +m --query "$LBUFFER" --prompt="History > ")
	CURSOR=$#BUFFER
}
zle -N select-history
bindkey '^r' select-history

fzf-z-search() {
	local res=$(history -n 1 | tail -f | fzf)
	if [ -n "$res" ]; then
		BUFFER+="$res"
		zle accept-line
	else
		return 0
	fi
}
zle -N fzf-z-search
bindkey '^s' fzf-z-search
# エイリアス
alias cp='cp -r'
alias mv='mv -i'
alias mkdir='mkdir -p'
# グローバルエイリアス
alias -g L='| less'

alias f="open ."
alias rm='rm -rf'
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

alias mkcd=mkcd
alias dl="\cd $HOME/Downloads"
alias dc="\cd $HOME/Documents"
alias ..='\cd ../'
alias ...='\cd ../../'
alias ....='\cd ../../../'
alias .....='\cd ../../../../'
alias ......='\cd ../../../../../'
alias ,,='\cd ../'
alias ,,,='\cd ../../'
alias ,,,,='\cd ../../../'
alias ,,,,,='cd ../../../../'
alias ,,,,,,='\cd ../../../../../'

setopt no_global_rcs

zstyle ':zle:*' word-chars " /=;@:{},|"
zstyle ':zle:*' word-style unspecified

if (($+commands[fastfetch])); then
	fastfetch
elif (($+commands[neofetch])); then
	neofetch
fi

[ -z "$_lazy_fzf_zsh" ] && {
	[ -f $HOME/.fzf.zsh ] && source $HOME/.fzf.zsh
	_lazy_fzf_zsh=1
}

export SHELL=${SHELL:-${commands[zsh]}}
export USER=${USER:-$USERNAME}

_get_cpucores() {
	if [ -z "$CPUCORES" ]; then
		if (($+commands[nproc])); then
			export CPUCORES="$(nproc)"
		else
			export CPUCORES="$(getconf _NPROCESSORS_ONLN)"
		fi
	fi
}

if [ -z "$TERMCMD" ]; then
	if (($+commands[ghostty])); then
		export TERMCMD="ghostty -e $SHELL -c tmux -S /tmp/tmux.sock -q has-session  && exec tmux -S /tmp/tmux.sock -2 attach-session -d || exec tmux -S /tmp/tmux.sock -2 new-session -n$USER -s$USER@$HOST"
	elif (($+commands[alacritty])); then
		export TERMCMD="alacritty -e $SHELL -c tmux -S /tmp/tmux.sock -q has-session  && exec tmux -S /tmp/tmux.sock -2 attach-session -d || exec tmux -S /tmp/tmux.sock -2 new-session -n$USER -s$USER@$HOST"
	elif (($+commands[urxvtc])); then
		export TERMCMD="urxvtc -e $SHELL -c tmux -S /tmp/tmux.sock -q has-session  && exec tmux -S /tmp/tmux.sock -2 attach-session -d || exec tmux -S /tmp/tmux.sock -2 new-session -n$USER -s$USER@$HOST"
	fi
fi

export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.data}

if [ -z "$TMUX" ]; then
	export TERM=${TERM:-"xterm-256color"}
else
	export TERM=${TERM:-"tmux-256color"}
fi

export SCOUT_DISABLE=${SCOUT_DISABLE:-1}

if (($+functions["zsh-defer"])); then
	zsh-defer -c "autoload -Uz select-word-style; select-word-style default"
else
	autoload -Uz select-word-style
	select-word-style default
fi

if (($+commands[xsel])); then
	alias pbcopy="xsel --clipboard --input"
	alias pbpaste="xsel --clipboard --output"
else
	if (($+commands["wl-copy"])); then
		alias pbcopy="wl-copy"
	fi

	if (($+commands["wl-paste"])); then
		alias pbpaste="wl-paste"
	fi
fi

if (($+commands[rg])); then
	alias grep=rg
fi

if (($+commands[fd])); then
	alias find='fd'
fi

if (($+commands[dutree])); then
	alias du='dutree'
fi

if (($+commands[bat])); then
	alias cat='bat'
fi

if (($+commands[hyperfine])); then
	alias time='hyperfine'
fi

if (($+commands[procs])); then
	alias ps='procs'
fi

if (($+commands[btop])); then
	alias top='btop'
	alias htop='btop'
	alias btm='btop'
elif (($+commands[btm])); then
	alias top='btm'
	alias htop='btm'
	alias btop='btm'
elif (($+commands[htop])); then
	alias top='htop'
	alias btop='htop'
	alias btm='htop'
fi

if (($+commands[lsd])); then
	alias ks="lsd"
	alias l="lsd"
	alias ll='lsd -l'
	alias la='lsd -aAlLh'
	alias lla='lsd -aAlLhi'
	alias tree='lsd --tree --total-size --human-readable'
	alias ls='lsd'
	alias lg='lsd -aAlLh | rg'
elif (($+commands[erd])); then
	alias ks='erd -H -d logical -I --level 1 --sort rsize -y inverted --dir-order first'
	alias l='erd -H -d logical -I --level 1 --sort rsize -y inverted --dir-order first'
	alias ll='erd -H -d logical -I --level 1 --sort rsize -y inverted --dir-order first'
	alias la='erd -H -d logical -I -l --group --octal --time-format iso --sort rsize -y inverted --dir-order first --threads 32 --hidden --color force --level 1'
	alias lla='erd -H -d logical -I -l --group --octal --time-format iso --sort rsize -y inverted --dir-order first --threads 32 --hidden --no-git --color force --level 2'
	alias tree='erd -H -d logical -I -l --group --octal --time-format iso --sort rsize -y inverted --dir-order first --threads 32 --hidden --no-git --color force'
	alias ls='erd -H -d logical -I --level 1 --sort rsize -y inverted --dir-order first'
	alias lg='erd -H -d logical -I -l --group --octal --time-format iso --sort rsize -y inverted --dir-order first --threads 32 --hidden --color force --level 1 | rg'
elif (($+commands[eza])); then
	alias ks="eza -G"
	alias l="eza -G "
	alias ll='eza -l'
	alias la='eza -aghHliS'
	alias lla='eza -aghHliSm'
	alias tree='eza -T'
	alias ls='eza -G'
	alias lg='la | rg'
else
	alias ks="ls "
	alias l="ls "
	alias ll='ls -la'
	alias la='ls -la'
	alias lg='ls -a | rg'
fi

if (($+commands[fzf])); then
	if (($+commands["fzf-tmux"])); then
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

if (($+commands[duf])); then
	alias df='\duf'
fi

zscompile() {
	for f in $(find "$HOME" -name "*.zsh" -type f); do
		zcompile "$f" &
	done
	wait
}
alias zscompile=zscompile

zsup() {
	rm -rf $HOME/.zcompd*
	rm $HOME/.zshrc.zwc
	rm -rf $HOME/.bashrc
	rm -rf $HOME/.fzf.bash
	zscompile
}
alias zsup=zsup

zsinit() {
	rm -rf $HOME/.zcompd*
	rm -rf $HOME/.zshrc.zwc
}
alias zsinit=zsinit

zclean() {
	rm -rf $HOME/.zcompdump*
	rm -rf $HOME/.zsh*.zwc
	rm -rf $HOME/.zsh_direnv_cache
	rm -rf $HOME/.zsh_starship_cache
	rm -rf $HOME/.sheldon_cache.zsh
	rm -rf $DOTFILES_DIR/zsh/*.zwc
}
alias zclean=zclean

zstime() {
	for i in $(seq 1 $1); do
		time $(zsh -i -c exit)
	done
}
alias zstime=zstime

jvgrule='(^|\/)\.zsh_history$|(^|\/)\.z$|(^|\/)\.cache|\.emlx$|\.mbox$|\.tar*|(^|\/)\.glide|(^|\/)\.stack|(^|\/)\.anyenv|(^|\/)\.gradle|(^|\/)vendor|(^|\/)Application\ Support|(^|\/)\.cargo|(^|\/)\.config|(^|\/)com\.apple\.|(^|\/)\.idea|(^|\/)\.zplug|(^|\/)\.nimble|(^|\/)build|(^|\/)node_modules|(^|\/)\.git$|(^|\/)\.svn$|(^|\/)\.hg$|\.o$|\.obj$|\.a$|\.exe~?$|\.schema.json&|\.svg$|(^|\/)tags$'

greptext() {
	_get_cpucores
	if [ $# -eq 2 ]; then
		if (($+commands[rg])); then
			rg $2 $1
		elif (($+commands[jvgrep])); then
			jvgrep -I -R $2 $1 --exclude $jvgrule
		else
			find $1 -type d \( -name 'vendor' -o -name '.git' -o -name '.svn' -o -name 'build' -o -name '*.mbox' -o -name '.idea' -o -name '.cache' -o -name 'Application\ Support' \) -prune -o -type f \( -name '.zsh_history' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.o' -o -name '*.so' -o -name '*.dll' -o -name '*.a' -o -name '*.out' -o -name '*.pdf' -o -name '*.swp' -o -name '*.bak' -o -name '*.back' -o -name '*.bac' -o -name '*.class' -o -name '*.bin' -o -name '.z' -o -name '*.dat' -o -name '*.plist' -o -name '*.db' -o -name '*.webhistory' \) -prune -o -type f -print0 | xargs -0 -P $CPUCORES grep -rnwe $2 /dev/null
		fi
	else
		echo "Not enough arguments"
	fi
}
alias gt=greptext
chperm() {
	if [ $# -eq 3 ]; then
		sudo chmod $1 $3
		sudo chown $2 $3
	elif [ $# -eq 4 ]; then
		sudo chmod -R $2 $4
		sudo chown -R $3 $4
	fi
}
chword() {
	_get_cpucores
	if [ $# -eq 3 ]; then
		if (($+commands[rg])); then
			rg --multiline -l $2 $1 | xargs -t -P $CPUCORES \sed -i -E "s/$2/$3/g"
		elif (($+commands[ug])); then
			cd $1 && ug -l $2 | xargs -t -P $CPUCORES \sed -i -E "s/$2/$3/g" && cd -
		elif (($+commands[jvgrep])); then
			jvgrep -I -R $2 $1 --exclude $jvgrule -l -r | xargs -t -P $CPUCORES \sed -i -E "s/$2/$3/g"
		else
			find $1 -type d \( -name 'vendor' -o -name '.git' -o -name '.svn' -o -name 'build' -o -name '*.mbox' -o -name '.idea' -o -name '.cache' -o -name 'Application\ Support' \) -prune -o -type f \( -name '.zsh_history' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.o' -o -name '*.so' -o -name '*.dll' -o -name '*.a' -o -name '*.out' -o -name '*.pdf' -o -name '*.swp' -o -name '*.bak' -o -name '*.back' -o -name '*.bac' -o -name '*.class' -o -name '*.bin' -o -name '.z' -o -name '*.dat' -o -name '*.plist' -o -name '*.db' -o -name '*.webhistory' -o -name '*.schema.json' \) -prune -o -type f -print0 | xargs -0 -P $CPUCORES grep -rnwe $2 | xargs -t -P $CPUCORES \sed -i -E "s/$2/$3/g"
		fi
	elif [ $# -eq 4 ]; then
		if (($+commands[rg])); then
			rg --multiline -l $2 $1 | xargs -t -P $CPUCORES \sed -i -E "s$4$2$4$3$4g"
		elif (($+commands[ug])); then
			cd $1 && ug -l $2 $1 | xargs -t -P $CPUCORES \sed -i -E "s$4$2$4$3$4g" && cd -
		elif (($+commands[jvgrep])); then
			jvgrep -I -R $2 $1 --exclude $jvgrule -l -r | xargs -t -P $CPUCORES \sed -i -E "s$4$2$4$3$4g"
		else
			find $1 -type d \( -name 'vendor' -o -name '.git' -o -name '.svn' -o -name 'build' -o -name '*.mbox' -o -name '.idea' -o -name '.cache' -o -name 'Application\ Support' \) -prune -o -type f \( -name '.zsh_history' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.o' -o -name '*.so' -o -name '*.dll' -o -name '*.a' -o -name '*.out' -o -name '*.pdf' -o -name '*.swp' -o -name '*.bak' -o -name '*.back' -o -name '*.bac' -o -name '*.class' -o -name '*.bin' -o -name '.z' -o -name '*.dat' -o -name '*.plist' -o -name '*.db' -o -name '*.webhistory' -o -name '*.schema.json' \) -prune -o -type f -print0 | xargs -0 -P $CPUCORES grep -rnwe $2 | xargs -t -P $CPUCORES \sed -i -E "s$4$2$4$3$4g"
		fi
	else
		echo "Not enough arguments"
	fi
}
alias chword=chword

alias :q=exit
alias :wq=exit

alias 600='chmod -R 600'
alias 644='chmod -R 644'
alias 655='chmod -R 655'
alias 755='chmod -R 755'
alias 777='chmod -R 777'

if (($+commands["xdg-open"])); then
	alias open=xdg-open
fi

if (($+commands[direnv])); then
	if [[ ! -f ~/.zsh_direnv_cache ]]; then
		direnv hook zsh >~/.zsh_direnv_cache
	fi
	source ~/.zsh_direnv_cache
fi
