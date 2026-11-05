#!/usr/bin/env bash
# install.sh -- deploy Antigravity (AGY) configuration into ~/.agy, ~/.gemini, and XDG dirs
# (called by `make agy/install` and `devrun` initialization).
#
# Usage: ROOTDIR=<dotfiles checkout> HOME=<home> install.sh [--force-repo-defaults]
#
# Why settings.json is merged as a 0600 regular file (never a symlink):
#   1. Antigravity CLI (`cli_setting_manager.go`) writes ~/.gemini/antigravity-cli/settings.json
#      via temp-file + atomic rename (0600) whenever `/model`, `/config`, Shift+Tab mode, or
#      workspace trust (`trustedWorkspaces`) changes, destroying any symlink.
#   2. Conversely, deploying a plain symlink over settings.json wipes runtime state
#      (`trustedWorkspaces`, `model`, `permissions`, `agentMode`, `toolPermission`, etc.).
#   3. Following `agent/harnesses/primeagent/install.sh`, ~/.gemini/antigravity-cli/settings.json
#      is maintained as a 0600 regular file = live * repo-owned keys * preserved runtime keys,
#      rewritten atomically only when missing, a symlink, or JSON-inequal under jq `==`.
set -euo pipefail

die() { printf 'agy/install: error: %s\n' "$1" >&2; exit 1; }
note() { printf 'agy/install: %s\n' "$1"; }
warn() { printf 'agy/install: warning: %s\n' "$1" >&2; }

FORCE_REPO_DEFAULTS=0
for arg in "$@"; do
	case "$arg" in
	--force-repo-defaults) FORCE_REPO_DEFAULTS=1 ;;
	*) die "unknown argument '$arg' (usage: install.sh [--force-repo-defaults])" ;;
	esac
done

