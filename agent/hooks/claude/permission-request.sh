#!/usr/bin/env bash
# PermissionRequest hook — auto-approve safe read-only tool calls, log others
set -euo pipefail

# ~/.claude/hooks は claude/hooks/ と agent/hooks/claude/ の2ソースを合成した「merged directory」
# (per-file symlink、2026-09-03のagent-hooks-and-pi-agents-unificationミッション以降)であり、
# ディレクトリ自体はsymlinkではない — `dirname`はファイル名を落としてから評価されるため、
# `cd -P dirname($BASH_SOURCE)`だけでは(ファイル自身のsymlinkが未解決のまま)ディレクトリの
# 物理パスは実体ディレクトリへ到達しない(実測で確認済み)。`readlink -f`でファイル自身の
# symlinkを先に解決してから`dirname`する必要がある(GNU coreutils限定、sync-verify.shの
# 既存コメントと同じ制約。security-gate.sh・write-security-gate.shと同じ理由)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
RULES_FILE="$ROOT/agent/security-rules.json"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")
RULE=$(echo "$INPUT" | jq -r '.rule // ""' 2>/dev/null || echo "")

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_DIR="${HOME}/.claude/session-data"
mkdir -p "${LOG_DIR}"

allow() {
    printf '{"decision":"allow","reason":"%s"}\n' "$1"
    echo "${TIMESTAMP} permission-request: tool=${TOOL} rule=${RULE} outcome=allow" >> "${LOG_DIR}/sessions.log" || true
    exit 0
}

# If jq is unavailable, try grep-based fallback for tool extraction
if [[ "$TOOL" == "unknown" ]]; then
    TOOL=$(echo "$INPUT" | grep -oP '"tool_name"\s*:\s*"\K[^"]+' 2>/dev/null || echo "unknown")
fi

# Auto-approve for known safe read-only patterns
case "${TOOL}" in
    Read|Glob|Grep|LS)
        allow "read-only tool auto-approved"
        ;;
    Bash)
        # jq unavailable: don't fall back to a text-based reconstruction of the command.
        # An earlier grep -oP fallback here truncated on the first unescaped-looking `"`,
        # including one that was actually an escaped `\"` inside the command string — a
        # silently truncated view is worse than no view, since every check below trusts
        # $CMD to be the complete command. Passthrough unconditionally instead.
        if ! command -v jq &>/dev/null; then
            :
        else
            CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || true)
            # If command extraction failed entirely, allow (security-gate.sh is the real boundary)
            if [[ -z "$CMD" ]]; then
                allow "command extraction unavailable — security-gate.sh provides primary protection"
            fi
            # Structural guard, in place of an earlier denylist of individual shell
            # metacharacters (`;`/`&`/`|`/backtick/`$(`/`*`/`?`/`[`/`{`). Four rounds of
            # adversarial review each found a metacharacter or technique the denylist had
            # missed — process substitution (`<(`/`>(`), a bare backslash (bash resolves
            # `\n` in an unquoted word down to the literal letter `n`, so
            # ".credentials.jso\n" executes as ".credentials.json"), and others. A denylist
            # is only ever as complete as its authors' imagination; this instead allowlists
            # the character set a simple, non-chaining, non-substituting command can be
            # built from — letters, digits, space, and `.` `/` `:` `=` `,` `@` `%` `+` `~`
            # `_` `-` `'` `"` — and rejects anything containing a character outside it,
            # falling through to the normal permission flow. This can't be as complete as
            # actually parsing the command, but it can't be incrementally defeated by a
            # single new metacharacter either: the character has to not be on the list, not
            # merely be a case this list's author didn't think of.
            ALLOWED_CMD_CHARS="[^A-Za-z0-9 ._/:=,@%+~'\"-]"
            if [[ "$CMD" =~ $ALLOWED_CMD_CHARS ]]; then
                :
            # Check the cheap leading-verb allowlist before doing any of the more
            # expensive sensitive-path resolution below. A command whose verb isn't
            # even a candidate for auto-approval ends up falling through to the normal
            # permission flow either way, so there's no reason to pay for
            # eval/realpath/per-word checks on it first — this ordering doesn't change
            # the outcome for any command, only how much work an already-rejected one
            # costs (measured: a non-matching command like `npm install ...` otherwise
            # paid the full sensitive-path check for nothing).
            elif ! grep -qE \
                '^(git (status|log|diff|show|branch|tag|remote -v|describe|rev-parse)|'\
