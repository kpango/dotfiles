#!/usr/bin/env bash
# PrimeAgent Harness Validation (prime-agent 0.10.0; CONTEXT "primeagent-max-customize (2026-10-14)").
#
# Repo checks always run. Live checks run only when $HOME/.prime/agent exists and never write it: files
# are only read, and prime-agent subcommands run against a throwaway copy (prime_run below), because
# even `prime-agent model list` creates auth.json in its agent dir.
#
# env:
#   PRIME_VALIDATE_FULL=1  also run the slow suites (measured 2026-10-17: test-pa-wrappers.sh ~170 s,
#                          test-prime-skills.sh ~280 s, swarm-adapter pytest ~75 s). Each keeps its own
#                          HOME/state in mktemp dirs; pytest via `uv run --with pytest` needs the network
#                          the first time and fills uv's cache.
#   SYNC_VERIFY_LIVE_ROOT  passed through to sync-verify.sh for the live wiring check
#
# Validating a fresh install without the real HOME: primeagent/install does not create the DOTFILES_MAP
# .prime/agent symlinks (AGENTS.md, models.json, model-routing.json; dotfiles/install does), so apply only
# those lines through DEPLOY_FUNC, as test-install.sh does (<repo> = this checkout):
#   H="$(mktemp -d)"
#   make -s -C <repo> -o dotfiles/install primeagent/install HOME="$H" ROOTDIR=<repo>
#   make -s -C <repo> -o dotfiles/install HOME="$H" ROOTDIR=<repo> --eval '_prime_map: ; @echo "$$DOTFILES_MAP" | grep " \.prime/agent/" | while read -r src dest; do $(call DEPLOY_FUNC,$(ROOTDIR)/$$src,$(HOME)/$$dest,); done' _prime_map
#   HOME="$H" bash <repo>/agent/harnesses/primeagent/validate-harness.sh
# Measured 2026-10-18: rc=0, 31/33 passed, 2 WARN (ipython not in PATH; the 10 remote model-routing
# selectors, see "model list" below). Without the second make, sync-verify FAILs those 3 entries.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -P "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=SCRIPTDIR/../../scripts/harness-check-lib.sh
source "$ROOT/agent/scripts/harness-check-lib.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/prime-validate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PA="$HOME/.prime/agent"

skip() { printf "  SK  %s: %s\n" "$1" "$2"; } # by design (opt-in / not installed), not counted

# prime-agent can run only offline (unshare -rn) so that no check depends on the network.
prime_ok=0
if ! command -v prime-agent &>/dev/null; then
    prime_why="prime-agent not in PATH"
elif ! unshare -rn true 2>/dev/null; then
    prime_why="unshare -rn unavailable (cannot guarantee an offline run)"
else
    prime_ok=1
fi

# prime_run <home> <args...>: prime-agent with HOME=<home>, its own daemon socket, no network and no
# inherited environment, so it neither reads nor writes the real ~/.prime/agent or the live daemon.
prime_run() {
    local h="$1"
    shift
    mkdir -p "$h/tmp"
    (cd "$h" && env -i HOME="$h" PATH="$PATH" TMPDIR="$h/tmp" XDG_DATA_HOME="$h/.local/share" \
        XDG_CONFIG_HOME="$h/.config" XDG_CACHE_HOME="$h/.cache" XDG_STATE_HOME="$h/.local/state" \
        PRIME_AGENT_DAEMON_SOCKET="$h/tmp/d.sock" PI_OFFLINE=1 timeout 120 unshare -rn prime-agent "$@" </dev/null)
}

# Top-level settings keys of the installed prime-agent: the CLI writes every schema key (null when unset)
# and keeps unknown keys when it rewrites settings.json, so a rewrite of {} lists exactly the schema.
schema_keys="" schema_why="${prime_why:-}"
if [[ $prime_ok -eq 1 ]]; then
    mkdir -p "$TMP/schema/.prime/agent"
    printf '{}\n' >"$TMP/schema/.prime/agent/settings.json"
    if ! prime_run "$TMP/schema" telemetry off >/dev/null 2>&1; then
        schema_why="prime-agent telemetry off in a sandbox failed"
    elif ! schema_keys="$(jq -r 'keys[]' "$TMP/schema/.prime/agent/settings.json" 2>&1)"; then
        schema_why="settings.json rewritten by telemetry off is not readable: $(head -n 1 <<<"$schema_keys")"
        schema_keys=""
    fi
