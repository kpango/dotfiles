#!/usr/bin/env bash
# Regression test for agent/scripts/hooks/supermemory.sh (the shared Bash local supermemory client).
# Verifies the public contract of sm_endpoint / sm_search / sm_inject / sm_ingest / sm_document
# entirely offline via a loopback (127.0.0.1) mock HTTP server, never connecting to a real provider.
#
# Contract (required spec. Items the current implementation does not yet satisfy are intentional
# RED = expected behavior):
#   - sm_endpoint: only allows http://localhost[:port] / http://127.0.0.1[:port] / http://[::1][:port]
#     (trailing slash tolerated). Rejects userinfo/path/query/fragment/non-loopback with non-zero,
#     and never silently substitutes an invalid config value with the default.
#   - sm_search: returns validated JSON with a results array, or fails non-zero on
#     HTTP/transport/malformed failures (including a plausible-looking HTTP 302 JSON body and
#     concatenated multi-JSON-object responses).
#   - sm_inject: masks all read failures (including partial responses and HTTP 302) as an exit-0
#     empty string.
#   - sm_ingest FILE TAG: returns {id: non-empty string, status: a known success/non-terminal
#     status} only on acceptance (queued is a valid acceptance but is not treated as done).
#     Missing/empty file, missing tool, HTTP error (even with an id in the body), HTTP 302 (even
#     with a plausible JSON body), timeout, malformed/concatenated-multi-JSON responses, missing/
#     unknown status, empty id, and failed/unknown status must all fail non-zero and must not emit
#     success stdout. A normal-sized ~200KiB single Markdown document must also be accepted
#     successfully (the implementation must not depend on argv and hit something like Linux's
#     MAX_ARG_STRLEN limit).
#   - sm_document ID: fetches {id,status,memories: array (returns the count)} via
#     GET /v3/documents/ID. A live metadata-only GET probe against the real service showed that
#     `memories` is a JSON array (18 entries observed), not a number, so the mock fixtures below
#     uniformly use an array for `memories` (the helper's own output still reports the array
#     length as a number). Numeric/missing/object/string-typed memories are rejected. Fetching a
#     failed status itself is allowed (the caller decides what to do with it). Unsafe IDs,
#     response id mismatched against the requested id, malformed/concatenated-multi-JSON
#     responses, and missing/unknown status values are all rejected.
#   - sm_ingest's customId is stable for a given content+tag pair (independent of the file name),
#     differs when content/tag differ, uses a safe character set, and has no truncation
#     collisions. Furthermore, concatenating tag/content must not collide even when the delimiter
#     (newline) itself appears inside the tag or content (either the delimiter must be
#     unambiguous, or such an invalid tag must be rejected).
#
# usage: agent/scripts/test-supermemory-client.sh
# exit: 0 = all tests PASS, 1 = one or more FAIL
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$ROOT/agent/scripts/hooks/supermemory.sh"
REAL_PATH="$PATH"

total_fail=0
section() { echo; echo "=== $1 ==="; }
ok() { echo "[OK] $1"; }
fail() { echo "[FAIL] $1"; total_fail=$((total_fail + 1)); }

# ------------------------------------------------------------------
# isolated fixtures (under /tmp)
# ------------------------------------------------------------------
FAKE_HOME="$(mktemp -d /tmp/sm-test-home.XXXXXX)"
MOCKDIR="$(mktemp -d /tmp/sm-test-mock.XXXXXX)"
FILES_DIR="$(mktemp -d /tmp/sm-test-files.XXXXXX)"
MOCK_CONTROL="$MOCKDIR/control.json"
MOCK_LOG="$MOCKDIR/requests.log"
: > "$MOCK_LOG"
printf '{}' > "$MOCK_CONTROL"

free_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}
MOCK_PORT="$(free_port)"
CLOSED_PORT="$(free_port)"   # intentionally never bound -> for connection refused

cat > "$MOCKDIR/server.py" << 'PYEOF'
import http.server, json, sys, threading, time

PORT = int(sys.argv[1])
CONTROL = sys.argv[2]
LOGFILE = sys.argv[3]
_log_lock = threading.Lock()

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _read_body(self):
        try:
            length = int(self.headers.get('Content-Length') or 0)
        except ValueError:
            length = 0
        return self.rfile.read(length) if length > 0 else b''

    def _load_control(self):
        try:
            with open(CONTROL, 'r') as f:
                return json.load(f)
        except Exception:
            return {}

    def _match(self, cfg):
        path_only = self.path.split('?', 1)[0]
        for r in cfg.get('routes', []):
            if r.get('method') != self.command:
                continue
            if 'path' in r and r['path'] == path_only:
                return r
            if 'path_prefix' in r and path_only.startswith(r['path_prefix']):
                return r
        return cfg.get('default', {"status": 404, "body": "{}"})

    def _handle(self):
        body = self._read_body()
        try:
            with _log_lock, open(LOGFILE, 'a') as f:
                f.write(json.dumps({
                    "method": self.command,
                    "path": self.path,
                    "headers": {k: v for k, v in self.headers.items()},
                    "body": body.decode('utf-8', 'replace'),
                }) + "\n")
        except Exception:
            pass
        cfg = self._load_control()
        route = self._match(cfg)
        delay = route.get('delay', 0)
        if delay:
            time.sleep(delay)
        if route.get('hang'):
            time.sleep(3600)
            return
        status = route.get('status', 200)
        resp_body = route.get('body', '')
        if isinstance(resp_body, (dict, list)):
            resp_body = json.dumps(resp_body)
        resp_bytes = resp_body.encode('utf-8')
        if route.get('truncate'):
            self.send_response(status)
            self.send_header('Content-Type', route.get('content_type', 'application/json'))
            self.send_header('Content-Length', str(len(resp_bytes) + 500))
            for hk, hv in route.get('extra_headers', {}).items():
                self.send_header(hk, hv)
            self.end_headers()
            try:
                self.wfile.write(resp_bytes)
                self.wfile.flush()
            except Exception:
                pass
            self.close_connection = True
            return
        self.send_response(status)
        self.send_header('Content-Type', route.get('content_type', 'application/json'))
        self.send_header('Content-Length', str(len(resp_bytes)))
        for hk, hv in route.get('extra_headers', {}).items():
            self.send_header(hk, hv)
        self.end_headers()
        try:
            self.wfile.write(resp_bytes)
        except Exception:
            pass

    def do_GET(self):
        self._handle()

    def do_POST(self):
        self._handle()

if __name__ == '__main__':
    httpd = http.server.ThreadingHTTPServer(('127.0.0.1', PORT), Handler)
    httpd.daemon_threads = True
    httpd.serve_forever()
PYEOF

python3 "$MOCKDIR/server.py" "$MOCK_PORT" "$MOCK_CONTROL" "$MOCK_LOG" > "$MOCKDIR/server.out" 2>&1 &
MOCK_PID=$!

cleanup() {
    kill "$MOCK_PID" 2>/dev/null
    wait "$MOCK_PID" 2>/dev/null
    rm -rf "$FAKE_HOME" "$MOCKDIR" "$FILES_DIR" 2>/dev/null
}
trap cleanup EXIT

# wait for the server to come up (up to 3 seconds)
for _ in $(seq 1 30); do
    curl -s -o /dev/null "http://127.0.0.1:$MOCK_PORT/" 2>/dev/null && break
    sleep 0.1
done

MOCK_URL="http://127.0.0.1:$MOCK_PORT"

# ------------------------------------------------------------------
# helpers
# ------------------------------------------------------------------

