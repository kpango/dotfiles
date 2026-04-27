HISTFILE=$HOME/.zsh_history
HISTSIZE=1000000
SAVEHIST=1000000
setopt APPEND_HISTORY SHARE_HISTORY hist_ignore_all_dups hist_ignore_space hist_reduce_blanks hist_save_no_dups \
	auto_cd auto_list auto_menu auto_param_keys auto_param_slash auto_pushd correct extended_glob ignore_eof \
	interactive_comments list_packed list_types magic_equal_subst no_beep no_flow_control noautoremoveslash \
	nonomatch notify print_eight_bit prompt_subst pushd_ignore_dups

export KEYTIMEOUT=1
select-history() {
	BUFFER=$(history -n -r 1 |
		awk 'length($0) > 6 && $0 != "exit"' |
		uniq -u |
		fzf-tmux --no-sort +m --query "$LBUFFER" --prompt="History > ")
	CURSOR=$#BUFFER
}
zle -N select-history
if [[ ! -f "$ZCACHE_DIR/atuin.zsh" ]]; then
	bindkey '^r' select-history
fi

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
