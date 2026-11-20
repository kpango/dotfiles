#!/usr/bin/env bash
# fetch-harness-models.py: fake omp/agy binaries on PATH, no live CLI calls.
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

cat >"$TMP/bin/omp" <<'FAKE'
#!/usr/bin/env bash
[[ "$*" == "models --json --no-extensions" ]] || exit 9
echo '{"models":[{"provider":"anthropic","kind":"chat","id":"claude-opus-5-5","selector":"anthropic/claude-opus-5-5"},{"provider":"openai-codex","kind":"chat","id":"gpt-6.2-astra","selector":"openai-codex/gpt-6.2-astra"},{"provider":"x","kind":"embedding","id":"e","selector":"x/e"}]}'
FAKE
printf '#!/usr/bin/env bash\nprintf "Fetching available models...\\n"\nprintf "gemini-4-hydrogen\\tGemini 4 H\\ngemini-4-hydrogen-high\\tGemini 4 H High\\nclaude-opus-5-5-max\\tOpus Max\\ngemini-pro-orchestrator-neon\\tOrch\\n"\n' >"$TMP/bin/agy"
chmod +x "$TMP/bin/omp" "$TMP/bin/agy"
PATH="$TMP/bin:$PATH"

python3 "$FETCH" omp agy >/dev/null
check "omp ok" test "$(field omp "d['status']")" = ok
check "omp chat models only, as provider/id" test "$(field omp "','.join(d['models'])")" = "anthropic/claude-opus-5-5,openai-codex/gpt-6.2-astra"
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

# Garbage output -> unavailable
printf '#!/usr/bin/env bash\necho not-json\n' >"$TMP/bin/omp"
python3 "$FETCH" omp >/dev/null 2>&1
check "unparseable output -> unavailable" test "$(field omp "d['status']")" = unavailable

check "unknown cli rejected" bash -c "! python3 '$FETCH' bogus"

# agy SessionStart hook refreshes agy's cache and still allows the session
printf '#!/usr/bin/env bash\nprintf "gemini-4-argon\\tA\\n"\n' >"$TMP/bin/agy"
chmod +x "$TMP/bin/agy"
out="$(HOME="$TMP/home" bash "$HOOK" </dev/null)"
check "hook allows session" test "$out" = '{"continue":true,"decision":"allow"}'
check "hook refreshed agy cache" test "$(field agy "d['models'][0]")" = antigravity-cli/gemini-4-argon

echo "fetch-harness-models: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
