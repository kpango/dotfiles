#!/usr/bin/env bash
# install.sh -- deploy the prime-agent 0.10.0 layout into ~/.prime/agent (called by `make primeagent/install`).
#
# Usage: ROOTDIR=<dotfiles checkout> HOME=<home> install.sh
#
# Decisions: CONTEXT.md "primeagent-max-customize (2026-10-14)" (P-1..P-7, Q4, Q7, C-1, C-2).
#   - Preflight first, no changes: HOME must be an existing absolute directory other than /, path types
#     are checked, and settings.json is merged, validated and diffed. Any failure there exits non-zero
#     with every file and link left unchanged. A failure after that prints one "stopped part-way" warning.
#   - settings.json is a regular 0600 file, never a symlink (P-2): live (CLI-owned keys) * repo-owned
#     keys * keys derived from model-routing.json, written atomically and last. It is rewritten only
#     when it is a symlink, missing, or not equal to the merge under jq's `==` (so key order,
#     indentation and number spelling such as the CLI's 60.0 vs the repo's 60 are ignored). On a rewrite
#     every non-null live value that changes (same `==`) is printed as "path: old -> new" (a type change
#     is one line at the first differing path) and the previous file is kept as
#     settings.json.bak.<timestamp> (Q7). A settings.json symlink not into this checkout, or a
#     non-regular one, aborts.
#   - SYSTEM.md replaces prime's core prompt layers (P-1): a SYSTEM.md this installer did not link aborts.
#   - skills/, machines/, bin/, sessions/, ~/.prime/agent and ~/.local/bin must be directories (or
#     creatable); a regular file there, or a skills/machines/bin symlink not into the checkout, aborts.
#   - Leftovers of the old pi-derived layout (SYSTEM.md, extensions/, prompts, rules, keybindings.json,
#     mcp.json) are removed only when they are symlinks into this checkout (P-3). Inside a real
#     extensions/, prompts/ or rules/ directory, a directory is removed only when removing those
#     symlinks left it empty; user files, foreign symlinks and directories that were already empty stay.
#   - Any other link destination (agents, themes, *.md, entries under skills/machines/bin,
#     ~/.local/bin/pa-sandbox, pa-auto) that holds a user file or a foreign symlink is kept, with a warning.
#   - skills/ and machines/ are real directories of per-entry symlinks (P-5, P-7); swarm-adapter and the
#     shell guard must stay symlinks because both locate the checkout from their own real path (C-1).
# Per-file symlinks of AGENTS.md, models.json and model-routing.json come from DOTFILES_MAP (dotfiles/install).
set -euo pipefail

die() { printf 'primeagent/install: error: %s\n' "$1" >&2; exit 1; }
note() { printf 'primeagent/install: %s\n' "$1"; }
warn() { printf 'primeagent/install: warning: %s\n' "$1" >&2; }

: "${ROOTDIR:?ROOTDIR unset}"
# An unset/empty or relative HOME would resolve against the caller's cwd, and HOME=/ would install
# into /.prime.
[[ "${HOME-}" == /* && -n "${HOME//\//}" && -d "$HOME" ]] ||
	die "HOME='${HOME-}' must be an existing absolute directory other than /"
ROOTDIR="${ROOTDIR%/}"
ROOT_REAL="$(cd -P "$ROOTDIR" && pwd)"
PRIME="$ROOTDIR/agent/harnesses/primeagent"
PA="$HOME/.prime/agent"

command -v jq >/dev/null 2>&1 || die "jq not found in PATH"

# A symlink whose target lies inside this checkout (written by this or the old installer).
owned() {
	local t
	[[ -L "$1" ]] || return 1
	t="$(readlink "$1")"
	[[ "$t" == "$ROOTDIR"/* || "$t" == "$ROOT_REAL"/* ]]
}

# link <src> <dest>: create or retarget OUR symlink; never replace a user's file, dir or foreign symlink.
link() {
	if [[ -L "$2" ]]; then
		[[ "$(readlink "$2")" == "$1" ]] && return 0
		owned "$2" || { warn "$2 is a symlink not into $ROOTDIR; left alone"; return 0; }
	elif [[ -e "$2" ]]; then
		warn "$2 exists and is not a symlink; left alone"
		return 0
	fi
	ln -sfn "$1" "$2"
	note "linked $2 -> $1"
}

# remove_owned <path>: drop our symlink, or our symlinks inside a real dir. After each removal the
# parents up to <path> are rmdir'ed while they are empty, so only directories that removal emptied
# go; a directory that was already empty never held one of our links and is never visited.
remove_owned() {
	local l p
	if owned "$1"; then
		rm -f "$1"
		note "removed $1"
	elif [[ -d "$1" && ! -L "$1" ]]; then
		while IFS= read -r -d '' l; do
			owned "$l" || continue
			rm -f "$l"
			note "removed $l"
			p="${l%/*}"
			while [[ "$p" == "$1" || "$p" == "$1"/* ]] && rmdir "$p" 2>/dev/null; do p="${p%/*}"; done
		done < <(find "$1" -type l -print0)
		[[ -e "$1" ]] && warn "$1 left in place (removing this installer's symlinks did not empty it)"
	elif [[ -e "$1" || -L "$1" ]]; then
		warn "$1 is not a symlink into $ROOTDIR; left alone (prime-agent 0.10.0 does not read it)"
	fi
	return 0
}

# own_dir <dir>: make <dir> a real directory (an old dir symlink into the checkout is dropped first).
own_dir() {
	if owned "$1"; then
		rm -f "$1"
		note "removed old directory symlink $1"
	fi
	[[ -L "$1" ]] && die "$1 is a symlink not into $ROOTDIR; move it away and re-run"
	mkdir -p "$1"
}

# dir_ok <path>: <path> is a directory, or missing below a directory (so `mkdir -p` can create it).
dir_ok() {
	local p="$1"
	while [[ -n "$p" && ! -e "$p" && ! -L "$p" && "$p" == */* ]]; do p="${p%/*}"; done
	[[ -n "$p" && -d "$p" ]]
}

