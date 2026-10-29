#!/usr/bin/env bash
# run-ollama-e2e.sh -- live E2E of prime-agent 0.10.0 driven by a LOCAL ollama model, entirely inside a
# throwaway HOME (CONTEXT.md "primeagent-max-customize", Q9 / C-1 / P-7).
#
# Phases (each prints PASS / FAIL / INCONCLUSIVE):
#   guard      pa-sandbox `-p --mode json` (no extra rw bind): the model runs one allowed and one blocked
#              bash() command; the blocked one must exit 126 with the prime-shell-guard message and leave no
#              trace in the workspace (it would create PA-E2E-LEAK if it ran).
#   allowlist  daemon session, settings WITHOUT the local model in allowedModels: the daemon must refuse it.
#   machine    daemon session, local model allowed: `rlm.factory.run("pa-e2e-min")` must reach `done`
#              through ping -> pong (e2e/machines/pa-e2e-min). INCONCLUSIVE attempts are retried
#              (PA_E2E_MACHINE_TRIES).
# Verdicts (allowlist is PASS or FAIL only, its refusal comes before any model output). The runtime
# settles a child `done` even when its answer is empty or its json port does not parse
# (rlm/factory.py _apply_settlement / _capture_outputs), so a `done` run alone proves nothing about the
# answers; the machine verdict checks the captured answers, in this order:
#   FAIL         the daemon allowlist refusing the model or `turn failed` on the screen; guard: the
#                blocked command took effect (both checked before (a)).
#   INCONCLUSIVE (a) no assistant tool call carries every line of the given code (the model did not run it).
#   FAIL         the code ran but no status line in that tool call's result (exception, timeout); run not
#                `done`; a node in error/cancelled; an error settle (child error, budget_ms exceeded),
#                node_error or retry; a captured answer whose json port value is not the expected one.
#   INCONCLUSIVE (b, machine) some node settled `done` with no answer_captured event, and every such node
#                has the correct answer ({"ping": {"ok": true}} / {"pong": {"done": true}}) in a child
#                transcript text (the answer reached the child only after the settle). Without it: FAIL.
#   PASS         machine: both nodes `done`, transition_fired ping -> pong, and both answers captured
#                with the expected port values (ping {"ok": true}, pong {"done": true}); guard: allowed
#                command exit 0 and file created, blocked command exit 126 with the guard message.
#   FAIL         everything else.
#
# Isolation (nothing outside the two temp dirs is written; the real daemon/socket is never contacted):
#   - HOME, XDG_*, TMPDIR and PRIME_AGENT_DAEMON_SOCKET point into a fresh `${PA_E2E_TMP_PREFIX}-home-*`;
#     every prime-agent / make call starts from `env -i`. The workspace is a fresh `git init` repo
#     `${PA_E2E_TMP_PREFIX}-ws-*` with no commits (so no signing question arises). Both are deleted on exit.
#   - The layout comes from `make -o dotfiles/install primeagent/install HOME=<tmp>`; models.json is copied
#     (dotfiles/install would symlink it); settings and the machine are written into the temp HOME only.
#   - Every run where the model can act goes through pa-sandbox (bwrap), launched by a wrapper that sources
#     it unchanged and also masks the invoking user's real HOME (pa-sandbox's tmpfs masks are /tmp,
#     /run/user, /run/dbus and $HOME, which is the temp HOME here), re-binding read-only only this checkout
#     and the prime-agent binary dirs. Inside a sandbox the temp HOME is a tmpfs, so the only host paths a
#     model can write are the workspace (its .git is ro) and the agent dir's rw binds.
#   - Every host-side write into the agent dir (settings, models.json, the machine) happens before any
#     sandbox sees that dir: each phase runs in its own fresh copy (`cp -aT` of a host-only template into
#     the then non-existent ~/.prime/agent), and afterwards that copy is only renamed aside (`mv -T`), read
#     and finally removed (`chmod -R u+rwx`, then `rm -rf`; neither follows symlinks; a temp dir that
#     survives is reported and fails the run, exit 5). Session files a sandbox could have planted are
#     read only if they are regular files (find -type f; O_NOFOLLOW|O_NONBLOCK + fstat in python;
#     grep -D skip), and every find/grep/python/git read of the agent dir or workspace runs under `timeout`.
#   - The only host-side prime-agent run is the kernel pre-warm below. Its settings name a local socket that
#     never answers in every model slot (default, backup, subagent, auxiliary) and models.json lists only
#     that sink while it runs, so no model output (hence no tool call) can exist; it is killed as soon as
#     the kernel venv is ready.
#   - On exit every process whose environment has HOME=<tmp home> (or whose command line names it) is
#     SIGKILLed and reported; finding one makes the run fail (exit 4).
#   - Host-side ollama traffic: the tag listing and a load-only warm-up request (no prompt) per machine try.
#
# Deviations the phases need, and why (each is a finding about the shipped tools, not a fix):
#   - PA_SANDBOX_RO_EXTRA=<home>/.local/share/uv/python: the kernel venv's bin/python and pyvenv.cfg `home`
#     go through uv's minor-version symlink (cpython-3.11-linux-x86_64-gnu -> cpython-3.11.17-...). pa-sandbox
#     ro-binds only the resolved interpreter dir, so inside the sandbox the venv looks broken, prime-agent
#     tries to rebuild it in the read-only agent dir and the kernel never starts.
#   - Daemon phases add ONE rw bind of the (throwaway, per-phase) agent dir: under the read-only agent dir the 0.10.0
#     daemon fails with EROFS creating `daemon-workers/<sha256(socket)[:12]>/supervisor-config.tmp-*`, so no
#     daemon-backed session (hence no rlm.spawn / factory machine) is possible.
#   - The model is always given with --provider/--model: `-p` ignored settings' defaultProvider/defaultModel
#     in this setup and fell back to an unauthenticated amazon-bedrock fixture model.
#
# Exit codes: 0 all PASS (or SKIP: ollama/model/tool missing), 1 a FAIL, 2 setup error,
#             3 INCONCLUSIVE (case (a) or (b) above, in every machine try), 4 leftover processes after cleanup,
#             5 a temp dir could not be removed (exit codes 1-4 take precedence).
# Env: PA_E2E_OLLAMA_URL (http://127.0.0.1:11434), PA_E2E_TMP_PREFIX (/var/tmp/pa-e2e),
#      PA_E2E_MACHINE_TRIES (3), PA_E2E_KEEP=1 keeps the temp dirs, PA_SANDBOX_ALLOW_HOST_PROC (default 1:
#      hosts without a private /proc mount need it; pa-sandbox uses the host /proc only when the private
#      mount fails).
set -euo pipefail

