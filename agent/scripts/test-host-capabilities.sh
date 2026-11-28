#!/usr/bin/env bash
# Pi ホスト (@earendil-works/pi-coding-agent) および自己ホスト型拡張の能力表明を検証する。
#
# 契約:
# - ホストパッケージが見つからない場合 (Pi 未導入 / PI_HOME=/nonexistent) は
#   SKIP を出して exit 0 (CI 互換)。
# - ホストが存在する場合は dist/core/extensions/types.d.ts と自己ホスト拡張 5 件
#   (hashline-edit / lsp-client / dap-client / ttsr-guard / model-roles) の存在と
#   存在しない OMP イベント (session_stop / session_before_branch) への死んだ購読がゼロであることを検証。
#
# usage: agent/scripts/test-host-capabilities.sh
# env:   PI_HOME=<host package dir | install root>
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"
PI_SETTINGS="$ROOT/agent/harnesses/pi/settings.json"
EXT_DIR="$ROOT/agent/harnesses/pi/extensions"
EXT_LIB="$EXT_DIR/lib"

PASSES=0
FAILS=0
SKIPS=0

pass() { printf 'PASS: %s\n' "$1"; PASSES=$((PASSES + 1)); }
skip() { printf 'SKIP: %s\n' "$1"; SKIPS=$((SKIPS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }

is_pkg_dir() { [[ -f "$1/dist/core/extensions/types.d.ts" ]]; }

resolve_host_dir() {
    local cand="" dir="" real=""

    if [[ -n "${PI_HOME:-}" ]]; then
        if is_pkg_dir "$PI_HOME"; then
            printf '%s' "$PI_HOME"
        elif is_pkg_dir "$PI_HOME/node_modules/@earendil-works/pi-coding-agent"; then
            printf '%s' "$PI_HOME/node_modules/@earendil-works/pi-coding-agent"
        fi
        return 0
    fi

    if command -v pi >/dev/null 2>&1; then
        real="$(readlink -f "$(command -v pi)" 2>/dev/null || true)"
        if [[ -n "$real" && -e "$real" ]]; then
            dir="$(dirname "$real")"
            while [[ -n "$dir" && "$dir" != "/" ]]; do
                if [[ "$(basename "$dir")" == "pi-coding-agent" \
                    && "$(basename "$(dirname "$dir")")" == "@earendil-works" ]] && is_pkg_dir "$dir"; then
                    printf '%s' "$dir"
                    return 0
                fi
                dir="$(dirname "$dir")"
            done
        fi
    fi

    for cand in \
        "$HOME/.bun/install/global/node_modules/@earendil-works/pi-coding-agent" \
        "/usr/local/install/global/node_modules/@earendil-works/pi-coding-agent"; do
        if is_pkg_dir "$cand"; then
            printf '%s' "$cand"
            return 0
        fi
    done

    return 0
}

HOST_DIR="$(resolve_host_dir)"

if [[ -z "$HOST_DIR" ]]; then
    printf '=== Host Capability Conformance (Pi) ===\n'
    printf 'Host package (@earendil-works/pi-coding-agent) not found'
    [[ -n "${PI_HOME:-}" ]] && printf ' at PI_HOME=%s' "$PI_HOME"
    printf '; nothing to verify.\n'
    for name in \
        "Pi extension types (session_before_fork, agent_before_settle, agent_settled, registerVirtualModel)" \
        "Self-hosted extensions (hashline-edit, lsp-client, dap-client, ttsr-guard, model-roles)" \
        "Zero dead OMP subscriptions (session_stop, session_before_branch)" \
        "RLM: RLM_BACKEND passthrough and config absence" \
        "ObservationPack: 10240B threshold + session-dir archive path"; do
        skip "$name (host absent)"
    done
    printf -- '---\npass=%d fail=%d skip=%d\n' "$PASSES" "$FAILS" "$SKIPS"
    printf 'RESULT: SKIP\n'
    exit 0
fi

display_path() {
    local file="$1"
    case "$file" in
        "$HOST_DIR"/*) printf '%s' "host:${file#"$HOST_DIR"/}" ;;
        "$ROOT"/*) printf '%s' "${file#"$ROOT"/}" ;;
        *) printf '%s' "$file" ;;
    esac
}

evidence() {
    local file="$1" pattern="$2" hit=""
    hit="$(grep -nE -- "$pattern" "$file" 2>/dev/null | head -n 1 || true)"
    [[ -n "$hit" ]] || return 0
    printf '%s:%s' "$(display_path "$file")" "$hit"
}

echo "=== Host Capability Conformance (Pi) ==="
echo "host: $HOST_DIR"
echo

echo "[ Pi 1.7.0 ExtensionAPI Types ]"
EXT_TYPES="$HOST_DIR/dist/core/extensions/types.d.ts"
for sym in session_before_fork agent_before_settle agent_settled registerVirtualModel; do
    ev="$(evidence "$EXT_TYPES" "$sym")"
    if [[ -n "$ev" ]]; then
        pass "ExtensionAPI declares $sym [$ev]"
    else
        fail "ExtensionAPI missing $sym ($(display_path "$EXT_TYPES"))"
    fi
done

checkpoint="$EXT_DIR/git-checkpoint.ts"
cp_ev="$(evidence "$checkpoint" 'session_before_fork')"
if [[ -n "$cp_ev" ]]; then
    pass "git-checkpoint.ts registers session_before_fork [$cp_ev]"
else
    fail "git-checkpoint.ts does not register session_before_fork"
fi

stop_v="$EXT_DIR/stop-verify.ts"
sv_ev="$(evidence "$stop_v" 'agent_before_settle')"
if [[ -n "$sv_ev" ]]; then
    pass "stop-verify.ts registers agent_before_settle [$sv_ev]"
else
    fail "stop-verify.ts does not register agent_before_settle"
fi

for dead_ev in session_stop session_before_branch; do
    dead_hits=""
    for dir in "$EXT_DIR" "$ROOT/agent/hooks/pi"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r f; do
            hit="$(grep -nE -- "pi\.on\(['\"]${dead_ev}['\"]" "$f" 2>/dev/null | head -n 1 || true)"
            if [[ -n "$hit" ]]; then
                dead_hits="${f#"$ROOT"/}:$hit"
                break 2
            fi
        done < <(find "$dir" -maxdepth 2 -type f -name '*.ts' 2>/dev/null | sort)
    done
    if [[ -n "$dead_hits" ]]; then
        fail "handler subscribes to dead OMP event $dead_ev [$dead_hits]"
    else
        pass "zero dead OMP subscriptions for $dead_ev"
    fi
done
echo

echo "[ Self-Hosted Local Extensions & Settings ]"
for ext in hashline-edit.ts lsp-client.ts dap-client.ts ttsr-guard.ts model-roles.ts; do
    if [[ -f "$EXT_DIR/$ext" ]]; then
        pass "self-hosted extension present: $ext"
    else
        fail "self-hosted extension missing: $EXT_DIR/$ext"
    fi
done

if [[ -f "$PI_SETTINGS" ]] && grep -qF 'npm:@estebanforge/pi-antigravity-bridge@1.16.0' "$PI_SETTINGS"; then
    pass "settings.json pins npm:@estebanforge/pi-antigravity-bridge@1.16.0"
else
    fail "settings.json missing pinned @estebanforge/pi-antigravity-bridge@1.16.0"
fi
echo

echo "[ RLM ]"
repl_core="$EXT_LIB/repl-context-core.ts"
if [[ -f "$repl_core" ]] && grep -qE 'RLM_ENV_PASSTHROUGH.*RLM_BACKEND|RLM_BACKEND"' "$repl_core"; then
    pass "repl core passes RLM_BACKEND through"
else
    fail "repl core missing or does not pass RLM_BACKEND"
fi

if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    mapfile -t cfg_files < <(git -C "$ROOT" ls-files -co --exclude-standard -- \
        '*.yml' '*.yaml' '*.json' '*.toml' '*.sh' '*.bash' '*.zsh' '*.conf' \
        '*.env' '*.service' '*.mk' 'Makefile' 2>/dev/null \
        | grep -vE '^(\.claude|\.trail|node_modules)/' | sort)
else
    mapfile -t cfg_files < <(cd "$ROOT" && find . -type f \
        \( -name '*.yml' -o -name '*.yaml' -o -name '*.json' -o -name '*.toml' \
        -o -name '*.sh' -o -name '*.bash' -o -name '*.zsh' -o -name '*.conf' \
        -o -name '*.env' -o -name '*.service' -o -name '*.mk' -o -name 'Makefile' \) \
        -not -path './.git/*' -not -path './.trail/*' -not -path './.claude/*' \
        -not -path './node_modules/*' 2>/dev/null | sed 's|^\./||' | sort)
fi

rlm_cfg_hits=""
scanned=0
for rel in "${cfg_files[@]:-}"; do
    [[ -n "$rel" ]] || continue
    case "$rel" in
        test-*.sh | */test-*.sh) continue ;;
    esac
    [[ -f "$ROOT/$rel" ]] || continue
    scanned=$((scanned + 1))
    hit="$(grep -nE -- 'RLM_BACKEND[[:space:]]*[:=]' "$ROOT/$rel" 2>/dev/null | head -n 1 || true)"
    if [[ -n "$hit" ]]; then
        rlm_cfg_hits="$rel:$hit"
        break
    fi
done
if [[ -n "$rlm_cfg_hits" ]]; then
    fail "repo/shell config assigns RLM_BACKEND (unexpected): $rlm_cfg_hits"
else
    pass "no repo/shell config assigns RLM_BACKEND ($scanned config/shell files scanned, test fixtures excluded)"
fi

repl_ext="$EXT_DIR/repl-context.ts"
if [[ -f "$repl_ext" ]] && grep -qE 'RLM_BACKEND.*\?\? "stub"' "$repl_ext"; then
    pass "repl_query defaults to the offline stub backend"
else
    fail "repl_query missing offline default backend"
fi
echo

echo "[ ObservationPack ]"
sol_pi_core="$EXT_LIB/sol-pi-core.ts"
if [[ -f "$sol_pi_core" ]] && grep -qE 'minBytesThreshold: *10240' "$sol_pi_core"; then
    pass "observation pack threshold is 10240 bytes"
else
    fail "observation pack threshold is not 10240 bytes"
fi
if [[ -f "$sol_pi_core" ]] && grep -qE 'path\.join\(sessionDir, *"sol-pi", *"observations"\)' "$sol_pi_core"; then
    pass "archive path has a session-dir branch"
else
    fail "archive path is not resolved under the session dir"
fi
echo

printf -- '---\npass=%d fail=%d skip=%d\n' "$PASSES" "$FAILS" "$SKIPS"
if [[ "$FAILS" -gt 0 ]]; then
    echo "RESULT: FAIL"
    exit 1
fi
echo "RESULT: PASS"
exit 0