# prune <dir> <wanted names...>: drop our symlinks in <dir> that are no longer wanted.
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
if [[ -e "$PA/SYSTEM.md" || -L "$PA/SYSTEM.md" ]] && ! owned "$PA/SYSTEM.md"; then
	die "$PA/SYSTEM.md exists and was not linked by this installer: prime-agent replaces its core/usage/opinionated system prompt layers with it (CONTEXT P-1). Move it away and re-run."
fi
for d in "$PA" "$PA/sessions" "$HOME/.local/bin"; do
	dir_ok "$d" || die "$d is not a directory (or a path that can be created as one); move it away and re-run"
done
for d in skills machines bin; do
	if [[ -L "$PA/$d" ]]; then
		owned "$PA/$d" || die "$PA/$d is a symlink not into $ROOTDIR; move it away and re-run"
	elif ! dir_ok "$PA/$d"; then
		die "$PA/$d is not a directory; move it away and re-run"
	fi
done

skills=()
while IFS= read -r line || [[ -n "$line" ]]; do
	line="${line%%#*}"
	line="${line//[[:space:]]/}"
	[[ -z "$line" ]] && continue
	[[ -f "$ROOTDIR/agent/skills/$line/SKILL.md" ]] || die "skills.list names '$line' but agent/skills/$line/SKILL.md does not exist"
	skills+=("$line")
done <"$PRIME/skills.list"
prime_skills=()
for d in "$PRIME"/skills/*/; do
	d="${d%/}"
	[[ -f "$d/SKILL.md" ]] || continue
	for s in "${skills[@]}"; do [[ "$s" == "${d##*/}" ]] && die "skill '$s' is both in skills.list and agent/harnesses/primeagent/skills/"; done
	prime_skills+=("${d##*/}")
done
machines=()
for d in "$PRIME"/machines/*/; do
	d="${d%/}"
	[[ -f "$d/MACHINE.md" ]] && machines+=("${d##*/}")
done