'ls\b|ll\b|la\b|cat\b|head\b|tail\b|'\
'grep\b|rg\b|find\b|wc\b|stat\b|file\b|du\b|df\b|'\
'which\b|command -v\b|type\b|echo\b|printf\b|pwd\b|'\
'python3 -m json\.tool\b|jq -r?\b|'\
'go (version|env|list)\b|cargo (--version|metadata)\b|'\
'codegraph (status|files|query|hook status)\b|'\
'graphify (query|path|explain|hook status)\b|'\
'pass show\b|'\
'paru (-Ss|-Qi|-Si|-Sl|-Ql|-Qu|-Q)\b|'\
'cargo fmt --check\b|'\
'tmux (list-sessions|list-windows|list-panes|show-options|display-message)\b|'\
'make (proto/(all|go|swagger)|license|format|lint|test|test/rust|build|update|init|help)\b|'\
'buf (lint|breaking|format|check)\b|'\
'kubectl (get|describe|logs|top|explain|api-resources|version)\b|'\
'docker (ps|logs|inspect|images|stats|version|info)\b|'\
'helm (list|status|get|version|history|show)\b|'\
'systemctl (status|is-active|is-enabled|list-units|list-timers)\b|'\
'journalctl\b|'\
'rtk (gain|discover|--version)\b|'\
'cargo (check|clippy|audit|tree)\b|'\
'rustup (show|target|toolchain)\b|'\
'npm (list|ls|outdated|audit)\b)' <<< "$CMD"; then
                :
            else
                # Check whether the command's words, interpreted the way bash actually
                # would (quote removal and tilde-expansion included), resolve to a
                # sensitive file. A naive `for word in $CMD` never performs quote
                # removal, so "cat ~/.claude/.credenti""als.json" (adjacent empty
                # quotes) reads as literal fragments split apart, never as the
                # ".credentials.json" bash itself joins them into at execution time.
                # `eval "words=($CMD)"` is safe to use here specifically *because* $CMD
                # has already passed the character whitelist above — nothing in it can
                # introduce a new command (no `$`, backtick, `(`, `;`, `&`, `|`) — so the
                # only thing eval can do with it is the word-splitting, quote-removal,
                # and tilde-expansion a real invocation would apply. Malformed quoting
                # (an unmatched `'`/`"`) makes the eval fail; treated as a hit rather
                # than silently skipping the check.
                # agent/security-rules.json の sensitive_write_path_rules を正典とする
                # (agent/hooks/claude/write-security-gate.sh・agent/hooks/agy/security-gate.shと
                # 同一データ)。以前は
                # ここに独自のハードコードリストを持っており、.gnupg/.cargo/credentials/
                # .npmrc/etc-auth/boot/sys/proc/dev/systemd等が判定漏れになっていた
                # (2026-09-03の突き合わせで発見・修正)。パターンは `(?:...)` 等PCRE構文を
                # 含むため、以下2箇所の照合は`grep -P`(PCRE)を使う — write-security-gate.sh
                # の`grep -Pqi`と同じ理由、POSIX ERE(`-E`)では非捕捉グループを解釈できない。
                SENSITIVE_PATH_PATTERN=$(jq -r '(.sensitive_write_path_rules // []) | map(.pattern) | join("|")' "$RULES_FILE" 2>/dev/null || true)
                # ルールデータ欠落・破損時は fail-safe: 判定不能な全コマンドをセンシティブ
                # 扱いにして(常にマッチする`.`へフォールバック)自動承認をスキップし、通常の
                # 確認ダイアログへ委ねる。security-gate.sh/write-security-gate.shのfail-open
                # (無条件allow)とは意図的に非対称 — ここでの誤判定コストは「確認が1回増える」
                # 程度で済むため、より安全側(fail-closed寄り)に倒す。
                [[ -z "$SENSITIVE_PATH_PATTERN" ]] && SENSITIVE_PATH_PATTERN='.'
                SENSITIVE_HIT=0
                # Blanket first pass over the raw (quote-corrected only, not yet
                # word-split) command text. The per-word loop below also extracts a
                # `--flag=value`/`-f=value` word's value for its own realpath-based
                # check, so this pass is not the only thing catching a fused flag
                # value — but it's a strictly cheaper, purely textual check that runs
                # first, and it's the only one that still works if `eval` below fails
                # to parse the command (SENSITIVE_HIT is already 1 by then) or if
                # realpath resolution of the extracted value doesn't turn up a match
                # for some other reason. Keep both; they're not fully redundant.
                if grep -qiP "$SENSITIVE_PATH_PATTERN" <<< "$CMD"; then
                    SENSITIVE_HIT=1
                elif ! eval "words=($CMD)" 2>/dev/null; then
                    SENSITIVE_HIT=1
                else
                    # Resolve each word through symlinks and re-check the *real* path,
                    # case-insensitively. A quote-corrected but otherwise literal
                    # command string still can't see that "cat ./innocuous.json"
                    # targets `.credentials.json` when innocuous.json is a symlink to
                    # it, or that "cat ~/.claude/.CREDENTIALS.JSON" is the same file on
                    # a case-insensitive filesystem (macOS's default APFS/HFS+) —
                    # `realpath -m` canonicalizes (without requiring the target to
                    # exist) and still resolves any symlink that does exist along the
                    # way. GNU coreutils only. `realpath -m -- "$value" || true` must
                    # keep going (not gate the whole check on `command -v realpath`
                    # first) when resolution fails for any reason — missing binary,
                    # BSD/macOS's `realpath` not supporting `-m`, or anything else —
                    # falling back to checking the value as written. Gating on
                    # `command -v realpath` alone previously meant a *present but
                    # `-m`-incompatible* realpath (exactly BSD/macOS) short-circuited
                    # every word to `continue` and never fell back to any check at
                    # all — silently disabling this entirely, which is worse than
                    # realpath being absent. A `--flag=value`/`-f=value` word extracts
                    # its value for this per-word symlink check too (the blanket pass
                    # above already covers such a value verbatim; this extends the
                    # same symlink-resolution coverage the blanket pass can't provide
                    # to it as well); a bare flag with no `=` carries no path and is
                    # skipped.
                    for word in "${words[@]}"; do
                        case "$word" in
                            -*=*) value="${word#*=}" ;;
                            -*) continue ;;
                            *) value="$word" ;;
                        esac
                        resolved=$(realpath -m -- "$value" 2>/dev/null) || true
                        check="${resolved:-$value}"
                        if grep -qiP "$SENSITIVE_PATH_PATTERN" <<< "$check"; then
                            SENSITIVE_HIT=1
                            break
                        fi
                    done
                fi

                if ((SENSITIVE_HIT)); then
                    :
                else
                    allow "read-only bash command auto-approved"
                fi
            fi
        fi
        ;;
esac

# Pass through — let Claude Code handle the permission dialog
echo "${TIMESTAMP} permission-request: tool=${TOOL} rule=${RULE} outcome=passthrough" >> "${LOG_DIR}/sessions.log" || true
exit 0
