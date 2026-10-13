#!/usr/bin/env bash
# CONTEXT.md "ai-env-followup-refactor" F-2: agent/hooks/claude/{post-write,session-end,
# session-start,post-tool-failure}.sh each carry an identical
#   SESSION_ID=$(printf '%s' "$INPUT" | jq -rs '<filter>' 2>/dev/null || echo unknown)
#   SESSION_ID=${SESSION_ID:-unknown}
# pair, meant to accept exactly the same session_id strings as
# agent/scripts/jev/evidence_reducer.py's _sanitize_session_id() for the inputs below (none is
# longer than 128 chars; that Python function also rejects longer ids, which the jq filter does
# not). Nothing pinned these 4 shell copies to each other or to the Python
# source before this test; the parity-test pattern (mktemp -d isolation, [OK]/[FAIL] lines,
# non-zero exit on any FAIL) follows agent/scripts/test-write-scope-parity.sh.
#
# Structure:
#   Part 1: extract the `SESSION_ID=$(printf ... jq -rs '...')` line from each of the 4 hooks
#           and assert all 4 are byte-identical (and each also carries the
#           `SESSION_ID=${SESSION_ID:-unknown}` fallback line). This is what actually pins the
#           4 copies to each other -- a change to only one copy fails here.
#   Part 2: run the (now-confirmed-shared) extracted line verbatim -- not a re-typed
#           re-implementation of it -- in a throwaway bash script with a controlled $INPUT,
#           under both LC_ALL=C and LC_ALL=en_US.UTF-8 (the latter is skipped with a note if
#           `locale -a` doesn't have it), for a fixed table of JSON inputs. Each result is
#           compared against agent/scripts/jev/evidence_reducer.py's _sanitize_session_id()
#           applied (via a small stdlib-only oracle script) to the same input's first parsed
#           JSON value -- Python is the parity oracle here, so Part 2 does not hardcode the expected
#           values; for the inputs in the table, a regression in either side that disagrees
#           with the other fails this part.
#   Part 2b: pin the jq filter's allowed set itself to CONTEXT.md F-2's [A-Za-z0-9._-] for every
#           ASCII code 0-127 (catches a change made identically to both sides).
#   Part 3: end-to-end run of all 4 hooks with $HOME redirected to a fresh, per-case tmp dir,
#           once with a valid session id and once with a path-traversal id, asserting exit 0,
#           that the resulting log file name / log line uses the first 8 chars of the valid id
#           (or "unknown" for the traversal id), and that after the run the fake $HOME holds
#           no files outside $HOME/.claude/session-data (files created and removed during the run,
#           or outside the fake $HOME such as /tmp, are not checked).
#
# Offline / HOME-independent: no external network calls (session-start.sh's supermemory
# injection is pointed at loopback port 1, expected to be closed, so it fails open deterministically instead of depending on
# whatever supermemory server may or may not be running on this machine), no real desktop
# notification (post-tool-failure.sh's dunstify call is shadowed by a no-op stub on PATH), and
# every hook invocation in Part 3 runs with HOME pointed at a throwaway mktemp -d directory.
#
# usage: agent/scripts/test-hook-session-id.sh
# exit: 0 = 全テストPASS, 1 = 1件以上FAIL
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_DIR="$ROOT/agent/hooks/claude"
JEV_DIR="$ROOT/agent/scripts/jev"

HOOKS=(
    "$HOOKS_DIR/post-write.sh"
    "$HOOKS_DIR/session-end.sh"
    "$HOOKS_DIR/session-start.sh"
    "$HOOKS_DIR/post-tool-failure.sh"
)

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
pass() { echo "[OK] $1"; }
fail() { echo "[FAIL] $1"; total_fail=$((total_fail + 1)); }
trap cleanup EXIT

total_fail=0