# make_path_without <tool...> -> builds a minimal PATH dir excluding the given tools and echoes it
make_path_without() {
    local excludes=("$@")
    local dir; dir="$(mktemp -d /tmp/sm-test-path.XXXXXX)"
    local tool
    for tool in bash sed tr cut mktemp printf cat basename dirname wc head jq curl python3 rm mkdir chmod grep date sleep env timeout seq; do
        local skip=0
        for e in "${excludes[@]}"; do [[ "$tool" == "$e" ]] && skip=1; done
        [[ "$skip" -eq 1 ]] && continue
        local p; p="$(command -v "$tool" 2>/dev/null)" || continue
        ln -sf "$p" "$dir/$tool"
    done
    printf '%s' "$dir"
}

log_count() { wc -l < "$MOCK_LOG" 2>/dev/null | tr -d ' '; }
last_log_line() { tail -n1 "$MOCK_LOG" 2>/dev/null; }

# run_lib <home> <extra_env_script> <call_expr> [<path>] [<timeout_secs>]
#
# NOTE: SUPERMEMORY_API_URL always defaults to the mock server here (below,
# before $extra runs), so any test that forgets to override it can never
# accidentally reach a live local supermemory service on the production
# default port. Tests that specifically need to observe sm_endpoint's *true*
# unset/default-resolution behavior must explicitly `unset SUPERMEMORY_API_URL`
# in their extra env script to undo this default.
LAST_OUT=""; LAST_CODE=0; LAST_ERR=""
run_lib() {
    local home="$1" extra="$2" call="$3" pth="${4:-$REAL_PATH}" tmo="${5:-20}"
    local errfile; errfile="$(mktemp /tmp/sm-test-err.XXXXXX)"
    LAST_OUT="$(timeout "$tmo" env -i HOME="$home" PATH="$pth" bash -c "
set -u
export SUPERMEMORY_API_URL='$MOCK_URL'
$extra
source '$LIB'
$call
" 2>"$errfile")"
    LAST_CODE=$?
    LAST_ERR="$(cat "$errfile" 2>/dev/null)"
    rm -f "$errfile"
}

expect_exit0() {
    local desc="$1"
    if [[ "$LAST_CODE" -eq 0 ]]; then ok "$desc"; else fail "$desc : expected exit=0 got=$LAST_CODE out=<<$LAST_OUT>> err=<<$LAST_ERR>>"; fi
}
expect_nonzero() {
    local desc="$1"
    if [[ "$LAST_CODE" -ne 0 ]]; then ok "$desc"; else fail "$desc : expected exit!=0 got=0 out=<<$LAST_OUT>>"; fi
}
expect_empty_stdout() {
    local desc="$1"
    if [[ -z "$LAST_OUT" ]]; then ok "$desc"; else fail "$desc : expected empty stdout got=<<$LAST_OUT>>"; fi
}
expect_stdout_contains() {
    local desc="$1" needle="$2"
    if [[ "$LAST_OUT" == *"$needle"* ]]; then ok "$desc"; else fail "$desc : expected to contain '$needle' got=<<$LAST_OUT>>"; fi
}
expect_stdout_not_contains() {
    local desc="$1" needle="$2"
    if [[ "$LAST_OUT" != *"$needle"* ]]; then ok "$desc"; else fail "$desc : did not expect '$needle' got=<<$LAST_OUT>>"; fi
}
expect_json_field() {
    local desc="$1" filter="$2" expected="$3" actual
    actual="$(printf '%s' "$LAST_OUT" | jq -r "$filter" 2>/dev/null)"
    if [[ "$actual" == "$expected" ]]; then ok "$desc"; else fail "$desc : filter=$filter expected='$expected' got='$actual' raw=<<$LAST_OUT>>"; fi
}
expect_json_results_array() {
    local desc="$1"
    if printf '%s' "$LAST_OUT" | jq -e '(.results|type)=="array"' >/dev/null 2>&1; then
        ok "$desc"
    else
        fail "$desc : .results is not an array, raw=<<$LAST_OUT>>"
    fi
}
expect_no_new_request() {
    local desc="$1" before="$2" after; after="$(log_count)"
    if [[ "$after" -eq "$before" ]]; then ok "$desc"; else fail "$desc : expected no new request, before=$before after=$after last=<<$(last_log_line)>>"; fi
}
expect_new_request() {
    local desc="$1" before="$2" after; after="$(log_count)"
    if [[ "$after" -gt "$before" ]]; then ok "$desc"; else fail "$desc : expected a new request, before=$before after=$after"; fi
}
expect_regex() {
    local desc="$1" value="$2" re="$3"
    if [[ "$value" =~ $re ]]; then ok "$desc"; else fail "$desc : value='$value' does not match /$re/"; fi
}

route_exact() {
    local method="$1" path="$2" status="$3" body="$4" extra="${5:-{\}}"
    jq -nc --arg m "$method" --arg p "$path" --argjson st "$status" --arg b "$body" --argjson ex "$extra" \
        '{routes:[({method:$m, path:$p, status:$st, body:$b} + $ex)], default:{status:404, body:"{}"}}'
}
route_prefix() {
    local method="$1" prefix="$2" status="$3" body="$4" extra="${5:-{\}}"
    jq -nc --arg m "$method" --arg p "$prefix" --argjson st "$status" --arg b "$body" --argjson ex "$extra" \
        '{routes:[({method:$m, path_prefix:$p, status:$st, body:$b} + $ex)], default:{status:404, body:"{}"}}'
}
set_route() { printf '%s' "$1" > "$MOCK_CONTROL"; }

# ==================================================================
section "sm_endpoint: valid loopback forms are accepted"
# ==================================================================
run_lib "$FAKE_HOME" "unset SUPERMEMORY_API_URL" "sm_endpoint"; expect_exit0 "env unset -> default http://localhost:6767"
expect_stdout_contains "env unset: returns the default URL" "http://localhost:6767"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='http://localhost:6767'" "sm_endpoint"
expect_exit0 "http://localhost:6767 is valid"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='http://localhost'" "sm_endpoint"; expect_exit0 "http://localhost (port omitted) is valid"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='http://127.0.0.1:9999'" "sm_endpoint"; expect_exit0 "http://127.0.0.1:9999 is valid"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='http://127.0.0.1'" "sm_endpoint"; expect_exit0 "http://127.0.0.1 (port omitted) is valid"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='http://[::1]:6767'" "sm_endpoint"; expect_exit0 "http://[::1]:6767 is valid"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='http://[::1]'" "sm_endpoint"; expect_exit0 "http://[::1] (port omitted) is valid"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='http://localhost:6767/'" "sm_endpoint"
expect_exit0 "trailing slash is valid"
expect_stdout_not_contains "trailing slash is normalized away" "6767/"

section "sm_endpoint: invalid forms are rejected non-zero (never silently substituted with the default)"
invalid_endpoint_case() {
    local desc="$1" val="$2"
    run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$val'" "sm_endpoint"
    expect_nonzero "$desc: rejected non-zero"
    if [[ "$LAST_OUT" == "http://localhost:6767" ]]; then
        fail "$desc: invalid value was silently substituted with the default (got=$LAST_OUT)"
    else
        ok "$desc: no silent substitution with the default"
    fi
}
invalid_endpoint_case "with userinfo" "http://user:pass@localhost:6767"
invalid_endpoint_case "with path" "http://localhost:6767/api"
invalid_endpoint_case "with query" "http://localhost:6767?x=1"
invalid_endpoint_case "with fragment" "http://localhost:6767#frag"
invalid_endpoint_case "non-loopback hostname" "http://example.com"
invalid_endpoint_case "non-loopback IP" "http://192.168.1.5:6767"
invalid_endpoint_case "0.0.0.0 is non-loopback" "http://0.0.0.0:6767"
invalid_endpoint_case "https scheme is disallowed" "https://localhost:6767"
invalid_endpoint_case "invalid port" "http://localhost:abc"
invalid_endpoint_case "malformed as a URL" "not a url"