here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
real_home="$(cd -P "${HOME:?}" && pwd)" # masked inside every sandbox launched here
root="$(cd -P "$here/../../../.." && pwd)"
OLLAMA_URL="${PA_E2E_OLLAMA_URL:-http://127.0.0.1:11434}"
PREFIX="${PA_E2E_TMP_PREFIX:-/var/tmp/pa-e2e}"
PROVIDER=local-ollama
MODEL=qwen3:4b-instruct # the local-ollama entry of models.json and the model pa-e2e-min names
MID="$PROVIDER/$MODEL"
MACHINE_SRC="$here/machines/pa-e2e-min/MACHINE.md"

log() { printf 'pa-e2e: %s\n' "$*"; }
skip() {
	printf 'SKIP: %s\n' "$1"
	exit 0
}
die() {
	printf 'pa-e2e: setup error: %s\n' "$1" >&2
	exit 2
}

# ---------------------------------------------------------------- preconditions (SKIP, exit 0)
for c in bwrap jq git curl script python3 make mkfifo timeout; do
	command -v "$c" >/dev/null 2>&1 || skip "$c not found in PATH"
done
pa_bin="$(command -v prime-agent 2>/dev/null)" || skip "prime-agent not found in PATH"
pa_dir="$(dirname "$pa_bin")"
tags="$(curl -fsS --max-time 5 "$OLLAMA_URL/api/tags" 2>/dev/null)" || skip "ollama not reachable at $OLLAMA_URL"
jq -e --arg m "$MODEL" 'any(.models[]?; .name == $m)' <<<"$tags" >/dev/null ||
	skip "ollama has no $MODEL (this script never pulls models)"
jq -e --arg m "$MODEL" 'any(.providers["local-ollama"].models[]?; .id == $m)' \
	"$root/agent/harnesses/primeagent/models.json" >/dev/null || die "models.json has no local-ollama/$MODEL"
[[ -f "$MACHINE_SRC" ]] || die "$MACHINE_SRC missing"

# ---------------------------------------------------------------- temp dirs and cleanup
H="$(mktemp -d "$PREFIX-home-XXXXXX")"
WS="$(mktemp -d "$PREFIX-ws-XXXXXX")"
PA="$H/.prime/agent"
L="$H/e2e-logs"
mkdir -p "$L" "$H/tmp" "$H/boot"
bg_pids=()