echo "=== Part 1: SESSION_ID line byte-identical across the 4 hooks ==="
SESSION_LINE=""
for h in "${HOOKS[@]}"; do
    line="$(grep -F 'SESSION_ID=$(printf' "$h" | head -1 || true)"
    if [[ -z "$line" ]]; then
        fail "$h: no 'SESSION_ID=\$(printf ...)' line found"
        continue
    fi
    if grep -qxF 'SESSION_ID=${SESSION_ID:-unknown}' "$h"; then
        pass "$h: has the exact line SESSION_ID=\${SESSION_ID:-unknown}"
    else
        fail "$h: missing SESSION_ID=\${SESSION_ID:-unknown} fallback line"
    fi
    if [[ -z "$SESSION_LINE" ]]; then
        SESSION_LINE="$line"
        pass "$h: captured as reference SESSION_ID line"
    elif [[ "$line" == "$SESSION_LINE" ]]; then
        pass "$h: byte-identical to reference"
    else
        fail "$h: differs from reference SESSION_ID line"
        echo "  ref : $SESSION_LINE"
        echo "  this: $line"
    fi
done

if [[ -z "$SESSION_LINE" ]]; then
    echo "[FAIL] could not extract a SESSION_ID line from any hook; skipping Part 2/3"
    echo "---"
    echo "test-hook-session-id: $((total_fail + 1)) 件のFAILあり"
    exit 1
fi

# The extracted line is run on its own: it reads only $INPUT and assigns $SESSION_ID.
# set -euo pipefail mirrors each hook's own top-of-file setting; the line's own
# `2>/dev/null || echo unknown` fallback means neither -e nor pipefail change its outcome.
cat > "$WORK/run_line.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
$SESSION_LINE
printf '%s' "\$SESSION_ID"
EOF

# Python parity oracle for the inputs below: decode the first top-level JSON value, require it
# to be a JSON object, and pass its "session_id" to the real _sanitize_session_id() (imported,
# not re-implemented). For the inputs used here this gives the same result as the hooks' jq -s
# filter; it is not a general model of jq -s (which fails on any malformed part of the stream).
cat > "$WORK/oracle.py" <<'PYEOF'
import json
import sys

sys.path.insert(0, sys.argv[1])
import evidence_reducer as er  # noqa: E402


def _first_json_value(text):
    dec = json.JSONDecoder()
    i, n = 0, len(text)
    while i < n and text[i] in " \t\r\n":
        i += 1
    if i >= n:
        raise ValueError("empty input")
    value, _ = dec.raw_decode(text, i)
    return value


def main():
    raw = sys.stdin.buffer.read()
    try:
        text = raw.decode("utf-8")
        value = _first_json_value(text)
    except Exception:
        print("unknown")
        return
    if not isinstance(value, dict):
        print("unknown")
        return
    print(er._sanitize_session_id(value.get("session_id")))


if __name__ == "__main__":
    main()
PYEOF

echo
echo "=== Part 2: jq filter vs Python _sanitize_session_id() parity ==="

LOCALES=(C)
if locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
    LOCALES+=("en_US.UTF-8")
else
    echo "[SKIP] en_US.UTF-8 locale not installed on this system (per 'locale -a'); testing LC_ALL=C only"
fi

TEST_DESC=()
TEST_INPUT=()
add_case() { TEST_DESC+=("$1"); TEST_INPUT+=("$2"); }