: "${ROOTDIR:?ROOTDIR unset}"
[[ "${HOME-}" == /* && -n "${HOME//\//}" && -d "$HOME" ]] ||
	die "HOME='${HOME-}' must be an existing absolute directory other than /"

ROOTDIR="${ROOTDIR%/}"
[[ -d "$ROOTDIR" ]] || die "ROOTDIR='$ROOTDIR' does not exist"
ROOT_REAL="$(cd -P "$ROOTDIR" && pwd)"
AGY_SRC="$ROOTDIR/agent/harnesses/agy"
[[ -f "$AGY_SRC/settings.json" ]] || die "missing $AGY_SRC/settings.json"

command -v jq >/dev/null 2>&1 || die "jq not found in PATH"

# Resolve canonical path of an existing file or directory portably (works on Linux and macOS).
canon_path() {
	local p="$1"
	if [[ -d "$p" ]]; then
		(cd -P "$p" 2>/dev/null && pwd)
	elif [[ -e "$p" ]]; then
		local d="${p%/*}" b="${p##*/}"
		[[ "$d" == "$p" ]] && d="."
		(cd -P "$d" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$b")
	else
		return 1
	fi
}

# A symlink whose target belongs to this dotfiles checkout (including host<->container $HOME aliases).
owned() {
	local t
	[[ -L "$1" ]] || return 1
	t="$(readlink "$1")"
	[[ "$t" == "$ROOTDIR"/* || "$t" == "$ROOT_REAL"/* || "$t" == */dotfiles/agent/* ]]
}

# link <src> <dest>: create or retarget our symlink; preserve an already-resolving symlink to the
# same real target so macOS host (/Users/<user>/...) and devrun container (/home/kpango/...) do not churn.
link() {
	local src="$1" dest="$2"
	if [[ -L "$dest" ]]; then
		local cur_target
		cur_target="$(readlink "$dest")"
		[[ "$cur_target" == "$src" ]] && return 0
		if [[ -e "$dest" ]] && owned "$dest"; then
			local c_src c_dest
			c_src="$(canon_path "$src" || true)"
			c_dest="$(canon_path "$dest" || true)"
			if [[ -n "$c_src" && "$c_src" == "$c_dest" ]]; then
				return 0
			fi
		fi
		owned "$dest" || { warn "$dest is a symlink not into $ROOTDIR; left alone"; return 0; }
	elif [[ -e "$dest" ]]; then
		warn "$dest exists and is not a symlink; left alone"
		return 0
	fi
	ln -sfn "$src" "$dest"
	note "linked $dest -> $src"
}

own_dir() {
	if owned "$1"; then
		rm -f "$1"
		note "removed old directory symlink $1"
	fi
	[[ -L "$1" ]] && die "$1 is a symlink not into $ROOTDIR; move it away and re-run"
	mkdir -p "$1"
}

dir_ok() {
	local p="$1"
	while [[ -n "$p" && ! -e "$p" && ! -L "$p" && "$p" == */* ]]; do p="${p%/*}"; done
	[[ -n "$p" && -d "$p" ]]
}

prune() {
	local dir="$1" l n w keep
	shift
	while IFS= read -r -d '' l; do
		n="${l##*/}"
		keep=0
		for w in "$@"; do [[ "$n" == "$w" ]] && keep=1 && break; done
		[[ $keep -eq 0 ]] && owned "$l" && rm -f "$l" && note "removed stale $l"
	done < <(find "$dir" -mindepth 1 -maxdepth 1 -type l -print0)
	return 0
}

# ---------------------------------------------------------------- preflight (no changes yet)
PERSIST_DIRS=(
	"$HOME/.agy"
	"$HOME/.agy/policies"
	"$HOME/.gemini"
	"$HOME/.gemini/antigravity-cli"
	"$HOME/.gemini/antigravity-cli/conversations"
	"$HOME/.gemini/antigravity-cli/brain"
	"$HOME/.gemini/antigravity-cli/annotations"
	"$HOME/.gemini/antigravity-cli/cache"
	"$HOME/.gemini/antigravity"
	"$HOME/.gemini/antigravity/conversations"
	"$HOME/.gemini/config"
	"$HOME/.gemini/config/projects"
	"$HOME/.gemini/policies"
	"$HOME/.gemini/memory"
	"$HOME/.gemini/extensions"
	"$HOME/.antigravity"
	"$HOME/.config/Antigravity"
	"$HOME/.config/antigravity"
	"$HOME/.cache/antigravity"
)

for d in "${PERSIST_DIRS[@]}"; do
	dir_ok "$d" || die "$d is not a directory (or creatable as one); move it away and re-run"
done
for d in "$HOME/.agy/hooks" "$HOME/.gemini/hooks"; do
	if [[ -L "$d" ]]; then
		owned "$d" || die "$d is a symlink not into $ROOTDIR; move it away and re-run"
	elif ! dir_ok "$d"; then
		die "$d is not a directory; move it away and re-run"
	fi
done

hook_files=()
hook_names=()
for hd in "$AGY_SRC/hooks" "$ROOTDIR/agent/hooks/agy"; do
	[[ -d "$hd" ]] || continue
	for hf in "$hd"/*; do
		[[ -f "$hf" ]] || continue
		hook_files+=("$hf")
		hook_names+=("${hf##*/}")
	done
done

live="$HOME/.gemini/antigravity-cli/settings.json"
live_src=""
if [[ -L "$live" ]]; then
	owned "$live" || die "$live is a symlink not into $ROOTDIR; move it away and re-run (must be a regular file)"
	if [[ -e "$live" ]]; then
		live_src="$live"
	else
		warn "$live is a dangling symlink; starting from {}"
	fi
elif [[ -e "$live" ]]; then
	live_src="$live"
fi
[[ -z "$live_src" || -f "$live_src" ]] || die "$live is not a regular file; move it away and re-run"

