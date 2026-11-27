#!/usr/bin/env bash
# ホスト(OMP = @oh-my-pi/pi-coding-agent)の能力表明が実物と一致しているかを検証する。
#
# 背景: ハーネス側のドキュメント/拡張は「hashline編集モード」「session_before_fork(旧)」
# 「evalの永続セッション状態」「RLM(repl_query)」「ObservationPack」といったホスト機能を
# 前提にしている。ホストはリポジトリ外の npm パッケージであり、バージョン更新で型定義だけが
# 静かに変わるため、リポジトリ側の主張が「存在しないAPIへの購読(dead handler)」に化ける。
# 本スクリプトはその乖離を、ホストの .d.ts とリポジトリ設定の双方を突き合わせて機械検出する。
#
# 契約:
# - ホストパッケージが見つからない場合(OMP未導入、`OMP_HOME=/nonexistent` 等)は
#   何も主張せず SKIP: を並べて exit 0。CIでホスト無しでも緑になる。
# - 必須チェックが落ちるのは「ホストが存在する かつ 表明が偽」のときだけ。
# - pass/fail の根拠は file:line、集計行は件数のみ。実行はしない(型定義と設定のgrepのみ)。
#
# usage: agent/scripts/test-host-capabilities.sh
# env:   OMP_HOME=<host package dir | install root>  ホスト解決の上書き(存在しなければSKIP)

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"
OMP_CONFIG="$ROOT/agent/harnesses/omp/config.yml"
EXT_LIB="$ROOT/agent/harnesses/omp/extensions/lib"

PASSES=0
FAILS=0
SKIPS=0