add_case "valid: sess-abc_1.2"                          '{"session_id":"sess-abc_1.2"}'
add_case "valid: ..x (not exactly \"..\")"              '{"session_id":"..x"}'
add_case "exactly \".\""                                '{"session_id":"."}'
add_case "exactly \"..\""                                '{"session_id":".."}'
add_case "traversal: ../x"                              '{"session_id":"../x"}'
add_case "slash: a/b"                                   '{"session_id":"a/b"}'
add_case "empty string value"                           '{"session_id":""}'
add_case "embedded newline: abc\\n (\\A..\\z vs \$ anchor regression guard)" '{"session_id":"abc\n"}'
add_case "embedded NUL escape: ab\\u0000cd"              '{"session_id":"ab\u0000cd"}'
add_case "non-ASCII: café"                              '{"session_id":"café"}'
add_case "fullwidth: Ａbc"                               '{"session_id":"Ａbc"}'
add_case "leading space: \" x\""                        '{"session_id":" x"}'
add_case "number 123"                                   '{"session_id":123}'
add_case "boolean true"                                 '{"session_id":true}'
add_case "boolean false"                                '{"session_id":false}'
add_case "null"                                         '{"session_id":null}'
add_case "object {}"                                    '{"session_id":{}}'
add_case "array []"                                     '{"session_id":[]}'
add_case "missing key"                                  '{}'
add_case "non-object top-level (array)"                 '[1,2,3]'
add_case "malformed JSON"                               '{not json'
add_case "empty stdin"                                  ''
add_case "two concatenated objects (jq -s -> .[0] is the first)" '{"session_id":"abc123"}{"session_id":"def456"}'
add_case "allowed-set boundaries: AZaz09._-"            '{"session_id":"AZaz09._-"}'
# Every ASCII code 0-127 as "a<ch>b", whether inside or outside [A-Za-z0-9._-]; the character is
# built inside jq so that newline and NUL are real characters of the JSON string. Removing or
# adding any single ASCII character to the allowed set on either side changes the result for
# its input.
for _code in $(seq 0 127); do
    add_case "ASCII code $_code" "$(jq -nc --argjson c "$_code" '{session_id: ("a" + ([$c] | implode) + "b")}')"
done

for loc in "${LOCALES[@]}"; do
    echo "--- LC_ALL=$loc ---"
    for i in "${!TEST_DESC[@]}"; do
        desc="${TEST_DESC[$i]}"
        input="${TEST_INPUT[$i]}"
        set +e
        bash_out="$(INPUT="$input" LC_ALL="$loc" bash "$WORK/run_line.sh" 2>"$WORK/bash_err.txt")"
        set -e
        set +e
        py_out="$(printf '%s' "$input" | LC_ALL="$loc" python3 -B "$WORK/oracle.py" "$JEV_DIR" 2>"$WORK/py_err.txt")"
        set -e
        if [[ "$bash_out" == "$py_out" ]]; then
            pass "$desc -> '$bash_out' (bash=python)"
        else
            fail "$desc : bash='$bash_out' python='$py_out'"
        fi
    done
done

echo
echo "=== Part 2b: the jq filter's allowed set equals CONTEXT.md F-2's [A-Za-z0-9._-] ==="
# Part 2 compares the two implementations with each other, so a change made identically to
# both would not show there. This part pins the set itself: for each ASCII code 0-127, "a<ch>b"
# is kept only for the codes of [A-Za-z0-9._-] (listed by code, not by a locale-dependent
# range) and is "unknown" otherwise.
for _code in $(seq 0 127); do
    if (( _code == 45 || _code == 46 || (_code >= 48 && _code <= 57) || (_code >= 65 && _code <= 90) || _code == 95 || (_code >= 97 && _code <= 122) )); then
        _allowed=1
    else
        _allowed=0
    fi
    _input="$(jq -nc --argjson c "$_code" '{session_id: ("a" + ([$c] | implode) + "b")}')"
    _got="$(INPUT="$_input" LC_ALL=C bash "$WORK/run_line.sh" 2>/dev/null)"
    if (( _allowed )); then
        _want="$(jq -nr --argjson c "$_code" '"a" + ([$c] | implode) + "b"')"
    else
        _want="unknown"
    fi
    if [[ "$_got" == "$_want" ]]; then
        pass "2b ASCII code $_code -> '$_got'"
    else
        fail "2b ASCII code $_code : got='$_got' want='$_want'"
    fi
done

