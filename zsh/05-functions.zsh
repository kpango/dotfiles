zclean() {
	rm -rf $HOME/.zcompdump*(N) \
		$HOME/.zsh*.zwc(N) \
		$HOME/.zsh_*_cache*(N) \
		$HOME/.*_cache.zsh*(N) \
		$HOME/.zfunc/*.zwc(N) \
		$ZCACHE_DIR \
		$DOTFILES_DIR/zsh/*.zwc(N) \
		$DOTFILES_DIR/zfunc/*.zwc(N) \
		${SHELDON_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/sheldon}/**/*.zwc(N) \
		${SHELDON_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/sheldon}/**/*.zwc(N) \
		${XDG_CACHE_HOME:-$HOME/.cache}/sheldon
}

jvgrule='(^|\/)\.zsh_history$|(^|\/)\.z$|(^|\/)\.cache|\.emlx$|\.mbox$|\.tar*|(^|\/)\.glide|(^|\/)\.stack|(^|\/)\.anyenv|(^|\/)\.gradle|(^|\/)vendor|(^|\/)Application\ Support|(^|\/)\.cargo|(^|\/)\.config|(^|\/)com\.apple\.|(^|\/)\.idea|(^|\/)\.zplug|(^|\/)\.nimble|(^|\/)build|(^|\/)node_modules|(^|\/)\.git$|(^|\/)\.svn$|(^|\/)\.hg$|\.o$|\.obj$|\.a$|\.exe~?$|\.schema.json&|\.svg$|(^|\/)tags$'

_find_text_files() {
	find $1 -type d \( -name 'vendor' -o -name '.git' -o -name '.svn' -o -name 'build' -o -name '*.mbox' -o -name '.idea' -o -name '.cache' -o -name 'Application\ Support' \) -prune -o -type f \( -name '.zsh_history' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.o' -o -name '*.so' -o -name '*.dll' -o -name '*.a' -o -name '*.out' -o -name '*.pdf' -o -name '*.swp' -o -name '*.bak' -o -name '*.back' -o -name '*.bac' -o -name '*.class' -o -name '*.bin' -o -name '.z' -o -name '*.dat' -o -name '*.plist' -o -name '*.db' -o -name '*.webhistory' -o -name '*.schema.json' \) -prune -o -type f -print0
}

greptext() {
	if [ $# -eq 2 ]; then
		if (($+commands[rg])); then
			rg $2 $1
		elif (($+commands[jvgrep])); then
			jvgrep -I -R $2 $1 --exclude $jvgrule
		else
			_find_text_files $1 | xargs -0 -P ${CPUCORES:-4} grep -rnwe $2 /dev/null
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
	if [ $# -ge 3 ] && [ $# -le 4 ]; then
		local sep="/"
		if [ $# -eq 4 ]; then
			sep=$4
		fi

		local sed_cmd="s${sep}$2${sep}$3${sep}g"

		if (($+commands[rg])); then
			rg --multiline -l $2 $1 | xargs -t -P ${CPUCORES:-4} \sed -i -E "$sed_cmd"
		elif (($+commands[ug])); then
			cd $1 && ug -l $2 | xargs -t -P ${CPUCORES:-4} \sed -i -E "$sed_cmd" && cd -
		elif (($+commands[jvgrep])); then
			jvgrep -I -R $2 $1 --exclude $jvgrule -l -r | xargs -t -P ${CPUCORES:-4} \sed -i -E "$sed_cmd"
		else
			_find_text_files $1 | xargs -0 -P ${CPUCORES:-4} grep -rnwe $2 | xargs -t -P ${CPUCORES:-4} \sed -i -E "$sed_cmd"
		fi
	else
		echo "Not enough arguments"
	fi
}

