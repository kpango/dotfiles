skip_global_compinit=1
# ZSH_DEFER_MAX_MS=1
ZCACHE_DIR="${ZCACHE_DIR:-$HOME/.zcache}"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
unsetopt GLOBAL_RCS

# Fast path for inline script execution (-c flag): skip .zshrc and ATUIN_SESSION setup.
# .zshrc only provides interactive features (plugins, completions, prompt, ZLE bindings).
# Load functions/aliases from zcache so they are available in non-interactive shells
# (e.g., Claude Code Bash tool, shell scripts invoked with zsh -c).
if [[ -n "$ZSH_EXECUTION_STRING" ]]; then
	unsetopt RCS
	[[ -f "$ZCACHE_DIR/env.zsh" ]] && source "$ZCACHE_DIR/env.zsh"
	[[ -f "$ZCACHE_DIR/combined.zsh" ]] && source "$ZCACHE_DIR/combined.zsh" 2>/dev/null
	[[ -n "$_ZSH_OS" && -f "$ZCACHE_DIR/os-${_ZSH_OS}.zsh" ]] && source "$ZCACHE_DIR/os-${_ZSH_OS}.zsh" 2>/dev/null
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