# The other two F-2 rules, as fixed expectations: exactly "." / ".." and every non-string
# value become "unknown", while other strings built only from the allowed set are kept.
while IFS=$'\t' read -r _desc _input _want; do
    _got="$(INPUT="$_input" LC_ALL=C bash "$WORK/run_line.sh" 2>/dev/null)"
    if [[ "$_got" == "$_want" ]]; then
        pass "2b $_desc -> '$_got'"
    else
        fail "2b $_desc : got='$_got' want='$_want'"
    fi
done <<'SPECEOF'
exactly "."	{"session_id":"."}	unknown
exactly ".."	{"session_id":".."}	unknown
"..."	{"session_id":"..."}	...
"..x"	{"session_id":"..x"}	..x
empty string	{"session_id":""}	unknown
trailing newline	{"session_id":"abc\n"}	unknown
two trailing newlines	{"session_id":"abc\n\n"}	unknown
trailing CR	{"session_id":"abc\r"}	unknown
leading newline	{"session_id":"\nabc"}	unknown
number 123	{"session_id":123}	unknown
number 1.5	{"session_id":1.5}	unknown
true	{"session_id":true}	unknown
false	{"session_id":false}	unknown
null	{"session_id":null}	unknown
object	{"session_id":{"a":"b"}}	unknown
array	{"session_id":["abc"]}	unknown
missing key	{}	unknown
SPECEOF

# Python side of the same rules, checked on the returned value itself (repr), so a trailing
# newline is not hidden by $() the way it is for the shell side above.
_py_fixed="$(python3 -B - "$JEV_DIR" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
import evidence_reducer as er
cases = [("abc\n", "unknown"), ("abc\n\n", "unknown"), ("abc\r", "unknown"), ("\nabc", "unknown"),
         (".", "unknown"), ("..", "unknown"), ("...", "..."), ("", "unknown"), (123, "unknown"),
         (True, "unknown"), (None, "unknown"), ("sess-abc_1.2", "sess-abc_1.2")]
for value, want in cases:
    got = er._sanitize_session_id(value)
    print(("OK" if got == want else "FAIL") + "\t" + repr(value) + "\t" + repr(got) + "\t" + repr(want))
PYEOF
)"
while IFS=$'\t' read -r _st _val _got _want; do
    if [[ "$_st" == "OK" ]]; then
        pass "2b python _sanitize_session_id($_val) -> $_got"
    else
        fail "2b python _sanitize_session_id($_val) : got=$_got want=$_want"
    fi
done <<< "$_py_fixed"
if [[ -z "$_py_fixed" ]]; then
    fail "2b python fixed-expectation check produced no output"
fi

echo "=== Part 3: end-to-end hook execution (HOME redirected per case, never the real \$HOME) ==="

VALID_ID="abcd1234efgh5678"
VALID_PREFIX="${VALID_ID:0:8}"
TRAVERSAL_ID="../x"
TRAVERSAL_PREFIX="unknown"

# Neutralizes post-tool-failure.sh's `dunstify -u critical ...` real-desktop-notification call
# so this test never pops a visible notification on a machine that happens to have dunst
# installed; `command -v dunstify` will resolve to this stub via the prepended PATH below.
STUBBIN="$WORK/stubbin"
mkdir -p "$STUBBIN"
cat > "$STUBBIN/dunstify" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUBBIN/dunstify"

