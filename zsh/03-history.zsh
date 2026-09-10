HISTFILE=${HISTFILE:-$HOME/.zsh_history}
HISTSIZE=1000000
SAVEHIST=1000000
# The setopt line that used to live here now lives in zshrc's synchronous TTY-only
# block: this file is sourced deferred (via combined.zsh) under zsh-defer, whose
# _zsh-defer-resume runs every deferred task inside `emulate -L zsh`, silently
# discarding any setopt/unsetopt made here once that scope unwinds.

fzf-z-search() {
	local res
	res=$(fc -rl 1 2>/dev/null | fzf --no-sort +m -n '2..' --tiebreak=index --query="${BUFFER}" </dev/tty)
	if [[ -n "$res" ]]; then
		BUFFER="${res##* }"
		CURSOR=$#BUFFER
		zle redisplay
	fi
}
zle -N fzf-z-search
bindkey '^s' fzf-z-search
