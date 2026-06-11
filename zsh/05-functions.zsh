zclean() {
	setopt localoptions nullglob
	local _zc="${ZCACHE_DIR:-$HOME/.zcache}"
	sudo rm -rf $HOME/.zcompdump* \
		$HOME/.zsh*.zwc \
		$HOME/.zsh_*_cache* \
		$HOME/.*_cache.zsh* \
		$HOME/.zfunc/*.zwc \
		$DOTFILES_DIR/zsh/*.zwc \
		$DOTFILES_DIR/zfunc/*.zwc \
		${SHELDON_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/sheldon}/**/*.zwc \
		${SHELDON_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/sheldon}/**/*.zwc \
		${XDG_CACHE_HOME:-$HOME/.cache}/sheldon
	# Clean ZCACHE_DIR contents only (not the dir itself — it may be a mount point)
	if [[ -d "$_zc" ]]; then
		sudo rm -rf "$_zc"/* "$_zc"/*.lock
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
	setopt localoptions nullglob
	command rm -f "$d"/*.{zsh,zwc}
	command rm -rf "$d"/*.lock

	# Reload _zcache_eval from current source (avoids loading a stale .zwc).
	zcompile "$_df/zfunc/_zcache_eval" 2>/dev/null
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
			[[ "${_f:t}" = 20-os-*.zsh || "${_f:t}" = 01-tmux.zsh ]] || cat "$_f"
		done' \
		"$_df/zsh"/*.zsh

	local _os_src="$_df/zsh/20-os-${_ZSH_OS}.zsh"
	[[ -f "$_os_src" ]] &&
		_zcache_eval "os-${_ZSH_OS}" -1 "cat '$_os_src'" "$_os_src"

	local _gui_src="$_df/zsh/20-os-gui.zsh"
	[[ -f "$_gui_src" && "$_gui_src" != "$_os_src" ]] &&
		_zcache_eval os-gui -1 "cat '$_gui_src'" "$_gui_src"

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

		if (($+commands[rg])); then
			rg --multiline -l $2 $1 | xargs -t -r -P ${CPUCORES:-4} \sed -i -E "$sed_cmd"
		elif (($+commands[ug])); then
			cd $1 && ug -l $2 | xargs -t -r -P ${CPUCORES:-4} \sed -i -E "$sed_cmd" && cd -
		elif (($+commands[jvgrep])); then
			jvgrep -I -R $2 $1 --exclude $jvgrule -l -r | xargs -t -r -P ${CPUCORES:-4} \sed -i -E "$sed_cmd"
		else
			_find_text_files $1 | xargs -0 -r -P ${CPUCORES:-4} grep -rnwe $2 | xargs -t -r -P ${CPUCORES:-4} \sed -i -E "$sed_cmd"
		fi
	else
		echo "Not enough arguments"
	fi
}

graphify() {
	GEMINI_API_KEY="$(pass show ai/gemini 2>/dev/null)" command graphify "$@"
}

_sysclean_step() {
	local _label="$1"; shift
	printf '\033[34m[sysclean]\033[0m %s\n' "$_label"
	if "$@"; then
		printf '\033[34m[sysclean]\033[0m %s: \033[32mOK\033[0m\n' "$_label"
		typeset -g _SYSCLEAN_OK=$((_SYSCLEAN_OK + 1))
	else
		printf '\033[34m[sysclean]\033[0m %s: \033[33mFAILED\033[0m (continuing)\n' "$_label"
		typeset -g _SYSCLEAN_FAIL=$((_SYSCLEAN_FAIL + 1))
	fi
}

_sysclean_chrome() {
	local _dir="$1"
	[[ -d "$_dir" ]] || return 0
	rm_targets+=(
		"$_dir/Cache"
		"$_dir/Code Cache"
		"$_dir/GPUCache"
		"$_dir/Service Worker/CacheStorage"
		"$_dir/Service Worker/ScriptCache"
		"$_dir/blob_storage"
	)
	return 0
}

_sysclean_pyc() {
	local _dir="$1"
	[[ -d "$_dir" ]] || return 0
	local -a pyc_dirs
	pyc_dirs=("$_dir"/**/__pycache__(N/))
	(( ${#pyc_dirs[@]} > 0 )) && rm_targets+=("${pyc_dirs[@]}")
	return 0
}

_sysclean_log_tail() {
	local _f="$1" _n="${2:-1000}" _tmp
	[[ -f "$_f" ]] || return 0
	_tmp=$(mktemp)
	tail -n "$_n" "$_f" > "$_tmp" 2>/dev/null && sudo mv "$_tmp" "$_f" || { rm -f "$_tmp"; return 1; }
}

_sysclean_tmpdir() {
	local _dir="$1"
	[[ -d "$_dir" ]] || return 0
	local -a tmp_files
	tmp_files=($_dir/fzf-*(N) $_dir/.pin-*(N))
	(( ${#tmp_files[@]} > 0 )) && rm_targets+=("${tmp_files[@]}")
	return 0
}

_sysclean_drop_caches() {
	sync 2>/dev/null
	sudo sysctl -w vm.drop_caches=3
}

_sysclean_swap_reset() {
	sudo swapoff -a && sudo swapon -a
}

_sysclean_claude() {
	local _d="$HOME/.claude"
	[[ -d "$_d" ]] || return 0
	# clearly-named backups
	rm_targets+=("$_d/projects.bak" "$_d/skills.bak" "$_d/history.jsonl.bak")
	# session-data: stale .tmp files older than 15 days
	local -a stale
	stale=("$_d/session-data"/*.tmp(Nm+15))
	(( ${#stale[@]} > 0 )) && rm_targets+=("${stale[@]}")
	# session-env, file-history, shell-snapshots: UUID dirs older than 30 days
	local _sub
	for _sub in session-env file-history shell-snapshots; do
		[[ -d "$_d/$_sub" ]] || continue
		stale=("$_d/$_sub"/*(Nm+30))
		(( ${#stale[@]} > 0 )) && rm_targets+=("${stale[@]}")
	done
	# paste-cache contents
	if [[ -d "$_d/paste-cache" ]]; then
		local -a paste_cache
		paste_cache=("$_d/paste-cache"/*(N))
		(( ${#paste_cache[@]} > 0 )) && rm_targets+=("${paste_cache[@]}")
	fi
	# log files: keep last 1000 lines
	local _f _tmp
	for _f in "$_d/bash-commands.log" "$_d/cost-tracker.log" "$_d/daemon.log"; do
		[[ -f "$_f" ]] || continue
		_tmp=$(mktemp)
		tail -n 1000 "$_f" > "$_tmp" 2>/dev/null && mv "$_tmp" "$_f" || rm -f "$_tmp"
	done
	return 0
}

sysclean() {
	setopt localoptions nullglob
	typeset -g _SYSCLEAN_OK=0 _SYSCLEAN_FAIL=0
	printf '\033[1m[sysclean] Starting system cleanup...\033[0m\n\n'

	local -a rm_targets=()
	local -a truncate_targets=()

	printf '\033[1m[sysclean] Building deletion candidate lists...\033[0m\n'

	# --- Runtime state: stale locks, sockets & temp files ---
	local _xdg_data_eff="${XDG_DATA_HOME:-$HOME/.local/share}"
	[[ -f "$_xdg_data_eff/atuin/history.db-lock" ]] && rm_targets+=("$_xdg_data_eff/atuin/history.db-lock")
	
	local _herdr_session="${USER:-$USERNAME}-${HOST:-$HOSTNAME}"
	[[ -S "/tmp/herdr-${_herdr_session}.sock" ]] && rm_targets+=("/tmp/herdr-${_herdr_session}.sock")
	
	local _tmpdir="${TMPDIR:-${XDG_RUNTIME_DIR:-/tmp}}"
	[[ -d "$_tmpdir" ]] && _sysclean_tmpdir "$_tmpdir"

	# --- Coredumps ---
	if [[ -d /var/lib/systemd/coredump ]]; then
		local -a coredumps=(/var/lib/systemd/coredump/*(N))
		(( ${#coredumps[@]} > 0 )) && rm_targets+=("${coredumps[@]}")
	fi

	# --- /tmp: regular files+symlinks older than 12h (directories and sockets preserved) ---
	local -a old_tmp
	old_tmp=(${(f)"$(sudo find /tmp -mindepth 1 -mmin +720 \( -type f -o -type l \) 2>/dev/null)"})
	(( ${#old_tmp[@]} > 0 )) && rm_targets+=("${old_tmp[@]}")

	# --- /var/tmp: same rule ---
	local -a old_vartmp
	old_vartmp=(${(f)"$(sudo find /var/tmp -mindepth 1 -mmin +720 \( -type f -o -type l \) 2>/dev/null)"})
	(( ${#old_vartmp[@]} > 0 )) && rm_targets+=("${old_vartmp[@]}")

	# --- /var/cache/paru ---
	if [[ -d /var/cache/paru ]]; then
		local -a paru_cache=(/var/cache/paru/*(N))
		(( ${#paru_cache[@]} > 0 )) && rm_targets+=("${paru_cache[@]}")
	fi

	# --- /var/cache/aur-src ---
	if [[ -d /var/cache/aur-src ]]; then
		local -a aur_src=(/var/cache/aur-src/*(N))
		(( ${#aur_src[@]} > 0 )) && rm_targets+=("${aur_src[@]}")
	fi

	# --- fwupd metadata cache ---
	if [[ -d /var/cache/fwupd ]]; then
		local -a fwupd_cache=(/var/cache/fwupd/*(N))
		(( ${#fwupd_cache[@]} > 0 )) && rm_targets+=("${fwupd_cache[@]}")
	fi

	# --- Go ---
	if (($+commands[go])); then
		local _gomodcache
		_gomodcache=$(go env GOMODCACHE 2>/dev/null)
		if [[ -n "$_gomodcache" && -d "$_gomodcache/cache" ]]; then
			rm_targets+=("$_gomodcache/cache")
		fi
	fi

	# --- Cargo ---
	local _cargo_home="${CARGO_HOME:-$HOME/.cargo}"
	[[ -d "$_cargo_home/registry/cache" ]] && rm_targets+=("$_cargo_home/registry/cache")
	[[ -d "$_cargo_home/registry/src" ]] && rm_targets+=("$_cargo_home/registry/src")
	[[ -d "$_cargo_home/git/checkouts" ]] && rm_targets+=("$_cargo_home/git/checkouts")

	# --- Bun ---
	if (($+commands[bun])); then
		local _bun_cache="${BUN_INSTALL:-$HOME/.bun}/install/cache"
		[[ -d "$_bun_cache" ]] && rm_targets+=("$_bun_cache")
	fi

	# --- Browser caches (only if browser is not running) ---
	if ! pgrep -f "google-chrome" > /dev/null 2>&1 && ! pgrep -x chromium > /dev/null 2>&1; then
		local _chrome_dir _profile
		for _chrome_dir in 			"$HOME/.config/google-chrome-beta" 			"$HOME/.config/google-chrome" 			"$HOME/.config/chromium"; do
			[[ -d "$_chrome_dir" ]] || continue
			for _profile in "$_chrome_dir"/Default "$_chrome_dir"/Profile*; do
				[[ -d "$_profile" ]] || continue
				_sysclean_chrome "$_profile"
			done
		done
	fi

	# --- Claude Code: session/history caches & backup files ---
	if [[ -d "$HOME/.claude" ]]; then
		_sysclean_claude
	fi

	# --- Python __pycache__ in project source dirs ---
	local _src_dir="${GOPATH:-$HOME/go}/src"
	if [[ -d "$_src_dir" ]]; then
		_sysclean_pyc "$_src_dir"
	fi

	# --- Thumbnails ---
	local _thumb="${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails"
	[[ -d "$_thumb" ]] && rm_targets+=("$_thumb")
	[[ -d "$HOME/.thumbnails" ]] && rm_targets+=("$HOME/.thumbnails")

	# --- GTK / XDG recently-used ---
	if [[ -f "$HOME/.local/share/recently-used.xbel" ]]; then
		rm_targets+=("$HOME/.local/share/recently-used.xbel")
	fi
	local _xdg_data="${XDG_DATA_HOME:-$HOME/.local/share}"
	if [[ "$_xdg_data" != "$HOME/.local/share" && -f "$_xdg_data/recently-used.xbel" ]]; then
		rm_targets+=("$_xdg_data/recently-used.xbel")
	fi

	# --- atuin backup files ---
	local _f
	for _f in 		"${_xdg_data}/atuin.bak" 		"$HOME/.data/atuin.bak" 		"$HOME/.local/share/atuin.bak"; do
		[[ -f "$_f" ]] && rm_targets+=("$_f")
	done

	# Remove empty strings from rm_targets (just in case)
	rm_targets=("${(@)rm_targets:#}")

	# --- Execute Deletions ---
	if (( ${#rm_targets[@]} > 0 )); then
		_sysclean_step "parallel file deletion (${#rm_targets[@]} items)" 			sh -c 'printf "%s\0" "$@" | sudo xargs -0 -P "$1" rm -rf' _ "${CPUCORES:-4}" "${rm_targets[@]}"
	fi

	# --- Zsh caches ---
	_sysclean_step "zsh caches (.zwc / .zcache / sheldon)" 		zclean

	# --- Pacman / AUR ---
	if (($+commands[pacman])); then
		_sysclean_step "pacman: pkg cache + orphans" 			kacclean
	fi

	# --- Docker ---
	if (($+commands[docker])); then
		_sysclean_step "docker: truncate container logs" 			sh -c 'sudo find /var/lib/docker/containers -name "*-json.log" -print0 2>/dev/null | sudo xargs -0 -r truncate -s 0'
		_sysclean_step "docker: system prune (stopped containers / dangling images / unused volumes)" 			docker system prune -f --volumes
		_sysclean_step "docker: build cache" 			docker builder prune -f
		_sysclean_step "docker: all unused images" 			docker image prune -a -f
	fi

	# --- systemd journal ---
	if (($+commands[journalctl])); then
		_sysclean_step "systemd journal: vacuum entries older than 7 days" 			sudo journalctl --vacuum-time=7d
		_sysclean_step "systemd journal: vacuum size >256M" 			sudo journalctl --vacuum-size=256M
	fi

	# --- /var/log: truncate large log files ---
	_sysclean_step "/var/log/pacman.log: keep last 1000 lines" 		_sysclean_log_tail /var/log/pacman.log 1000

	[[ -f /var/log/haskell-register.log ]] && truncate_targets+=("/var/log/haskell-register.log")
	[[ -f /var/log/wtmp ]] && truncate_targets+=("/var/log/wtmp")
	
	if (( ${#truncate_targets[@]} > 0 )); then
		_sysclean_step "truncate logs (${#truncate_targets[@]} items)" 			sudo truncate -s 0 "${truncate_targets[@]}"
	fi

	# --- Go ---
	if (($+commands[go])); then
		_sysclean_step "go: build cache" 			go clean -cache
		_sysclean_step "go: test result cache" 			go clean -testcache
	fi

	# --- npm ---
	if (($+commands[npm])); then
		_sysclean_step "npm: package cache" 			npm cache clean --force
	fi

	# --- pip ---
	if (($+commands[pip3])); then
		_sysclean_step "pip: cache purge" 			pip3 cache purge
	fi

	# --- fontconfig ---
	if (($+commands[fc-cache])); then
		_sysclean_step "fontconfig: rebuild cache" 			sudo fc-cache -f
	fi

	# --- Network: flush DNS cache ---
	if (($+commands[resolvectl])); then
		_sysclean_step "DNS: flush systemd-resolved cache" 			resolvectl flush-caches
	fi

	# --- Memory: flush page cache + reset swap ---
	_sysclean_step "memory: flush page cache (drop_caches=3)" 		_sysclean_drop_caches
	_sysclean_step "memory: reset swap" 		_sysclean_swap_reset

	printf '\n\033[1m[sysclean] Done: %d OK, %d failed/skipped\033[0m\n' 		$_SYSCLEAN_OK $_SYSCLEAN_FAIL
	unset _SYSCLEAN_OK _SYSCLEAN_FAIL
}