pass() { printf 'PASS: %s\n' "$1"; PASSES=$((PASSES + 1)); }
skip() { printf 'SKIP: %s\n' "$1"; SKIPS=$((SKIPS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }

# パッケージディレクトリ(dist/types を持つ)かを判定する。
is_pkg_dir() { [[ -d "$1/dist/types" ]]; }

# ホストパッケージを解決する。$OMP_HOME は「上書き」であり、無効ならフォールバックしない
# (未導入のシミュレーションを効かせるため)。
resolve_host_dir() {
    local cand="" dir="" real=""

    if [[ -n "${OMP_HOME:-}" ]]; then
        if is_pkg_dir "$OMP_HOME"; then
            printf '%s' "$OMP_HOME"
        elif is_pkg_dir "$OMP_HOME/node_modules/@oh-my-pi/pi-coding-agent"; then
            printf '%s' "$OMP_HOME/node_modules/@oh-my-pi/pi-coding-agent"
        fi
        return 0
    fi

    if command -v omp >/dev/null 2>&1; then
        real="$(readlink -f "$(command -v omp)" 2>/dev/null || true)"
        if [[ -n "$real" && -e "$real" ]]; then
            dir="$(dirname "$real")"
            while [[ -n "$dir" && "$dir" != "/" ]]; do
                if [[ "$(basename "$dir")" == "pi-coding-agent" \
                    && "$(basename "$(dirname "$dir")")" == "@oh-my-pi" ]] && is_pkg_dir "$dir"; then
                    printf '%s' "$dir"
                    return 0
                fi
                dir="$(dirname "$dir")"
            done
        fi
    fi

    cand="/usr/local/install/global/node_modules/@oh-my-pi/pi-coding-agent"
    if is_pkg_dir "$cand"; then
        printf '%s' "$cand"
        return 0
    fi

    return 0
}

HOST_DIR="$(resolve_host_dir)"

if [[ -z "$HOST_DIR" ]]; then
    printf '=== Host Capability Conformance (OMP) ===\n'
    printf 'Host package (@oh-my-pi/pi-coding-agent) not found'
    [[ -n "${OMP_HOME:-}" ]] && printf ' at OMP_HOME=%s' "$OMP_HOME"
    printf '; nothing to verify.\n'
    for name in \
        "hashline: edit mode + repo config" \
        "session tree: session_before_branch / session_before_fork" \
        "eval: py/js + persistent session state (host-only)" \
        "RLM: RLM_BACKEND passthrough and config absence" \
        "observation pack: 10240B threshold + session-dir archive path"; do
        skip "$name (host absent)"
    done
    printf -- '---\npass=%d fail=%d skip=%d\n' "$PASSES" "$FAILS" "$SKIPS"
    printf 'RESULT: SKIP\n'
    exit 0
fi

# 拡張子違い(.ts/.d.ts)を吸収して実在する最初のファイルを返す。
pick_file() {
    local base="$1" cand
    for cand in "$base" "$base.d.ts" "$base.ts"; do
        if [[ -f "$cand" ]]; then
            printf '%s' "$cand"
            return 0
        fi
    done
    return 1
}

# 根拠表示用に、ホスト/リポジトリ配下は相対パスへ短縮する。
display_path() {
    local file="$1"
    case "$file" in
        "$HOST_DIR"/*) printf '%s' "host:${file#"$HOST_DIR"/}" ;;
        "$ROOT"/*) printf '%s' "${file#"$ROOT"/}" ;;
        *) printf '%s' "$file" ;;
    esac
}

# パターンに最初に一致した行を "path:line:content" で返す(根拠表示用)。
evidence() {
    local file="$1" pattern="$2" hit=""
    hit="$(grep -nE -- "$pattern" "$file" 2>/dev/null | head -n 1 || true)"
    [[ -n "$hit" ]] || return 0
    printf '%s:%s' "$(display_path "$file")" "$hit"
}

echo "=== Host Capability Conformance (OMP) ==="
echo "host: $HOST_DIR"
echo

# ---------------------------------------------------------------------------
# 1. hashline 編集モード
# ---------------------------------------------------------------------------
echo "[ hashline ]"
edit_index="$(pick_file "$HOST_DIR/dist/types/edit/index" || true)"
edit_settings="$(pick_file "$HOST_DIR/dist/types/edit/settings" || true)"

if [[ -z "$edit_index" || -z "$edit_settings" ]]; then
    fail "hashline type declarations missing (dist/types/edit/{index,settings}.d.ts)"
else
    ev="$(evidence "$edit_index" 'hashline')"
    if [[ -n "$ev" ]]; then
        pass "edit/index declares hashline [$ev]"
    else
        fail "edit/index does not mention hashline ($edit_index)"
    fi

    # 編集モードの union が hashline を含むこと(EDIT_MODES または cfgEditMode の型)。
    ev="$(evidence "$edit_settings" '"apply_patch".*"hashline"|"hashline".*"apply_patch"')"
    if [[ -n "$ev" ]]; then
        pass "edit/settings edit-mode union includes hashline [$ev]"
    else
        ev="$(evidence "$edit_settings" 'hashline')"
        fail "edit/settings edit-mode union lacks hashline ($edit_settings${ev:+; only: $ev})"
    fi
fi

if [[ ! -f "$OMP_CONFIG" ]]; then
    fail "harness config missing: $OMP_CONFIG"
else
    # edit: ブロック配下の mode を厳密に拾う(他セクションの mode: を誤認しない)。
    ev="$(awk '
        /^edit:[[:space:]]*$/ { inblock = 1; next }
        inblock && /^[^[:space:]#]/ { inblock = 0 }
        inblock && /^[[:space:]]+mode:[[:space:]]*hashline[[:space:]]*$/ { print FNR ":" $0; exit }
    ' "$OMP_CONFIG")"
    if [[ -n "$ev" ]]; then
        pass "repo config resolves edit.mode=hashline [$(display_path "$OMP_CONFIG"):$ev]"
    else
        fail "repo config edit.mode is not hashline ($(display_path "$OMP_CONFIG"))"
    fi
fi

echo

# ---------------------------------------------------------------------------
# 2. セッションツリーイベント
# ---------------------------------------------------------------------------
echo "[ session tree ]"
session_types="$(pick_file "$HOST_DIR/dist/types/extensibility/extensions/types" || true)"
if [[ -z "$session_types" ]]; then
    fail "extension event types missing (dist/types/extensibility/extensions/types.{ts,d.ts})"
else
    ev="$(evidence "$session_types" 'session_before_branch')"
    if [[ -n "$ev" ]]; then
        pass "session_before_branch is declared [$ev]"
    else
        fail "session_before_branch is NOT declared ($session_types)"
    fi

    # repo invariant: git-checkpoint must register the host's branch event and gate on fork.
    checkpoint="$ROOT/agent/harnesses/omp/extensions/git-checkpoint.ts"
    if [[ ! -f "$checkpoint" ]]; then
        fail "git-checkpoint.ts missing: $(display_path "$checkpoint")"
    else
        cp_ev="$(evidence "$checkpoint" 'session_before_branch')"
        if [[ -n "$cp_ev" ]]; then
            pass "git-checkpoint.ts registers session_before_branch [$cp_ev]"
        else
            fail "git-checkpoint.ts does not register session_before_branch ($(display_path "$checkpoint"))"
        fi
        if grep -qF 'event.reason !== "fork"' "$checkpoint"; then
            pass "git-checkpoint.ts gates on reason=fork"
        else
            fail "git-checkpoint.ts does not gate on reason=fork ($(display_path "$checkpoint"))"
        fi
    fi

    for dead_ev in session_before_fork agent_settled session_compact_failed; do
        ev_line="$(evidence "$session_types" "$dead_ev")"
        if [[ -n "$ev_line" ]]; then
            pass "$dead_ev is declared [$ev_line]"
            continue
        fi
        dead_hits=""
        for dir in "$ROOT/agent/harnesses/omp/extensions" "$ROOT/agent/hooks/omp"; do
            [[ -d "$dir" ]] || continue
            while IFS= read -r f; do
                hit="$(grep -nE -- "pi\.on\(['\"]${dead_ev}['\"]" "$f" 2>/dev/null | head -n 1 || true)"
                if [[ -n "$hit" ]]; then
                    dead_hits="${f#"$ROOT"/}:$hit"
                    break 2
                fi
            done < <(find "$dir" -type f -name '*.ts' 2>/dev/null | sort)
        done
        if [[ -n "$dead_hits" ]]; then
            fail "a handler subscribes to the non-existent $dead_ev [$dead_hits]"
        else
            pass "$dead_ev absent and no handler subscribes to it"
        fi
    done
fi
echo

# ---------------------------------------------------------------------------
# 3. eval: 言語トークンと永続セッション状態(ホスト固有、サンドボックス主張なし)
# ---------------------------------------------------------------------------
echo "[ eval ]"
eval_types="$(pick_file "$HOST_DIR/dist/types/tools/eval" || true)"
if [[ -z "$eval_types" ]]; then
    fail "eval tool types missing (dist/types/tools/eval.d.ts)"
else
    ev="$(evidence "$eval_types" 'EvalLanguageToken')"
    if [[ -n "$ev" ]] && grep -qE '"py"|"js"' "$eval_types"; then
        pass "eval language union is py|js, HOST-ONLY (no sandbox claim) [$ev]"
    else
        fail "eval language union missing py/js ($eval_types)"
    fi

    ev_reset="$(evidence "$eval_types" 'reset\??: *boolean')"
    ev_timeout="$(evidence "$eval_types" 'timeout\??: *number')"
    if [[ -n "$ev_reset" && -n "$ev_timeout" ]]; then
        pass "eval carries persistent-session controls [$ev_reset] [$ev_timeout]"
    else
        fail "eval lacks reset/timeout session-state params ($eval_types)"
    fi
fi
echo

# ---------------------------------------------------------------------------
# 4. RLM: RLM_BACKEND のパススルーと、設定側での不在
# ---------------------------------------------------------------------------
echo "[ RLM ]"
repl_core="$EXT_LIB/repl-context-core.ts"
if [[ ! -f "$repl_core" ]]; then
    fail "repl-context-core.ts missing: $repl_core"
else
    ev="$(evidence "$repl_core" 'RLM_ENV_PASSTHROUGH.*RLM_BACKEND|RLM_BACKEND"')"
    if [[ -n "$ev" ]]; then
        pass "repl core passes RLM_BACKEND through [$ev]"
    else
        fail "repl core does not pass RLM_BACKEND ($repl_core)"
    fi

    # リポジトリ内の設定/shell設定が RLM_BACKEND を代入していないこと。
    # 走査対象は「設定フォーマットのみ」: .py/.md の散文に書かれた env 名の説明文を
    # 代入と誤認しないため。grep の --include/--exclude 併用はこの環境のGNU grep 3.12で
    # 順序依存の取りこぼしが起きるので使わず、ファイル列挙は git ls-files -co(無ければ find)で行う。
    # -co --exclude-standard は未追跡の設定も含む。テストフィクスチャ(agent/scripts/test-*.sh)は
    # 意図的な代入なので除外する。Makefile は `Makefile` と `*.mk` を明示し、git の
    # `Makefile*` pathspec が Makefile.d/scripts/* まで拾う非対称を避ける。
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

    if (( ${#cfg_files[@]} == 0 )); then
        fail "config enumeration produced no files (check the git ls-files/find paths)"
    else
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
    fi

    repl_ext="$ROOT/agent/harnesses/omp/extensions/repl-context.ts"
    ev="$(evidence "$repl_ext" 'RLM_BACKEND.*\?\? "stub"')"
    if [[ -n "$ev" ]]; then
        pass "repl_query defaults to the offline stub backend [$ev]"
    else
        fail "repl_query has no offline default backend ($(display_path "$repl_ext"))"
    fi
fi
echo

# ---------------------------------------------------------------------------
# 5. ObservationPack: 閾値とアーカイブ先(実行はしない)
# ---------------------------------------------------------------------------
echo "[ observation pack ]"
sol_pi_core="$EXT_LIB/sol-pi-core.ts"
if [[ ! -f "$sol_pi_core" ]]; then
    fail "sol-pi-core.ts missing: $sol_pi_core"
else
    ev="$(evidence "$sol_pi_core" 'minBytesThreshold: *10240')"
    if [[ -n "$ev" ]]; then
        pass "observation pack threshold is 10240 bytes [$ev]"
    else
        fail "observation pack threshold is not 10240 bytes ($sol_pi_core)"
    fi

    ev="$(evidence "$sol_pi_core" 'path\.join\(sessionDir, *"sol-pi", *"observations"\)')"
    if [[ -n "$ev" ]]; then
        pass "archive path has a session-dir branch [$ev]"
    else
        fail "archive path is not resolved under the session dir ($sol_pi_core)"
    fi
fi
echo

printf -- '---\npass=%d fail=%d skip=%d\n' "$PASSES" "$FAILS" "$SKIPS"

if [[ "$FAILS" -gt 0 ]]; then
    echo "RESULT: FAIL"
    exit 1
fi
echo "RESULT: PASS"
exit 0