section "sm_endpoint: an invalid value in the config file (~/.supermemory/env) is likewise rejected"
CFG_HOME="$(mktemp -d /tmp/sm-test-cfghome.XXXXXX)"
mkdir -p "$CFG_HOME/.supermemory"
printf 'SUPERMEMORY_API_URL=http://evil.example.com\n' > "$CFG_HOME/.supermemory/env"
run_lib "$CFG_HOME" "unset SUPERMEMORY_API_URL" "sm_endpoint"
expect_nonzero "invalid URL from the config file is non-zero"
if [[ "$LAST_OUT" == "http://localhost:6767" ]]; then
    fail "invalid config-file value was silently substituted with the default"
else
    ok "invalid config-file value was not substituted with the default"
fi
rm -rf "$CFG_HOME"

# ==================================================================
section "invalid endpoint: no function ever issues a network request"
# ==================================================================
BEFORE="$(log_count)"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='http://localhost:$MOCK_PORT/extra-path'" "sm_search foo tag 5"
expect_nonzero "sm_search: non-zero for endpoint with a path"
expect_no_new_request "sm_search: no request sent for an invalid endpoint" "$BEFORE"

BEFORE="$(log_count)"
INGFILE="$FILES_DIR/valid-endpoint-check.md"
printf 'hello world' > "$INGFILE"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='http://localhost:$MOCK_PORT/extra-path'" "sm_ingest '$INGFILE' tag"
expect_nonzero "sm_ingest: non-zero for endpoint with a path"
expect_empty_stdout "sm_ingest: no success stdout for an invalid endpoint"
expect_no_new_request "sm_ingest: no request sent for an invalid endpoint" "$BEFORE"

BEFORE="$(log_count)"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='http://localhost:$MOCK_PORT/extra-path'" "sm_document doc123"
expect_nonzero "sm_document: non-zero for endpoint with a path"
expect_no_new_request "sm_document: no request sent for an invalid endpoint" "$BEFORE"

BEFORE="$(log_count)"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='http://localhost:$MOCK_PORT/extra-path'" "sm_inject '/some/proj' tag"
expect_exit0 "sm_inject: masked as exit0 even for an invalid endpoint"
expect_empty_stdout "sm_inject: empty string for an invalid endpoint"
expect_no_new_request "sm_inject: no request sent for an invalid endpoint" "$BEFORE"

# ==================================================================
section "sm_search: returns validated JSON with a results array / non-zero on various failures"
# ==================================================================
set_route "$(route_exact POST /v4/search 200 '{"results":[{"memory":"foo bar"}]}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_search query tag 5"
expect_exit0 "happy path: exit0"
expect_json_results_array "happy path: .results is an array"
expect_json_field "happy path: contains the content" '.results[0].memory' "foo bar"

set_route "$(route_exact POST /v4/search 200 'not-json{')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_search query tag 5"
expect_nonzero "malformed JSON: non-zero"
expect_empty_stdout "malformed JSON: empty stdout"

set_route "$(route_exact POST /v4/search 200 '{"data":[]}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_search query tag 5"
expect_nonzero "JSON missing results: non-zero"

set_route "$(route_exact POST /v4/search 200 '{"results":"not-an-array"}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_search query tag 5"
expect_nonzero "JSON with wrong results type: non-zero"

set_route "$(route_exact POST /v4/search 200 '{"results":[]}{"results":[]}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_search query tag 5"
expect_nonzero "response of concatenated JSON objects: non-zero"
expect_empty_stdout "concatenated JSON objects: empty stdout"

set_route "$(route_exact POST /v4/search 500 '{"results":[]}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_search query tag 5"
expect_nonzero "HTTP error (500): non-zero even with a well-formed body"
expect_empty_stdout "HTTP error (500): empty stdout"

run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='http://127.0.0.1:$CLOSED_PORT'" "sm_search query tag 5"
expect_nonzero "transport failure (connection refused): non-zero"
expect_empty_stdout "transport failure: empty stdout"

section "sm_search: HTTP 302 is rejected as a redirect even with a plausible-looking JSON body"
BEFORE="$(log_count)"
set_route "$(route_exact POST /v4/search 302 '{"results":[{"memory":"redirect-should-not-be-trusted"}]}' "{\"extra_headers\":{\"Location\":\"$MOCK_URL/should-not-be-fetched\"}}")"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_search query tag 5"
expect_nonzero "a 302 response (with a plausible JSON body) is not followed and is non-zero"
expect_empty_stdout "302 response: does not leak the body via stdout"
if grep -q 'should-not-be-fetched' "$MOCK_LOG" 2>/dev/null; then
    fail "the redirect target was actually followed"
else
    ok "the redirect target was not followed"
fi

# ==================================================================
section "curl hardening: .curlrc disabled / proxy env vars ignored"
# ==================================================================
# NOTE: both sub-tests below MUST pin SUPERMEMORY_API_URL to the mock server
# explicitly. A previous version of this test omitted it, which meant a
# missing override silently fell back to the production default
# (http://localhost:6767) and could hit a *live* local supermemory service
# instead of the mock. run_lib now also defaults SUPERMEMORY_API_URL to the
# mock server for defense in depth, but pin it here too so this test remains
# correct even if that default is ever changed.
CURLRC_HOME="$(mktemp -d /tmp/sm-test-curlrchome.XXXXXX)"
cat > "$CURLRC_HOME/.curlrc" << 'EOF'
header = "X-Injected-By-Curlrc: yes"
EOF
BEFORE="$(log_count)"
set_route "$(route_exact POST /v4/search 200 '{"results":[]}')"
run_lib "$CURLRC_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_search query tag 5"
expect_exit0 "the happy path still works even with a .curlrc present"
expect_new_request "curlrc: a new request is sent to the mock" "$BEFORE"
NEWLINE="$(last_log_line)"
if [[ "$NEWLINE" == *"X-Injected-By-Curlrc"* ]]; then
    fail "curl read ~/.curlrc and had a header injected (--disable/-q not used)"
else
    ok "curl ignores ~/.curlrc"
fi
find "$CURLRC_HOME" -mindepth 0 -maxdepth 2 -exec chmod u+w {} \; 2>/dev/null
python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$CURLRC_HOME"

BEFORE="$(log_count)"
set_route "$(route_exact POST /v4/search 200 '{"results":[{"memory":"proxy-ignored-ok"}]}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'; export http_proxy='http://127.0.0.1:1'; export https_proxy='http://127.0.0.1:1'" "sm_search query tag 5"
expect_exit0 "connects directly, ignoring http_proxy/https_proxy env vars"
expect_new_request "proxy: a new request is sent to the mock" "$BEFORE"
expect_json_field "proxy ignored: got the expected content" '.results[0].memory' "proxy-ignored-ok"

# ==================================================================
section "sm_inject: all read failures are masked as exit0 with an empty string"
# ==================================================================
set_route "$(route_exact POST /v4/search 200 '{"results":[{"memory":"proj context fact"}]}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_inject '/tmp/some-proj' tag"
expect_exit0 "happy path: exit0"
expect_stdout_contains "happy path: contains the memory block" "proj context fact"

set_route "$(route_exact POST /v4/search 200 'not-json{')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_inject '/tmp/some-proj' tag"
expect_exit0 "malformed response: masked as exit0"
expect_empty_stdout "malformed response: empty string"

set_route "$(route_exact POST /v4/search 500 '{}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_inject '/tmp/some-proj' tag"
expect_exit0 "HTTP error: masked as exit0"
expect_empty_stdout "HTTP error: empty string"

run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='http://127.0.0.1:$CLOSED_PORT'" "sm_inject '/tmp/some-proj' tag"
expect_exit0 "transport failure: masked as exit0"
expect_empty_stdout "transport failure: empty string"

