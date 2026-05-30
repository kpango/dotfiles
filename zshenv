skip_global_compinit=1
# ZSH_DEFER_MAX_MS=1
ZCACHE_DIR="${ZCACHE_DIR:-$HOME/.zcache}"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
unsetopt GLOBAL_RCS

# Fast path for inline script execution (-c flag): skip .zshrc and ATUIN_SESSION setup.
# .zshrc only provides interactive features (plugins, completions, prompt, ZLE bindings).
# PATH is inherited from the parent shell; ATUIN_SESSION not needed for one-shot scripts.
if [[ -n "$ZSH_EXECUTION_STRING" ]]; then
	unsetopt RCS
else
	# Generate ATUIN_SESSION early — required for daemon IPC even before atuin.zsh loads.
	# atuin.zsh will keep this value (only regenerates when unset or SHLVL changes).
	if [[ -z "${ATUIN_SESSION}" ]]; then
		if [[ -r /proc/sys/kernel/random/uuid ]]; then
			read -r _atuin_uuid < /proc/sys/kernel/random/uuid
		else
			_atuin_uuid="${$}-${EPOCHREALTIME:-$(date +%s%N)}"
		fi
		export ATUIN_SESSION="${_atuin_uuid//-/}"
		unset _atuin_uuid
	fi
fi