# SIGKILL every process that belongs to the temp HOME (environment HOME=<H>, or <H> on its command
# line); prints one line per process. Our own ancestors are never touched.
reap() {
	python3 -I - "$H" <<'PY'
import os, signal, sys
home = sys.argv[1].encode()
skip, p = set(), os.getpid()
while p > 1:
    skip.add(p)
    try:
        p = int(open(f"/proc/{p}/stat").read().rsplit(")", 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
        break
for e in os.listdir("/proc"):
    if not e.isdigit() or int(e) in skip:
        continue
    try:
        env = open(f"/proc/{e}/environ", "rb").read().split(b"\0")
        cmd = open(f"/proc/{e}/cmdline", "rb").read()
    except OSError:
        continue
    if b"HOME=" + home in env or home in cmd:
        print(e, cmd.replace(b"\0", b" ")[:120].decode(errors="replace"))
        try:
            os.kill(int(e), signal.SIGKILL)
        except OSError:
            pass
PY
}

# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() {
	local rc=$? p left
	trap - EXIT
	for p in "${bg_pids[@]}"; do kill "$p" 2>/dev/null || true; done
	left="$(reap)"
	if [[ -n "$left" ]]; then
		printf 'pa-e2e: leftover processes of the temp HOME were killed:\n%s\n' "$left" >&2
		[[ $rc -eq 0 ]] && rc=4
	fi
	if [[ "${PA_E2E_KEEP:-0}" == 1 ]]; then
		log "kept $H and $WS (PA_E2E_KEEP=1)"
	else
		# A sandboxed run can leave dirs without u+rwx (e.g. mode 000), which rm -rf cannot empty.
		# chmod -R does not follow symlinks met during the walk; $H and $WS are our own mktemp dirs.
		chmod -R u+rwx -- "$H" "$WS" 2>/dev/null || true
		command rm -rf -- "$H" "$WS" 2>/dev/null || true
		for p in "$H" "$WS"; do
			if [[ -e "$p" || -L "$p" ]]; then
				printf 'pa-e2e: could not remove %s\n' "$p" >&2
				[[ $rc -eq 0 ]] && rc=5
			fi
		done
	fi
	exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

user="$(id -un)"
base_env=(env -i HOME="$H" PATH="$H/.local/bin:$pa_dir:/usr/bin:/bin" LANG=C.UTF-8 USER="$user" LOGNAME="$user"
	XDG_CONFIG_HOME="$H/.config" XDG_DATA_HOME="$H/.local/share" XDG_CACHE_HOME="$H/.cache"
	XDG_STATE_HOME="$H/.local/state" TMPDIR="$H/tmp" PRIME_AGENT_DAEMON_SOCKET="$H/daemon.sock"
	PRIME_AGENT_TELEMETRY=0 DO_NOT_TRACK=1 OLLAMA_API_KEY=ollama)
sb_env=(PA_SANDBOX_ALLOW_HOST_PROC="${PA_SANDBOX_ALLOW_HOST_PROC:-1}" PA_SANDBOX_PASS_ENV=DO_NOT_TRACK
	PA_SANDBOX_RO_EXTRA="$H/.local/share/uv/python")

# ---------------------------------------------------------------- install into the temp HOME
log "temp HOME $H, workspace $WS"
"${base_env[@]}" make -C "$root" -o dotfiles/install primeagent/install HOME="$H" >"$L/install.log" 2>&1 ||
	{ tail -n 20 "$L/install.log" >&2; die "make primeagent/install failed"; }
command cp "$root/agent/harnesses/primeagent/models.json" "$PA/models.json"
mkdir -p "$PA/machines/pa-e2e-min"
command cp "$MACHINE_SRC" "$PA/machines/pa-e2e-min/MACHINE.md"
installed_allowed="$(jq -c --arg id "$MID" 'any(.allowedModels[]?; . == $id)' "$PA/settings.json")"
log "installed settings: factory.enabled=$(jq -c '.factory.enabled' "$PA/settings.json"), $MID in allowedModels=$installed_allowed"

# settings.A: local default model, first-run screens marked done, no MCP servers / autoRefine (no network
# side traffic); allowedModels as installed. settings.B: A plus the local model in allowedModels.
jq --arg p "$PROVIDER" --arg m "$MODEL" --arg id "$MID" '. + {defaultProvider: $p, defaultModel: $m,
		providerBackupModel: $id, subagentDefaultModel: $id, auxiliaryModel: $id, defaultThinkingLevel: "off",
		onboardingShown: true, onboardingCompleted: true}
	| .autoRefine.enabled = false | .telemetry.noticeShown = true | del(.mcpServers)' \
	"$PA/settings.json" >"$H/settings.A.json"
jq --arg id "$MID" '.allowedModels = ((.allowedModels // []) + [$id] | unique)' "$H/settings.A.json" >"$H/settings.B.json"
# settings.W (pre-warm only): every model slot (default, backup, subagent, auxiliary) names the sink.
jq '. + {defaultProvider: "pa-e2e-sink", defaultModel: "none", providerBackupModel: "pa-e2e-sink/none",
		subagentDefaultModel: "pa-e2e-sink/none", auxiliaryModel: "pa-e2e-sink/none"}
	| .allowedModels = ((.allowedModels // []) + ["pa-e2e-sink/none"] | unique)' \
	"$H/settings.A.json" >"$H/settings.W.json"
use_settings() { # <variant> [agent dir]; only for dirs no sandbox has seen yet
	local d=${2:-$PA}
	command cp --remove-destination "$H/settings.$1.json" "$d/settings.json"
	chmod 600 "$d/settings.json"
}

# ---------------------------------------------------------------- kernel venv pre-warm (host, no model)
# The sandbox's agent dir is read-only, so the kernel venv (with the Python skills, swarm-adapter
# included) must exist beforehand. `-p` builds it at startup while the model request hangs on a
# socket that accepts and never answers.
python3 -I -c '
import socket, sys
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(16)
open(sys.argv[1], "w").write(str(s.getsockname()[1]))
held = []
while True:
    held.append(s.accept()[0])
' "$H/sink.port" &
bg_pids+=($!)
for _ in $(seq 1 50); do [[ -s "$H/sink.port" ]] && break; sleep 0.1; done
[[ -s "$H/sink.port" ]] || die "sink did not start"
command cp "$PA/models.json" "$H/models.orig.json"
jq --arg u "http://127.0.0.1:$(cat "$H/sink.port")/v1" '.providers = {"pa-e2e-sink": {baseUrl: $u,
	apiKey: "OLLAMA_API_KEY", api: "openai-completions",
	models: [{id: "none", name: "never answers", contextWindow: 8192, maxTokens: 256, reasoning: false}]}}' \
	"$H/models.orig.json" >"$PA/models.json"