fi

# json_object_why <file>: silent and 0 when the file holds exactly one JSON object; otherwise prints why
# and returns 1 (unparsable, empty, an array, several values: key checks on it would read nothing).
json_object_why() {
    local t
    if ! t="$(jq -r type "$1" 2>&1)"; then
        printf 'not valid JSON (%s)' "$(head -n 1 <<<"$t")"
        return 1
    fi
    [[ "$t" == object ]] && return 0
    t="${t//$'\n'/ }"
    printf 'not a single JSON object (top level: %s)' "${t:-empty}"
    return 1
}

# key_report <settings.json>: "<keys outside the schema>|<those that pi's settings.json has>" (space separated)
key_report() {
    jq -r --arg s "$schema_keys" --slurpfile pi "$ROOT/agent/harnesses/pi/settings.json" '
        ($s | split("\n")) as $schema | ($pi[0] | keys) as $pk
        | [keys[] | select(. as $k | $schema | index($k) | not)] as $u
        | "\($u | join(" "))|\([$u[] | select(. as $k | $pk | index($k))] | join(" "))"' "$1"
}

echo "=== PrimeAgent Harness Validation ==="
echo

echo "[ Configuration Files ]"
for f in settings.json models.json model-routing.json; do
    if [[ ! -f "$SCRIPT_DIR/$f" ]]; then
        check "$f" "MISSING"
    elif python3 -m json.tool "$SCRIPT_DIR/$f" >/dev/null 2>&1; then
        check "$f valid JSON" "OK"
    else
        check "$f valid JSON" "INVALID"
    fi
done
if [[ -z "$schema_keys" ]]; then
    check "settings.json keys in prime-agent's schema" "WARN:schema not derivable ($schema_why)"
elif ! why="$(json_object_why "$SCRIPT_DIR/settings.json")"; then
    check "settings.json keys in prime-agent's schema" "agent/harnesses/primeagent/settings.json is $why"
elif ! why="$(json_object_why "$ROOT/agent/harnesses/pi/settings.json")"; then
    check "settings.json keys in prime-agent's schema" "agent/harnesses/pi/settings.json (read for the pi-only keys) is $why"
elif ! pi_only="$(jq -r --arg s "$schema_keys" '($s | split("\n")) as $schema | [keys[] | select(. as $k | $schema | index($k) | not)] | join(" ")' "$ROOT/agent/harnesses/pi/settings.json" 2>&1)" ||
    ! report="$(key_report "$SCRIPT_DIR/settings.json" 2>&1)"; then
    check "settings.json keys in prime-agent's schema" "jq failed: $(tail -n 1 <<<"${report:-$pi_only}")"
else
    IFS='|' read -r unknown unknown_pi <<<"$report"
    if [[ -z "$unknown" ]]; then
        check "settings.json keys all in prime-agent's schema ($(wc -l <<<"$schema_keys") keys); pi-only keys absent: $pi_only" "OK"
    else
        check "settings.json keys in prime-agent's schema" "not in schema: $unknown${unknown_pi:+ (pi-only: $unknown_pi)}"
    fi
fi

echo
echo "[ Shared SSoT Files ]"
for f in AGENTS.md RTK.md SWARM.md SWARM_REFERENCES.md; do
    if [[ -f "$ROOT/agent/$f" ]]; then check "agent/$f exists" "OK"; else check "agent/$f" "MISSING"; fi
done

echo
echo "[ Skills & Machines ]"
listed=() missing=()
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -z "$line" ]] && continue
    listed+=("$line")
    [[ -f "$ROOT/agent/skills/$line/SKILL.md" ]] || missing+=("$line")