set_route "$(route_exact POST /v4/search 200 '{"results":[{"memory":"partial-body-should-not-leak"}]}' '{"truncate":true}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_inject '/tmp/some-proj' tag"
expect_exit0 "partial response that makes curl fail: masked as exit0"
expect_empty_stdout "partial response: empty string (partial body not leaked)"

set_route "$(route_exact POST /v4/search 302 '{"results":[{"memory":"redirect-should-not-leak"}]}' "{\"extra_headers\":{\"Location\":\"$MOCK_URL/should-not-be-fetched\"}}")"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_inject '/tmp/some-proj' tag"
expect_exit0 "302 response (with a plausible JSON body): masked as exit0"
expect_empty_stdout "302 response: empty string (fail-open)"

# ==================================================================
section "sm_ingest: returns {id,status} only on acceptance"
# ==================================================================
mk_ing_file() {
    local name="$1" content="$2" p
    p="$FILES_DIR/$name"
    printf '%s' "$content" > "$p"
    printf '%s' "$p"
}

F1="$(mk_ing_file ingest-ok.md 'ingest content one')"

set_route "$(route_exact POST /v3/documents 200 '{"id":"docQ","status":"queued"}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$F1' tag"
expect_exit0 "status=queued (non-terminal): succeeds as an acceptance"
expect_json_field "status=queued: returns id" '.id' "docQ"
expect_json_field "status=queued: returns status" '.status' "queued"

set_route "$(route_exact POST /v3/documents 200 '{"id":"docD","status":"done"}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$F1' tag"
expect_exit0 "status=done (successful terminal): succeeds as an acceptance"
expect_json_field "status=done: returns id" '.id' "docD"

set_route "$(route_exact POST /v3/documents 200 '{"id":"docF","status":"failed"}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$F1' tag"
expect_nonzero "status=failed: non-zero"
expect_empty_stdout "status=failed: no success stdout"

set_route "$(route_exact POST /v3/documents 200 '{"id":"docU","status":"banana"}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$F1' tag"
expect_nonzero "status=unknown value: non-zero"
expect_empty_stdout "status=unknown value: no success stdout"

set_route "$(route_exact POST /v3/documents 200 '{"id":"docNoStatus"}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$F1' tag"
expect_nonzero "status missing: non-zero"
expect_empty_stdout "status missing: no success stdout"

set_route "$(route_exact POST /v3/documents 200 '{"id":"docX","status":"done"}{"id":"docY","status":"done"}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$F1' tag"
expect_nonzero "response of concatenated JSON objects: non-zero"
expect_empty_stdout "concatenated JSON objects: no success stdout"

set_route "$(route_exact POST /v3/documents 500 '{"id":"leaked-id-500","status":"done"}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$F1' tag"
expect_nonzero "HTTP error (500, id present in body): non-zero"
expect_empty_stdout "HTTP error (500): does not leak the id"

set_route "$(route_exact POST /v3/documents 200 'not-json{')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$F1' tag"
expect_nonzero "malformed response: non-zero"
expect_empty_stdout "malformed response: no success stdout"

set_route "$(route_exact POST /v3/documents 200 '{"id":"","status":"done"}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$F1' tag"
expect_nonzero "empty id string: non-zero"
expect_empty_stdout "empty id string: no success stdout"

BEFORE="$(log_count)"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$FILES_DIR/does-not-exist.md' tag"
expect_nonzero "missing file: non-zero"
expect_empty_stdout "missing file: no success stdout"

EMPTYFILE="$FILES_DIR/empty.md"; : > "$EMPTYFILE"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$EMPTYFILE' tag"
expect_nonzero "empty file: non-zero"
expect_empty_stdout "empty file: no success stdout"

NO_CURL_PATH="$(make_path_without curl)"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$F1' tag" "$NO_CURL_PATH"
expect_nonzero "curl missing: non-zero"
expect_empty_stdout "curl missing: no success stdout"
rm -rf "$NO_CURL_PATH"

NO_JQ_PATH="$(make_path_without jq)"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$F1' tag" "$NO_JQ_PATH"
expect_nonzero "jq missing: non-zero"
expect_empty_stdout "jq missing: no success stdout"
rm -rf "$NO_JQ_PATH"

section "sm_ingest: HTTP 302 is rejected as a redirect even with a plausible-looking JSON body"
set_route "$(route_exact POST /v3/documents 302 '{"id":"redirect-id","status":"done"}' "{\"extra_headers\":{\"Location\":\"$MOCK_URL/should-not-be-fetched\"}}")"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$F1' tag"
expect_nonzero "a 302 response (with a plausible JSON body) is rejected"
expect_empty_stdout "302 response: does not leak the id"

section "sm_ingest: on timeout, non-zero, no success stdout, and returns on its own internally"
set_route "$(route_exact POST /v3/documents 200 '{"id":"docHang","status":"done"}' '{"hang":true}')"
START_NS="$(date +%s%N)"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$F1' tag" "$REAL_PATH" 45
END_NS="$(date +%s%N)"
ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
expect_nonzero "timeout: non-zero"
expect_empty_stdout "timeout: no success stdout"
if [[ "$ELAPSED_MS" -lt 44000 ]]; then
    ok "timeout: returned on its own before the outer safety valve (45s) (${ELAPSED_MS}ms)"
else
    fail "timeout: the internal timeout did not fire and the outer safety valve force-killed it (${ELAPSED_MS}ms)"
fi

# ==================================================================
section "sm_ingest: a normal-sized large Markdown document (~200KiB, a single document exceeding the argv limit)"
# ==================================================================
# A ~200KiB markdown file is an entirely normal, legitimate document to ingest
# (e.g. a long design doc or changelog). Linux's per-argument execve() limit
# (MAX_ARG_STRLEN, ~128KiB on typical 4KiB-page systems) means an
# implementation that passes the whole JSON body as a single `curl -d
# "$data"` argv argument can fail with "Argument list too long" (E2BIG) well
# below this size, even though the document itself is perfectly ordinary.
# A conforming implementation must not depend on argv for normal-sized docs.
BIGFILE="$FILES_DIR/large-doc.md"
python3 -c "
import sys
sys.stdout.write('# Large markdown doc\n')
sys.stdout.write('word ' * 45000)
" > "$BIGFILE"
BIGSIZE="$(wc -c < "$BIGFILE" | tr -d ' ')"
if [[ "$BIGSIZE" -ge 204800 ]]; then
    ok "fixture: the large document is at least ~200KiB (${BIGSIZE} bytes)"
else
    fail "fixture: the large document is smaller than ~200KiB (${BIGSIZE} bytes)"
fi
set_route "$(route_exact POST /v3/documents 200 '{"id":"docBig","status":"done"}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$BIGFILE' tag"
expect_exit0 "a normal-sized (~200KiB) single Markdown document is accepted successfully"
expect_json_field "large document: returns id" '.id' "docBig"

# ==================================================================
section "sm_ingest: customId is stable/unique/safe with respect to content+tag"
# ==================================================================
set_route "$(route_exact POST /v3/documents 200 '{"id":"docStable","status":"done"}')"

extract_cid() { last_log_line | jq -r '.body' | jq -r '.customId' 2>/dev/null; }

CONTENT_A="the quick brown fox jumps over the lazy dog $$"
FA1="$(mk_ing_file "dirchange-a1-$$.md" "$CONTENT_A")"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$FA1' tag-x"
CID_A1="$(extract_cid)"

mkdir -p "$FILES_DIR/subdir-$$"
FA2="$FILES_DIR/subdir-$$/renamed-different-name.md"
printf '%s' "$CONTENT_A" > "$FA2"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$FA2' tag-x"
CID_A2="$(extract_cid)"

if [[ -n "$CID_A1" && "$CID_A1" == "$CID_A2" ]]; then
    ok "customId: stable for identical content+tag even when the file name/path changes ($CID_A1)"
else
    fail "customId: unstable across a file rename (a1=$CID_A1 a2=$CID_A2)"