use_settings W
(cd "$H/boot" && exec "${base_env[@]}" PRIME_AGENT_BASH_COMMAND_PREFIX=". $PA/bin/prime-shell-guard.sh" \
	"$pa_bin" --no-session --provider pa-e2e-sink --model none -p warm </dev/null >"$L/prewarm.log" 2>&1) &
warm=$!
bg_pids+=("$warm")
warmed=0
for _ in $(seq 1 600); do
	if jq -e 'any(.python_skills[]?; .import_name == "swarm_adapter")' \
		"$PA/kernel-venv/.bootstrap-version" >/dev/null 2>&1; then
		warmed=1
		break
	fi
	kill -0 "$warm" 2>/dev/null || break
	sleep 1
done
kill "$warm" "${bg_pids[0]}" 2>/dev/null || true
wait "$warm" "${bg_pids[0]}" 2>/dev/null || true
bg_pids=()
command cp --remove-destination "$H/models.orig.json" "$PA/models.json"
[[ $warmed -eq 1 ]] || { tail -n 20 "$L/prewarm.log" >&2; die "kernel venv pre-warm did not finish"; }
left="$(reap)"
[[ -z "$left" ]] || log "pre-warm leftovers killed: $left"
log "kernel venv ready (python skills: $(jq -c '.python_skills | map(.import_name)' "$PA/kernel-venv/.bootstrap-version"))"

# Host-only templates, one per settings variant. No sandbox ever sees them (the temp HOME is a tmpfs
# inside every sandbox); each phase gets a fresh copy at $PA (see the header).
mv -T -- "$PA" "$H/agent-base"
for v in A B; do
	command cp -aT -- "$H/agent-base" "$H/agent-$v"
	use_settings "$v" "$H/agent-$v"
done
cur_phase=""
enter_phase() { # <settings variant> <phase tag>
	local left
	left="$(reap)"
	[[ -z "$left" ]] || log "leftover processes before phase $2 killed: $left"
	if [[ -n "$cur_phase" ]]; then
		mv -T -- "$PA" "$H/used-$cur_phase" # rename only; never written again
	fi
	command cp -aT -- "$H/agent-$1" "$PA"
	cur_phase=$2
}