done <"$SCRIPT_DIR/skills.list"
if [[ ${#missing[@]} -eq 0 ]]; then
    check "skills.list: ${#listed[@]} names, each agent/skills/<name>/SKILL.md exists" "OK"
else
    check "skills.list" "no agent/skills/<name>/SKILL.md for: ${missing[*]}"
fi
prime_skills=() missing=() both=()
for d in "$SCRIPT_DIR"/skills/*/; do
    n="$(basename "$d")"
    prime_skills+=("$n")
    [[ -f "$d/SKILL.md" ]] || missing+=("$n")
    for s in "${listed[@]}"; do if [[ "$s" == "$n" ]]; then both+=("$n"); fi; done
done
if [[ ${#missing[@]} -eq 0 && ${#both[@]} -eq 0 ]]; then
    check "primeagent/skills: ${#prime_skills[@]} skills, each with SKILL.md, none also in skills.list" "OK"
else
    check "primeagent/skills" "${missing[*]:+without SKILL.md: ${missing[*]} }${both[*]:+also in skills.list: ${both[*]}}"
fi
machines=() missing=()
for d in "$SCRIPT_DIR"/machines/*/; do
    machines+=("$(basename "$d")")
    [[ -f "$d/MACHINE.md" ]] || missing+=("$(basename "$d")")
done
if [[ ${#machines[@]} -eq 0 ]]; then
    check "primeagent/machines" "none found"
elif [[ ${#missing[@]} -eq 0 ]]; then
    check "primeagent/machines: ${#machines[@]} machines, each with MACHINE.md" "OK"
else
    check "primeagent/machines" "without MACHINE.md: ${missing[*]}"
fi

echo
echo "[ CLI Binaries ]"
for bin in prime-agent ipython python3 rtk jq flock git hx bwrap; do
    if command -v "$bin" &>/dev/null; then
        check "binary available: $bin" "OK"
    else
        check "binary available: $bin" "WARN:not found in PATH"
    fi
done

echo
echo "[ Shared Security & Governance Tests ]"
harness_run_shared_test "security-rules.json (shared engine)" "$ROOT/agent/scripts/test-security-rules.sh"
harness_run_shared_test "model-routing.json (shared engine, incl. install.sh derivation)" "$ROOT/agent/scripts/test-model-routing.sh"
# Also covers the AGENTS.md line/byte limits (constants in gen-agents-md.sh) and SYSTEM.md absence.
harness_run_shared_test "AGENTS.md (generated, loaded by prompt --json)" "$SCRIPT_DIR/test-agents-md.sh"
harness_run_shared_test "make primeagent/install (throwaway HOMEs)" "$SCRIPT_DIR/test-install.sh"
if [[ $prime_ok -eq 1 ]]; then
    harness_run_shared_test "MACHINE.md specs + sandboxed factory import + simulator" "$SCRIPT_DIR/machines/test-machines.sh"
else
    check "MACHINE.md factory import" "WARN:skipped ($prime_why)"
fi
if [[ "${PRIME_VALIDATE_FULL:-0}" == 1 ]]; then
    harness_run_shared_test "pa-sandbox / pa-auto" "$SCRIPT_DIR/bin/test-pa-wrappers.sh"
    harness_run_shared_test "prime-swarm-* skills" "$SCRIPT_DIR/skills/test-prime-skills.sh"
    if python3 -c 'import pytest' 2>/dev/null; then
        pytest_cmd=(python3 -m pytest)
    elif command -v uv &>/dev/null; then
        pytest_cmd=(uv run --no-project --with pytest python -m pytest)
    else
        pytest_cmd=()
    fi
    if [[ ${#pytest_cmd[@]} -eq 0 ]]; then
        check "swarm-adapter pytest" "WARN:neither pytest nor uv available"
    elif (cd "$SCRIPT_DIR/skills/swarm-adapter" && PYTHONDONTWRITEBYTECODE=1 "${pytest_cmd[@]}" -q -p no:cacheprovider) >"$TMP/pytest.log" 2>&1; then
        check "swarm-adapter pytest ($(tail -n 1 "$TMP/pytest.log"))" "OK"
    else
        check "swarm-adapter pytest" "FAILED: $(tail -n 1 "$TMP/pytest.log")"
    fi
else
    skip "pa-sandbox / pa-auto, prime-swarm-* skills, swarm-adapter pytest" "slow (~9 min together); set PRIME_VALIDATE_FULL=1"
fi

echo
echo "[ Live $PA (read-only) ]"
if [[ ! -d "$PA" ]]; then
    skip "live checks" "$PA does not exist"
else
    if [[ -e "$PA/SYSTEM.md" || -L "$PA/SYSTEM.md" ]]; then
        check "no SYSTEM.md (P-1)" "present: prime-agent replaces its core/usage/opinionated layers with it"
    else
        check "no SYSTEM.md (P-1)" "OK"
    fi

    # settings.json regular 0600 (P-2), AGENTS.md -> prime's, skills/ and machines/ per entry,
    # bin/prime-shell-guard.sh, agents, themes, *.md, models/model-routing, ~/.local/bin/pa-*.
    if out="$(SYNC_VERIFY_ONLY=primeagent bash "$ROOT/agent/scripts/sync-verify.sh" 2>&1)"; then
        check "live wiring ($(grep -c '^PASS:' <<<"$out") entries, agent/scripts/sync-verify.sh)" "OK"
    else
        check "live wiring (agent/scripts/sync-verify.sh SYNC_VERIFY_ONLY=primeagent)" \
            "$(grep -c '^FAIL:' <<<"$out") FAIL, first: $(grep -m1 '^FAIL:' <<<"$out" || tail -n 1 <<<"$out")"
    fi

    if [[ ! -f "$PA/settings.json" ]]; then
        check "live settings.json keys" "missing"
    elif ! why="$(json_object_why "$PA/settings.json")"; then
        # P-2: prime-agent reads it as all null, so every repo-owned key is gone. install.sh refuses to
        # merge into it ("could not merge ... (left unchanged)"), so re-running the install does not help.
        check "live settings.json is a JSON object (P-2)" "$why; repair it by hand, or move it away and run make primeagent/install (starts from {}, the CLI-owned keys are lost)"
    else
        if [[ -z "$schema_keys" ]]; then
            : # reported once above (schema not derivable)
        elif ! report="$(key_report "$PA/settings.json" 2>&1)"; then
            check "live settings.json keys in prime-agent's schema" "jq failed: $(tail -n 1 <<<"$report")"
        else
            IFS='|' read -r unknown unknown_pi <<<"$report"
            if [[ -n "$unknown_pi" ]]; then
                check "live settings.json has no pi-only keys" "pi-only: $unknown_pi"
            elif [[ -n "$unknown" ]]; then
                check "live settings.json keys in prime-agent's schema" "WARN:not in schema: $unknown"
            else
                check "live settings.json keys all in prime-agent's schema" "OK"
            fi
        fi
        if ! drift="$(jq -r -n --slurpfile l "$PA/settings.json" --slurpfile r "$SCRIPT_DIR/settings.json" \
            '$l[0] as $l | ($l * $r[0]) as $m | [$r[0] | keys[] | select($l[.] != $m[.])] | join(" ")' 2>&1)"; then
            check "live settings.json carries the repo-owned keys (Q7)" "not comparable with the repo settings.json: $(head -n 1 <<<"$drift")"
        elif [[ -z "$drift" ]]; then
            check "live settings.json carries the repo-owned keys (Q7)" "OK"
        else
            check "live settings.json carries the repo-owned keys (Q7)" "WARN:differs: $drift (re-run make primeagent/install)"
        fi
    fi

    if [[ $prime_ok -eq 0 ]]; then
        check "live prompt / model list" "WARN:skipped ($prime_why)"
    else
        # Throwaway copy of what prompt assembly and model listing read. Files are dereferenced; directories
        # keep their symlinks into the checkout (read only). No credentials (auth.json) are copied.
        live="$TMP/live"
        mkdir -p "$live/.prime/agent"
        for n in AGENTS.md SYSTEM.md APPEND_SYSTEM.md settings.json models.json model-routing.json; do
            if [[ -e "$PA/$n" ]]; then cp -L "$PA/$n" "$live/.prime/agent/$n"; fi
        done
        for n in skills machines agents themes; do
            if [[ -e "$PA/$n" || -L "$PA/$n" ]]; then cp -a "$PA/$n" "$live/.prime/agent/$n"; fi
        done
        if ! prime_run "$live" prompt --json >"$TMP/prompt.json" 2>"$TMP/prompt.err"; then
            check "prompt --json" "failed: $(head -c 300 "$TMP/prompt.err")"
        elif ! layers="$(jq -r '[.segments[] | select(.chars > 0) | .name] | join(" ")' "$TMP/prompt.json" 2>&1)"; then
            check "prompt --json" "output has no readable .segments: $(head -n 1 <<<"$layers")"
        else
            missing_layers=""
            for l in core usage opinionated; do if [[ " $layers " != *" $l "* ]]; then missing_layers+=" $l"; fi; done
            if [[ -z "$missing_layers" ]]; then
                check "prompt --json: core/usage/opinionated layers present" "OK"
            else
                check "prompt --json: core/usage/opinionated layers" "missing:$missing_layers (layers: $layers)"
            fi
            if jq -r .prompt "$TMP/prompt.json" | grep '^# Agent Instructions (prime-agent)' >/dev/null; then
                check "prompt --json: prime AGENTS.md loaded" "OK"
            else
                check "prompt --json: prime AGENTS.md loaded" "not found in the assembled prompt"
            fi
        fi

        routing="$PA/model-routing.json"
        [[ -f "$routing" ]] || routing="$SCRIPT_DIR/model-routing.json"
        models_json="$live/.prime/agent/models.json" providers=""
        if ! sels="$(jq -r '.tiers[] | .model, (.fallbacks // [])[].model' "$routing" 2>"$TMP/sels.err" | sort -u)" ||
            [[ -z "$sels" ]]; then
            check "model list: model-routing selectors" "none readable from $routing: $(head -c 200 "$TMP/sels.err")"
        elif [[ -e "$models_json" ]] &&
            ! providers="$(jq -r '.providers // {} | keys | join(" ")' "$models_json" 2>"$TMP/providers.err")"; then
            check "model list: models.json providers" "$PA/models.json not readable: $(head -c 200 "$TMP/providers.err")"
        elif ! prime_run "$live" model list >"$TMP/models.txt" 2>"$TMP/models.err"; then
            check "model list" "WARN:failed offline: $(head -c 200 "$TMP/models.err")"
        else
            absent_local="" absent_remote=0
            while IFS= read -r sel; do
                p="${sel%%/*}" id="${sel#*/}"
                awk -v p="$p" -v id="$id" '$1 == p && $2 == id { f = 1 } END { exit !f }' "$TMP/models.txt" && continue
                if [[ " $providers " == *" $p "* ]]; then absent_local+=" $sel"; else absent_remote=$((absent_remote + 1)); fi
            done <<<"$sels"
            if [[ -n "$absent_local" ]]; then
                check "model list: model-routing selectors of models.json providers" "not listed:$absent_local"
            elif [[ $absent_remote -gt 0 ]]; then
                # By design, not a fault: credentials stay out of the throwaway copy, and model list lists a
                # remote provider only with its credentials, so these can never be listed here.
                check "model list: model-routing selectors" "WARN:$absent_remote selectors of providers outside models.json not verifiable (validate copies no credentials (auth.json) and runs prime-agent offline, and model list lists a remote provider only with credentials)"
            else
                check "model list: all model-routing selectors listed" "OK"
            fi
        fi
    fi

    if [[ -d "$PA/harness" ]]; then
        if size="$(du -sb "$PA/harness" 2>&1)"; then
            check "global harness state: ${size%%[[:space:]]*} bytes in $PA/harness (report only, Q6)" "OK"
        else
            check "global harness state: $PA/harness (report only, Q6)" "WARN:du failed: $(head -n 1 <<<"$size")"
        fi
    else
        check "global harness state: $PA/harness not created yet (report only, Q6)" "OK"
    fi
fi

harness_summary "PrimeAgent"
