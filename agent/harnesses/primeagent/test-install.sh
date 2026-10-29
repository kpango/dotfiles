#!/usr/bin/env bash
# test-install.sh -- `make primeagent/install` against throwaway HOMEs (never the real HOME, never sudo:
# dotfiles/install is skipped with -o; its DOTFILES_MAP .prime/agent entries are applied through the real
# DEPLOY_FUNC by a --eval target). Optional: `prime-agent prompt --json` on the result (skipped if absent).
# check() evals its condition later, so conditions are single-quoted on purpose (SC2016) and the variables
# they read (RC, ok_s, ...) look unused to shellcheck (SC2034).
# shellcheck disable=SC2016,SC2034
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -P "$SCRIPT_DIR/../../.." && pwd)"
PRIME="$ROOT/agent/harnesses/primeagent"
TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/prime-install-test.XXXXXX")"
trap 'command rm -rf "$TMPROOT"' EXIT

pass=0 fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; } # <name> <condition>

n=0
newhome() { n=$((n + 1)); H="$TMPROOT/h$n"; mkdir -p "$H/.prime/agent"; PA="$H/.prime/agent"; }
install_rc() { # <log>; sets RC
	RC=0
	make -s -C "$ROOT" -o dotfiles/install primeagent/install HOME="$H" ROOTDIR="$ROOT" >"$1" 2>&1 || RC=$?
}
apply_map() {
	make -s -C "$ROOT" -o dotfiles/install HOME="$H" ROOTDIR="$ROOT" \
		--eval '_t10_prime_map: ; @echo "$$DOTFILES_MAP" | grep " \.prime/agent/" | while read -r src dest; do $(call DEPLOY_FUNC,$(ROOTDIR)/$$src,$(HOME)/$$dest,); done' \
		_t10_prime_map >/dev/null
}
snapshot() { # layout + link targets + modes + regular-file hashes under $H
	find "$H" -mindepth 1 -printf '%P %y %m %l\n' | LC_ALL=C sort
	find "$H" -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
}
mode() { stat -c %a "$1"; }
lt() { [[ -L "$1" && "$(readlink "$1")" == "$2" ]]; } # <link> <target>