assert_only_session_data() { # <fake_home> <desc>
    local fake_home="$1" desc="$2" bad
    bad="$(find "$fake_home" -type f ! -path "$fake_home/.claude/session-data/*" 2>/dev/null || true)"
    if [[ -z "$bad" ]]; then
        pass "$desc: no files left in the fake \$HOME outside \$HOME/.claude/session-data"
    else
        fail "$desc: unexpected file(s) outside \$HOME/.claude/session-data:"
        echo "$bad"
    fi
}

echo "--- post-write.sh ---"
for case_name in valid traversal; do
    if [[ "$case_name" == valid ]]; then sid="$VALID_ID"; prefix="$VALID_PREFIX"; else sid="$TRAVERSAL_ID"; prefix="$TRAVERSAL_PREFIX"; fi
    FAKE_HOME="$WORK/home-post-write-$case_name"
    RUN_CWD="$WORK/cwd-post-write-$case_name"
    mkdir -p "$FAKE_HOME" "$RUN_CWD"
    input_json="$(jq -n --arg sid "$sid" '{session_id:$sid, tool_input:{file_path:"/tmp/fake-post-write-test.log"}}')"
    set +e
    ( cd "$RUN_CWD" && printf '%s' "$input_json" | env HOME="$FAKE_HOME" bash "${HOOKS[0]}" ) >"$WORK/out.txt" 2>"$WORK/err.txt"
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
        pass "post-write.sh ($case_name): exit 0"
    else
        fail "post-write.sh ($case_name): exit $rc"
    fi
    log_file="$FAKE_HOME/.claude/session-data/${prefix}-writes.log"
    if [[ -f "$log_file" ]] && grep -qF "write: /tmp/fake-post-write-test.log" "$log_file"; then
        pass "post-write.sh ($case_name): wrote $log_file with expected content"
    else
        fail "post-write.sh ($case_name): expected log file $log_file (with write: line) not found as expected"
    fi
    assert_only_session_data "$FAKE_HOME" "post-write.sh ($case_name)"
done

echo "--- session-end.sh ---"
for case_name in valid traversal; do
    if [[ "$case_name" == valid ]]; then sid="$VALID_ID"; prefix="$VALID_PREFIX"; else sid="$TRAVERSAL_ID"; prefix="$TRAVERSAL_PREFIX"; fi
    FAKE_HOME="$WORK/home-session-end-$case_name"
    RUN_CWD="$WORK/cwd-session-end-$case_name"
    mkdir -p "$FAKE_HOME/.claude/session-data" "$RUN_CWD"
    start_file="$FAKE_HOME/.claude/session-data/.session-${prefix}.start"
    date +%s > "$start_file"
    input_json="$(jq -n --arg sid "$sid" '{session_id:$sid, turn_count:3}')"
    set +e
    ( cd "$RUN_CWD" && printf '%s' "$input_json" | env HOME="$FAKE_HOME" bash "${HOOKS[1]}" ) >"$WORK/out.txt" 2>"$WORK/err.txt"
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
        pass "session-end.sh ($case_name): exit 0"
    else
        fail "session-end.sh ($case_name): exit $rc"
    fi
    if [[ ! -e "$start_file" ]]; then
        pass "session-end.sh ($case_name): consumed .session-${prefix}.start (proves SESSION_ID:0:8 == $prefix)"
    else
        fail "session-end.sh ($case_name): .session-${prefix}.start was not consumed as expected"
    fi
    sessions_log="$FAKE_HOME/.claude/session-data/sessions.log"
    if [[ -f "$sessions_log" ]] && grep -q "session-end.*duration=.*turns=3" "$sessions_log"; then
        pass "session-end.sh ($case_name): sessions.log has session-end/duration/turns line"
    else
        fail "session-end.sh ($case_name): sessions.log missing expected session-end line"
    fi
    assert_only_session_data "$FAKE_HOME" "session-end.sh ($case_name)"
done

echo "--- session-start.sh ---"
for case_name in valid traversal; do
    if [[ "$case_name" == valid ]]; then sid="$VALID_ID"; prefix="$VALID_PREFIX"; else sid="$TRAVERSAL_ID"; prefix="$TRAVERSAL_PREFIX"; fi
    FAKE_HOME="$WORK/home-session-start-$case_name"
    RUN_CWD="$WORK/cwd-session-start-$case_name"
    mkdir -p "$FAKE_HOME" "$RUN_CWD"
    input_json="$(jq -n --arg sid "$sid" '{session_id:$sid}')"
    set +e
    # SUPERMEMORY_API_URL points at a closed loopback port (nothing listens there) so
    # sm_inject() fails fast and deterministically instead of depending on whether this
    # machine happens to be running a real supermemory server on its default port.
    ( cd "$RUN_CWD" && printf '%s' "$input_json" | env HOME="$FAKE_HOME" SUPERMEMORY_API_URL="http://127.0.0.1:1" bash "${HOOKS[2]}" ) >"$WORK/out.txt" 2>"$WORK/err.txt"
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
        pass "session-start.sh ($case_name): exit 0"
    else
        fail "session-start.sh ($case_name): exit $rc"
    fi
    if jq -e '.continue == true' "$WORK/out.txt" >/dev/null 2>&1; then
        pass "session-start.sh ($case_name): stdout is valid hook-output JSON with continue:true"
    else
        fail "session-start.sh ($case_name): stdout is not the expected JSON"
    fi
    sessions_log="$FAKE_HOME/.claude/session-data/sessions.log"
    if [[ -f "$sessions_log" ]] && grep -qF "Session started: ${prefix} cwd=" "$sessions_log"; then
        pass "session-start.sh ($case_name): sessions.log line uses ${prefix}"
    else
        fail "session-start.sh ($case_name): sessions.log missing 'Session started: ${prefix} cwd='"
    fi
    start_files="$(find "$FAKE_HOME/.claude/session-data" -maxdepth 1 -name '.session-*.start' -printf '%f\n' 2>/dev/null)"
    if [[ "$start_files" == ".session-${prefix}.start" ]]; then
        pass "session-start.sh ($case_name): start file is .session-${prefix}.start"
    else
        fail "session-start.sh ($case_name): start files '${start_files}', want '.session-${prefix}.start'"
    fi
    assert_only_session_data "$FAKE_HOME" "session-start.sh ($case_name)"
done

echo "--- post-tool-failure.sh ---"
for case_name in valid traversal; do
    if [[ "$case_name" == valid ]]; then sid="$VALID_ID"; prefix="$VALID_PREFIX"; else sid="$TRAVERSAL_ID"; prefix="$TRAVERSAL_PREFIX"; fi
    FAKE_HOME="$WORK/home-post-tool-failure-$case_name"
    RUN_CWD="$WORK/cwd-post-tool-failure-$case_name"
    mkdir -p "$FAKE_HOME" "$RUN_CWD"
    input_json="$(jq -n --arg sid "$sid" '{session_id:$sid, tool_name:"Bash", error:"boom"}')"
    set +e
    ( cd "$RUN_CWD" && printf '%s' "$input_json" | env HOME="$FAKE_HOME" PATH="$STUBBIN:$PATH" bash "${HOOKS[3]}" ) >"$WORK/out.txt" 2>"$WORK/err.txt"
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
        pass "post-tool-failure.sh ($case_name): exit 0"
    else
        fail "post-tool-failure.sh ($case_name): exit $rc"
    fi
    sessions_log="$FAKE_HOME/.claude/session-data/sessions.log"
    failures_log="$FAKE_HOME/.claude/session-data/tool-failures.log"
    if [[ -f "$sessions_log" ]] && grep -qF "TOOL_FAILURE session=${prefix} Bash: boom" "$sessions_log"; then
        pass "post-tool-failure.sh ($case_name): sessions.log line uses session=${prefix}"
    else
        fail "post-tool-failure.sh ($case_name): sessions.log missing expected TOOL_FAILURE line"
    fi
    if [[ -f "$failures_log" ]] && grep -qF "session=${prefix} tool=Bash: boom" "$failures_log"; then
        pass "post-tool-failure.sh ($case_name): tool-failures.log line uses session=${prefix}"
    else
        fail "post-tool-failure.sh ($case_name): tool-failures.log missing expected line"
    fi
    assert_only_session_data "$FAKE_HOME" "post-tool-failure.sh ($case_name)"
done

echo
echo "---"
if [[ "$total_fail" -gt 0 ]]; then
    echo "test-hook-session-id: $total_fail 件のFAILあり"
    exit 1
fi
echo "test-hook-session-id: 全テストPASS"
exit 0
