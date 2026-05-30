zclean() {
	local _zc="${ZCACHE_DIR:-$HOME/.zcache}"
	sudo rm -rf $HOME/.zcompdump*(N) \
		$HOME/.zsh*.zwc(N) \
		$HOME/.zsh_*_cache*(N) \
		$HOME/.*_cache.zsh*(N) \
		$HOME/.zfunc/*.zwc(N) \
		$DOTFILES_DIR/zsh/*.zwc(N) \
		$DOTFILES_DIR/zfunc/*.zwc(N) \
		${SHELDON_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/sheldon}/**/*.zwc(N) \
		${SHELDON_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/sheldon}/**/*.zwc(N) \
		${XDG_CACHE_HOME:-$HOME/.cache}/sheldon
	# Clean ZCACHE_DIR contents only (not the dir itself — it may be a mount point)
	if [[ -d "$_zc" ]]; then
		sudo rm -rf "$_zc"/*(.N) "$_zc"/*.lock(N)
	fi
}

zprecompile() {
	local d="${ZCACHE_DIR:-$HOME/.zcache}"
	local _df="${DOTFILES_DIR:-$HOME/dotfiles}"

	# Ensure the cache directory exists and is writable.
	mkdir -p "$d" 2>/dev/null
	if ! { command touch "$d/.writable_check" 2>/dev/null && command rm -f "$d/.writable_check" 2>/dev/null }; then
		printf 'Error: ZCACHE_DIR (%s) is not writable.\n' "$d" >&2
		printf 'If running in a container, recreate the bind-mount source on the host:\n' >&2
		printf '  mkdir -p %s\n' "$d" >&2
		return 1
	fi

	printf 'Pre-compiling zsh caches into %s\n' "$d"

	# Wipe existing caches and any stale lock dirs so regeneration is unconditional.
	command rm -f "$d"/*.{zsh,zwc}(N)
	command rm -rf "$d"/*.lock(N)

	# Reload _zcache_eval from current source (avoids loading a stale .zwc).
	zcompile "$_df/zfunc/_zcache_eval" 2>/dev/null
	unfunction _zcache_eval 2>/dev/null
	autoload -Uz _zcache_eval

	# delegate all generation to _zcache_eval (defer=-1: force+sync zcompile+no source)
	autoload -Uz _gen_env
	_zcache_eval env -1 "_gen_env"

	(($+commands[sheldon])) && \
		_zcache_eval sheldon -1 "sheldon source" \
			"${XDG_CONFIG_HOME:-$HOME/.config}/sheldon/plugins.toml"

	_zcache_eval combined -1 \
		'for _f in "$DOTFILES_DIR/zsh"/*.zsh(N); do
			[[ "${_f:t}" = 20-os-*.zsh || "${_f:t}" = 01-tmux.zsh ]] || cat "$_f"
		done' \
		"$_df/zsh"/*.zsh(N)

	local _os_src="$_df/zsh/20-os-${_ZSH_OS}.zsh"
	[[ -f "$_os_src" ]] && \
		_zcache_eval "os-${_ZSH_OS}" -1 "cat '$_os_src'" "$_os_src"

	local _gui_src="$_df/zsh/20-os-gui.zsh"
	[[ -f "$_gui_src" && "$_gui_src" != "$_os_src" ]] && \
		_zcache_eval os-gui -1 "cat '$_gui_src'" "$_gui_src"

	if (($+commands[atuin])); then
		autoload -Uz _atuin_init
		_zcache_eval atuin -1 "_atuin_init" "$commands[atuin]"
	fi

	(($+commands[zoxide])) && \
		_zcache_eval zoxide -1 "zoxide init zsh" "$commands[zoxide]"

	(($+commands[direnv])) && \
		_zcache_eval direnv -1 "direnv hook zsh" "$commands[direnv]"

	(($+commands[pay-respects])) && \
		_zcache_eval pay-respects -1 "pay-respects zsh" "$commands[pay-respects]"

	(($+commands[zsh-patina])) && \
		_zcache_eval zsh-patina -1 "zsh-patina activate" "$commands[zsh-patina]"

	# zcompile rc files and autoloaded functions (_zcache_eval covers its own output)
	local f
	for f in \
		"$HOME/.zshrc" \
		"$HOME/.zshenv" \
		"$_df/zsh/01-tmux.zsh" \
		"$_df/zfunc/_zcache_eval" \
		"$_df/zfunc/_atuin_init" \
		"$_df/zfunc/_gen_env" \
		"$_df/zfunc/pinentry-tmux"; do
		[[ -f "$f" ]] && zcompile "$f" 2>/dev/null
	done

	local -a _zpc_files=($d/*.zsh(N))
	printf 'Done: %d cache files in %s\n' ${#_zpc_files} "$d"
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

graphify() {
	GEMINI_API_KEY="$(pass show ai/gemini 2>/dev/null)" command graphify "$@"
}