REPO_SETTINGS_SHA="$(sha256sum <"$PRIME/settings.json")"
mapfile -t LISTED < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$PRIME/skills.list")
mapfile -t PSKILLS < <(find "$PRIME/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -printf '%h\n' | xargs -n1 basename | LC_ALL=C sort)
mapfile -t MACHINES < <(find "$PRIME/machines" -mindepth 2 -maxdepth 2 -name MACHINE.md -printf '%h\n' | xargs -n1 basename | LC_ALL=C sort)

# Old (pre-T10) layout: the old recipe + old DOTFILES_MAP .prime/agent symlinks.
old_layout() {
	local f
	mkdir -p "$PA/sessions" "$PA/extensions/lib"
	ln -s "$ROOT/agent/agents" "$PA/agents"
	ln -s "$ROOT/agent/skills" "$PA/skills"
	ln -s "$ROOT/agent/rules" "$PA/rules"
	ln -s "$ROOT/agent/harnesses/pi/prompts" "$PA/prompts"
	ln -s "$ROOT/agent/harnesses/pi/themes" "$PA/themes"
	ln -s "$ROOT/agent/SWARM.md" "$PA/SWARM.md"
	ln -s "$ROOT/agent/SWARM_REFERENCES.md" "$PA/SWARM_REFERENCES.md"
	ln -s "$ROOT/agent/RTK.md" "$PA/RTK.md"
	ln -s "$ROOT/agent/harnesses/pi/SYSTEM.md" "$PA/SYSTEM.md"
	for f in "$ROOT"/agent/harnesses/pi/extensions/* "$ROOT"/agent/hooks/pi/*; do [[ -f "$f" ]] && ln -s "$f" "$PA/extensions/"; done
	for f in "$ROOT"/agent/harnesses/pi/extensions/lib/* "$ROOT"/agent/hooks/pi/lib/*; do [[ -f "$f" ]] && ln -s "$f" "$PA/extensions/lib/"; done
	ln -s "$ROOT/agent/harnesses/pi/AGENTS.md" "$PA/AGENTS.md"
	ln -s "$PRIME/settings.json" "$PA/settings.json"
	ln -s "$PRIME/models.json" "$PA/models.json"
	ln -s "$PRIME/model-routing.json" "$PA/model-routing.json"
	ln -s "$ROOT/agent/harnesses/pi/keybindings.json" "$PA/keybindings.json"
	ln -s "$ROOT/agent/harnesses/pi/mcp.json" "$PA/mcp.json"
}

allowed_ok() { # allowedModels (as a set, no duplicates) == expected set derived from the repo files
	local got want
	got="$(jq -c '.allowedModels | if length == (unique | length) then sort else "dup" end' "$PA/settings.json")"
	want="$(jq -c -n --slurpfile r "$PRIME/settings.json" --slurpfile m "$PRIME/model-routing.json" \
		'["\($r[0].defaultProvider)/\($r[0].defaultModel)", $r[0].providerBackupModel]
		 + [$m[0].tiers[] | .model, (.fallbacks // [])[].model] | unique')"
	[[ "$got" == "$want" ]]
}
repo_keys_ok() { # every scalar leaf of the repo settings.json has the same value in the live file
	[[ "$(jq -c --slurpfile r "$PRIME/settings.json" \
		'. as $s | [$r[0] | paths(scalars)] | all(.[]; . as $p | ($s | getpath($p)) == ($r[0] | getpath($p)))' \
		"$PA/settings.json")" == true ]]
}

layout_checks() { # <label>
	local s ok_s=1 m ok_m=1 p missing=""
	check "$1: settings.json regular 0600" '[[ -f "$PA/settings.json" && ! -L "$PA/settings.json" && $(mode "$PA/settings.json") == 600 ]]'
	check "$1: subagentDefaultModel = High" '[[ $(jq -r .subagentDefaultModel "$PA/settings.json") == $(jq -r .tiers.High.model "$PRIME/model-routing.json") ]]'
	check "$1: auxiliaryModel = Low" '[[ $(jq -r .auxiliaryModel "$PA/settings.json") == $(jq -r .tiers.Low.model "$PRIME/model-routing.json") ]]'
	check "$1: allowedModels = root + tier primaries/fallbacks + backup, unique" allowed_ok
	check "$1: repo-owned keys present" repo_keys_ok
	for p in SYSTEM.md extensions prompts rules keybindings.json mcp.json; do
		check "$1: no $p" '[[ ! -e "$PA/$p" && ! -L "$PA/$p" ]]'
	done
	check "$1: skills is a real dir" '[[ -d "$PA/skills" && ! -L "$PA/skills" ]]'
	for s in "${LISTED[@]}"; do lt "$PA/skills/$s" "$ROOT/agent/skills/$s" || ok_s=0; done
	for s in "${PSKILLS[@]}"; do lt "$PA/skills/$s" "$PRIME/skills/$s" || ok_s=0; done
	check "$1: skills = skills.list + primeagent/skills (${#LISTED[@]}+${#PSKILLS[@]})" '[[ $ok_s == 1 ]]'
	check "$1: no excluded shared skill (swarm-loop/security-scan)" '[[ ! -e "$PA/skills/swarm-loop" && ! -e "$PA/skills/security-scan" ]]'
	for m in "${MACHINES[@]}"; do lt "$PA/machines/$m" "$PRIME/machines/$m" || ok_m=0; done
	check "$1: machines (${#MACHINES[@]}) linked" '[[ $ok_m == 1 && ${#MACHINES[@]} -ge 3 ]]'
	check "$1: guard symlink" 'lt "$PA/bin/prime-shell-guard.sh" "$ROOT/agent/scripts/prime-shell-guard.sh"'
	check "$1: pa-sandbox/pa-auto on ~/.local/bin" 'lt "$H/.local/bin/pa-sandbox" "$PRIME/bin/pa-sandbox" && lt "$H/.local/bin/pa-auto" "$PRIME/bin/pa-auto"'
	check "$1: agents/themes/SWARM*.md/RTK.md links" 'lt "$PA/agents" "$ROOT/agent/agents" && lt "$PA/themes" "$ROOT/agent/harnesses/pi/themes" && lt "$PA/SWARM.md" "$ROOT/agent/SWARM.md" && lt "$PA/SWARM_REFERENCES.md" "$ROOT/agent/SWARM_REFERENCES.md" && lt "$PA/RTK.md" "$ROOT/agent/RTK.md"'
	check "$1: AGENTS.md is the prime version (DOTFILES_MAP)" 'lt "$PA/AGENTS.md" "$PRIME/AGENTS.md"'
	check "$1: no write-scope-rules.json link" '[[ ! -e "$PA/write-scope-rules.json" ]]'
	# every ~/.prime/agent/<path> the prime docs/skills reference by a concrete name resolves
	for p in AGENTS.md agents settings.json model-routing.json models.json themes SWARM.md bin/prime-shell-guard.sh \
		skills/grill-interview/SKILL.md skills/prime-swarm-meta/SKILL.md skills/prime-swarm-release-gate/SKILL.md skills/swarm-adapter/SKILL.md; do
		[[ -e "$PA/$p" ]] || missing+=" $p"
	done
	check "$1: referenced ~/.prime/agent paths resolve${missing:+ (missing:$missing)}" '[[ -z "$missing" ]]'
}

# --- 1. empty HOME
newhome
install_rc "$TMPROOT/1.log"
apply_map
check "empty HOME: install exit 0" '[[ $RC == 0 ]]'
layout_checks "empty HOME"
check "empty HOME: no settings backup" '! compgen -G "$PA/settings.json.bak.*" >/dev/null'
EMPTY_HOME="$H"

# --- 2. idempotent second run (no output change, no new backup)
before="$(snapshot)"
install_rc "$TMPROOT/2.log"
check "second run: exit 0" '[[ $RC == 0 ]]'
check "second run: zero diff" '[[ "$(snapshot)" == "$before" ]]'
check "second run: reports nothing changed" '! grep -q "linked\|removed\|wrote\|saved" "$TMPROOT/2.log"'

# --- 3. old layout HOME migrates
newhome
old_layout
apply_map
install_rc "$TMPROOT/3.log"
check "old layout: exit 0" '[[ $RC == 0 ]]'
layout_checks "old layout"
check "old layout: backup of the old symlinked settings (0600)" 'b=$(compgen -G "$PA/settings.json.bak.*") && [[ $(mode "$b") == 600 ]] && cmp -s "$b" "$PRIME/settings.json"'
check "old layout: repo settings.json not written through the old symlink" '[[ "$(sha256sum <"$PRIME/settings.json")" == "$REPO_SETTINGS_SHA" ]]'
before="$(snapshot)"
install_rc "$TMPROOT/3b.log"
check "old layout: second run zero diff" '[[ $RC == 0 && "$(snapshot)" == "$before" ]]'

# --- 4. live settings with CLI-owned keys
newhome
cat >"$PA/settings.json" <<'EOF'
{
  "onboardingCompleted": true,
  "recentModels": ["opencode-go/kimi-k3"],
  "defaultModel": "openai/gpt-5.5",
  "telemetry": {"enabled": true, "noticeShown": true},
  "mcpServers": {"tt": {"type": "http", "url": "http://127.0.0.1:9/mcp"}},
  "compaction": null,
  "bogusKey": 1
}
EOF
chmod 644 "$PA/settings.json"
cp_before="$(cat "$PA/settings.json")"
install_rc "$TMPROOT/4.log"
S="$PA/settings.json"
check "cli keys: exit 0" '[[ $RC == 0 ]]'
check "cli keys: CLI values kept" '[[ $(jq -c "[.onboardingCompleted, .recentModels, .bogusKey, .telemetry.noticeShown, .mcpServers.tt.url]" "$S") == "[true,[\"opencode-go/kimi-k3\"],1,true,\"http://127.0.0.1:9/mcp\"]" ]]'
check "cli keys: repo keys override" '[[ $(jq -c "[.defaultModel, .telemetry.enabled, (.mcpServers.graft.command), .compaction.enabled]" "$S") == "[\"anthropic/claude-opus-5.5\",false,\"graft\",true]" ]]'
check "cli keys: result 0600" '[[ $(mode "$S") == 600 ]]'
check "cli keys: overridden values printed" 'grep -q "settings.json defaultModel: \"openai/gpt-5.5\" -> \"anthropic/claude-opus-5.5\"" "$TMPROOT/4.log" && grep -q "settings.json telemetry.enabled: true -> false" "$TMPROOT/4.log"'
check "cli keys: unchanged / null keys not printed" '! grep -q "settings.json \(compaction\|bogusKey\|onboardingCompleted\|telemetry.noticeShown\)" "$TMPROOT/4.log"'
check "cli keys: backup holds the old bytes (0600)" 'b=$(compgen -G "$PA/settings.json.bak.*") && [[ $(mode "$b") == 600 && "$(cat "$b")" == "$cp_before" ]]'
check "cli keys: no temp file left" '! compgen -G "$PA/.settings.json.*" >/dev/null'
install_rc "$TMPROOT/4b.log"
check "cli keys: second run makes no new backup" '[[ $RC == 0 && $(compgen -G "$PA/settings.json.bak.*" | wc -l) == 1 ]]'

# --- 5. regular SYSTEM.md fails the install and is kept
newhome
echo "user system prompt" >"$PA/SYSTEM.md"
install_rc "$TMPROOT/5.log"
check "SYSTEM.md: install fails" '[[ $RC != 0 ]]'
check "SYSTEM.md: error names P-1" 'grep -q "P-1" "$TMPROOT/5.log"'
check "SYSTEM.md: kept, nothing else created" '[[ $(cat "$PA/SYSTEM.md") == "user system prompt" && ! -e "$PA/settings.json" && ! -e "$PA/skills" ]]'
newhome
ln -s /etc/hostname "$PA/SYSTEM.md"
install_rc "$TMPROOT/5b.log"
check "SYSTEM.md: foreign symlink also fails and is kept" '[[ $RC != 0 && -L "$PA/SYSTEM.md" ]]'
newhome
ln -s /etc "$PA/skills"
install_rc "$TMPROOT/5c.log"
check "foreign skills symlink: fails before any change" '[[ $RC != 0 ]] && lt "$PA/skills" /etc && [[ ! -e "$PA/settings.json" && ! -e "$PA/bin" ]]'

# --- 6. user files are never removed
newhome
old_layout
echo "// mine" >"$PA/extensions/mine.ts"
command rm "$PA/keybindings.json"
echo '{}' >"$PA/keybindings.json"
command rm "$PA/skills"
mkdir -p "$PA/skills/my-skill"
echo "x" >"$PA/skills/my-skill/SKILL.md"
ln -s "$ROOT/agent/skills/swarm-loop" "$PA/skills/swarm-loop"
ln -s /etc "$PA/skills/foreign"
install_rc "$TMPROOT/6.log"
check "user files: exit 0" '[[ $RC == 0 ]]'
check "user files: extensions/mine.ts kept, our links gone" '[[ -f "$PA/extensions/mine.ts" && -z $(find "$PA/extensions" -type l) && ! -e "$PA/extensions/lib" ]]'
check "user files: regular keybindings.json kept" '[[ -f "$PA/keybindings.json" && ! -L "$PA/keybindings.json" ]]'
check "user files: real skill dir kept" '[[ -f "$PA/skills/my-skill/SKILL.md" ]]'
check "user files: stale checkout skill link removed" '[[ ! -e "$PA/skills/swarm-loop" && ! -L "$PA/skills/swarm-loop" ]]'
check "user files: foreign skill symlink kept" 'lt "$PA/skills/foreign" /etc'
check "user files: SYSTEM.md symlink into checkout removed" '[[ ! -e "$PA/SYSTEM.md" && ! -L "$PA/SYSTEM.md" ]]'

# --- 7. jq failure leaves live settings untouched
newhome
printf '{"broken": ' >"$PA/settings.json"
chmod 600 "$PA/settings.json"
bytes_before="$(sha256sum <"$PA/settings.json")"
install_rc "$TMPROOT/7.log"
check "jq failure: install fails" '[[ $RC != 0 ]]'
check "jq failure: live bytes unchanged" '[[ "$(sha256sum <"$PA/settings.json")" == "$bytes_before" ]]'
check "jq failure: no backup, no temp, no other change" '! compgen -G "$PA/settings.json.bak.*" >/dev/null && ! compgen -G "$PA/.settings.json.*" >/dev/null && [[ ! -e "$PA/skills" ]]'
newhome
echo '[]' >"$PA/settings.json"
install_rc "$TMPROOT/7b.log"
check "non-object settings: install fails, unchanged" '[[ $RC != 0 && $(cat "$PA/settings.json") == "[]" ]]'

# --- 8. dotfiles/clean no longer lists live settings.json (DOTFILES_MAP)
MAP_RC=0
map_out="$(make -s -C "$ROOT" -o dotfiles/install HOME="$TMPROOT/none" --eval '_t10_m: ; @echo "$$DOTFILES_MAP"' _t10_m 2>&1)" || MAP_RC=$?
check "DOTFILES_MAP: no .prime/agent/settings.json, keybindings.json, mcp.json" '[[ $MAP_RC == 0 ]] && grep -q " \.prime/agent/models\.json$" <<<"$map_out" && ! grep -q " \.prime/agent/\(settings\|keybindings\|mcp\)\.json$" <<<"$map_out"'

# --- 10. live/repo type changes (object<->scalar, array<->object, derived keys): merged, diffed, installed
newhome
cat >"$PA/settings.json" <<'EOF'
{
  "theme": {"name": "x"},
  "compaction": 5,
  "mcpServers": [1, 2],
  "themes": {"a": 1},
  "telemetry": {"enabled": {"x": 1}, "noticeShown": true},
  "allowedModels": {"a": "b"},
  "auxiliaryModel": ["x"],
  "keep": {"k": 1}
}
EOF
tc_before="$(cat "$PA/settings.json")"
install_rc "$TMPROOT/10.log"
apply_map
S="$PA/settings.json"
printed() { grep -qxF "primeagent/install: settings.json $1: $2 -> $3" "$TMPROOT/10.log"; } # <path> <old json> <new json>
check "type change: exit 0, no jq error" '[[ $RC == 0 ]] && ! grep -q "Cannot index\|jq: error" "$TMPROOT/10.log"'
layout_checks "type change"
check "type change: object -> scalar printed once (theme)" 'printed theme "{\"name\":\"x\"}" "$(jq -c .theme "$S")" && [[ $(grep -c "settings.json theme:" "$TMPROOT/10.log") == 1 ]]'
check "type change: scalar -> object printed (compaction)" 'printed compaction 5 "$(jq -c .compaction "$S")"'
check "type change: array -> object printed (mcpServers)" 'printed mcpServers "[1,2]" "$(jq -c .mcpServers "$S")"'
check "type change: object -> array printed (themes)" 'printed themes "{\"a\":1}" "$(jq -c .themes "$S")"'
check "type change: nested object -> scalar printed (telemetry.enabled)" 'printed telemetry.enabled "{\"x\":1}" false'
check "type change: derived keys printed (allowedModels, auxiliaryModel)" 'printed allowedModels "{\"a\":\"b\"}" "$(jq -c .allowedModels "$S")" && printed auxiliaryModel "[\"x\"]" "$(jq -c .auxiliaryModel "$S")"'
check "type change: repo values installed" '[[ $(jq -c "[.theme, .compaction, .mcpServers, .themes]" "$S") == "$(jq -c "[.theme, .compaction, .mcpServers, .themes]" "$PRIME/settings.json")" ]]'
check "type change: CLI values kept, unchanged ones not printed" '[[ $(jq -c "[.keep, .telemetry.noticeShown]" "$S") == "[{\"k\":1},true]" ]] && ! grep -q "settings.json \(keep\|telemetry.noticeShown\)" "$TMPROOT/10.log"'
check "type change: backup holds the old bytes" 'b=$(compgen -G "$PA/settings.json.bak.*") && [[ "$(cat "$b")" == "$tc_before" ]]'

# --- 11. preflight failures: nothing in HOME changes (types, link targets, modes, content hashes)
preflight_fail() { # <label> <setup, run on an old-layout HOME>
	local before
	newhome
	old_layout
	apply_map
	eval "$2"
	before="$(snapshot)"
	install_rc "$TMPROOT/11.$n.log"
	check "preflight $1: fails with an error, HOME unchanged" '[[ $RC != 0 ]] && grep -q "primeagent/install: error:" "$TMPROOT/11.$n.log" && [[ "$(snapshot)" == "$before" ]]'
}
preflight_fail "skills regular file" 'command rm "$PA/skills"; echo x >"$PA/skills"'
preflight_fail "machines regular file" 'echo x >"$PA/machines"'
preflight_fail "bin regular file" 'echo x >"$PA/bin"'
preflight_fail "skills dangling foreign symlink" 'command rm "$PA/skills"; ln -s /nonexistent/skills "$PA/skills"'
preflight_fail "sessions regular file" 'command rm -r "$PA/sessions"; echo x >"$PA/sessions"'
preflight_fail ".local/bin regular file" 'mkdir -p "$H/.local"; echo x >"$H/.local/bin"'
preflight_fail ".local regular file" 'echo x >"$H/.local"'
preflight_fail "settings.json foreign symlink" 'command rm "$PA/settings.json"; ln -s /etc/hostname "$PA/settings.json"'
preflight_fail "settings.json directory" 'command rm "$PA/settings.json"; mkdir "$PA/settings.json"'
preflight_fail "settings.json broken JSON" 'command rm "$PA/settings.json"; printf "{\"a\": " >"$PA/settings.json"'
preflight_fail "foreign SYSTEM.md" 'command rm "$PA/SYSTEM.md"; echo mine >"$PA/SYSTEM.md"'
n=$((n + 1))
H="$TMPROOT/h$n"
mkdir -p "$H"
echo x >"$H/.prime"
before="$(snapshot)"
install_rc "$TMPROOT/11.prime.log"
check "preflight .prime regular file: fails, HOME unchanged" '[[ $RC != 0 && "$(snapshot)" == "$before" ]]'

# --- 12. the CLI rewriting settings.json in its own format (key order, indentation) is not a change
newhome
install_rc "$TMPROOT/12a.log"
fmt_before="$(sha256sum <"$PA/settings.json")"
jq -S --tab . "$PA/settings.json" >"$TMPROOT/12.json"
cat "$TMPROOT/12.json" >"$PA/settings.json"
before="$(snapshot)"
install_rc "$TMPROOT/12.log"
check "reformatted settings: bytes really differ" '[[ "$(sha256sum <"$PA/settings.json")" != "$fmt_before" ]]'
check "reformatted settings: exit 0, nothing written, no backup" '[[ $RC == 0 && "$(snapshot)" == "$before" ]] && ! compgen -G "$PA/settings.json.bak.*" >/dev/null && ! grep -q "wrote\|saved\|settings.json [^ ]*:" "$TMPROOT/12.log"'

# --- 13. a user's ~/.local/bin/pa-* (regular file, foreign symlink) is kept, with a warning
newhome
mkdir -p "$H/.local/bin"
echo '#!/bin/sh' >"$H/.local/bin/pa-auto"
ln -s /usr/bin/true "$H/.local/bin/pa-sandbox"
install_rc "$TMPROOT/13.log"
check "local bin: exit 0" '[[ $RC == 0 ]]'
check "local bin: regular pa-auto kept" '[[ -f "$H/.local/bin/pa-auto" && ! -L "$H/.local/bin/pa-auto" && $(cat "$H/.local/bin/pa-auto") == "#!/bin/sh" ]]'
check "local bin: foreign pa-sandbox symlink kept" 'lt "$H/.local/bin/pa-sandbox" /usr/bin/true'
check "local bin: both warned" 'grep -qF "warning: $H/.local/bin/pa-auto exists and is not a symlink" "$TMPROOT/13.log" && grep -qF "warning: $H/.local/bin/pa-sandbox is a symlink not into" "$TMPROOT/13.log"'
check "local bin: rest of the layout installed" 'lt "$PA/bin/prime-shell-guard.sh" "$ROOT/agent/scripts/prime-shell-guard.sh" && [[ -f "$PA/settings.json" ]]'

# --- 14. settings.json in the CLI's own format (integers as 60.0, many null keys) is not a change
cli_format() { # <out>: the installed settings.json as prime-agent 0.10.0 writes it
	jq '. + {onboardingShown: null, updateChannel: null, recentModels: null, imageModel: null}
		| .compaction += {reserveTokens: null}' "$PA/settings.json" |
		sed -E 's/^( *"[^"]*": *-?[0-9]+)(,?)$/\1.0\2/' >"$1"
}
newhome
install_rc "$TMPROOT/14a.log"
cli_format "$TMPROOT/14.json"
cat "$TMPROOT/14.json" >"$PA/settings.json"
check "CLI format: live really has 60.0-style numbers and nulls" 'grep -q "\"maxTurns\": 60\.0" "$PA/settings.json" && [[ $(jq .imageModel "$PA/settings.json") == null ]]'
before="$(snapshot)"
install_rc "$TMPROOT/14.log"
check "CLI format: exit 0, nothing written, no backup, no diff line" '[[ $RC == 0 && "$(snapshot)" == "$before" ]] && ! compgen -G "$PA/settings.json.bak.*" >/dev/null && ! grep -q "wrote\|saved\|settings.json [^ ]*:" "$TMPROOT/14.log"'
jq '.defaultModel = "openai/gpt-5.5"' "$TMPROOT/14.json" | sed -E 's/^( *"[^"]*": *-?[0-9]+)(,?)$/\1.0\2/' >"$PA/settings.json"
install_rc "$TMPROOT/14b.log"
check "CLI format + real change: only the real change printed, one backup" '[[ $RC == 0 && $(grep -c "settings.json [^ ]*:" "$TMPROOT/14b.log") == 1 ]] && grep -q "settings.json defaultModel:" "$TMPROOT/14b.log" && [[ $(compgen -G "$PA/settings.json.bak.*" | wc -l) == 1 ]]'

# --- 15. a failure part-way through the changes warns exactly once (an unreadable dir under a
# read-only extensions/: fails both in a subshell and in the function that removes our links)
newhome
old_layout
apply_map
mkdir "$PA/extensions/locked"
chmod 000 "$PA/extensions/locked"
chmod 555 "$PA/extensions"
install_rc "$TMPROOT/15.log"
chmod 755 "$PA/extensions" "$PA/extensions/locked"
check "part-way failure: exit non-zero, settings.json untouched" '[[ $RC != 0 ]] && lt "$PA/settings.json" "$PRIME/settings.json"'
check "part-way failure: \"stopped part-way\" warned once" '[[ $(grep -c "stopped part-way" "$TMPROOT/15.log") == 1 ]]'

# --- 16. old-layout cleanup removes only directories that removing our links emptied
newhome
old_layout
mkdir -p "$PA/extensions/mine-empty" "$PA/extensions/lib/user-empty"
command rm "$PA/rules" "$PA/prompts"
mkdir -p "$PA/rules/empty-user" "$PA/prompts/sub"
ln -s "$ROOT/agent/harnesses/pi/prompts" "$PA/prompts/sub/ours"
install_rc "$TMPROOT/16.log"
check "empty dirs: exit 0" '[[ $RC == 0 ]]'
check "empty dirs: our extensions links gone, user empty dirs kept" '[[ -z $(find "$PA/extensions" -type l) && -d "$PA/extensions/mine-empty" && -d "$PA/extensions/lib/user-empty" ]]'
check "empty dirs: rules/ holding only a user empty dir kept" '[[ -d "$PA/rules/empty-user" ]]'
check "empty dirs: prompts/ emptied by removing our link removed" '[[ ! -e "$PA/prompts" ]]'

# --- 17. invalid HOME (relative, empty, /, //, missing) is refused before any change
mkdir -p "$TMPROOT/cwd17/rel"
before17="$(find "$TMPROOT/cwd17" -printf '%P %y\n' | LC_ALL=C sort)"
for bad in rel "" / // "$TMPROOT/missing17"; do
	RC=0
	(cd "$TMPROOT/cwd17" && ROOTDIR="$ROOT" HOME="$bad" timeout 30 bash "$PRIME/install.sh") >"$TMPROOT/17.log" 2>&1 || RC=$?
	check "invalid HOME '$bad': refused" '[[ $RC == 1 ]] && grep -q "primeagent/install: error: HOME=" "$TMPROOT/17.log"'
done
check "invalid HOME: nothing created (cwd, missing HOME)" '[[ "$(find "$TMPROOT/cwd17" -printf "%P %y\n" | LC_ALL=C sort)" == "$before17" && ! -e "$TMPROOT/missing17" ]]'

# --- 9. prime-agent prompt --json on the installed layout (optional)
if command -v prime-agent >/dev/null 2>&1; then
	H="$EMPTY_HOME"
	PA="$H/.prime/agent"
	mkdir -p "$H/tmp"
	out="$TMPROOT/prompt.json"
	if (cd "$TMPROOT" && env -i HOME="$H" PATH="$PATH" TMPDIR="$H/tmp" XDG_DATA_HOME="$H/.local/share" \
		XDG_CONFIG_HOME="$H/.config" XDG_CACHE_HOME="$H/.cache" XDG_STATE_HOME="$H/.local/state" \
		PRIME_AGENT_DAEMON_SOCKET="$H/tmp/d.sock" PI_OFFLINE=1 timeout 120 prime-agent prompt --json >"$out" 2>"$TMPROOT/prompt.err"); then
		check "prompt: core/usage/opinionated layers present" '[[ $(jq "[.segments[] | select((.name == \"core\" or .name == \"usage\" or .name == \"opinionated\") and .chars > 0)] | length" "$out") == 3 ]]'
		check "prompt: prime AGENTS.md loaded, pi AGENTS.md not" 'jq -r .prompt "$out" | grep -q "# Agent Instructions (prime-agent)" && ! jq -r .prompt "$out" | grep -q "AGENTS-pi-supplement"'
		names="$(jq -r .prompt "$out" | grep -o "<name>[^<]*</name>" | sed "s/<[^>]*>//g")"
		ok_p=1
		for s in "${LISTED[@]}" "${PSKILLS[@]}"; do grep -qx "$s" <<<"$names" || ok_p=0; done
		check "prompt: all allowed skills listed" '[[ $ok_p == 1 ]]'
		check "prompt: excluded shared skills not listed" '! grep -qx "swarm-loop\|security-scan\|mcp-ecosystem-audit" <<<"$names"'
		check "prompt: swarm-adapter is a python skill" 'jq -r .prompt "$out" | grep -q "<python_import>swarm_adapter</python_import>"'
	else
		ko "prompt: prime-agent prompt --json failed ($(head -c 300 "$TMPROOT/prompt.err"))"
	fi
	# the CLI rewriting settings.json itself (same isolation) is no change for the next install
	before="$(sha256sum <"$PA/settings.json")"
	if (cd "$TMPROOT" && env -i HOME="$H" PATH="$PATH" TMPDIR="$H/tmp" XDG_DATA_HOME="$H/.local/share" \
		XDG_CONFIG_HOME="$H/.config" XDG_CACHE_HOME="$H/.cache" XDG_STATE_HOME="$H/.local/state" \
		PRIME_AGENT_DAEMON_SOCKET="$H/tmp/d.sock" PI_OFFLINE=1 timeout 60 prime-agent telemetry off >/dev/null 2>"$TMPROOT/tel.err"); then
		check "CLI rewrite: prime-agent really rewrote settings.json" '[[ "$(sha256sum <"$PA/settings.json")" != "$before" ]]'
		before="$(snapshot)"
		install_rc "$TMPROOT/9b.log"
		check "CLI rewrite: next install writes nothing, no backup, no diff line" '[[ $RC == 0 && "$(snapshot)" == "$before" ]] && ! compgen -G "$PA/settings.json.bak.*" >/dev/null && ! grep -q "wrote\|saved\|settings.json [^ ]*:" "$TMPROOT/9b.log"'
	else
		ko "CLI rewrite: prime-agent telemetry off failed ($(head -c 300 "$TMPROOT/tel.err"))"
	fi
else
	printf 'skip prompt checks (prime-agent not in PATH)\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