fi

CONTENT_B="a totally different piece of content $$"
FB="$(mk_ing_file "content-b-$$.md" "$CONTENT_B")"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$FB' tag-x"
CID_B="$(extract_cid)"
if [[ -n "$CID_B" && "$CID_B" != "$CID_A1" ]]; then
    ok "customId: differs when content differs (a=$CID_A1 b=$CID_B)"
else
    fail "customId: collided despite different content (a=$CID_A1 b=$CID_B)"
fi

run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$FA1' tag-y"
CID_A_TAGY="$(extract_cid)"
if [[ -n "$CID_A_TAGY" && "$CID_A_TAGY" != "$CID_A1" ]]; then
    ok "customId: differs when tag differs (tag-x=$CID_A1 tag-y=$CID_A_TAGY)"
else
    fail "customId: collided despite different tag (tag-x=$CID_A1 tag-y=$CID_A_TAGY)"
fi

expect_regex "customId: uses only a safe character set" "$CID_A1" '^[A-Za-z0-9_-]+$'

PREFIX_200="$(printf 'a%.0s' $(seq 1 200))"
FE="$(mk_ing_file "trunc-e-$$.md" "${PREFIX_200}-SUFFIX-ONE")"
FF="$(mk_ing_file "trunc-f-$$.md" "${PREFIX_200}-SUFFIX-TWO")"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$FE' tag-x"
CID_E="$(extract_cid)"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$FF' tag-x"
CID_F="$(extract_cid)"
if [[ -n "$CID_E" && "$CID_E" != "$CID_F" ]]; then
    ok "customId: no truncation collision despite a long shared prefix + different suffixes (e=$CID_E f=$CID_F)"
else
    fail "customId: collided due to truncation (e=$CID_E f=$CID_F)"
fi

section "sm_ingest: customId must not collide due to tag/content boundary ambiguity (tag='a\\nb',content='c' vs tag='a',content='b\\nc')"
# A hash built as `printf '%s\n' "$tag"; cat "$file"` uses a bare newline as
# the tag/content delimiter. If either the tag or the content itself contains
# a literal newline, two different (tag, content) pairs can serialize to the
# exact same byte stream and therefore collide. The client must either
# delimit tag/content unambiguously, or reject a tag containing a newline
# outright.
TAG_MULTILINE_EXTRA="TAG_NL=\$'a\\nb'"
FCASE1="$(mk_ing_file "hash-ambig-case1-$$.md" 'c')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'; $TAG_MULTILINE_EXTRA" "sm_ingest '$FCASE1' \"\$TAG_NL\""
CASE1_CODE="$LAST_CODE"
CID_CASE1="$(extract_cid)"

FCASE2="$(mk_ing_file "hash-ambig-case2-$$.md" $'b\nc')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_ingest '$FCASE2' a"
CASE2_CODE="$LAST_CODE"
CID_CASE2="$(extract_cid)"

if [[ "$CASE1_CODE" -ne 0 ]]; then
    ok "customId boundary ambiguity: input with a newline in the tag was rejected as invalid (code=$CASE1_CODE)"
elif [[ "$CASE2_CODE" -ne 0 ]]; then
    fail "customId boundary ambiguity: tag='a',content='b\\nc' was unexpectedly rejected (code=$CASE2_CODE)"
elif [[ -n "$CID_CASE1" && "$CID_CASE1" != "$CID_CASE2" ]]; then
    ok "customId boundary ambiguity: tag='a\\nb',content='c' and tag='a',content='b\\nc' hash differently (case1=$CID_CASE1 case2=$CID_CASE2)"
else
    fail "customId boundary ambiguity: tag='a\\nb',content='c' and tag='a',content='b\\nc' hash-collide (case1=$CID_CASE1 case2=$CID_CASE2) - the tag/content boundary is ambiguous"
fi

# ==================================================================
section "sm_document: fetches {id,status,memories} via GET /v3/documents/ID (memories is an array as observed against the real API)"
# ==================================================================
# NOTE: a live metadata-only probe against GET /v3/documents/{id} returned
# HTTP 200, status="done", and a `memories` field that is a JSON *array*
# (observed with 18 entries), not a number. Mock fixtures below therefore use
# arrays for `memories` to match the real API; sm_document's own output still
# reports a numeric count (the array's length).
MEM18="$(jq -nc '[range(1;19) | "m" + (.|tostring)]')"

set_route "$(route_prefix GET /v3/documents/ 200 "{\"id\":\"doc-abc123\",\"status\":\"done\",\"memories\":$MEM18}")"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_document doc-abc123"
expect_exit0 "happy path (memories is an 18-element array): exit0"
expect_json_field "happy path: returns id" '.id' "doc-abc123"
expect_json_field "happy path: returns status" '.status' "done"
expect_json_field "happy path: memories returns the array length (18) as a number" '.memories' "18"
LASTPATH="$(last_log_line | jq -r '.path' 2>/dev/null)"
if [[ "$LASTPATH" == "/v3/documents/doc-abc123" ]]; then
    ok "happy path: GETs the correct URL path ($LASTPATH)"
else
    fail "happy path: wrong URL path (got=$LASTPATH)"
fi

set_route "$(route_prefix GET /v3/documents/ 200 '{"id":"doc-failed","status":"failed","memories":[]}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_document doc-failed"
expect_exit0 "failed status (empty memories array): fetching itself is allowed, exit0"
expect_json_field "failed status: returns status (caller decides)" '.status' "failed"
expect_json_field "failed status: memories is 0" '.memories' "0"

set_route "$(route_prefix GET /v3/documents/ 404 '{"error":"not found"}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_document doc-missing"
expect_nonzero "HTTP error (404): non-zero"

set_route "$(route_prefix GET /v3/documents/ 200 'not-json{')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_document doc-x"
expect_nonzero "malformed response: non-zero"

set_route "$(route_prefix GET /v3/documents/ 302 "{\"id\":\"doc-redirect\",\"status\":\"done\",\"memories\":[\"a\"]}" "{\"extra_headers\":{\"Location\":\"$MOCK_URL/should-not-be-fetched\"}}")"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_document doc-redirect"
expect_nonzero "a 302 response (with a plausible JSON body) is rejected"

section "sm_document: memories accepts a JSON array or absence (treated as 0); numeric/object/string is still rejected"
set_route "$(route_prefix GET /v3/documents/ 200 '{"id":"doc-nummem","status":"done","memories":5}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_document doc-nummem"
expect_nonzero "memories is a number (should be an array): non-zero"

# The real API legitimately omits `memories` entirely on many "failed" documents (and
# even some that later get marked failed after partially extracting a few memories) --
# observed directly against a live server during the 2026-09-10 T3 reconciliation.
# Treating an absent `memories` field as a parse failure silently misreported hundreds
# of genuinely-failed documents as "unreachable" instead of surfacing their real status.
set_route "$(route_prefix GET /v3/documents/ 200 '{"id":"doc-nomem","status":"failed"}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_document doc-nomem"
expect_exit0 "memories missing on a failed doc: exit0 (treated as 0, not a parse failure)"
expect_json_field "memories missing: reports memories:0" '.memories' "0"
expect_json_field "memories missing: still reports the real status" '.status' "failed"

set_route "$(route_prefix GET /v3/documents/ 200 '{"id":"doc-objmem","status":"done","memories":{"count":5}}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_document doc-objmem"
expect_nonzero "memories is an object type: non-zero"

set_route "$(route_prefix GET /v3/documents/ 200 '{"id":"doc-strmem","status":"done","memories":"5"}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_document doc-strmem"
expect_nonzero "memories is a string type: non-zero"

set_route "$(route_prefix GET /v3/documents/ 200 '{"status":"done","memories":[]}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_document doc-noid"
expect_nonzero "id missing: non-zero"

