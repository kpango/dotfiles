#!/usr/bin/env bash
# prime-shell-guard.sh -- primeagent bash() guard backed by agent/security-rules.json.
#
# Guardrail, not a security boundary (CONTEXT.md primeagent-max-customize Q5): it only sees
# commands issued through prime-agent's Python `bash()`; Python subprocess/os calls in the
# REPL bypass it. For untrusted runs wrap the whole process in a sandbox instead.
#
# How prime-agent applies the prefix (rlm/bash.py `_with_prefix` + `_status_script`,
# verified by spike): env PRIME_AGENT_BASH_COMMAND_PREFIX is spliced as
#     { <prefix>\n<command>\n} 8>&- 9>&-
# into ONE `bash -c` script. The prefix is shell code, not an argv wrapper, and never
# receives the command as an argument. The `shellCommandPrefix` settings key had NO effect
# on the model's ipython/bash() path in the spike; use the env var (set it in the launcher).
#
# Limits (known bypasses this guardrail does NOT stop; it pattern-matches the command text):
#   - variable indirection:            x=git; $x <dangerous subcommand>
#   - command substitution in strings: echo "$(<dangerous command>)"
#   - REPL Python subprocess/os calls (never pass through bash()).
#   - the REPL can unset/alter PRIME_AGENT_BASH_COMMAND_PREFIX via os.environ
#     (bash.py reads it on every call), disabling the guard for later bash() calls.
#   Not blocked on purpose: a leading `$var` command (too many legitimate uses, e.g. $EDITOR).
#   For untrusted runs wrap the whole prime-agent process in a sandbox.
#
# Usage:
#   PRIME_AGENT_BASH_COMMAND_PREFIX='. /path/to/prime-shell-guard.sh'   # sourced (prefix mode)
#   prime-shell-guard.sh "<command>"                                    # exec mode
#
# Prefix mode recovers the command text from /proc/$$/cmdline (Linux). If the script shape
# is not the expected one it fails CLOSED. allow -> run; block/ask -> reason on stderr, exit 126
# (ask is treated as block: no human is available in a non-interactive agent call).

_psg_check() { # $1 = command ; 0 = allow, 126 = refuse (message already printed)
    (
        set -euo pipefail
        local src root rules decide out decision reason
        src=$(readlink -f "${BASH_SOURCE[0]}") || exit 126
        root=$(cd -P "$(dirname "$src")/../.." && pwd) || exit 126
        rules="$root/agent/security-rules.json"
        decide="$root/agent/scripts/hooks/decide.py"
        if ! command -v python3 >/dev/null 2>&1; then
            echo "prime-shell-guard: python3 not found; refusing (fail-closed)" >&2
            exit 126
        fi
        if [[ ! -f "$decide" || ! -f "$rules" ]]; then
            echo "prime-shell-guard: decide.py or security-rules.json missing under $root; refusing (fail-closed)" >&2
            exit 126
        fi
        # Request shape matches agent/hooks/claude/security-gate.sh (family security_shell).
        out=$(_PSG_CMD="$1" python3 - "$decide" "$rules" "$PWD" <<'PY' 2>/dev/null
import json, os, subprocess, sys
decide, rules, cwd = sys.argv[1:4]
# decide.py fails OPEN on a missing/empty/invalid rules file; validate it here first.
with open(rules, encoding="utf-8") as f:
    rr = json.load(f)
if not (isinstance(rr, dict) and isinstance(rr.get("shell_command_rules"), list)
        and rr["shell_command_rules"]):
    print("block", "rules file invalid: needs non-empty shell_command_rules (fail-closed)", sep="\t")
    sys.exit(0)
req = {"family": "security_shell", "command": os.environ["_PSG_CMD"], "cwd": cwd,
       "rules_file": rules, "resolve_command_target": False, "harness": "claude"}
r = subprocess.run([sys.executable, decide], input=json.dumps(req), capture_output=True,
                   text=True, timeout=10, check=True)
d = json.loads(r.stdout)
reason = (d.get("reason") or "").replace("\n", " ")
dec = d.get("decision", "")
if "fail-open" in reason:  # decide.py degraded to allow: never trust that here
    dec = "block"
print(dec, reason, sep="\t")
PY
        ) || {
            echo "prime-shell-guard: decide.py failed or timed out; refusing (fail-closed)" >&2
            exit 126
        }
        decision=${out%%$'\t'*}
        reason=${out#*$'\t'}
        case "$decision" in
            allow) exit 0 ;;
            block) echo "prime-shell-guard: BLOCKED by security-rules.json: $reason" >&2 ;;
            ask) echo "prime-shell-guard: requires human approval (treated as blocked, non-interactive): $reason" >&2 ;;
            *) echo "prime-shell-guard: unrecognised decision '$decision'; refusing (fail-closed)" >&2 ;;
        esac
        exit 126
    )
}

# Extract <command> from prime's `bash -c` script: `...\n{\n<prefix>\n<command>\n} 8>&- 9>&-\n__prime_status=...`
_psg_extract() { # sets _PSG_EXTRACTED ; returns 1 on unexpected shape
    local -a argv
    local script
    mapfile -d '' -t argv </proc/$$/cmdline 2>/dev/null || return 1
    [[ ${#argv[@]} -ge 3 && "${argv[1]}" == "-c" ]] || return 1
    script=${argv[2]}
    [[ "$script" == *$'\n{\n'* && "$script" == *$'\n} 8>&- 9>&-\n'* ]] || return 1
    script=${script#*$'\n{\n'}   # drop everything up to the brace group
    script=${script#*$'\n'}      # drop the (single-line) prefix itself
    script=${script%$'\n} 8>&- 9>&-\n'*}
    _PSG_EXTRACTED=$script
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    # sourced as the prefix: guard the rest of this script, never alter the caller's shell options
    if _psg_extract; then
        _psg_check "$_PSG_EXTRACTED" || exit 126
    else
        echo "prime-shell-guard: unexpected bash -c script shape; refusing (fail-closed)" >&2
        exit 126
    fi
    unset -f _psg_check _psg_extract
    unset _PSG_EXTRACTED
    return 0
fi

set -euo pipefail
if [[ $# -ne 1 ]]; then
    echo "usage: prime-shell-guard.sh '<command>'" >&2
    exit 2
fi
_psg_check "$1" || exit 126
exec bash -c "$1"