# settings.json = live * repo-owned keys * derived keys (Q7, C-2), its diff and whether to write it.
live="$PA/settings.json"
live_src=""
if [[ -L "$live" ]]; then
	owned "$live" || die "$live is a symlink not into $ROOTDIR; move it away and re-run (P-2: it must be a regular file)"
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
		jq -e -s --slurpfile repo "$PRIME/settings.json" --slurpfile mr "$PRIME/model-routing.json" '
		def uniq: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
		def sel($m): if ($m | type) == "string" and $m != "" then $m else error("model-routing.json: missing model") end;
		if length != 1 or (.[0] | type) != "object" then error("live settings.json is not a JSON object") else .[0] end
		| ($repo[0]) as $r | ($mr[0].tiers) as $t
		| if ($r.defaultProvider | type) != "string" or ($r.defaultModel | type) != "string"
		     or ($r.providerBackupModel | type) != "string"
		  then error("repo settings.json must set defaultProvider, defaultModel and providerBackupModel (C-2)") else . end
		| . * $r * {
			subagentDefaultModel: sel($t.High.model),
			auxiliaryModel: sel($t.Low.model),
			allowedModels: (
				["\($r.defaultProvider)/\($r.defaultModel)"]
				+ [ ("Low", "Medium", "High", "XHigh", "Max") as $n | $t[$n] | sel(.model), (.fallbacks // [])[].model ]
				+ [$r.providerBackupModel]
				| map(sel(.)) | uniq)
		}
		| if type == "object" then . else error("merged settings.json is not a JSON object") end'
)" || die "could not merge $live (left unchanged)"
write_settings=1
settings_diff=""
if [[ -n "$live_src" ]]; then
	# Walk the live tree only while both sides are objects, so a type change is one "old -> new" line.
	settings_diff="$(jq -r -n --slurpfile o "$live_src" --argjson n "$new_json" '
		def d($o; $n; $p):
			if ($o | type) == "object" and ($n | type) == "object" then $o | to_entries[] | d(.value; $n[.key]; $p + [.key])
			elif $o != null and $o != $n then "primeagent/install: settings.json \($p | join(".")): \($o | tojson) -> \($n | tojson)"
			else empty end;
		d($o[0]; $n; [])')" || die "could not diff $live against the merged settings (left unchanged)"
	# jq's own equality: 60.0 == 60, so a rewrite by the CLI in its own number format is no change.
	same="$(jq -n --slurpfile o "$live_src" --argjson n "$new_json" '$o[0] == $n')" ||
		die "could not compare $live with the merged settings (left unchanged)"
	if [[ ! -L "$live" && "$same" == true ]]; then
		write_settings=0
	fi
fi

# ---------------------------------------------------------------- changes
# One warning on any non-zero exit from here on (a failed command under set -e, or die), printed
# by the EXIT trap so a failure inside a function or subshell is reported once, not once per level.
tmp=""
on_exit() {
	local rc=$?
	[[ -z "$tmp" ]] || rm -f "$tmp"
	[[ $rc -eq 0 ]] || warn "stopped part-way through the changes (settings.json is written last); fix the error above and re-run"
}
trap on_exit EXIT
mkdir -p "$PA/sessions"

# Old pi-derived layout (P-1, P-3).
for n in SYSTEM.md extensions prompts rules keybindings.json mcp.json; do
	remove_owned "$PA/$n"
done

link "$ROOTDIR/agent/agents" "$PA/agents"
link "$ROOTDIR/agent/harnesses/pi/themes" "$PA/themes"
for n in SWARM.md SWARM_REFERENCES.md RTK.md; do
	link "$ROOTDIR/agent/$n" "$PA/$n"
done

own_dir "$PA/skills"
for s in "${skills[@]}"; do link "$ROOTDIR/agent/skills/$s" "$PA/skills/$s"; done
for s in "${prime_skills[@]}"; do link "$PRIME/skills/$s" "$PA/skills/$s"; done
prune "$PA/skills" "${skills[@]}" "${prime_skills[@]}"

own_dir "$PA/machines"
for m in "${machines[@]}"; do link "$PRIME/machines/$m" "$PA/machines/$m"; done
prune "$PA/machines" "${machines[@]}"

own_dir "$PA/bin"
link "$ROOTDIR/agent/scripts/prime-shell-guard.sh" "$PA/bin/prime-shell-guard.sh"

# pa-auto finds pa-sandbox next to its own (link) path, so both go side by side on PATH.
mkdir -p "$HOME/.local/bin"
for n in pa-sandbox pa-auto; do link "$PRIME/bin/$n" "$HOME/.local/bin/$n"; done

# settings.json: write only when it is a symlink, missing, or differs as JSON (preflight decided).
if [[ $write_settings -eq 1 ]]; then
	[[ -z "$settings_diff" ]] || printf '%s\n' "$settings_diff"
	if [[ -e "$live" ]]; then
		bak="$live.bak.$(date +%Y%m%d%H%M%S)"
		i=0
		while [[ -e "$bak" || -L "$bak" ]]; do i=$((i + 1)); bak="${bak%.~*}.~$i"; done
		(umask 077 && cat "$live" >"$bak")
		chmod 600 "$bak"
		note "previous settings.json saved as $bak"
	fi
	tmp="$(mktemp "$PA/.settings.json.XXXXXX")"
	printf '%s\n' "$new_json" >"$tmp"
	chmod 600 "$tmp"
	jq -e 'type == "object"' "$tmp" >/dev/null || die "merged settings.json failed validation (left unchanged)"
	mv -f "$tmp" "$live"
	tmp=""
	note "wrote $live (0600)"
else
	chmod 600 "$live"
fi

[[ -x "$PA/kernel-venv/bin/python" ]] ||
	warn "$PA/kernel-venv not present yet: prime-agent creates it and installs the Python skills (swarm-adapter) editable at the first kernel start"
note "done"