section "sm_document: rejects missing/unknown status, mismatched response id, and concatenated JSON objects"
set_route "$(route_prefix GET /v3/documents/ 200 '{"id":"doc-nostatus","memories":["a"]}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_document doc-nostatus"
expect_nonzero "status missing: non-zero"

set_route "$(route_prefix GET /v3/documents/ 200 '{"id":"doc-unkstatus","status":"totally-bogus-status","memories":["a"]}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_document doc-unkstatus"
expect_nonzero "status is an unknown value: non-zero"

set_route "$(route_prefix GET /v3/documents/ 200 '{"id":"doc-other-id","status":"done","memories":["a"]}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_document doc-requested-id"
expect_nonzero "response id does not match the requested id: non-zero"

set_route "$(route_prefix GET /v3/documents/ 200 '{"id":"doc-multi-a","status":"done","memories":["a"]}{"id":"doc-multi-b","status":"done","memories":["b","c"]}')"
run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_document doc-multi-a"
expect_nonzero "response of concatenated JSON objects: non-zero"

unsafe_id_case() {
    local desc="$1" id="$2" before after
    before="$(log_count)"
    run_lib "$FAKE_HOME" "SUPERMEMORY_API_URL='$MOCK_URL'" "sm_document '$id'"
    expect_nonzero "$desc: non-zero"
    expect_no_new_request "$desc: no network request issued" "$before"
}
set_route "$(route_prefix GET /v3/documents/ 200 '{"id":"should-not-be-hit","status":"done","memories":[]}')"
unsafe_id_case "unsafe ID (path traversal)" "../etc/passwd"
unsafe_id_case "unsafe ID (slash)" "id/extra"
unsafe_id_case "unsafe ID (space)" "id with space"
unsafe_id_case "unsafe ID (semicolon)" "id;rm -rf"
unsafe_id_case "unsafe ID (newline)" $'id\nls'

# ==================================================================
# memory-guard.sh (swarm-memory-sync write-side CLI) — supermemory-backed
# contract regression tests.
#
# Approved contract for agent/skills/swarm-memory-sync/scripts/memory-guard.sh:
#   memory-guard.sh <keyword> [keyword...]
#     - joins all keywords into a single space-separated query and calls the
#       shared sm_search with tag "claude-memory" and a bounded limit of 10.
#     - prints the validated search JSON on success; non-zero and no success
#       stdout on any unavailable/invalid response. An empty `results` array
#       is a *valid* response (not proof of exhaustive dedup - it only means
#       the server returned zero matches for this particular query).
#     - an optional leading `--` delimiter lets a keyword that itself begins
#       with '-' be treated as a literal keyword rather than an option.
#   memory-guard.sh --ingest FILE
#     - calls the shared sm_ingest FILE claude-memory; on acceptance prints
#       the {"id":...,"status":...} receipt verbatim (queued is a valid
#       acceptance and must never be reported/rewritten as completed); any
#       failure is non-zero with no success stdout.
#   memory-guard.sh --status ID
#     - calls the shared sm_document ID; prints {"id":...,"status":...,
#       "memories":N} verbatim, including a "failed" status (fetching a
#       failed document's status is itself allowed - the caller inspects it).
#   Strict arity: --ingest/--status each require exactly one following
#   argument; unknown options, zero arguments, and the removed legacy
#   `--record` subcommand are all non-zero with no network call and no
#   legacy filesystem writes.
#   Legacy local-file memory (~/.claude/memory, ~/.gemini/memory,
#   ~/.agy/memory, CLAUDE_MEMORY_DIR, AGY_MEMORY_DIR, .edit-log.jsonl) must
#   never be read from or written to by any code path.
#
# These tests exercise the *actual* memory-guard.sh script (not a mock),
# invoked as a subprocess against the same isolated HOME + MOCK_URL fixtures
# used above, from an unrelated cwd, and (for the resolution test) through a
# temporary per-file symlink fixture that mimics (without performing) the
# real Makefile.d/install.mk installation layout.
# ==================================================================

GUARD="$ROOT/agent/skills/swarm-memory-sync/scripts/memory-guard.sh"
GUARD_CWD="$(mktemp -d /tmp/sm-test-guard-cwd.XXXXXX)"   # unrelated to $ROOT and to any test $home

# run_guard <home> <extra_env_script> <script_path> [args...]
# Always executes with cwd=$GUARD_CWD (unrelated to the repo and to $home) and
# SUPERMEMORY_API_URL defaulted to the mock server (overridable via $extra,
# same sticky-export trick as run_lib above: env -i already exports it, so a
# later plain reassignment in $extra keeps the export attribute across exec).
# Each positional arg is individually shell-quoted via `printf %q` so that
# leading-dash / path-traversal / space-containing test arguments survive
# reconstruction into the inner bash -c string intact.
run_guard() {
    local home="$1" extra="$2" script="$3"; shift 3
    local errfile; errfile="$(mktemp /tmp/sm-test-err.XXXXXX)"
    local argstr="" a
    for a in "$@"; do argstr="$argstr $(printf '%q' "$a")"; done
    LAST_OUT="$(timeout 20 env -i HOME="$home" PATH="$REAL_PATH" SUPERMEMORY_API_URL="$MOCK_URL" bash -c "
set -u
cd '$GUARD_CWD' || exit 97
$extra
exec '$script'$argstr
" 2>"$errfile")"
    LAST_CODE=$?
    LAST_ERR="$(cat "$errfile" 2>/dev/null)"
    rm -f "$errfile"
}

expect_path_absent() {
    local desc="$1" path="$2"
    if [[ ! -e "$path" ]]; then ok "$desc"; else fail "$desc : unexpectedly exists: $path"; fi
}
expect_file_content() {
    local desc="$1" path="$2" expected="$3" actual
    actual="$(cat "$path" 2>/dev/null)"
    if [[ "$actual" == "$expected" ]]; then ok "$desc"; else fail "$desc : expected='$expected' actual='$actual' path=$path"; fi
}
# last_request_body_field FILTER -> applies a jq FILTER to the JSON-encoded
# request body of the most recent mock-server request (same double-jq
# unwrapping idiom as extract_cid() above: .body is a string containing the
# raw JSON the client actually sent).
last_request_body_field() {
    last_log_line | jq -r '.body' 2>/dev/null | jq -r "$1" 2>/dev/null
}

# ==================================================================
section "memory-guard.sh: keyword search mode joins keywords into one sm_search query"
# ==================================================================
set_route "$(route_exact POST /v4/search 200 '{"results":[{"memory":"guard-search-ok"}]}')"
BEFORE="$(log_count)"
run_guard "$FAKE_HOME" "" "$GUARD" alpha beta gamma
expect_exit0 "single + multi keyword: exit0"
expect_new_request "single + multi keyword: sends a request to the mock" "$BEFORE"
expect_json_results_array "single + multi keyword: .results is an array"
expect_json_field "single + multi keyword: contains the content" '.results[0].memory' "guard-search-ok"
Q="$(last_request_body_field '.q')"
if [[ "$Q" == "alpha beta gamma" ]]; then
    ok "keywords are joined into a single space-separated query (q=\"$Q\")"
else
    fail "keywords were not joined as expected (q=\"$Q\")"
fi
CTAG0="$(last_request_body_field '.containerTags[0]')"
CTAG_LEN="$(last_request_body_field '.containerTags | length')"
if [[ "$CTAG0" == "claude-memory" && "$CTAG_LEN" == "1" ]]; then
    ok "search uses exactly the fixed claude-memory containerTag"
else
    fail "search did not use exactly the claude-memory containerTag (tag=\"$CTAG0\" len=\"$CTAG_LEN\")"
fi
LIMIT="$(last_request_body_field '.limit')"
if [[ "$LIMIT" == "10" ]]; then
    ok "search uses a bounded limit of 10"