# ---------------------------------------------------------------- helpers
plain() { sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$1" | tr -cd '[:print:]\n'; }

# session_query <mode> <arg> <file...> over session / --mode json JSON lines; exit 0 iff something matched.
# A file is read only if it is a regular file (not a symlink, FIFO, ...): sandboxed runs could plant one.
# "The given code" = an assistant tool call that contains every line of S, each stripped of surrounding
# blanks; status/results read only the toolResult whose toolCallId is the id of such a call (tool output
# of the given code only: the model can type a look-alike line in its reply or in another tool call).
#   toolcall  S  some assistant tool call is the given code (the model ran the code it was given)
#   status    S  print the first "PA-E2E-STATUS {...}" line of a toolResult of the given code
#   results   S  print (JSON-quoted) every string containing "PA-E2E-" of a toolResult of the given code
#   answer    J  a text part of an assistant message holds a JSON value equal to J (the child's answer;
#                JSON-strict: true never equals 1)
session_query() {
	timeout -k 5 60 python3 -I - "$@" <<'PY'
import json, os, re, stat, sys
mode, arg, files = sys.argv[1], sys.argv[2], sys.argv[3:]
def canon(v):
    # JSON-strict identity: json.dumps keeps true and 1 apart (Python's == does not).
    return json.dumps(v, sort_keys=True)
def lines(f):
    try:
        fd = os.open(f, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return []
    with os.fdopen(fd, "rb") as fh:
        if not stat.S_ISREG(os.fstat(fh.fileno()).st_mode):
            return []
        return fh.read().decode("utf-8", "replace").splitlines()
def strings(v):
    if isinstance(v, str):
        yield v
    elif isinstance(v, dict):
        for x in v.values():
            yield from strings(x)
    elif isinstance(v, list):
        for x in v:
            yield from strings(x)
def visit(v, role, hit):
    if isinstance(v, dict):
        if isinstance(v.get("role"), str):
            role = v["role"]
        if hit(v, role):
            return True
        return any(visit(x, role, hit) for x in v.values())
    if isinstance(v, list):
        return any(visit(x, role, hit) for x in v)
    return False
def objects():
    for f in files:
        for line in lines(f):
            try:
                yield json.loads(line)
            except ValueError:
                continue
needles = [n.strip() for n in arg.splitlines() if n.strip()]
call_ids, called = set(), []
def toolcall(v, role):
    t = v.get("type")
    if role != "assistant" or not isinstance(t, str) or "tool" not in t.lower():
        return False
    if all(n in "\n".join(strings(v)) for n in needles):
        called.append(1)
        if isinstance(v.get("id"), str) and v["id"]:
            call_ids.add(v["id"])
    return False
def own_result(v, role):
    return role == "toolResult" and v.get("toolCallId") in call_ids
def status(v, role):
    if own_result(v, role):
        for s in strings(v):
            for ln in s.splitlines():
                if ln.startswith("PA-E2E-STATUS {"):
                    print(ln[len("PA-E2E-STATUS "):])
                    return True
    return False
found = []
def results(v, role):
    if own_result(v, role):
        for s in strings(v):
            if "PA-E2E-" in s:
                print(json.dumps(s))
                found.append(1)
    return False
want = canon(json.loads(arg)) if mode == "answer" else None
dec = json.JSONDecoder()
def answer(v, role):
    s = v.get("text")
    if role != "assistant" or v.get("type") != "text" or not isinstance(s, str):
        return False
    for m in re.finditer(r"[\[{]", s):
        try:
            if canon(dec.raw_decode(s, m.start())[0]) == want:
                return True
        except ValueError:
            pass
    return False
if mode == "answer":
    sys.exit(0 if any(visit(o, None, answer) for o in objects()) else 1)
for o in objects():
    visit(o, None, toolcall)
if mode == "toolcall":
    sys.exit(0 if called else 1)
hit = {"status": status, "results": results}[mode]
for o in objects():
    if visit(o, None, hit):
        sys.exit(0)
sys.exit(0 if found else 1)
PY
}

# capture_report <status json> <want json>: one "<node> ok|wrong|none" line per state of <want>
# ({"<state>": {"<json output port>": <expected value>}}). "none": no answer_captured event for the
# state. Otherwise the state's answer_preview (the captured answer, rlm/factory.py _state_report) is
# parsed the way the runtime fills a json port (_parse_json_output: trailing ```json fences first, then
# the whole answer, first object holding the port name) and compared JSON-strictly with the expectation.
capture_report() {
	timeout -k 5 60 python3 -I - "$@" <<'PY'
import json, re, sys
status, want = json.loads(sys.argv[1]), json.loads(sys.argv[2])
fence = re.compile(r"```json\s*(.*?)\s*```", re.DOTALL)
def port(answer, name):
    for c in list(reversed(fence.findall(answer))) + [answer.strip()]:
        try:
            v = json.loads(c)
        except (ValueError, TypeError):
            continue
        if isinstance(v, dict) and name in v:
            return True, v[name]
    return False, None
captured = {e[1] for e in status.get("events") or [] if isinstance(e, list) and len(e) > 1 and e[0] == "answer_captured"}
preview = {n[0]: n[2] for n in status.get("nodes") or [] if isinstance(n, list) and len(n) > 2}
for node, ports in want.items():
    if node not in captured:
        print(node, "none")
        continue
    a = preview.get(node)
    good = isinstance(a, str)
    for name, expected in ports.items():
        hit, v = port(a, name) if good else (False, None)
        good = good and hit and json.dumps(v, sort_keys=True) == json.dumps(expected, sort_keys=True)
    print(node, "ok" if good else "wrong")
PY
}

# drive_tui <tag> <secs> <prompt file> <launcher> <stop regex on the screen> <marker in new session files>
# Runs the interactive (daemon-backed) UI under a pty, waits for the stop regex or the session marker,
# then leaves with /exit (Ctrl-C, then SIGTERM, as fallbacks). Sets TUI_OUTCOME; creates $L/<tag>.start.
drive_tui() {
	local tag=$1 secs=$2 prompt=$3 launcher=$4 stop=$5 marker=$6 inner fifo ts sp fd hits
	fifo="$H/tmp/$tag.fifo"
	ts="$L/$tag.typescript"
	: >"$L/$tag.start" # sessions of this phase are the ones newer than this
	mkfifo "$fifo"
	: >"$ts"
	inner="$(printf '%q ' "${base_env[@]}" TERM=xterm-256color "${sb_env[@]}" "$launcher" \
		--provider "$PROVIDER" --model "$MODEL")\"\$(cat $(printf '%q' "$prompt"))\""
	(cd "$WS" && SHELL=/bin/bash exec script -qfec "stty cols 200 rows 50; $inner" "$ts" <"$fifo" >/dev/null 2>&1) &
	sp=$!
	exec {fd}>"$fifo"
	TUI_OUTCOME=timeout
	SECONDS=0
	while ((SECONDS < secs)); do
		# grep -c (not -q) reads its whole input: an early exit would SIGPIPE the writer and, under
		# pipefail, turn a match into a failed pipeline.
		if plain "$ts" | grep -Ec "$stop" >/dev/null; then
			TUI_OUTCOME=stop
			break
		fi
		# Regular files only (-type f; grep -D skip): the sandbox can write here while this runs.
		hits="$(timeout -k 2 30 find "$PA/sessions" -type f -name '*.jsonl' -newer "$L/$tag.start" -print0 2>/dev/null |
			timeout -k 2 10 xargs -0 -r grep -D skip -lF "$marker" || true)"
		if [[ -n "$hits" ]]; then
			TUI_OUTCOME=marker
			sleep 10 # let the final reply land
			break
		fi
		kill -0 "$sp" 2>/dev/null || {
			TUI_OUTCOME=exited
			break
		}
		sleep 2
	done
	# Writes go through a subshell: once `script` is gone the fifo has no reader, and SIGPIPE on a builtin
	# write would kill this shell itself (no EXIT trap, no cleanup).
	(printf '/exit\r' >&"$fd") 2>/dev/null || true
	for _ in $(seq 1 30); do kill -0 "$sp" 2>/dev/null || break; sleep 1; done
	if kill -0 "$sp" 2>/dev/null; then
		(printf '\003\003' >&"$fd") 2>/dev/null || true
		sleep 5
	fi
	kill -0 "$sp" 2>/dev/null && kill -TERM "$sp" 2>/dev/null
	wait "$sp" 2>/dev/null || true
	exec {fd}>&-
	command rm -f "$fifo"
}

declare -A verdict=()

# ---------------------------------------------------------------- pa-sandbox wrappers
# Both source the installed pa-sandbox unchanged and only append bwrap mounts before its `--chdir <ws> --`
# tail. Every launch masks the invoking user's real HOME with a tmpfs (pa-sandbox masks $HOME, which is the
# temp HOME here, not the real one) and re-binds read-only the few dirs under it that the run needs: this checkout
# (the install symlinks point into it) and the prime-agent binary/bundle dirs. The daemon wrapper adds
# ONE rw bind of the phase's throwaway agent dir (see the header).
write_wrapper() { # <path> <agent rw: 0|1>
	local d ro=()
	# pa_dir/prime-agent is a launcher script that execs ../share/prime-agent/prime-agent.
	for d in "$root" "$pa_dir" "$(dirname "$(readlink -f "$pa_bin")")" "$pa_dir/../share/prime-agent"; do
		[[ -d "$d" ]] && d="$(cd -P "$d" && pwd)" && ro+=(--ro-bind "$d" "$d")
	done
	cat >"$1" <<EOF
#!/usr/bin/env bash
# E2E only, generated by run-ollama-e2e.sh.
set -euo pipefail
# shellcheck source=/dev/null
. $(printf '%q' "$H/.local/bin/pa-sandbox")
eval "_pa_e2e_orig_build_argv() \$(declare -f pa_sandbox_build_argv | tail -n +2)"
pa_sandbox_build_argv() {
	_pa_e2e_orig_build_argv "\$@" || return
	local n=\${#PA_BWRAP_ARGV[@]} extra=(--tmpfs $(printf '%q' "$real_home") $(printf '%q ' "${ro[@]}"))
	[[ "\${PA_BWRAP_ARGV[n-3]}" == --chdir && "\${PA_BWRAP_ARGV[n-1]}" == -- ]] || {
		echo "pa-e2e wrapper: unexpected bwrap argv tail" >&2
		return 1
	}
	if [[ $2 == 1 ]]; then
		local agent
		agent="\$(cd -P "\$HOME/.prime/agent" && pwd)"
		extra+=(--bind "\$agent" "\$agent")
	fi
	PA_BWRAP_ARGV=("\${PA_BWRAP_ARGV[@]:0:n-3}" "\${extra[@]}" "\${PA_BWRAP_ARGV[@]:n-3}")
}
pa_sandbox_main "\$@"
EOF
	chmod 700 "$1"
}
write_wrapper "$H/pa-sandbox-e2e" 0
write_wrapper "$H/pa-sandbox-daemon-e2e" 1

# ---------------------------------------------------------------- phase 1: guard (pa-sandbox, no extra rw)
git -C "$WS" init -q -b main
printf 'x\n' >"$WS/untracked.txt"
cat >"$H/guard.prompt" <<'PROMPT'
Use your Python tool to execute exactly the following code once, unchanged, then reply with the printed lines verbatim and nothing else:
r1 = await bash('touch PA-E2E-ALLOW && git status --short')
print('PA-E2E-ALLOW-RESULT', r1.exit_code, repr(r1.output))
r2 = await bash('touch PA-E2E-LEAK && git add -A')
print('PA-E2E-BLOCK-RESULT', r2.exit_code, repr(r2.output))
PROMPT
enter_phase B guard
log "phase guard: pa-sandbox -p (model $MID)"
grc=0
(cd "$WS" && exec timeout -k 10 400 "${base_env[@]}" TERM=dumb "${sb_env[@]}" "$H/pa-sandbox-e2e" \
	--mode json --provider "$PROVIDER" --model "$MODEL" -p "$(cat "$H/guard.prompt")" \
	</dev/null >"$L/guard.jsonl" 2>"$L/guard.err") || grc=$?
results="$(session_query results "$(sed 1d "$H/guard.prompt")" "$L/guard.jsonl" | grep -F 'RESULT ' || true)"
allow_line="$(grep -m1 -o 'PA-E2E-ALLOW-RESULT [0-9]*' <<<"$results" || true)"
block_line="$(grep -m1 -o 'PA-E2E-BLOCK-RESULT [0-9]*' <<<"$results" || true)"
guard_msg=no
grep -qF 'prime-shell-guard: BLOCKED by security-rules.json' <<<"$results" && guard_msg=yes
# The workspace's .git was read-only inside the sandbox (pa-sandbox ro-binds it).
staged="$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 timeout -k 5 30 git -C "$WS" ls-files --cached | wc -l)"
allow_file=no leak_file=no
[[ -e "$WS/PA-E2E-ALLOW" ]] && allow_file=yes
[[ -e "$WS/PA-E2E-LEAK" ]] && leak_file=yes
ran=no
session_query toolcall "$(sed 1d "$H/guard.prompt")" "$L/guard.jsonl" && ran=yes
log "guard: pa-sandbox rc=$grc; tool call with the given code=$ran; '${allow_line:-no allow result}'; '${block_line:-no block result}'; guard message=$guard_msg"
log "guard: workspace PA-E2E-ALLOW=$allow_file PA-E2E-LEAK=$leak_file index entries=$staged"
if [[ "$leak_file" == yes || "$staged" != 0 ]]; then
	verdict[guard]=FAIL # the blocked command took effect, whoever ran it
elif [[ "$ran" == no ]]; then
	verdict[guard]=INCONCLUSIVE
	tail -n 5 "$L/guard.err" >&2
elif [[ "$allow_line" == 'PA-E2E-ALLOW-RESULT 0' && "$block_line" == 'PA-E2E-BLOCK-RESULT 126' &&
	"$guard_msg" == yes && "$allow_file" == yes ]]; then
	verdict[guard]=PASS
else
	verdict[guard]=FAIL
	tail -n 5 "$L/guard.err" >&2
fi

cat >"$H/machine.prompt" <<'PROMPT'
Use your Python tool to execute exactly the following code once, unchanged, then reply with the printed lines verbatim and nothing else:
import asyncio, json
r = await rlm.factory.run("pa-e2e-min")
s = None
for _ in range(100):
    s = await rlm.factory.status(r["run_id"])
    if s["state"] not in ("running", "stopping"):
        break
    await asyncio.sleep(3)
print("PA-E2E-STATUS", json.dumps({"run_id": r["run_id"], "state": s["state"], "nodes": [[n["id"], n["status"], n.get("answer_preview")] for n in s["nodes"]], "events": [[e.get("kind"), e.get("node"), e.get("from"), e.get("to"), e.get("status")] for e in s["events"]]}))
PROMPT

# The correct answer of each pa-e2e-min state (its prompt asks for exactly this JSON), and the json
# output port values the factory must capture from it (MACHINE.md: port "ping" of ping, "pong" of pong).
declare -A want_answer=([ping]='{"ping": {"ok": true}}' [pong]='{"pong": {"done": true}}')
want_ports='{"ping": {"ping": {"ok": true}}, "pong": {"pong": {"done": true}}}'

# judge_machine <tag>: one machine attempt (verdicts: see the header); sets verdict[machine].
# Status events are [kind, node, from, to, status].
judge_machine() {
	local tag=$1 status_json files=() kids=() late n missing="" caps wrong
	drive_tui "$tag" 420 "$H/machine.prompt" "$H/pa-sandbox-daemon-e2e" \
		'blocked by the daemon model allowlist|turn failed' 'PA-E2E-STATUS {'
	if [[ "$TUI_OUTCOME" == stop ]]; then
		log "machine: FAIL, the screen shows: $(plain "$L/$tag.typescript" | grep -Eo '.{0,80}(blocked by the daemon model allowlist|turn failed)[^.]{0,120}' | head -n1)"
		verdict[machine]=FAIL
		return
	fi
	mapfile -d '' files < <(timeout -k 2 30 find "$PA" -type f -name '*.jsonl' -newer "$L/$tag.start" -print0 2>/dev/null)
	if ((${#files[@]} == 0)) || ! session_query toolcall "$(sed 1d "$H/machine.prompt")" "${files[@]}"; then
		log "machine: INCONCLUSIVE, no tool call carries every line of the given code (outcome=$TUI_OUTCOME); screen tail: $(plain "$L/$tag.typescript" | tail -c 300)"
		verdict[machine]=INCONCLUSIVE
		return
	fi
	status_json="$(session_query status "$(sed 1d "$H/machine.prompt")" "${files[@]}" || true)"
	if [[ -z "$status_json" ]] || ! jq -e 'type == "object" and (.nodes | type) == "array" and (.events | type) == "array"' \
		<<<"$status_json" >/dev/null 2>&1; then
		log "machine: FAIL, the given code ran but no PA-E2E-STATUS payload came back in its tool result (outcome=$TUI_OUTCOME); screen tail: $(plain "$L/$tag.typescript" | tail -c 300)"
		verdict[machine]=FAIL
		return
	fi
	log "machine: $(jq -c '{state, nodes, events: [.events[] | map(select(. != null) | tostring) | join(":")]}' <<<"$status_json")"
	# 1. FAIL: run not `done`, a node in error/cancelled, an error settle, node_error or retry.
	if ! jq -e '.state == "done" and all(.nodes[]; .[1] == "done" or .[1] == "pending")
		and all(.events[]; .[4] != "error" and .[0] != "node_error" and .[0] != "retry")' <<<"$status_json" >/dev/null; then
		log "machine: FAIL, the run did not end cleanly done"
		verdict[machine]=FAIL
		return
	fi
	caps="$(capture_report "$status_json" "$want_ports")" || {
		log "machine: FAIL, capture check failed"
		verdict[machine]=FAIL
		return
	}
	log "machine: captured answers: $(tr '\n' ' ' <<<"$caps")"
	# A captured answer that is not the expected port value is a FAIL.
	wrong="$(awk '$2 == "wrong" {printf "%s ", $1}' <<<"$caps")"
	if [[ -n "$wrong" ]]; then
		log "machine: FAIL, wrong captured answer: [${wrong% }]"
		verdict[machine]=FAIL
		return
	fi
	# 2. Case (b): nodes settled `done` with no captured answer (on the clean `done` run above).
	late="$(jq -r '[.events[] | select(.[0] == "settled" and .[4] == "done") | .[1]]
		- [.events[] | select(.[0] == "answer_captured") | .[1]] | unique | join(" ")' <<<"$status_json")"
	if [[ -n "$late" ]]; then
		# Child transcripts live at session-artifacts/<parent session>/sub-*/<child session>.jsonl.
		mapfile -d '' kids < <(timeout -k 2 30 find "$PA/session-artifacts" -type f -path '*/sub-*/*.jsonl' \
			! -name semantic-edges.jsonl -newer "$L/$tag.start" -print0 2>/dev/null)
		for n in $late; do
			[[ -n "${want_answer[$n]:-}" ]] && ((${#kids[@]} > 0)) &&
				jq -e --arg n "$n" 'any(.nodes[]; .[0] == $n and .[1] == "done")' <<<"$status_json" >/dev/null &&
				session_query answer "${want_answer[$n]}" "${kids[@]}" || missing+=" $n"
		done
		if [[ -z "$missing" ]]; then
			log "machine: INCONCLUSIVE, factory settled [$late] done without a captured answer; the child transcript has the correct answer"
			verdict[machine]=INCONCLUSIVE
		else
			log "machine: FAIL, settled without a captured answer: [$late]; no correct answer in a child transcript: [${missing# }]"
			verdict[machine]=FAIL
		fi
		return
	fi
	# 3. PASS: ping -> pong fired, both nodes done, both answers captured and correct.
	if jq -e '(.nodes | map(.[0:2])) == [["ping", "done"], ["pong", "done"]]
		and any(.events[]; .[0] == "transition_fired" and .[2] == "ping" and .[3] == "pong")' <<<"$status_json" >/dev/null &&
		[[ "$(awk '$2 == "ok" {print $1}' <<<"$caps" | sort | tr '\n' ' ')" == "ping pong " ]]; then
		verdict[machine]=PASS
		return
	fi
	# 4. Anything else.
	log "machine: FAIL, not done through ping -> pong with both answers captured"
	verdict[machine]=FAIL
}

enter_phase A allowlist
log "phase allowlist: daemon session, $MID NOT in allowedModels"
drive_tui allowlist 240 "$H/machine.prompt" "$H/pa-sandbox-daemon-e2e" 'blocked by the daemon model allowlist' 'PA-E2E-STATUS {'
msg="$(plain "$L/allowlist.typescript" | grep -o 'is blocked by the daemon model allowlist[^.]*' | head -n1 || true)"
log "allowlist: outcome=$TUI_OUTCOME${msg:+; daemon said: \"$msg\"}"
# The refusal comes before any model output, so anything but the refusal is a FAIL.
if [[ "$TUI_OUTCOME" == stop ]]; then verdict[allowlist]=PASS; else verdict[allowlist]=FAIL; fi

tries="${PA_E2E_MACHINE_TRIES:-3}"
for ((try = 1; try <= tries; try++)); do
	enter_phase B "machine$try"
	# Load the model before the run so neither child waits on a cold load (load only: no prompt).
	curl -fsS --max-time 180 "$OLLAMA_URL/api/generate" \
		-d "$(jq -cn --arg m "$MODEL" '{model: $m, keep_alive: "10m"}')" >/dev/null 2>&1 ||
		log "machine: ollama warm-up request failed (continuing)"
	log "phase machine (attempt $try/$tries): daemon session, rlm.factory.run(\"pa-e2e-min\")"
	judge_machine "machine$try"
	[[ "${verdict[machine]}" == INCONCLUSIVE ]] || break
done

# ---------------------------------------------------------------- summary
rc=0
for ph in guard allowlist machine; do
	printf '%-10s %s\n' "$ph" "${verdict[$ph]}"
	case "${verdict[$ph]}" in
	FAIL) rc=1 ;;
	INCONCLUSIVE) [[ $rc -eq 0 ]] && rc=3 ;;
	esac
done
exit "$rc"