new_json="$(
	{ if [[ -z "$live_src" ]]; then echo '{}'; else cat "$live_src"; fi; } |
		jq -e -s \
			--slurpfile repo "$AGY_SRC/settings.json" \
			--arg rootdir "$ROOTDIR" \
			--arg rootreal "$ROOT_REAL" \
			--argjson force "$FORCE_REPO_DEFAULTS" '
		def uniq: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
		def keep_str($obj; $k):
			if $force == 0 and (($obj[$k] // null) | type) == "string" and ($obj[$k] | length) > 0
			then { ($k): $obj[$k] }
			else {}
			end;
		if length != 1 or (.[0] | type) != "object" then error("live settings.json is not a JSON object") else .[0] end
		| . as $l
		| ($repo[0]) as $r
		| ($l * $r)
		* keep_str($l; "model")
		* keep_str($l; "agentMode")
		* keep_str($l; "toolPermission")
		* keep_str($l; "artifactReviewPolicy")
		* {
			trustedWorkspaces: (
				(($r.trustedWorkspaces // [])
				 + (if ($l.trustedWorkspaces | type) == "array" then $l.trustedWorkspaces else [] end)
				 + [$rootdir, $rootreal])
				| map(select(type == "string" and length > 0))
				| uniq
			)
		}
		| if type == "object" then . else error("merged settings.json is not a JSON object") end'
)" || die "could not merge $live (left unchanged)"

write_settings=1
settings_diff=""
if [[ -n "$live_src" ]]; then
	settings_diff="$(jq -r -n --slurpfile o "$live_src" --argjson n "$new_json" '
		def d($o; $n; $p):
			if ($o | type) == "object" and ($n | type) == "object" then $o | to_entries[] | d(.value; $n[.key]; $p + [.key])
			elif $o != null and $o != $n then "agy/install: settings.json \($p | join(".")): \($o | tojson) -> \($n | tojson)"
			else empty end;
		d($o[0]; $n; [])')" || die "could not diff $live against the merged settings (left unchanged)"
	same="$(jq -n --slurpfile o "$live_src" --argjson n "$new_json" '$o[0] == $n')" ||
		die "could not compare $live with the merged settings (left unchanged)"
	if [[ ! -L "$live" && "$same" == true ]]; then
		write_settings=0
	fi
fi

# ---------------------------------------------------------------- changes
tmp=""
on_exit() {
	local rc=$?
	[[ -z "$tmp" ]] || rm -f "$tmp"
	[[ $rc -eq 0 ]] || warn "stopped part-way through the changes (settings.json is written last); fix the error above and re-run"
}
trap on_exit EXIT

for d in "${PERSIST_DIRS[@]}"; do
	mkdir -p "$d"
done
chmod 700 "$HOME/.agy" "$HOME/.gemini/antigravity-cli" "$HOME/.config/antigravity"

# ~/.agy symlinks
link "$AGY_SRC/AGENTS.md"                "$HOME/.agy/AGENTS.md"
link "$AGY_SRC/SYSTEM.md"                "$HOME/.agy/SYSTEM.md"
link "$ROOTDIR/agent/SWARM.md"           "$HOME/.agy/SWARM.md"
link "$ROOTDIR/agent/SWARM_REFERENCES.md" "$HOME/.agy/SWARM_REFERENCES.md"
link "$ROOTDIR/agent/RTK.md"             "$HOME/.agy/RTK.md"
link "$AGY_SRC/settings.json"            "$HOME/.agy/settings.json"
link "$AGY_SRC/mcp_config.json"          "$HOME/.agy/mcp_config.json"
link "$AGY_SRC/model-routing.json"       "$HOME/.agy/model-routing.json"
link "$AGY_SRC/policies/policy.toml"     "$HOME/.agy/policies/policy.toml"
link "$AGY_SRC/policies/policy.toml"     "$HOME/.agy/policies/rules.toml"
link "$ROOTDIR/agent/agents"             "$HOME/.agy/agents"
link "$ROOTDIR/agent/skills"             "$HOME/.agy/skills"
link "$ROOTDIR/agent/rules"              "$HOME/.agy/rules"

own_dir "$HOME/.agy/hooks"
for hf in "${hook_files[@]}"; do
	link "$hf" "$HOME/.agy/hooks/${hf##*/}"
done
prune "$HOME/.agy/hooks" "${hook_names[@]}"

# ~/.gemini symlinks
link "$AGY_SRC/AGENTS.md"                "$HOME/.gemini/AGENTS.md"
link "$AGY_SRC/AGENTS.md"                "$HOME/.gemini/GEMINI.md"
link "$AGY_SRC/SYSTEM.md"                "$HOME/.gemini/SYSTEM.md"
link "$ROOTDIR/agent/SWARM.md"           "$HOME/.gemini/SWARM.md"
link "$ROOTDIR/agent/SWARM_REFERENCES.md" "$HOME/.gemini/SWARM_REFERENCES.md"
link "$ROOTDIR/agent/RTK.md"             "$HOME/.gemini/RTK.md"
link "$AGY_SRC/settings.json"            "$HOME/.gemini/settings.json"
link "$AGY_SRC/model-routing.json"       "$HOME/.gemini/model-routing.json"
link "$AGY_SRC/policies/policy.toml"     "$HOME/.gemini/policies/policy.toml"
link "$AGY_SRC/policies/policy.toml"     "$HOME/.gemini/policies/rules.toml"
link "$AGY_SRC/mcp_config.json"          "$HOME/.gemini/config/mcp_config.json"
link "$AGY_SRC/hooks/hooks.json"         "$HOME/.gemini/config/hooks.json"
link "$AGY_SRC/hooks/hooks.json"         "$HOME/.gemini/antigravity-cli/hooks.json"
link "$AGY_SRC/model-routing.json"       "$HOME/.gemini/config/model-routing.json"
link "$ROOTDIR/agent/skills"             "$HOME/.gemini/config/skills"
link "$ROOTDIR/agent/rules"              "$HOME/.gemini/config/rules"
link "$ROOTDIR/agent/agents"             "$HOME/.gemini/config/agents"
link "$ROOTDIR/agent/skills"             "$HOME/.gemini/skills"
link "$ROOTDIR/agent/rules"              "$HOME/.gemini/rules"
link "$ROOTDIR/agent/agents"             "$HOME/.gemini/agents"

own_dir "$HOME/.gemini/hooks"
for hf in "${hook_files[@]}"; do
	link "$hf" "$HOME/.gemini/hooks/${hf##*/}"
done
prune "$HOME/.gemini/hooks" "${hook_names[@]}"

# ~/.gemini/antigravity-cli/settings.json: regular 0600 file, never a symlink.
if [[ $write_settings -eq 1 ]]; then
	[[ -z "$settings_diff" ]] || printf '%s\n' "$settings_diff"
	if [[ -e "$live" && ! -L "$live" ]]; then
		bak="$live.bak.$(date +%Y%m%d%H%M%S)"
		i=0
		while [[ -e "$bak" || -L "$bak" ]]; do i=$((i + 1)); bak="${bak%.~*}.~$i"; done
		(umask 077 && cat "$live" >"$bak")
		chmod 600 "$bak"
		note "previous settings.json saved as $bak"
	elif [[ -L "$live" ]]; then
		rm -f "$live"
	fi
	tmp="$(mktemp "$HOME/.gemini/antigravity-cli/.settings.json.XXXXXX")"
	printf '%s\n' "$new_json" >"$tmp"
	chmod 600 "$tmp"
	jq -e 'type == "object"' "$tmp" >/dev/null || die "merged settings.json failed validation (left unchanged)"
	mv -f "$tmp" "$live"
	tmp=""
	note "wrote $live (0600)"
else
	chmod 600 "$live"
fi

note "done"