else
    fail "search limit was not bounded to 10 (got=\"$LIMIT\")"
fi

section "memory-guard.sh: keyword search - empty results array is a valid (not a failure) response"
set_route "$(route_exact POST /v4/search 200 '{"results":[]}')"
run_guard "$FAKE_HOME" "" "$GUARD" nonexistent-topic
expect_exit0 "empty results array: still exit0 (valid, not an error)"
expect_json_results_array "empty results array: .results is still an array"

section "memory-guard.sh: keyword search - unavailable/invalid responses are non-zero with no success stdout"
set_route "$(route_exact POST /v4/search 200 'not-json{')"
run_guard "$FAKE_HOME" "" "$GUARD" some keyword
expect_nonzero "malformed JSON response: non-zero"
expect_empty_stdout "malformed JSON response: no success stdout"

set_route "$(route_exact POST /v4/search 500 '{"results":[]}')"
run_guard "$FAKE_HOME" "" "$GUARD" some keyword
expect_nonzero "HTTP error (500): non-zero"
expect_empty_stdout "HTTP error (500): no success stdout"

run_guard "$FAKE_HOME" "SUPERMEMORY_API_URL='http://127.0.0.1:$CLOSED_PORT'" "$GUARD" some keyword
expect_nonzero "unavailable server (connection refused): non-zero"
expect_empty_stdout "unavailable server: no success stdout"

section "memory-guard.sh: -- delimiter permits a topic keyword beginning with '-' as a literal"
set_route "$(route_exact POST /v4/search 200 '{"results":[]}')"
run_guard "$FAKE_HOME" "" "$GUARD" -- -foo bar
expect_exit0 "'-- -foo bar': treats -foo as a literal keyword, not an option (exit0)"
Q2="$(last_request_body_field '.q')"
if [[ "$Q2" == "-foo bar" ]]; then
    ok "'-- -foo bar': -foo is preserved literally in the joined query (q=\"$Q2\")"
else
    fail "'-- -foo bar': -foo was not preserved literally (q=\"$Q2\")"
fi

# ==================================================================
section "memory-guard.sh: --ingest FILE calls sm_ingest FILE claude-memory, receipt JSON only on acceptance"
# ==================================================================
GFILE="$(mk_ing_file "guard-ingest-ok.md" "guard ingest content")"

set_route "$(route_exact POST /v3/documents 200 '{"id":"docGQ","status":"queued"}')"
run_guard "$FAKE_HOME" "" "$GUARD" --ingest "$GFILE"
expect_exit0 "status=queued: succeeds as an acceptance receipt"
expect_json_field "status=queued: returns id" '.id' "docGQ"
expect_json_field "status=queued: status is preserved as queued, not completed" '.status' "queued"
KEYS="$(printf '%s' "$LAST_OUT" | jq -cS 'keys' 2>/dev/null)"
if [[ "$KEYS" == '["id","status"]' ]]; then
    ok "acceptance receipt has exactly {id,status}, no fabricated completion field"
else
    fail "acceptance receipt has unexpected shape (keys=$KEYS)"
fi
CTAG="$(last_request_body_field '.containerTags[0]')"
if [[ "$CTAG" == "claude-memory" ]]; then
    ok "--ingest uses the fixed claude-memory containerTag"
else
    fail "--ingest did not use the claude-memory containerTag (got=\"$CTAG\")"
fi

set_route "$(route_exact POST /v3/documents 200 '{"id":"docGF","status":"failed"}')"
run_guard "$FAKE_HOME" "" "$GUARD" --ingest "$GFILE"
expect_nonzero "status=failed: non-zero"
expect_empty_stdout "status=failed: no success stdout"

run_guard "$FAKE_HOME" "" "$GUARD" --ingest "$FILES_DIR/guard-does-not-exist.md"
expect_nonzero "missing file: non-zero"
expect_empty_stdout "missing file: no success stdout"

section "memory-guard.sh: --ingest strict arity (exactly one FILE argument)"
BEFORE="$(log_count)"
run_guard "$FAKE_HOME" "" "$GUARD" --ingest
expect_nonzero "--ingest with zero args: non-zero"
expect_no_new_request "--ingest with zero args: no network call" "$BEFORE"

BEFORE="$(log_count)"
run_guard "$FAKE_HOME" "" "$GUARD" --ingest "$GFILE" extra-arg
expect_nonzero "--ingest with two args: non-zero"
expect_no_new_request "--ingest with two args: no network call" "$BEFORE"

# ==================================================================
section "memory-guard.sh: --status ID calls sm_document ID, {id,status,memories} JSON, failed status preserved"
# ==================================================================
set_route "$(route_prefix GET /v3/documents/ 200 '{"id":"docGuardOk","status":"done","memories":["a","b","c"]}')"
run_guard "$FAKE_HOME" "" "$GUARD" --status docGuardOk
expect_exit0 "status=done: exit0"
expect_json_field "status=done: returns id" '.id' "docGuardOk"
expect_json_field "status=done: returns status" '.status' "done"
expect_json_field "status=done: returns memories count" '.memories' "3"
KEYS2="$(printf '%s' "$LAST_OUT" | jq -cS 'keys' 2>/dev/null)"
if [[ "$KEYS2" == '["id","memories","status"]' ]]; then
    ok "--status receipt has exactly {id,status,memories}"
else
    fail "--status receipt has unexpected shape (keys=$KEYS2)"
fi

set_route "$(route_prefix GET /v3/documents/ 200 '{"id":"docGuardFailed","status":"failed","memories":[]}')"
run_guard "$FAKE_HOME" "" "$GUARD" --status docGuardFailed
expect_exit0 "status=failed is inspectable data, not itself an error: exit0"
expect_json_field "status=failed: status is preserved verbatim as failed" '.status' "failed"

set_route "$(route_prefix GET /v3/documents/ 404 '{"error":"not found"}')"
run_guard "$FAKE_HOME" "" "$GUARD" --status does-not-exist
expect_nonzero "HTTP error (404): non-zero"

BEFORE="$(log_count)"
run_guard "$FAKE_HOME" "" "$GUARD" --status '../etc/passwd'
expect_nonzero "unsafe id: non-zero"
expect_no_new_request "unsafe id: no network call" "$BEFORE"

section "memory-guard.sh: --status strict arity (exactly one ID argument)"
BEFORE="$(log_count)"
run_guard "$FAKE_HOME" "" "$GUARD" --status
expect_nonzero "--status with zero args: non-zero"
expect_no_new_request "--status with zero args: no network call" "$BEFORE"

BEFORE="$(log_count)"
run_guard "$FAKE_HOME" "" "$GUARD" --status docGuardOk extra-arg
expect_nonzero "--status with two args: non-zero"
expect_no_new_request "--status with two args: no network call" "$BEFORE"

# ==================================================================
section "memory-guard.sh: zero args, unknown options, and the removed --record are all non-zero without network"
# ==================================================================
BEFORE="$(log_count)"
run_guard "$FAKE_HOME" "" "$GUARD"
expect_nonzero "zero args: non-zero"
expect_no_new_request "zero args: no network call" "$BEFORE"

BEFORE="$(log_count)"
run_guard "$FAKE_HOME" "" "$GUARD" --bogus-option
expect_nonzero "unknown long option: non-zero"
expect_no_new_request "unknown long option: no network call" "$BEFORE"

BEFORE="$(log_count)"
run_guard "$FAKE_HOME" "" "$GUARD" -x
expect_nonzero "unknown short option: non-zero"
expect_no_new_request "unknown short option: no network call" "$BEFORE"

BEFORE="$(log_count)"
run_guard "$FAKE_HOME" "" "$GUARD" --record some-file.md created
expect_nonzero "removed legacy --record subcommand: non-zero"
expect_no_new_request "removed --record: no network call" "$BEFORE"

