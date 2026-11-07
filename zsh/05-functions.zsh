zclean() {
	setopt localoptions nullglob
	local _zc="${ZCACHE_DIR:-$HOME/.zcache}"
	sudo rm -rf $HOME/.zcompdump* \
		$HOME/.zsh*.zwc \
		$HOME/.zsh_*_cache* \
		$HOME/.*_cache.zsh* \
		$HOME/.zfunc/*.zwc \
		$DOTFILES_DIR/zsh/*.zwc* \
		$DOTFILES_DIR/zfunc.zwc* \
		$DOTFILES_DIR/zfunc/*.zwc* \
		${SHELDON_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/sheldon}/**/*.zwc \
		${SHELDON_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/sheldon}/**/*.zwc \
		${XDG_CACHE_HOME:-$HOME/.cache}/sheldon
	# Clean ZCACHE_DIR contents only (not the dir itself — it may be a mount point)
	if [[ -d "$_zc" ]]; then
		sudo rm -rf "$_zc"/* "$_zc"/*.lock
	fi
	# Unset stale $TMUX if the server is no longer running
	if (($+commands[tmux])) && [[ -n "$TMUX" ]] && ! tmux info &>/dev/null; then
		unset TMUX TMUX_PANE
	fi
}

zprecompile() {
	local d="${ZCACHE_DIR:-$HOME/.zcache}"
	local _df="${DOTFILES_DIR:-$HOME/dotfiles}"

	# Ensure the cache directory exists and is writable.
	mkdir -p "$d" 2>/dev/null
	if ! { command touch "$d/.writable_check" 2>/dev/null && command rm -f "$d/.writable_check" 2>/dev/null; }; then
		printf 'Error: ZCACHE_DIR (%s) is not writable.\n' "$d" >&2
		printf 'If running in a container, recreate the bind-mount source on the host:\n' >&2
		printf '  mkdir -p %s\n' "$d" >&2
		return 1
	fi

	printf 'Pre-compiling zsh caches into %s\n' "$d"

	# Wipe existing caches and any stale lock dirs so regeneration is unconditional.
	# Also sweeps orphaned *.tmp.<pid> files: _zcache_eval writes each generation
	# to a PID-suffixed temp name (avoids a shared-name write race, see its own
	# comments) and cleans up after itself on the normal paths, but a shell
	# killed mid-write leaves that file behind with no other reaper -- *.zsh/
	# *.zwc above don't match ".zsh.tmp.<pid>" since it doesn't end in those
	# suffixes. The autosuggest-bind and fzf-* caches are not regenerated below;
	# the next interactive shell creates them (an orphaned autosuggest-bind
	# *.<pid>.d dir from a killed writer is only removed by zclean).
	setopt localoptions nullglob
	command rm -f "$d"/*.{zsh,zwc}
	command rm -f "$d"/*.tmp.*
	command rm -rf "$d"/*.lock

	# Reload _zcache_eval from current source (avoids loading a stale .zwc).
	command rm -f "$_df/zfunc.zwc" "$_df/zfunc.zwc.old" 2>/dev/null
	zcompile -U -z -R "$_df/zfunc/_zcache_eval" 2>/dev/null
	unfunction _zcache_eval 2>/dev/null
	autoload -Uz _zcache_eval

	# delegate all generation to _zcache_eval (defer=-1: force+sync zcompile+no source)
	autoload -Uz _gen_env
	_zcache_eval env -1 "_gen_env"

	(($+commands[sheldon])) &&
		_zcache_eval sheldon -1 "sheldon source" \
			"${XDG_CONFIG_HOME:-$HOME/.config}/sheldon/plugins.toml"

	_zcache_eval combined -1 \
		'for _f in "$DOTFILES_DIR/zsh"/*.zsh; do
			[[ -e "$_f" ]] || continue
			[[ "${_f:t}" = 20-os-*.zsh || "${_f:t}" = 01-tmux.zsh ]] || print -r -- "$(<"$_f")"
		done' \
		"$_df/zsh"/*.zsh

	local _os_src="$_df/zsh/20-os-${_ZSH_OS}.zsh"
	[[ -f "$_os_src" ]] &&
		_zcache_eval "os-${_ZSH_OS}" -1 'print -r -- "$(<"$_os_src")"' "$_os_src"

	local _gui_src="$_df/zsh/20-os-gui.zsh"
	[[ -f "$_gui_src" && "$_gui_src" != "$_os_src" ]] &&
		_zcache_eval os-gui -1 'print -r -- "$(<"$_gui_src")"' "$_gui_src"

	if (($+commands[atuin])); then
		autoload -Uz _atuin_init
		_zcache_eval atuin -1 "_atuin_init" "$commands[atuin]"
	fi

	(($+commands[zoxide])) &&
		_zcache_eval zoxide -1 "zoxide init zsh" "$commands[zoxide]"

	(($+commands[direnv])) &&
		_zcache_eval direnv -1 "direnv hook zsh" "$commands[direnv]"

	(($+commands[pay-respects])) &&
		_zcache_eval pay-respects -1 "pay-respects zsh" "$commands[pay-respects]"

	(($+commands[zsh-patina])) &&
		_zcache_eval zsh-patina -1 "zsh-patina activate | sed -e 's/^autoload -U add-zle-hook-widget add-zsh-hook$/autoload -Uz add-zle-hook-widget/' -e 's/^add-zsh-hook chpwd _zsh_patina_chpwd$/chpwd_functions+=(_zsh_patina_chpwd)/'" "$commands[zsh-patina]"

	# zcompile rc files and autoloaded functions (_zcache_eval covers its own output).
	local f
	for f in "$HOME/.zshrc" "$HOME/.zshenv" "$_df/zsh/01-tmux.zsh"; do
		[[ -f "$f" ]] && zcompile -U -R "$f" 2>/dev/null
	done
	local -a _zf_srcs=()
	for f in "$_df/zfunc"/*; do
		[[ -f "$f" && "${f:e}" != "zwc" && "$f" != *.zwc.old ]] || continue
		_zf_srcs+=("$f")
		zcompile -U -z -R "$f" 2>/dev/null
	done
	((${#_zf_srcs})) && zcompile -U -z -M "$_df/zfunc.zwc" "${_zf_srcs[@]}" 2>/dev/null
	command rm -f "$_df/zfunc.zwc.old" "$_df/zfunc"/*.zwc.old 2>/dev/null
	local _zcd="${ZDOTDIR:-$HOME}/.zcompdump"
	[[ -f "$_zcd" ]] && zcompile -U -M "$_zcd" 2>/dev/null
	for f in "$d"/*.zsh; do
		[[ -f "$f" ]] && zcompile -U -R "$f" 2>/dev/null
	done

	local -a _zpc_files=($d/*.zsh)
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

		# GNU sed's bare -i takes no backup suffix; BSD/macOS sed's -i requires
		# the (possibly empty) suffix as its own argument. GNU xargs' -r (skip
		# invocation on empty input) has no BSD/macOS flag, but BSD/macOS xargs
		# already behaves like -r by default, so it is only added on non-darwin.
		local -a sedi=(-i)
		local -a xargs_re=(-r)
		if [[ "$OSTYPE" == darwin* ]]; then
			sedi=(-i '')
			xargs_re=()
		fi

		if (($+commands[rg])); then
			rg --multiline -l $2 $1 | xargs -t "${xargs_re[@]}" -P ${CPUCORES:-4} \sed "${sedi[@]}" -E "$sed_cmd"
		elif (($+commands[ug])); then
			cd $1 && ug -l $2 | xargs -t "${xargs_re[@]}" -P ${CPUCORES:-4} \sed "${sedi[@]}" -E "$sed_cmd" && cd -
		elif (($+commands[jvgrep])); then
			jvgrep -I -R $2 $1 --exclude $jvgrule -l -r | xargs -t "${xargs_re[@]}" -P ${CPUCORES:-4} \sed "${sedi[@]}" -E "$sed_cmd"
		else
			_find_text_files $1 | xargs -0 "${xargs_re[@]}" -P ${CPUCORES:-4} grep -rnwe $2 | xargs -t "${xargs_re[@]}" -P ${CPUCORES:-4} \sed "${sedi[@]}" -E "$sed_cmd"
		fi
	else
		echo "Not enough arguments"
	fi
}

# duk [DIR] [K] — ディスク使用量 Top-K ディレクトリを表示 (デフォルト: DIR=/, K=10)
# -x を使わないことで bind mount 先も正確に集計する
duk() {
	local dir="${1:-/}"
	local k="${2:-10}"
	sudo du -h -d 1 "$dir" 2>/dev/null |
		sort -rh |
		awk -v d="${dir%/}" -v k="$k" '
			$2 == d "/proc" || $2 == d "/sys" || $2 == d "/dev" || $2 == d "/run" { next }
			$2 != d && $2 != d "/" { print; if (++cnt >= k) exit }
		'
}

autoload -Uz sysclean
