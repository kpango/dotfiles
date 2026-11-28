#!/usr/bin/env bash
# fetch-harness-models.py: fake pi/agy binaries on PATH, no live CLI calls.
set -euo pipefail

ROOT="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
FETCH="$ROOT/agent/scripts/fetch-harness-models.py"
HOOK="$ROOT/agent/hooks/agy/session-start.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export AGENT_MODEL_LIST_DIR="$TMP/cache"

pass=0 fail=0
check() { # desc, command...
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $desc"; fi
}
field() { python3 -c "import json,sys; d=json.load(open('$AGENT_MODEL_LIST_DIR/$1.json')); print($2)"; }

cat >"$TMP/bin/pi" <<'FAKE'
#!/usr/bin/env bash
[[ "$*" == "--list-models --no-extensions" ]] || exit 9
printf "Warning: ignored probe noise\n"
printf "provider      model              context  max-out  thinking  images\n"
printf "anthropic     claude-opus-5-5    1M       64K      yes       yes\n"
printf "openai-codex  gpt-6.2-astra      256K     32K      yes       no\n"
FAKE
printf '#!/usr/bin/env bash\nprintf "Fetching available models...\\n"\nprintf "gemini-4-hydrogen\\tGemini 4 H\\ngemini-4-hydrogen-high\\tGemini 4 H High\\nclaude-opus-5-5-max\\tOpus Max\\ngemini-pro-orchestrator-neon\\tOrch\\n"\n' >"$TMP/bin/agy"
chmod +x "$TMP/bin/pi" "$TMP/bin/agy"
PATH="$TMP/bin:$PATH"

python3 "$FETCH" pi agy >/dev/null
check "pi ok" test "$(field pi "d['status']")" = ok
check "pi models parsed from table as provider/id" test "$(field pi "','.join(d['models'])")" = "anthropic/claude-opus-5-5,openai-codex/gpt-6.2-astra"
check "agy ok" test "$(field agy "d['status']")" = ok
check "agy strips effort suffix, drops orchestrator, dedups" test "$(field agy "','.join(d['models'])")" = "antigravity-cli/claude-opus-5-5,antigravity-cli/gemini-4-hydrogen"
check "fetched_at recorded" test "$(field agy "type(d['fetched_at']).__name__")" = float

# CLI failure overwrites a previous good list with unavailable (no stale reuse)
printf '#!/usr/bin/env bash\nexit 3\n' >"$TMP/bin/agy"
python3 "$FETCH" agy >/dev/null 2>&1
check "failing CLI -> unavailable" test "$(field agy "d['status']")" = unavailable
check "failing CLI -> models emptied" test "$(field agy "len(d['models'])")" = 0

# Missing binary -> unavailable, exit 0
rm "$TMP/bin/agy"
PATH="$TMP/bin:/usr/bin:/bin" python3 "$FETCH" agy >/dev/null 2>&1
check "missing binary -> unavailable" test "$(field agy "d['status']")" = unavailable

# Warning-only output -> unavailable (empty model list)
printf '#!/usr/bin/env bash\necho "Warning: No models available."\n' >"$TMP/bin/pi"
python3 "$FETCH" pi >/dev/null 2>&1
check "empty table output -> unavailable" test "$(field pi "d['status']")" = unavailable

check "unknown cli rejected" bash -c "! python3 '$FETCH' bogus"

# agy SessionStart hook refreshes agy's cache and still allows the session
printf '#!/usr/bin/env bash\nprintf "gemini-4-argon\\tA\\n"\n' >"$TMP/bin/agy"
chmod +x "$TMP/bin/agy"
out="$(HOME="$TMP/home" bash "$HOOK" </dev/null)"
check "hook allows session" test "$out" = '{"continue":true,"decision":"allow"}'
check "hook refreshed agy cache" test "$(field agy "d['models'][0]")" = antigravity-cli/gemini-4-argon

echo "fetch-harness-models: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