# ==================================================================
section "memory-guard.sh: legacy local-file memory is never read from or written to"
# ==================================================================
SENTINEL_HOME="$(mktemp -d /tmp/sm-test-sentinel-home.XXXXXX)"
mkdir -p "$SENTINEL_HOME/.claude/memory" "$SENTINEL_HOME/.gemini/memory" "$SENTINEL_HOME/.agy/memory"
printf 'sentinel-claude-index\n' > "$SENTINEL_HOME/.claude/memory/MEMORY.md"
printf '{"ts":"sentinel","file":"x.md","op":"updated"}\n' > "$SENTINEL_HOME/.claude/memory/.edit-log.jsonl"
printf 'sentinel-gemini-index\n' > "$SENTINEL_HOME/.gemini/memory/MEMORY.md"
printf 'sentinel-agy-index\n' > "$SENTINEL_HOME/.agy/memory/MEMORY.md"

set_route "$(route_exact POST /v4/search 200 '{"results":[]}')"
run_guard "$SENTINEL_HOME" "" "$GUARD" some keyword
set_route "$(route_exact POST /v3/documents 200 '{"id":"docSentinel","status":"queued"}')"
run_guard "$SENTINEL_HOME" "" "$GUARD" --ingest "$GFILE"
set_route "$(route_prefix GET /v3/documents/ 200 '{"id":"docSentinelStatus","status":"done","memories":[]}')"
run_guard "$SENTINEL_HOME" "" "$GUARD" --status docSentinelStatus
run_guard "$SENTINEL_HOME" "" "$GUARD" --bogus-option
run_guard "$SENTINEL_HOME" "" "$GUARD"
run_guard "$SENTINEL_HOME" "" "$GUARD" --record some-file.md created

expect_file_content "sentinel ~/.claude/memory/MEMORY.md: unchanged" "$SENTINEL_HOME/.claude/memory/MEMORY.md" "sentinel-claude-index"
expect_file_content "sentinel ~/.claude/memory/.edit-log.jsonl: unchanged (no legacy writes)" "$SENTINEL_HOME/.claude/memory/.edit-log.jsonl" '{"ts":"sentinel","file":"x.md","op":"updated"}'
expect_file_content "sentinel ~/.gemini/memory/MEMORY.md: unchanged" "$SENTINEL_HOME/.gemini/memory/MEMORY.md" "sentinel-gemini-index"
expect_file_content "sentinel ~/.agy/memory/MEMORY.md: unchanged" "$SENTINEL_HOME/.agy/memory/MEMORY.md" "sentinel-agy-index"

CLAUDE_MEM_COUNT="$(find "$SENTINEL_HOME/.claude/memory" -type f | wc -l | tr -d ' ')"
if [[ "$CLAUDE_MEM_COUNT" -eq 2 ]]; then
    ok "sentinel ~/.claude/memory: no extra files created (still exactly MEMORY.md + .edit-log.jsonl)"
else
    fail "sentinel ~/.claude/memory: file count changed (expected 2, got $CLAUDE_MEM_COUNT)"
fi

section "memory-guard.sh: dirs absent before must stay absent after; CLAUDE_MEMORY_DIR/AGY_MEMORY_DIR are ignored"
FRESH_HOME="$(mktemp -d /tmp/sm-test-fresh-home.XXXXXX)"
ENV_DIR_CLAUDE_PARENT="$(mktemp -d /tmp/sm-test-envdir-claude.XXXXXX)"
ENV_DIR_AGY_PARENT="$(mktemp -d /tmp/sm-test-envdir-agy.XXXXXX)"
ENV_DIR_CLAUDE="$ENV_DIR_CLAUDE_PARENT/nested"
ENV_DIR_AGY="$ENV_DIR_AGY_PARENT/nested"
EXTRA_ENV_DIRS="CLAUDE_MEMORY_DIR='$ENV_DIR_CLAUDE'; AGY_MEMORY_DIR='$ENV_DIR_AGY'"

set_route "$(route_exact POST /v4/search 200 '{"results":[]}')"
run_guard "$FRESH_HOME" "$EXTRA_ENV_DIRS" "$GUARD" some keyword
expect_exit0 "search still works normally even with CLAUDE_MEMORY_DIR/AGY_MEMORY_DIR set: exit0"
set_route "$(route_exact POST /v3/documents 200 '{"id":"docFresh","status":"queued"}')"
run_guard "$FRESH_HOME" "$EXTRA_ENV_DIRS" "$GUARD" --ingest "$GFILE"
run_guard "$FRESH_HOME" "$EXTRA_ENV_DIRS" "$GUARD" --bogus-option
run_guard "$FRESH_HOME" "$EXTRA_ENV_DIRS" "$GUARD"

expect_path_absent "fresh HOME: ~/.claude never created" "$FRESH_HOME/.claude"
expect_path_absent "fresh HOME: ~/.gemini never created" "$FRESH_HOME/.gemini"
expect_path_absent "fresh HOME: ~/.agy never created" "$FRESH_HOME/.agy"
expect_path_absent "CLAUDE_MEMORY_DIR is ignored: target dir never created" "$ENV_DIR_CLAUDE"
expect_path_absent "AGY_MEMORY_DIR is ignored: target dir never created" "$ENV_DIR_AGY"

EDIT_LOG_HITS="$(find "$SENTINEL_HOME" "$FRESH_HOME" -name '.edit-log.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$EDIT_LOG_HITS" -eq 1 ]]; then
    ok ".edit-log.jsonl: only the pre-existing sentinel file exists, none newly created"
else
    fail ".edit-log.jsonl: unexpected count (expected 1 pre-existing sentinel, got $EDIT_LOG_HITS)"
fi

rm -rf "$SENTINEL_HOME" "$FRESH_HOME" "$ENV_DIR_CLAUDE_PARENT" "$ENV_DIR_AGY_PARENT" 2>/dev/null

# ==================================================================
section "memory-guard.sh: resolves the shared supermemory.sh from its own canonical location, not cwd, through a per-file symlink fixture"
# ==================================================================
# This mimics (without performing) the real Makefile.d/install.mk installation
# layout, where individual files (not whole directories) are symlinked into
# the merged ~/.claude/skills tree (see test-merged-dir-root-resolution.sh for
# the analogous hooks-side regression). Only the *skill script* is symlinked
# here; agent/scripts/hooks/supermemory.sh stays at its normal repository-
# relative location, unsymlinked. A conforming implementation must resolve
# back to it via its own symlink target (e.g. readlink -f "${BASH_SOURCE[0]}"),
# not via $PWD or the symlink's containing directory.
SYMLINK_ROOT="$(mktemp -d /tmp/sm-test-symlink-root.XXXXXX)"
MERGED_SKILLS_DIR="$SYMLINK_ROOT/.claude/skills/swarm-memory-sync/scripts"
mkdir -p "$MERGED_SKILLS_DIR"
ln -sf "$GUARD" "$MERGED_SKILLS_DIR/memory-guard.sh"

set_route "$(route_exact POST /v4/search 200 '{"results":[{"memory":"via-symlink-ok"}]}')"
run_guard "$FAKE_HOME" "" "$MERGED_SKILLS_DIR/memory-guard.sh" some keyword
expect_exit0 "invoked via a per-file symlink from an unrelated cwd: still resolves the shared lib (exit0)"
expect_json_results_array "invoked via symlink: .results is an array"
expect_json_field "invoked via symlink: returns the expected content" '.results[0].memory' "via-symlink-ok"

rm -rf "$SYMLINK_ROOT" "$GUARD_CWD" 2>/dev/null

echo
echo "---"
if [[ "$total_fail" -gt 0 ]]; then
    echo "test-supermemory-client: ${total_fail} FAIL(s)"
    exit 1
fi
echo "test-supermemory-client: all tests PASS"
exit 0
