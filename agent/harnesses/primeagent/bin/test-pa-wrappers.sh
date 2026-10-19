#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2030,SC2031  # A&&B||C is the ok/bad reporter idiom; single quotes defer expansion to the sandbox shell
# Tests for pa-auto (gate detection) and pa-sandbox (bwrap profile).
# No network, no paid calls, never writes the real HOME (pa-sandbox only reads the
# passwd home's symlinks / mounts, HOME SYMLINKS): every case uses a
# fake HOME under a fresh mktemp dir. Sandbox cases run harmless shell commands
# inside the exact bwrap argv that pa-sandbox builds (pa_sandbox_build_argv).
set -euo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PA_AUTO="$HERE/pa-auto"
PA_SANDBOX="$HERE/pa-sandbox"

# The fixture tree lives OUTSIDE /tmp (the sandbox mounts a tmpfs over /tmp, which
# would hide it instead of the HOME tmpfs under test) and OUTSIDE the real $HOME
# (never expose real-home paths to experiments). Default: /var/tmp.
PA_TEST_ROOT="${PA_TEST_ROOT:-/var/tmp}"
mkdir -p "$PA_TEST_ROOT"
T="$(mktemp -d "$PA_TEST_ROOT/pa-wrappers-test.XXXXXX")"
case "$T" in
/tmp/* | "$HOME"/* | "$HOME")
	echo "fixture root must be outside /tmp and \$HOME: $T" >&2
	command rm -rf "$T"
	exit 2
	;;
esac
trap 'command rm -rf "$T"' EXIT
FAIL=0 PASS=0

# Hermetic git: never the real global config, system config or signing key.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
	GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2:-}"; }
# expect <name> <expected-substring-or-exact> <actual>
expect_eq() { [[ "$2" == "$3" ]] && ok "$1" || bad "$1" "want [$2] got [$3]"; }
expect_has() { [[ "$3" == *"$2"* ]] && ok "$1" || bad "$1" "want substring [$2] in [$3]"; }
expect_lacks() { [[ "$3" != *"$2"* ]] && ok "$1" || bad "$1" "unexpected [$2] in [$3]"; }

mkrepo() { # mkrepo <dir>
	mkdir -p "$1"
	git -C "$1" init -q
}

# ---------------------------------------------------------------- pa-auto
export PA_SANDBOX_TEST_STUB=1
for f in "$PA_AUTO" "$PA_SANDBOX"; do
	[[ -x "$f" ]] && ok "exists+executable: ${f##*/}" || bad "exists+executable: ${f##*/}"
done

# table: name | files (name:content;...) | expected -n stdout gates
run_auto_case() { # <name> <repo> <expected-substring...>
	local name="$1" repo="$2" out
	shift 2
	out="$(cd "$repo" && "$PA_AUTO" -n 2>&1 || true)"
	for want in "$@"; do expect_has "$name: has [$want]" "$want" "$out"; done
}

R="$T/r-make"
mkrepo "$R"
printf 'lint:\n\t@echo l\ntest:\n\t@echo t\n' >"$R/Makefile"
run_auto_case "make lint+test" "$R" "--autonomous-gate 'make lint'" "--autonomous-gate 'make test'" "pa-sandbox"

R="$T/r-make-test-only"
mkrepo "$R"
printf 'test:\n\t@echo t\n' >"$R/Makefile"
touch "$R/go.mod"
out="$(cd "$R" && "$PA_AUTO" -n 2>&1 || true)"
expect_has "make test only: make test" "'make test'" "$out"
expect_lacks "make test only: no lint gate" "make lint" "$out"
expect_lacks "make present: no go fallback" "go test" "$out"

R="$T/r-make-no-targets"
mkrepo "$R"
printf 'build:\n\t@echo b\n' >"$R/Makefile"
printf 'module x\n' >"$R/go.mod"
run_auto_case "makefile without lint/test falls back to go" "$R" "'go vet ./...'" "'go test ./...'"

R="$T/r-go"
mkrepo "$R"
printf 'module x\n' >"$R/go.mod"
run_auto_case "go defaults" "$R" "'go vet ./...'" "'go test ./...'"

R="$T/r-cargo"
mkrepo "$R"
touch "$R/Cargo.toml"
run_auto_case "cargo defaults" "$R" "'cargo check'" "'cargo test'"

R="$T/r-npm"
mkrepo "$R"
printf '{"scripts":{"test":"jest"}}\n' >"$R/package.json"
run_auto_case "npm test script" "$R" "'npm test'"

R="$T/r-py"
mkrepo "$R"
printf '[project]\nname="x"\n' >"$R/pyproject.toml"
run_auto_case "python defaults" "$R" "'python3 -m pytest'"

# Detection must never invoke make (make -q evaluates $(shell ...) on the host).
R="$T/r-make-shell"
mkrepo "$R"
printf 'X := $(shell touch %s/marker)\nlint:\n\t@echo l\nlint2:=1\n' "$R" >"$R/Makefile"
out="$(cd "$R" && "$PA_AUTO" -n 2>&1 || true)"
[[ ! -e "$R/marker" ]] && ok "pa-auto -n does not execute the Makefile" || bad "pa-auto -n does not execute the Makefile" "marker created"
expect_has "textual detection finds lint" "'make lint'" "$out"
expect_lacks "var assignment lint2:=1 is not a target" "lint2" "$out"
R="$T/r-make-assign"
mkrepo "$R"
printf 'lint::=1\ntest ::= x\nlint ?= 2\ntest += 3\nlint != echo\nbuild:\n\t@true\n' >"$R/Makefile"
out="$(cd "$R" && "$PA_AUTO" -n 2>&1 || true)"
expect_lacks "assignment forms (::= ?= += !=) are not targets: lint" "'make lint'" "$out"
expect_lacks "assignment forms are not targets: test" "'make test'" "$out"
R="$T/r-make-dcolon"
mkrepo "$R"
printf 'lint::\n\t@true\n' >"$R/Makefile"
out="$(cd "$R" && "$PA_AUTO" -n 2>&1 || true)"
expect_has "double-colon rule lint:: is a target" "'make lint'" "$out"
R="$T/r-make-tsv"
mkrepo "$R"
printf 'build:\n\t@true\ntest: CFLAGS = -O2\nlint: override X := 1\nlint: export Y = 1\ntest: private Z = 1\n' >"$R/Makefile"
printf 'module x\n' >"$R/go.mod"
out="$(cd "$R" && "$PA_AUTO" -n 2>&1 || true)"
expect_lacks "target-specific vars are not rules: lint" "'make lint'" "$out"
expect_lacks "target-specific vars are not rules: test" "'make test'" "$out"
expect_has "target-specific vars only -> go defaults" "'go test ./...'" "$out"
R="$T/r-make-phony"
mkrepo "$R"
printf '.PHONY: lint test\nbuild:\n\t@true\nfoo test: dep\n\t@true\n' >"$R/Makefile"
out="$(cd "$R" && "$PA_AUTO" -n 2>&1 || true)"
expect_has "multi-target line finds test" "'make test'" "$out"
expect_lacks ".PHONY alone does not define lint" "make lint" "$out"

R="$T/r-none"
mkrepo "$R"
out="$(cd "$R" && "$PA_AUTO" -n 2>&1)" && rc=0 || rc=$?
expect_eq "no gates detected -> nonzero" "2" "$rc"
expect_has "no gates detected -> message" "no gates" "$out"

R="$T/r-override"
mkrepo "$R"
printf 'lint:\n\t@echo l\n' >"$R/Makefile"
out="$(cd "$R" && "$PA_AUTO" -n --gate 'just ci' --gate 'echo two words' 2>&1 || true)"
expect_has "override gate 1" "--autonomous-gate 'just ci'" "$out"
expect_has "override gate 2" "--autonomous-gate 'echo two words'" "$out"
expect_lacks "override disables detection" "make lint" "$out"

# passthrough args + non -n execution through a stub pa-sandbox
STUB="$T/stub-sandbox"
printf '#!/bin/sh\nprintf "STUB:"; for a in "$@"; do printf " [%%s]" "$a"; done; echo\n' >"$STUB"
chmod +x "$STUB"
R="$T/r-pass"
mkrepo "$R"
touch "$R/go.mod"
out="$(cd "$R" && PA_SANDBOX="$STUB" "$PA_AUTO" -p "do it" 2>/dev/null)"
expect_has "exec passes --autonomous" "[--autonomous]" "$out"
expect_has "exec passes gate pair" "[--autonomous-gate] [go test ./...]" "$out"
expect_has "exec passes user args last" "[-p] [do it]" "$out"
err="$(cd "$R" && PA_SANDBOX="$STUB" "$PA_AUTO" -p x 2>&1 >/dev/null)"
expect_has "resolved command printed to stderr first" "pa-auto: stub-sandbox --autonomous" "$err"

# ------------------------------------------------------------- pa-sandbox
if ! command -v bwrap >/dev/null 2>&1; then
	bad "bwrap available for sandbox tests" "bwrap missing"
else
	# hermetic HOME SYMLINKS / git config scan: no launch env from the caller's own shell setup
	# (XDG_CONFIG_HOME / XDG_DATA_HOME / ZDOTDIR are HOME SYMLINKS scan roots, git reads XDG_CONFIG_HOME)
	unset DOTFILES_DIR ZCACHE_DIR ZDOTDIR XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME XDG_CONFIG_DIRS XDG_DATA_DIRS ENV BASH_ENV
	# ... and no symlinks of the caller's passwd home (pa-sandbox scans every home, `getent passwd
	# <uid>` too): a stub getent names $HOME as the passwd home
	mkdir -p "$T/stub-bin"
	printf '#!/bin/sh\nprintf "u:x:%%s:%%s::%%s:/bin/sh\\n" "$(id -u)" "$(id -g)" "$HOME"\n' >"$T/stub-bin/getent"
	chmod +x "$T/stub-bin/getent"
	export PATH="$T/stub-bin:$PATH"
	FH="$T/home"
	mkdir -p "$FH/.ssh" "$FH/.aws" "$FH/.gnupg" "$FH/.kube" "$FH/.config/gh" \
		"$FH/.password-store" "$FH/.prime/agent/bin" "$FH/.local/bin" "$FH/.local/share/prime-agent" "$FH/work"
	for p in .ssh/id_x .aws/credentials .gnupg/key .kube/config .config/gh/hosts.yml .netrc \
		.password-store/s.gpg work/.env outside.txt; do
		printf 'SENTINEL-SECRET\n' >"$FH/$p"
	done
	# The guard is a symlink into a fake dotfiles tree under the fake HOME (the real
	# install layout); the tree holds real copies of the guard's dependencies.
	DOT="$FH/dotfiles"
	mkdir -p "$DOT/agent/scripts/hooks"
	REAL_ROOT="$(cd -P "$HERE/../../../.." && pwd)"
	command cp "$REAL_ROOT/agent/scripts/prime-shell-guard.sh" "$DOT/agent/scripts/"
	command cp "$REAL_ROOT/agent/scripts/hooks/decide.py" "$REAL_ROOT/agent/scripts/hooks/rule_engine.py" "$DOT/agent/scripts/hooks/"
	command cp "$REAL_ROOT/agent/security-rules.json" "$DOT/agent/"
	ln -s "$DOT/agent/scripts/prime-shell-guard.sh" "$FH/.prime/agent/bin/prime-shell-guard.sh"
	# trusted files/dirs an unsandboxed run later executes or reads
	mkdir -p "$FH/.prime/agent/machines" "$FH/.prime/agent/kernel-venv/bin" \
		"$FH/.prime/agent/sessions" "$FH/.data/uv/python/cpy/bin" "$DOT/agent/primeskills" "$DOT/agent/agents" "$DOT/agent/harnesses/primeagent"
	# install.mk-like layout: skills/agents/AGENTS.md/models.json are symlinks into the checkout
	printf 'TRUSTED\n' >"$DOT/agent/primeskills/s.md"
	printf 'TRUSTED\n' >"$DOT/agent/agents/a.md"
	printf 'TRUSTED\n' >"$DOT/agent/AGENTS.md"
	printf 'TRUSTED\n' >"$DOT/agent/harnesses/primeagent/models.json"
	ln -s "$DOT/agent/primeskills" "$FH/.prime/agent/skills"
	ln -s "$DOT/agent/agents" "$FH/.prime/agent/agents"
	ln -s "$DOT/agent/AGENTS.md" "$FH/.prime/agent/AGENTS.md"
	ln -s "$DOT/agent/harnesses/primeagent/models.json" "$FH/.prime/agent/models.json"
	mkdir -p "$FH/.prime/agent/harness" "$FH/.prime/agent/daemon-workers/w1"
	printf 'TRUSTED\n' >"$FH/.prime/agent/mcp-service-catalog.v2.json"
	printf 'TRUSTED\n' >"$FH/.prime/agent/daemon-workers/w1/supervisor-config"
	printf 'T\n' >"$FH/.prime/agent/telemetry.json"
	printf 'T\n' >"$FH/.prime/agent/telemetry.jsonl"
	printf '{}\n' >"$FH/.prime/agent/harness/harness_state.json"
	printf '[]\n' >"$FH/.prime/agent/cron-jobs.json"
	for f in settings.json auth.json machines/m.json kernel-venv/pkg.py; do
		printf 'TRUSTED\n' >"$FH/.prime/agent/$f"
	done
	printf '#!/bin/sh\necho interp\n' >"$FH/.data/uv/python/cpy/bin/python3.11"
	chmod +x "$FH/.data/uv/python/cpy/bin/python3.11"
	ln -s "$FH/.data/uv/python/cpy/bin/python3.11" "$FH/.prime/agent/kernel-venv/bin/python"
	REPO="$FH/work/repo"
	mkrepo "$REPO"
	printf 'inrepo\n' >"$REPO/.env"
	printf 'SENTINEL-SECRET\n' >"$FH/.env"
	# real unix sockets: a stand-in docker socket, and a "host daemon" socket in /tmp
	mkdir -p "$T/socks"
	python3 -I -c 'import socket,sys,time
s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(1); time.sleep(120)' "$T/socks/docker.sock" &
	SOCKPID=$!
	HOSTTMP="$(mktemp -d /tmp/pa-hostdaemon.XXXXXX)"
	python3 -I -c 'import socket,sys,time
s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(1); time.sleep(120)' "$HOSTTMP/daemon.sock" &
	SOCK2PID=$!
	trap 'kill $SOCKPID $SOCK2PID 2>/dev/null || true; command rm -rf "$T" "$HOSTTMP"' EXIT
	sleep 0.5
	export PA_SANDBOX_MASK_PATHS="$T/socks/docker.sock"

	# shellcheck source=pa-sandbox
	source "$PA_SANDBOX"
	# Hosts that cannot mount a private /proc need the explicit opt-in; the
	# fail-closed behaviour itself is asserted below.
	if ! bwrap --ro-bind / / --unshare-pid --proc /proc true 2>/dev/null; then
		printf 'note: private /proc unavailable here; sandbox cases use PA_SANDBOX_ALLOW_HOST_PROC=1\n'
		HOST_PROC_DEGRADED=1
		export PA_SANDBOX_ALLOW_HOST_PROC=1
	fi
	run_in() { # run_in <sh-snippet>; runs in the real built profile
		(
			cd "$REPO"
			export HOME="$FH" SSH_AUTH_SOCK=/x/agent AWS_SECRET_ACCESS_KEY=leak GITHUB_TOKEN=leak OLLAMA_API_KEY=keepme
			pa_sandbox_build_argv "$REPO" 2>/dev/null
			"${PA_BWRAP_ARGV[@]}" sh -c "$1"
		) 2>&1
	}

	# Positive control first: a broken bwrap invocation would make every
	# "hides" assertion below pass vacuously.
	out="$(run_in "echo alive")" || true
	expect_eq "sandbox runs commands (positive control)" "alive" "$(printf '%s' "$out" | tail -n1)"

	run_mut() { # same profile WITHOUT the --tmpfs $HOME pair (mutation: proves the hide tests have teeth)
		(
			cd "$REPO"
			export HOME="$FH"
			pa_sandbox_build_argv "$REPO" 2>/dev/null
			local -a mut=()
			local i=0
			while [[ $i -lt ${#PA_BWRAP_ARGV[@]} ]]; do
				if [[ "${PA_BWRAP_ARGV[$i]}" == --tmpfs && "${PA_BWRAP_ARGV[$((i + 1))]}" == "$FH" ]]; then
					i=$((i + 2))
					continue
				fi
				mut+=("${PA_BWRAP_ARGV[$i]}")
				i=$((i + 1))
			done
			"${mut[@]}" sh -c "$1"
		) 2>&1
	}
	for p in .ssh/id_x .aws/credentials .gnupg/key .kube/config .config/gh/hosts.yml .netrc \
		.password-store/s.gpg work/.env .env outside.txt; do
		out="$(run_mut "cat \"\$HOME/$p\"" || true)"
		expect_has "MUTATION (no HOME tmpfs) leaks \$HOME/$p" "SENTINEL-SECRET" "$out"
	done
	for p in .ssh/id_x .aws/credentials .gnupg/key .kube/config .config/gh/hosts.yml .netrc \
		.password-store/s.gpg work/.env .env outside.txt; do
		out="$(run_in "cat \"\$HOME/$p\"" || true)"
		expect_lacks "sandbox hides \$HOME/$p" "SENTINEL-SECRET" "$out"
	done
	out="$(run_in 'cat "$HOME/work/repo/.env"')"
	expect_eq "sandbox exposes repo .env" "inrepo" "$out"

	run_in 'echo hi > "$HOME/work/repo/created-in-repo"' >/dev/null
	[[ -f "$REPO/created-in-repo" ]] && ok "write inside repo persists" || bad "write inside repo persists"

	run_in 'echo hi > "$HOME/created-outside" || true; echo hi > "$HOME/.ssh/planted" || true' >/dev/null
	[[ ! -e "$FH/created-outside" && ! -e "$FH/.ssh/planted" ]] \
		&& ok "write to \$HOME outside binds does not persist" || bad "write to \$HOME outside binds does not persist"

	run_in 'echo state > "$HOME/.prime/agent/sessions/state-file"; echo x > "$HOME/.prime/agent/root-file" 2>/dev/null; true' >/dev/null
	[[ -f "$FH/.prime/agent/sessions/state-file" && ! -e "$FH/.prime/agent/root-file" ]] && ok "agent dir: state dirs writable, root writes do not reach the host" || bad "agent dir: state dirs writable, root writes do not reach the host"

	run_in 'echo x > /usr/pa-test-write || true' >/dev/null
	[[ ! -e /usr/pa-test-write ]] && ok "/usr is read-only" || bad "/usr is read-only"

	out="$(run_in 'env')"
	for k in SSH_AUTH_SOCK AWS_SECRET_ACCESS_KEY GITHUB_TOKEN; do
		expect_lacks "env cleared: $k" "$k=" "$out"
	done
	expect_has "env allowlist keeps provider key" "OLLAMA_API_KEY=keepme" "$out"
	expect_has "env sets guard prefix" 'PRIME_AGENT_BASH_COMMAND_PREFIX=. "$HOME/.prime/agent/bin/prime-shell-guard.sh"' "$out"
	expect_has "env sets own daemon socket" "PRIME_AGENT_DAEMON_SOCKET=/tmp/pa-sandbox/" "$out"
	expect_has "env sets coding agent dir" "PRIME_AGENT_CODING_AGENT_DIR=$FH/.prime/agent" "$out"

	out="$(run_in 'ls /run/user/ 2>&1 | wc -l; test -s /run/docker.sock && echo DOCKER-VISIBLE || echo docker-hidden')"
	expect_has "docker socket masked" "docker-hidden" "$out"

	# (1) trusted agent-dir paths are read-only; host copies unchanged
	for p in bin/prime-shell-guard.sh settings.json models.json AGENTS.md auth.json skills/s.md agents/a.md machines/m.json kernel-venv/pkg.py; do
		before="$(cat "$FH/.prime/agent/$p" 2>/dev/null || true)"
		run_in "printf 'ATTACK\\n' > \"\$HOME/.prime/agent/$p\" || true; command rm -f \"\$HOME/.prime/agent/$p\" || true" >/dev/null
		after="$(cat "$FH/.prime/agent/$p" 2>/dev/null || true)"
		[[ -n "$after" && "$before" == "$after" && "$after" != *ATTACK* ]] \
			&& ok "agent-dir $p cannot be modified/removed" || bad "agent-dir $p cannot be modified/removed" "before=[$before] after=[$after]"
	done
	for d in bin skills machines kernel-venv; do
		run_in "touch \"\$HOME/.prime/agent/$d/planted\" || true" >/dev/null
		[[ ! -e "$FH/.prime/agent/$d/planted" ]] && ok "agent-dir $d/ cannot gain files" || bad "agent-dir $d/ cannot gain files"
	done
	run_in 'cp /dev/null "$HOME/.prime/agent/sessions/new-session"' >/dev/null
	[[ -e "$FH/.prime/agent/sessions/new-session" ]] && ok "sessions/ stays writable" || bad "sessions/ stays writable"

	# install-like symlinked entries are readable inside
	out="$(run_in 'cat "$HOME/.prime/agent/skills/s.md" "$HOME/.prime/agent/AGENTS.md" "$HOME/.prime/agent/models.json" "$HOME/.prime/agent/agents/a.md"')"
	expect_eq "symlinked skills/agents/AGENTS.md/models.json readable inside" "$(printf 'TRUSTED\nTRUSTED\nTRUSTED\nTRUSTED')" "$out"

	# NEW names may be created inside (the agent dir root is a sandbox-private tmpfs; machines/
	# is a read-only host dir), but none of them reaches the host
	run_in 'for n in SYSTEM.md machines/evil.md extensions rules keybindings.json mcp.json model-routing.json newdir; do touch "$HOME/.prime/agent/$n" 2>/dev/null || mkdir "$HOME/.prime/agent/$n" 2>/dev/null || true; done' >/dev/null
	for n in SYSTEM.md machines/evil.md extensions rules keybindings.json mcp.json model-routing.json newdir; do
		[[ ! -e "$FH/.prime/agent/$n" ]] && ok "new agent-dir entry $n does not reach the host" || bad "new agent-dir entry $n does not reach the host"
	done
	# MUTATION: with the agent dir bound rw instead of ro, creation DOES succeed (the private
	# tmpfs root becomes a rw bind of the host dir; its per-entry ro binds and private tmpfs
	# dirs go too). run_mut_root <op> <sh-snippet>: the same with the root bound by <op>.
	run_mut_rw() { run_mut_root --bind "$1"; }
	run_mut_root() {
		(
			cd "$REPO"
			export HOME="$FH"
			pa_sandbox_build_argv "$REPO" 2>/dev/null
			local -a mut=()
			local i=0 a="$FH/.prime/agent" x y
			while [[ $i -lt ${#PA_BWRAP_ARGV[@]} ]]; do
				x="${PA_BWRAP_ARGV[$i]}"
				y="${PA_BWRAP_ARGV[$((i + 1))]:-}"
				if [[ "$x" == --tmpfs && "$y" == "$a" ]]; then
					mut+=("$1" "$a" "$a")
					i=$((i + 2))
				elif [[ ("$x" == --ro-bind || "$x" == --ro-bind-try) && "$y" == "$a"/* && "$y" != "$a"/*/* ]]; then
					i=$((i + 3))
				elif [[ "$x" == --tmpfs && "$y" == "$a"/* ]]; then
					i=$((i + 2))
				else
					mut+=("$x")
					i=$((i + 1))
				fi
			done
			"${mut[@]}" sh -c "$2"
		) 2>&1
	}
	run_mut_rw 'touch "$HOME/.prime/agent/SYSTEM.md"' >/dev/null
	[[ -e "$FH/.prime/agent/SYSTEM.md" ]] && ok "MUTATION (agent dir rw) lets SYSTEM.md be created" || bad "MUTATION (agent dir rw) lets SYSTEM.md be created"
	command rm -f "$FH/.prime/agent/SYSTEM.md"

	# rw state dirs are created on the host before binding and stay writable
	command rm -rf "$FH/.prime/agent/logs"
	run_in 'echo l > "$HOME/.prime/agent/logs/x"' >/dev/null
	[[ -f "$FH/.prime/agent/logs/x" ]] && ok "missing rw state dir created on host, writable inside" || bad "missing rw state dir created on host, writable inside"

	# ---- git metadata is entirely read-only (Checker attacks A-D) -------------
	# run_mut_drop: same profile with the ro bind of <path> turned rw (mutation); inside
	# the workspace the bind of its top-level ancestor (see pa-sandbox ANCESTORS) goes too
	run_mut_drop() { # <workspace> <ro-path> <sh-snippet>
		(
			cd "$1"
			export HOME="$FH"
			pa_sandbox_build_argv "$1" 2>/dev/null
			local -a mut=()
			local i=0 mtop="$2" rel
			if [[ "$2" == "$1"/* ]]; then
				rel="${2#"$1"/}"
				mtop="$1/${rel%%/*}"
			fi
			while [[ $i -lt ${#PA_BWRAP_ARGV[@]} ]]; do
				if [[ "${PA_BWRAP_ARGV[$i]}" == --ro-bind && ("${PA_BWRAP_ARGV[$((i + 1))]}" == "$2" || "${PA_BWRAP_ARGV[$((i + 1))]}" == "$mtop") ]]; then
					if [[ "$2" == "$1"/* ]]; then
						i=$((i + 3)) # inside the rw workspace: drop the bind entirely
					else
						mut+=(--bind) # outside it: same mount, rw instead of ro
						i=$((i + 1))
					fi
					continue
				fi
				mut+=("${PA_BWRAP_ARGV[$i]}")
				i=$((i + 1))
			done
			"${mut[@]}" sh -c "$3"
		) 2>&1
	}
	run_ws() { # <workspace> <sh-snippet>: real profile
		( cd "$1"; export HOME="$FH"; pa_sandbox_build_argv "$1" 2>/dev/null; "${PA_BWRAP_ARGV[@]}" sh -c "$2" ) 2>&1
	}
	git -C "$REPO" -c commit.gpgsign=false commit -q --allow-empty -m init

	# A: plain repo, .git/commondir -> evil dir whose config sets core.fsmonitor
	EVIL="$FH/evil-common"
	mkdir -p "$EVIL"
	attackA='printf "%s\n" "$HOME/evil-common" > .git/commondir'
	run_mut_drop "$REPO" "$REPO/.git" "$attackA" >/dev/null
	[[ -f "$REPO/.git/commondir" ]] && ok "MUTATION (no .git ro bind): commondir write succeeds" || bad "MUTATION (no .git ro bind): commondir write succeeds"
	command rm -f "$REPO/.git/commondir"
	run_ws "$REPO" "$attackA" >/dev/null || true
	[[ ! -e "$REPO/.git/commondir" ]] && ok "A: .git/commondir cannot be written" || bad "A: .git/commondir cannot be written"

	# B: replace .git wholesale (mv .git .git-old; fresh .git with hooks)
	attackB='mv .git .git-old && mkdir .git && mkdir .git/hooks'
	BREPO="$FH/work/repoB"
	mkrepo "$BREPO"
	run_mut_drop "$BREPO" "$BREPO/.git" "$attackB" >/dev/null
	[[ -d "$BREPO/.git-old" ]] && ok "MUTATION: .git can be renamed away without the ro bind" || bad "MUTATION: .git can be renamed away without the ro bind"
	command rm -rf "$BREPO/.git" && mv "$BREPO/.git-old" "$BREPO/.git"
	run_ws "$BREPO" "$attackB" >/dev/null || true
	[[ ! -e "$BREPO/.git-old" && -f "$BREPO/.git/HEAD" && ! -d "$BREPO/.git/hooks-planted" ]] && ok "B: .git cannot be renamed or replaced" || bad "B: .git cannot be renamed or replaced"
	run_ws "$BREPO" 'rmdir .git 2>/dev/null; rm -rf .git 2>/dev/null; true' >/dev/null || true
	[[ -f "$BREPO/.git/HEAD" ]] && ok "B: .git cannot be removed" || bad "B: .git cannot be removed"

	# C: linked worktree: gitfile rewrite and $gcd/worktrees/<n>/commondir redirect
	WT="$FH/work/wt"
	git -C "$REPO" worktree add -q "$WT" -b wtbranch
	WTN="$(ls "$REPO/.git/worktrees")"
	attackC1='printf "gitdir: %s\n" "$HOME/evil-common" > .git'
	attackC2="printf '%s\\n' \"\$HOME/evil-common\" > \"$REPO/.git/worktrees/$WTN/commondir\""
	cp "$WT/.git" "$T/wt-gitfile.orig"
	run_mut_drop "$WT" "$WT/.git" "$attackC1" >/dev/null
	! cmp -s "$WT/.git" "$T/wt-gitfile.orig" && ok "MUTATION: worktree gitfile rewrite succeeds without ro bind" || bad "MUTATION: worktree gitfile rewrite succeeds without ro bind"
	cp "$T/wt-gitfile.orig" "$WT/.git"
	run_ws "$WT" "$attackC1" >/dev/null || true
	cmp -s "$WT/.git" "$T/wt-gitfile.orig" && ok "C1: worktree gitfile cannot be rewritten" || bad "C1: worktree gitfile cannot be rewritten"
	run_mut_drop "$WT" "$REPO/.git" "$attackC2" >/dev/null || true
	[[ -f "$REPO/.git/worktrees/$WTN/commondir" ]] && ok "MUTATION: worktrees/<n>/commondir writable without ro bind" || bad "MUTATION: worktrees/<n>/commondir writable without ro bind"
	printf '../..\n' >"$REPO/.git/worktrees/$WTN/commondir"
	run_ws "$WT" "$attackC2" >/dev/null || true
	[[ "$(cat "$REPO/.git/worktrees/$WTN/commondir")" == "../.." ]] && ok "C2: worktrees/<n>/commondir cannot be redirected" || bad "C2: worktrees/<n>/commondir cannot be redirected"
	run_ws "$WT" 'touch "$HOME/work/repo/.git/objects/x" 2>/dev/null; true' >/dev/null || true
	[[ ! -e "$REPO/.git/objects/x" ]] && ok "worktree common dir is read-only as a whole" || bad "worktree common dir is read-only as a whole"
	out="$(run_ws "$WT" 'git status --short >/dev/null && echo git-read-ok')"
	expect_has "worktree: git read operations still work" "git-read-ok" "$out"

	# D: repo without .git/hooks: hooks cannot be created
	DREPO="$FH/work/repoD"
	git init -q --template= "$DREPO"
	[[ ! -e "$DREPO/.git/hooks" ]] && ok "D fixture: repo has no .git/hooks" || bad "D fixture: repo has no .git/hooks"
	run_mut_drop "$DREPO" "$DREPO/.git" 'mkdir .git/hooks && echo x > .git/hooks/pre-commit' >/dev/null
	[[ -f "$DREPO/.git/hooks/pre-commit" ]] && ok "MUTATION: hooks creatable without the .git ro bind" || bad "MUTATION: hooks creatable without the .git ro bind"
	command rm -rf "$DREPO/.git/hooks"
	run_ws "$DREPO" 'mkdir .git/hooks 2>/dev/null; echo x > .git/hooks/pre-commit 2>/dev/null; echo "[evil]" >> .git/config 2>/dev/null; true' >/dev/null || true
	[[ ! -e "$DREPO/.git/hooks" ]] && ok "D: .git/hooks cannot be created" || bad "D: .git/hooks cannot be created"
	! grep -q "^\[evil\]" "$DREPO/.git/config" && ok "D: .git/config cannot be appended" || bad "D: .git/config cannot be appended"

	# nested .git (e.g. a vendored clone) is read-only too; write ops fail by design
	mkdir -p "$REPO/vendor"
	git init -q "$REPO/vendor/dep"
	run_ws "$REPO" 'echo x > vendor/dep/.git/config 2>/dev/null; mkdir vendor/dep/.git/hooks2 2>/dev/null; echo ok > vendor/dep/tree-file 2>/dev/null; echo ok > root-file; true' >/dev/null || true
	[[ ! -e "$REPO/vendor/dep/.git/hooks2" ]] && ok "nested .git is read-only" || bad "nested .git is read-only"
	# documented trade-off: the top-level dir holding a nested .git is read-only as a whole
	[[ ! -e "$REPO/vendor/dep/tree-file" ]] && ok "TRADE-OFF: top-level dir holding a nested .git is read-only" || bad "TRADE-OFF: top-level dir holding a nested .git is read-only"
	[[ -f "$REPO/root-file" ]] && ok "workspace files outside protected subtrees stay writable" || bad "workspace files outside protected subtrees stay writable"
	command rm -f "$REPO/root-file"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$REPO") 2>&1 )" || true
	expect_has "read-only top-level dirs are announced on stderr" "read-only inside the sandbox" "$out"
	expect_has "announcement names the dir" "vendor/" "$out"
	out="$(run_ws "$REPO" 'git -c commit.gpgsign=false commit --allow-empty -m x 2>&1; echo rc=$?')"
	expect_has "git commit fails inside (by design)" "rc=128" "$out"
	# workspace without .git is refused unless overridden
	NOGIT="$FH/work/nogit"
	mkdir -p "$NOGIT"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$NOGIT") 2>&1 )" && rc=0 || rc=$?
	expect_eq "non-git workspace refused rc" "1" "$rc"
	out="$( (HOME="$FH" PA_SANDBOX_ALLOW_NO_GIT=1 pa_sandbox_build_argv "$NOGIT") 2>&1 )" && rc=0 || rc=$?
	expect_eq "non-git workspace override allowed" "0" "$rc"

	# deeply nested .git (depth 9) is read-only; mutation shows it would be writable
	DEEP="$REPO/a/b/c/d/e/f/g/h"
	mkdir -p "$DEEP"
	git init -q "$DEEP/dep"
	run_mut_drop "$REPO" "$DEEP/dep/.git" 'echo "[evil]" >> a/b/c/d/e/f/g/h/dep/.git/config' >/dev/null || true
	grep -q '^\[evil\]' "$DEEP/dep/.git/config" && ok "MUTATION: depth-9 nested .git/config writable without its ro bind" || bad "MUTATION: depth-9 nested .git/config writable without its ro bind"
	git -C "$DEEP/dep" config --unset-all evil 2>/dev/null || true
	sed -i '/^\[evil\]/d' "$DEEP/dep/.git/config"
	run_ws "$REPO" 'echo "[evil]" >> a/b/c/d/e/f/g/h/dep/.git/config 2>/dev/null; true' >/dev/null || true
	! grep -q '^\[evil\]' "$DEEP/dep/.git/config" && ok "depth-9 nested .git/config is read-only inside" || bad "depth-9 nested .git/config is read-only inside"
	# more nested .git than the cap fails closed (never silently skipped)
	out="$( (HOME="$FH" PA_SANDBOX_MAX_NESTED_GIT=1 pa_sandbox_build_argv "$REPO") 2>&1 )" && rc=0 || rc=$?
	expect_eq "nested .git count over the cap fails closed rc" "1" "$rc"
	expect_has "nested .git cap message" "nested .git" "$out"

	# symlinked nested .git: refuse to start (cannot be bound safely)
	mkdir -p "$REPO/store/dep.git" "$REPO/lnkd/dep2"
	git init -q --bare "$REPO/store/dep.git"
	ln -s ../../store/dep.git "$REPO/lnkd/dep2/.git"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$REPO") 2>&1 )" && rc=0 || rc=$?
	expect_eq "symlinked nested .git refused rc" "1" "$rc"
	expect_has "symlinked nested .git listed" "lnkd/dep2/.git" "$out"
	# MUTATION: with the (UNSAFE) override the sandbox starts and the symlink itself can be
	# re-pointed (its target, a bare repo in the workspace, is protected on its own)
	( cd "$REPO"; export HOME="$FH" PA_SANDBOX_ALLOW_GIT_SYMLINKS=1; pa_sandbox_build_argv "$REPO" 2>/dev/null; "${PA_BWRAP_ARGV[@]}" sh -c 'echo "[evil]" >> store/dep.git/config 2>/dev/null; mkdir -p evil && ln -sfn ../../evil lnkd/dep2/.git' ) >/dev/null 2>&1 || true
	[[ "$(readlink "$REPO/lnkd/dep2/.git")" == ../../evil ]] && ok "MUTATION (symlink override): symlinked .git can be re-pointed" || bad "MUTATION (symlink override): symlinked .git can be re-pointed"
	! grep -q '^\[evil\]' "$REPO/store/dep.git/config" && ok "bare repo in the workspace (symlink target) stays read-only" || bad "bare repo in the workspace (symlink target) stays read-only"
	command rm -rf "$REPO/evil"
	command rm -rf "$REPO/lnkd" "$REPO/store"

	# find errors fail closed: an unreadable directory could hide a nested .git
	mkdir -p "$REPO/locked/x"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$REPO") 2>&1 )" && rc=0 || rc=$?
	expect_eq "scan baseline (readable tree) ok rc" "0" "$rc"
	chmod 000 "$REPO/locked"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$REPO") 2>&1 )" && rc=0 || rc=$?
	chmod 755 "$REPO/locked"
	expect_eq "unreadable dir during .git scan fails closed rc" "1" "$rc"
	expect_has "scan failure message" "scan for nested .git failed" "$out"
	command rm -rf "$REPO/locked"

	# planted symlinks in rw state dirs are scrubbed at launch and after exit
	VICTIM="$T/victim-file"
	printf 'ORIG\n' >"$VICTIM"
	STUBDIR="$T/stubbin"
	mkdir -p "$STUBDIR"
	printf '#!/bin/sh\nln -s "%s" "$HOME/.prime/agent/sessions/evil.window-cache.json"\nmkfifo "$HOME/.prime/agent/logs/evil.fifo" 2>/dev/null\nexit 3\n' "$VICTIM" >"$STUBDIR/prime-agent"
	chmod +x "$STUBDIR/prime-agent"
	# MUTATION: without the scrub the planted symlink persists on the host
	run_ws "$REPO" "ln -s \"$VICTIM\" \"\$HOME/.prime/agent/sessions/planted-link\"" >/dev/null || true
	[[ -L "$FH/.prime/agent/sessions/planted-link" ]] && ok "MUTATION (no scrub): symlink planted in sessions/ persists on host" || bad "MUTATION (no scrub): symlink planted in sessions/ persists on host"
	# launch-time scrub (symlink already there before start)
	( cd "$REPO"; export HOME="$FH" PATH="$STUBDIR:$PATH"; pa_sandbox_main ) >"$T/main.out" 2>&1 && rc=0 || rc=$?
	expect_eq "pa_sandbox_main returns the sandboxed command's rc" "3" "$rc"
	[[ ! -L "$FH/.prime/agent/sessions/planted-link" ]] && ok "launch scrub removed pre-planted symlink" || bad "launch scrub removed pre-planted symlink"
	[[ ! -L "$FH/.prime/agent/sessions/evil.window-cache.json" && ! -e "$FH/.prime/agent/logs/evil.fifo" ]] && ok "post-exit scrub removed symlink and FIFO planted during the run" || bad "post-exit scrub removed symlink and FIFO planted during the run"
	expect_eq "scrub left the symlink target untouched" "ORIG" "$(cat "$VICTIM")"

	# setsid grandchild outliving the command must not plant a symlink after the scrub
	cat >"$STUBDIR/prime-agent" <<'STUB'
#!/bin/sh
(setsid sh -c 'sleep 2; ln -s /etc/hostname "$HOME/.prime/agent/sessions/late-link"' >/dev/null 2>&1 &)
exit 0
STUB
	chmod +x "$STUBDIR/prime-agent"
	# MUTATION: same background trick without the sweep -> the link appears
	run_ws "$REPO" '(setsid sh -c "sleep 2; ln -s /etc/hostname \"$HOME/.prime/agent/sessions/late-link\"" >/dev/null 2>&1 &); exit 0' >/dev/null || true
	sleep 3.5
	[[ -L "$FH/.prime/agent/sessions/late-link" ]] && ok "MUTATION (no sweep): setsid grandchild plants late-link after exit" || bad "MUTATION (no sweep): setsid grandchild plants late-link after exit"
	command rm -f "$FH/.prime/agent/sessions/late-link"
	( cd "$REPO"; export HOME="$FH" PATH="$STUBDIR:$PATH"; pa_sandbox_main ) >"$T/main.out" 2>&1 && rc=0 || rc=$?
	expect_eq "setsid case: pa_sandbox_main rc" "0" "$rc"
	sleep 3.5
	[[ ! -L "$FH/.prime/agent/sessions/late-link" ]] && ok "setsid grandchild swept: no late-link after main returns (waited 3.5s)" || bad "setsid grandchild swept: no late-link after main returns (waited 3.5s)"
	command rm -f "$FH/.prime/agent/sessions/late-link"
	# sweep never targets pa-sandbox's own namespaces and needs BOTH ids to match
	out="$( (pa_sandbox_sweep "$(readlink /proc/self/ns/ipc)" "$(readlink /proc/self/ns/user)") 2>&1 )" && rc=0 || rc=$?
	expect_eq "sweep refuses pa-sandbox's own namespace pair" "1" "$rc"

	# (B) FORGE: a same-uid host process in ANOTHER ipc+user ns must never be killed
	unshare -U --ipc sh -c 'exec sleep 25' &
	VPID=$!
	sleep 0.4
	VIPC="$(readlink /proc/$VPID/ns/ipc)"
	VUSR="$(readlink /proc/$VPID/ns/user)"
	cat >"$STUBDIR/prime-agent" <<STUB
#!/bin/sh
# try everything: leave forged ids in every writable place, including the old token style
for f in /tmp/tmp.* /tmp/*/* "\$HOME"/.prime/agent/sessions/* ; do [ -f "\$f" ] && printf '%s\n%s\n' "$VIPC" "$VUSR" > "\$f" 2>/dev/null; done
exit 0
STUB
	chmod +x "$STUBDIR/prime-agent"
	( cd "$REPO"; export HOME="$FH" PATH="$STUBDIR:$PATH"; pa_sandbox_main ) >"$T/main.out" 2>&1 && rc=0 || rc=$?
	expect_eq "forge attempt: main rc" "0" "$rc"
	kill -0 "$VPID" 2>/dev/null && ok "forge attempt: host victim in another namespace survives" || bad "forge attempt: host victim in another namespace survives"
	# pair semantics: right ipc but wrong user id (and vice versa) kills nothing
	pa_sandbox_sweep "$VIPC" "user:[1]" >/dev/null 2>&1 || true
	kill -0 "$VPID" 2>/dev/null && ok "sweep with matching ipc but wrong user ns kills nothing" || bad "sweep with matching ipc but wrong user ns kills nothing"
	# MUTATION: taking the id from a sandbox-writable file lets the sandbox pick the victim
	FORGEF="$T/forge-token"
	: >"$FORGEF"
	( cd "$REPO"; export HOME="$FH"; pa_sandbox_build_argv "$REPO" 2>/dev/null
	  mut=("${PA_BWRAP_ARGV[@]:0:${#PA_BWRAP_ARGV[@]}-1}" --bind "$FORGEF" "$FORGEF" --)
	  "${mut[@]}" sh -c "printf '%s\n%s\n' '$VIPC' '$VUSR' > '$FORGEF'" ) >/dev/null 2>&1 || true
	{ read -r fi_ && read -r fu_; } <"$FORGEF" || true
	pa_sandbox_sweep "$fi_" "$fu_" >/dev/null 2>&1 || true
	! kill -0 "$VPID" 2>/dev/null && ok "MUTATION (id read from sandbox-writable file): sandbox picks the victim, it is killed" || bad "MUTATION (id read from sandbox-writable file): sandbox picks the victim, it is killed"
	kill "$VPID" 2>/dev/null || true
	wait "$VPID" 2>/dev/null || true

	# (A) ESCAPE: nested user namespace + new ipc ns must be impossible
	out="$(run_ws "$REPO" 'unshare -U true >/dev/null 2>&1; echo u=$?; unshare --ipc true >/dev/null 2>&1; echo i=$?')"
	expect_eq "unshare -U and unshare --ipc fail inside" "$(printf 'u=1\ni=1')" "$out"
	out="$( (cd "$REPO"; export HOME="$FH"; pa_sandbox_build_argv "$REPO" 2>/dev/null
		mut=()
		for a in "${PA_BWRAP_ARGV[@]}"; do [[ "$a" == --disable-userns || "$a" == --assert-userns-disabled ]] || mut+=("$a"); done
		"${mut[@]}" sh -c 'unshare -U true >/dev/null 2>&1; echo u=$?') 2>&1 )" || true
	expect_has "MUTATION (no --disable-userns): nested userns possible" "u=0" "$out"
	cat >"$STUBDIR/prime-agent" <<'STUB'
#!/bin/sh
(setsid unshare -U --ipc sh -c 'sleep 2; ln -s /etc/hostname "$HOME/.prime/agent/sessions/late-link-userns"' >/dev/null 2>&1 &)
exit 0
STUB
	chmod +x "$STUBDIR/prime-agent"
	( cd "$REPO"; export HOME="$FH" PATH="$STUBDIR:$PATH"; pa_sandbox_main ) >"$T/main.out" 2>&1 && rc=0 || rc=$?
	expect_eq "escape repro: main rc" "0" "$rc"
	sleep 3.5
	[[ ! -L "$FH/.prime/agent/sessions/late-link-userns" ]] && ok "escape repro blocked: no late-link-userns after main returns (waited 3.5s)" || bad "escape repro blocked: no late-link-userns after main returns (waited 3.5s)"
	command rm -f "$FH/.prime/agent/sessions/late-link-userns"

	# PA_SANDBOX_MAX_NESTED_GIT is honoured from the environment at source time
	CAPR="$FH/work/caprepo"
	mkrepo "$CAPR"
	for i in $(seq 1 501); do mkdir -p "$CAPR/n$i/.git"; done
	out="$(HOME="$FH" "$BASH" -c 'source "$1"; pa_sandbox_build_argv "$2"' _ "$PA_SANDBOX" "$CAPR" 2>&1)" && rc=0 || rc=$?
	expect_eq "default cap (500) refuses 501 nested .git" "1" "$rc"
	out="$(HOME="$FH" PA_SANDBOX_MAX_NESTED_GIT=5000 "$BASH" -c 'source "$1"; pa_sandbox_build_argv "$2"' _ "$PA_SANDBOX" "$CAPR" 2>&1)" && rc=0 || rc=$?
	expect_eq "env PA_SANDBOX_MAX_NESTED_GIT=5000 is honoured" "0" "$rc"
	command rm -rf "$CAPR"

	# unreadable dirs (0111 / 000, nested) must not hide planted entries from the scrub
	cat >"$STUBDIR/prime-agent" <<STUB
#!/bin/sh
d="\$HOME/.prime/agent"
mkdir -p "\$d/sessions/s1/s2" && ln -s "$VICTIM" "\$d/sessions/s1/s2/evil.json"
mkfifo "\$d/logs/plainfifo"
chmod 000 "\$d/sessions/s1/s2"; chmod 0111 "\$d/sessions/s1"
exit 0
STUB
	chmod +x "$STUBDIR/prime-agent"
	# MUTATION: the old scrub (no permission normalisation) leaves the symlink behind
	run_ws "$REPO" "mkdir -p \"\$HOME/.prime/agent/sessions/s1/s2\" && ln -s \"$VICTIM\" \"\$HOME/.prime/agent/sessions/s1/s2/evil.json\"; chmod 000 \"\$HOME/.prime/agent/sessions/s1/s2\"; chmod 0111 \"\$HOME/.prime/agent/sessions/s1\"" >/dev/null || true
	find -P "$FH/.prime/agent/sessions" -type l -delete 2>/dev/null || true
	chmod u+rwx "$FH/.prime/agent/sessions/s1" && ls -A "$FH/.prime/agent/sessions/s1/s2" >/dev/null 2>&1 || true
	chmod u+rwx "$FH/.prime/agent/sessions/s1/s2"
	[[ -L "$FH/.prime/agent/sessions/s1/s2/evil.json" ]] && ok "MUTATION (no permission normalisation): planted symlink survives the old scrub" || bad "MUTATION (no permission normalisation): planted symlink survives the old scrub"
	command rm -rf "$FH/.prime/agent/sessions/s1"
	( cd "$REPO"; export HOME="$FH" PATH="$STUBDIR:$PATH"; pa_sandbox_main ) >"$T/main.out" 2>&1 && rc=0 || rc=$?
	expect_eq "unreadable-dir repro: main rc" "0" "$rc"
	[[ -r "$FH/.prime/agent/sessions/s1/s2" && ! -e "$FH/.prime/agent/sessions/s1/s2/evil.json" && ! -L "$FH/.prime/agent/sessions/s1/s2/evil.json" && ! -e "$FH/.prime/agent/logs/plainfifo" ]] \
		&& ok "scrub removed planted symlink (nested 0111/000 dirs) and FIFO" || bad "scrub removed planted symlink (nested 0111/000 dirs) and FIFO"
	expect_eq "unreadable-dir repro: victim untouched" "ORIG" "$(cat "$VICTIM")"
	[[ -r "$FH/.prime/agent/sessions/s1/s2" ]] && ok "directories were normalised readable" || bad "directories were normalised readable"
	command rm -rf "$FH/.prime/agent/sessions/s1"

	# a scan error makes the scrub, and main, fail loudly (find shim fails on -delete)
	SHIM="$T/shimbin"
	mkdir -p "$SHIM"
	REALFIND="$(command -v find)"
	cat >"$SHIM/find" <<SHIMEOF
#!/bin/sh
case "\$*" in
*-delete*)
	n=\$(cat "$T/shim-count" 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n >"$T/shim-count"
	if [ "\$n" -gt "\$(cat "$T/shim-after")" ]; then echo "find: boom" >&2; exit 1; fi ;;
esac
exec "$REALFIND" "\$@"
SHIMEOF
	chmod +x "$SHIM/find"
	# launch failure
	echo 0 >"$T/shim-after"; echo 0 >"$T/shim-count"
	cat >"$STUBDIR/prime-agent" <<'STUB'
#!/bin/sh
exit 0
STUB
	out="$( (cd "$REPO"; export HOME="$FH" PATH="$SHIM:$STUBDIR:$PATH"; pa_sandbox_main) 2>&1 )" && rc=0 || rc=$?
	expect_eq "scrub scan error at launch: main refuses rc" "1" "$rc"
	expect_has "scrub scan error at launch: loud message" "refusing to start" "$out"
	# post-exit failure: launch scrub (5 rw dirs) passes, exit scrub fails
	echo "${#PA_SANDBOX_AGENT_RW_DIRS[@]}" >"$T/shim-after"; echo 0 >"$T/shim-count"
	out="$( (cd "$REPO"; export HOME="$FH" PATH="$SHIM:$STUBDIR:$PATH"; pa_sandbox_main) 2>&1 )" && rc=0 || rc=$?
	expect_eq "scrub scan error after exit: main fails rc" "71" "$rc"
	expect_has "scrub scan error after exit: loud message" "post-exit state scrub failed" "$out"

	# UNSAFE no-guard override warns on every run
	out="$( (cd "$REPO"; export HOME="$FH" PATH="$STUBDIR:$PATH" PA_SANDBOX_ALLOW_NO_GUARD=1; pa_sandbox_main) 2>&1 )" && rc=0 || rc=$?
	expect_has "PA_SANDBOX_ALLOW_NO_GUARD warns UNSAFE per run" "UNSAFE" "$out"

	# nested gitfile -> gitdir not named .git, inside the workspace: ro-bound; outside: refused
	mkdir -p "$REPO/vendor/gf" "$REPO/vendor/gitdata-custom"
	printf 'gitdir: ../gitdata-custom\n' >"$REPO/vendor/gf/.git"
	printf '[core]\n' >"$REPO/vendor/gitdata-custom/config"
	run_mut_drop "$REPO" "$REPO/vendor/gitdata-custom" 'echo "[evil]" >> vendor/gitdata-custom/config' >/dev/null || true
	grep -q '^\[evil\]' "$REPO/vendor/gitdata-custom/config" && ok "MUTATION: gitfile target writable without its ro bind" || bad "MUTATION: gitfile target writable without its ro bind"
	printf '[core]\n' >"$REPO/vendor/gitdata-custom/config"
	run_ws "$REPO" 'echo "[evil]" >> vendor/gitdata-custom/config 2>/dev/null; true' >/dev/null || true
	! grep -q '^\[evil\]' "$REPO/vendor/gitdata-custom/config" && ok "nested gitfile's gitdir (not named .git) is read-only inside" || bad "nested gitfile's gitdir (not named .git) is read-only inside"
	mkdir -p "$FH/outside-gitdir"
	printf 'gitdir: %s\n' "$FH/outside-gitdir" >"$REPO/vendor/gf/.git"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$REPO") 2>&1 )" && rc=0 || rc=$?
	expect_eq "nested gitfile pointing outside the workspace refused rc" "1" "$rc"
	expect_has "outside gitfile message" "outside the workspace" "$out"
	command rm -rf "$REPO/vendor/gf" "$REPO/vendor/gitdata-custom"

	# ---- rename-a-parent attacks (Checker attempt 9): a mount point cannot be renamed,
	# but a writable parent could, freeing the original path for an attacker git dir with
	# core.fsmonitor that a later HOST git run executes. Each case: MUTATION (ancestor bind
	# dropped) shows the attack works; the real profile blocks it.
	rename_case() { # <label> <workspace> <ro-path> <attack sh> <host git dir> <marker>
		local lbl="$1" ws="$2" rp="$3" atk="$4" hg="$5" mk="$6"
		command cp -a "$ws" "$ws.pristine"
		run_mut_drop "$ws" "$rp" "$atk" >/dev/null 2>&1 || true
		git -C "$hg" status >/dev/null 2>&1 || true
		[[ -e "$mk" ]] && ok "MUTATION ($lbl, no ancestor bind): rename attack runs fsmonitor on host" || bad "MUTATION ($lbl, no ancestor bind): rename attack runs fsmonitor on host"
		command rm -rf "$ws" "$mk"
		command cp -a "$ws.pristine" "$ws"
		run_ws "$ws" "$atk" >/dev/null 2>&1 || true
		git -C "$hg" status >/dev/null 2>&1 || true
		[[ ! -e "$mk" ]] && ok "$lbl: rename attack blocked (no host fsmonitor run)" || bad "$lbl: rename attack blocked (no host fsmonitor run)"
		command rm -rf "$ws.pristine" "$mk"
	}
	plant='printf "[core]\n\tfsmonitor = touch %s\n" "$MK" >>'
	# (a) nested gitfile vendor/gf/.git -> store/gd: rename store/, plant store/gd
	RA="$FH/work/rename-a"
	mkrepo "$RA"
	mkdir -p "$RA/vendor" "$RA/store"
	git init -q --separate-git-dir="$RA/store/gd" "$RA/vendor/gf"
	rename_case "(a) gitfile target" "$RA" "$RA/store/gd" \
		"MK=$T/PWNED-a; mv store store-old && mkdir store && cp -r store-old/gd store/gd && $plant store/gd/config" \
		"$RA/vendor/gf" "$T/PWNED-a"
	# (b) workspace .git -> separate git dir inside the workspace (meta/gs)
	RB="$FH/work/rename-b"
	mkdir -p "$RB/meta"
	git init -q --separate-git-dir="$RB/meta/gs" "$RB"
	rename_case "(b) in-workspace common dir" "$RB" "$RB/meta/gs" \
		"MK=$T/PWNED-b; mv meta meta-old && mkdir meta && cp -r meta-old/gs meta/gs && $plant meta/gs/config" \
		"$RB" "$T/PWNED-b"
	# (c) plain nested .git: rename vendor/dep, recreate vendor/dep/.git
	RC="$FH/work/rename-c"
	mkrepo "$RC"
	mkdir -p "$RC/vendor"
	git init -q "$RC/vendor/dep"
	rename_case "(c) nested .git" "$RC" "$RC/vendor/dep/.git" \
		"MK=$T/PWNED-c; mv vendor/dep vendor/depX && mkdir -p vendor/dep && cp -r vendor/depX/.git vendor/dep/.git && $plant vendor/dep/.git/config" \
		"$RC/vendor/dep" "$T/PWNED-c"
	# a gitdir path through a symlink (re-pointable inside the workspace) is refused
	mkdir -p "$RC/sub/gf"
	ln -s vendor/dep "$RC/lnk"
	printf 'gitdir: ../../lnk/.git\n' >"$RC/sub/gf/.git"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$RC") 2>&1 )" && rc=0 || rc=$?
	expect_eq "gitdir path through a symlink refused rc" "1" "$rc"
	expect_has "gitdir symlink message" "goes through a symlink" "$out"
	# same for the workspace's own gitfile (lnk -> meta, in the rw root)
	ln -s meta "$RB/lnk"
	printf 'gitdir: %s\n' "$RB/lnk/gs" >"$RB/.git"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$RB") 2>&1 )" && rc=0 || rc=$?
	expect_eq "workspace gitfile through a symlink refused rc" "1" "$rc"
	expect_has "workspace gitfile symlink message" "goes through a symlink" "$out"
	command rm -rf "$RA" "$RB" "$RC"

	# ---- git config references (Checker attempt 10): paths that HOST git later runs or
	# reads because a config names them. Each case: MUTATION (the new ro bind dropped)
	# shows host git runs the attacker's code; the real profile blocks it.
	host_case() { # <label> <workspace> <ro-path> <attack sh> <host cmd> <marker>
		local lbl="$1" ws="$2" rp="$3" atk="$4" hc="$5" mk="$6"
		command cp -a "$ws" "$ws.pristine"
		run_mut_drop "$ws" "$rp" "$atk" >/dev/null 2>&1 || true
		(eval "$hc") >/dev/null 2>&1 || true
		[[ -e "$mk" ]] && ok "MUTATION ($lbl, ro bind dropped): host git runs the attacker's code" || bad "MUTATION ($lbl, ro bind dropped): host git runs the attacker's code"
		command rm -rf "$ws" "$mk"
		command cp -a "$ws.pristine" "$ws"
		(HOME="$FH" pa_sandbox_build_argv "$ws") >/dev/null 2>&1 && ok "$lbl: real profile builds (control)" || bad "$lbl: real profile builds (control)"
		run_ws "$ws" "$atk" >/dev/null 2>&1 || true
		(eval "$hc") >/dev/null 2>&1 || true
		[[ ! -e "$mk" ]] && ok "$lbl: blocked (host git does not run it)" || bad "$lbl: blocked (host git does not run it)"
		command rm -rf "$ws.pristine" "$mk"
	}
	hook='printf "#!/bin/sh\ntouch %s\n" "$MK" >'
	# (1) core.hooksPath = .githooks (directly under the root, exists)
	H1="$FH/work/cfg-hooks"
	mkrepo "$H1"
	mkdir -p "$H1/.githooks"
	printf '#!/bin/sh\nexit 0\n' >"$H1/.githooks/pre-commit"
	chmod +x "$H1/.githooks/pre-commit"
	git -C "$H1" config core.hooksPath .githooks
	host_case "(1) core.hooksPath .githooks" "$H1" "$H1/.githooks" \
		"MK=$T/PWNED-h1; $hook .githooks/pre-commit" \
		"git -C '$H1' -c commit.gpgsign=false commit -q --allow-empty -m x" "$T/PWNED-h1"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$H1") 2>&1 )" || true
	expect_has "hooksPath dir announced as read-only" ".githooks" "$out"
	# (1b) husky layout: core.hooksPath = .husky/_ (relative, nested) -> .husky/ ro
	H2="$FH/work/cfg-husky"
	mkrepo "$H2"
	mkdir -p "$H2/.husky/_"
	printf '#!/bin/sh\nexit 0\n' >"$H2/.husky/_/pre-commit"
	chmod +x "$H2/.husky/_/pre-commit"
	git -C "$H2" config core.hooksPath .husky/_
	host_case "(1b) core.hooksPath .husky/_" "$H2" "$H2/.husky/_" \
		"MK=$T/PWNED-h2; $hook .husky/_/pre-commit" \
		"git -C '$H2' -c commit.gpgsign=false commit -q --allow-empty -m x" "$T/PWNED-h2"
	# (1c) relative hooksPath that does not exist yet (tools/hooks): its top-level dir is
	# ro, so the sandbox cannot create it
	H3="$FH/work/cfg-relhooks"
	mkrepo "$H3"
	mkdir -p "$H3/tools"
	git -C "$H3" config core.hooksPath tools/hooks
	host_case "(1c) missing relative core.hooksPath tools/hooks" "$H3" "$H3/tools/hooks" \
		"MK=$T/PWNED-h3; mkdir -p tools/hooks && $hook tools/hooks/pre-commit && chmod +x tools/hooks/pre-commit" \
		"git -C '$H3' -c commit.gpgsign=false commit -q --allow-empty -m x" "$T/PWNED-h3"
	# relative hooksPath resolves against the worktree root of a NESTED repo too
	mkdir -p "$H3/vendor"
	git init -q "$H3/vendor/dep"
	mkdir -p "$H3/vendor/dep/hk"
	git -C "$H3/vendor/dep" config core.hooksPath hk
	out="$(run_ws "$H3" 'echo x > vendor/dep/hk/pre-commit 2>/dev/null; echo rc=$?')"
	[[ ! -e "$H3/vendor/dep/hk/pre-commit" ]] && ok "nested repo: relative hooksPath (to its own root) is read-only" || bad "nested repo: relative hooksPath (to its own root) is read-only" "$out"
	# a missing hooksPath directly under the root cannot be protected: refuse
	git -C "$H3" config core.hooksPath .missing-hooks
	out="$( (HOME="$FH" pa_sandbox_build_argv "$H3") 2>&1 )" && rc=0 || rc=$?
	expect_eq "missing hooksPath directly under the root refused rc" "1" "$rc"
	expect_has "missing hooksPath message" "does not exist" "$out"
	command rm -rf "$H1" "$H2" "$H3"

	# (2) include.path ../.gitconfig (workspace file) + recursive include + includeIf
	I2="$FH/work/cfg-inc"
	mkrepo "$I2"
	mkdir -p "$I2/conf"
	printf '[include]\n\tpath = conf/inner.cfg\n' >"$I2/.gitconfig"
	printf '[user]\n\tname = t\n' >"$I2/conf/inner.cfg"
	printf '[user]\n\tname = t\n' >"$I2/cond.cfg"
	git -C "$I2" config include.path ../.gitconfig
	git -C "$I2" config 'includeIf.gitdir:/nonexistent-pa/.path' ../cond.cfg
	fsmon='printf "[core]\n\tfsmonitor = touch %s\n" "$MK" >>'
	host_case "(2) include.path ../.gitconfig" "$I2" "$I2/.gitconfig" \
		"MK=$T/PWNED-i1; $fsmon .gitconfig" "git -C '$I2' status" "$T/PWNED-i1"
	host_case "(2b) recursive include conf/inner.cfg" "$I2" "$I2/conf/inner.cfg" \
		"MK=$T/PWNED-i2; $fsmon conf/inner.cfg" "git -C '$I2' status" "$T/PWNED-i2"
	run_mut_drop "$I2" "$I2/cond.cfg" 'echo "[evil]" >> cond.cfg' >/dev/null 2>&1 || true
	grep -q '^\[evil\]' "$I2/cond.cfg" && ok "MUTATION: includeIf target (condition false now) writable without its bind" || bad "MUTATION: includeIf target (condition false now) writable without its bind"
	printf '[user]\n\tname = t\n' >"$I2/cond.cfg"
	run_ws "$I2" 'echo "[evil]" >> cond.cfg 2>/dev/null; true' >/dev/null 2>&1 || true
	! grep -q '^\[evil\]' "$I2/cond.cfg" && ok "(2c) includeIf target is read-only even while its condition is false" || bad "(2c) includeIf target is read-only even while its condition is false"
	# reading the configs never runs fsmonitor on the host (git config --file only parses)
	printf '[core]\n\tfsmonitor = touch %s\n' "$T/PWNED-read" >>"$I2/conf/inner.cfg"
	(HOME="$FH" pa_sandbox_build_argv "$I2") >/dev/null 2>&1 || true
	[[ ! -e "$T/PWNED-read" ]] && ok "config scan does not run fsmonitor of a scanned file" || bad "config scan does not run fsmonitor of a scanned file"
	# include loop and a missing include directly under the root: refuse
	printf '[include]\n\tpath = conf/inner.cfg\n' >"$I2/.gitconfig"
	printf '[include]\n\tpath = ../.gitconfig\n' >"$I2/conf/inner.cfg"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$I2") 2>&1 )" && rc=0 || rc=$?
	expect_eq "include loop refused rc" "1" "$rc"
	expect_has "include loop message" "too deep" "$out"
	printf '[user]\n\tname = t\n' >"$I2/conf/inner.cfg"
	git -C "$I2" config --add include.path ../missing.cfg
	out="$( (HOME="$FH" pa_sandbox_build_argv "$I2") 2>&1 )" && rc=0 || rc=$?
	expect_eq "missing include directly under the root refused rc" "1" "$rc"
	command rm -rf "$I2"

	# (2d) command value naming a workspace script: core.fsmonitor = sh tools/fsmon.sh
	C2="$FH/work/cfg-cmd"
	mkrepo "$C2"
	mkdir -p "$C2/tools"
	printf 'exit 1\n' >"$C2/tools/fsmon.sh"
	git -C "$C2" config core.fsmonitor 'sh tools/fsmon.sh'
	host_case "(2d) core.fsmonitor command naming tools/fsmon.sh" "$C2" "$C2/tools/fsmon.sh" \
		"MK=$T/PWNED-c2; printf 'touch %s\nexit 1\n' \"\$MK\" > tools/fsmon.sh" "git -C '$C2' status" "$T/PWNED-c2"
	command rm -rf "$C2"

	# (3) gitdir path `lnk/../meta/gs` with lnk -> src: the old realpath -s/readlink -f
	# comparison accepted it (both give meta/gs); the per-component walk refuses
	S3="$FH/work/cfg-symdot"
	mkdir -p "$S3/src" "$S3/meta"
	git init -q --separate-git-dir="$S3/meta/gs" "$S3"
	ln -s src "$S3/lnk"
	printf 'gitdir: %s/lnk/../meta/gs\n' "$S3" >"$S3/.git"
	[[ "$(realpath -s -m -- "$S3/lnk/../meta/gs")" == "$(readlink -f -- "$S3/lnk/../meta/gs")" ]] && ok "(3) fixture: the old symlink comparison does not see lnk/.." || bad "(3) fixture: the old symlink comparison does not see lnk/.."
	atk3="MK=$T/PWNED-s3; rm lnk && mkdir -p evil/sub evil/meta && ln -s evil/sub lnk && cp -r meta/gs evil/meta/gs && $fsmon evil/meta/gs/config"
	MUTSB="$T/pa-sandbox.mut-walk"
	# (the `..` check is removed as well: lnk/.. now also leaves the writable src/, `..` IN GIT PATHS)
	sed -e 's|_rw "$cur/$c" \&\& return 2|: # MUTATION|' -e 's|^\t_hdot() { # <dir>.*$|&\n\t\treturn 0|' "$PA_SANDBOX" >"$MUTSB"
	grep -q ': # MUTATION' "$MUTSB" && grep -A1 '^	_hdot() {' "$MUTSB" | grep -q 'return 0' && ok "(3) mutation applied (writable-symlink refusal removed)" || bad "(3) mutation applied (writable-symlink refusal removed)"
	command cp -a "$S3" "$S3.pristine"
	# shellcheck source=/dev/null # mutated copy of pa-sandbox
	( cd "$S3"; export HOME="$FH"; source "$MUTSB"; pa_sandbox_build_argv "$S3" 2>/dev/null && "${PA_BWRAP_ARGV[@]}" sh -c "$atk3" ) >/dev/null 2>&1 || true
	git -C "$S3" status >/dev/null 2>&1 || true
	[[ -e "$T/PWNED-s3" ]] && ok "MUTATION ((3) no per-component check): re-pointed lnk runs fsmonitor on host" || bad "MUTATION ((3) no per-component check): re-pointed lnk runs fsmonitor on host"
	command rm -rf "$S3" "$T/PWNED-s3"
	command cp -a "$S3.pristine" "$S3"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$S3") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(3) gitdir lnk/../meta/gs refused rc" "1" "$rc"
	expect_has "(3) refusal message" "goes through a symlink" "$out"
	# nested gitfile with the same trick, and a legitimate `..` path (no symlink) accepted
	printf 'gitdir: %s/meta/gs\n' "$S3" >"$S3/.git"
	mkdir -p "$S3/vendor/gf"
	git init -q --bare "$S3/store/gd"
	printf 'gitdir: ../../lnk/../store/gd\n' >"$S3/vendor/gf/.git"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$S3") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(3) nested gitfile lnk/.. refused rc" "1" "$rc"
	# attempt 32: `../../src/../store/gd` leaves the WRITABLE src/ through `..` (src could be
	# replaced by a symlink, so the gitdir would name an attacker's repo): refused now
	printf 'gitdir: ../../src/../store/gd\n' >"$S3/vendor/gf/.git"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$S3") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(3) .. leaving the writable src/ in a gitdir path refused rc" "1" "$rc"
	expect_has "(3) message" "goes through '$S3/src', which the sandbox can write" "$out"
	printf 'gitdir: ../../store/gd\n' >"$S3/vendor/gf/.git"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$S3") 2>&1 )" && rc=0 || rc=$?
	expect_eq "legitimate .. in a gitdir path (no symlink) accepted rc" "0" "$rc"
	# a symlink OUTSIDE the workspace whose target goes through the workspace's lnk
	ln -s "$S3/lnk" "$T/outlnk"
	printf 'gitdir: %s/outlnk/../meta/gs\n' "$T" >"$S3/.git"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$S3") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(3) outside symlink chaining into a workspace symlink refused rc" "1" "$rc"
	command rm -rf "$S3" "$S3.pristine" "$T/outlnk"

	# (4) workspace gitfile -> admin dir inside the workspace, NOT under the common dir:
	# the admin dir (tgd) itself and its commondir file are read-only
	T4="$FH/work/cfg-tgd"
	mkdir -p "$T4/admin"
	git init -q "$T4/main"
	git -C "$T4/main" -c commit.gpgsign=false commit -q --allow-empty -m i
	git -C "$T4/main" worktree add -q --detach "$T4/tmpwt"
	mv "$T4/main/.git/worktrees/tmpwt" "$T4/admin/wt"
	command rm -rf "$T4/tmpwt"
	printf '%s\n' "$T4/main/.git" >"$T4/admin/wt/commondir"
	printf '%s\n' "$T4/.git" >"$T4/admin/wt/gitdir"
	printf 'gitdir: %s\n' "$T4/admin/wt" >"$T4/.git"
	git -C "$T4" status >/dev/null 2>&1 && ok "(4) fixture: host git accepts the layout" || bad "(4) fixture: host git accepts the layout"
	host_case "(4) workspace gitdir (tgd) commondir redirect" "$T4" "$T4/admin/wt" \
		"MK=$T/PWNED-t4; mkdir -p evil && cp -r main/.git evil/gcd && $fsmon evil/gcd/config && printf '%s\n' \"\$PWD/evil/gcd\" > admin/wt/commondir" \
		"git -C '$T4' status" "$T/PWNED-t4"
	command rm -rf "$T4"

	# (5) nested .git DIRECTORY with a commondir file -> shared/c (not named .git)
	N5="$FH/work/cfg-ncd"
	mkrepo "$N5"
	git -C "$N5" -c commit.gpgsign=false commit -q --allow-empty -m i
	mkdir -p "$N5/shared" "$N5/vendor/dep/.git"
	git init -q --bare "$N5/shared/c"
	git -C "$N5/shared/c" config core.bare false
	printf 'ref: refs/heads/main\n' >"$N5/vendor/dep/.git/HEAD"
	printf '../../../shared/c\n' >"$N5/vendor/dep/.git/commondir"
	git -C "$N5/vendor/dep" status >/dev/null 2>&1 && ok "(5) fixture: host git accepts the layout" || bad "(5) fixture: host git accepts the layout"
	host_case "(5) nested .git dir commondir target" "$N5" "$N5/shared/c" \
		"MK=$T/PWNED-n5; $fsmon shared/c/config" "git -C '$N5/vendor/dep' status" "$T/PWNED-n5"
	command rm -rf "$N5"

	# ---- symlinked git control files + every config value (Checker attempt 11, items 1-5).
	# mut_case: a mutated pa-sandbox (the new check removed) lets the sandbox change code
	# host git later runs; the real profile refuses to start.
	mut_case() { # <label> <workspace> <mutated pa-sandbox> <attack sh> <host cmd> <marker> <refusal substring>
		local lbl="$1" ws="$2" msb="$3" atk="$4" hc="$5" mk="$6" msg="$7"
		command cp -a "$ws" "$ws.pristine"
		# shellcheck source=/dev/null # mutated copy of pa-sandbox
		( cd "$ws"; export HOME="$FH"; source "$msb"; pa_sandbox_build_argv "$ws" 2>/dev/null && "${PA_BWRAP_ARGV[@]}" sh -c "$atk" ) >/dev/null 2>&1 || true
		(eval "$hc") >/dev/null 2>&1 || true
		[[ -e "$mk" ]] && ok "MUTATION ($lbl, check removed): host git runs the attacker's code" || bad "MUTATION ($lbl, check removed): host git runs the attacker's code"
		command rm -rf "$ws" "$mk"
		command cp -a "$ws.pristine" "$ws"
		command rm -rf "$ws.pristine"
		out="$( (HOME="$FH" pa_sandbox_build_argv "$ws") 2>&1 )" && rc=0 || rc=$?
		expect_eq "$lbl: refused rc" "1" "$rc"
		expect_has "$lbl: refusal message" "$msg" "$out"
	}
	# M1: no symlink scan of git dirs / hooksPath dirs, config files not walked
	MUT1="$T/pa-sandbox.mut-links"
	sed -e 's|^\t_scan_links() {$|&\n\t\treturn 0|' -e 's|_protect_path "$f" "git config file" \&\& ||' "$PA_SANDBOX" >"$MUT1"
	grep -A1 '^	_scan_links() {$' "$MUT1" | grep -q 'return 0' && ! grep -q '_protect_path "$f" "git config file"' "$MUT1" && ok "M1 mutation applied" || bad "M1 mutation applied"
	# M2: no writable-symlink refusal in _walk, no outside-symlink-into-workspace refusal
	MUT2="$T/pa-sandbox.mut-into"
	sed -e 's|_rw "$cur/$c" \&\& return 2|: # MUTATION|' -e 's|^\t_into_ws() {$|&\n\t\treturn 1|' "$PA_SANDBOX" >"$MUT2"
	grep -q ': # MUTATION' "$MUT2" && grep -A1 '_into_ws() {' "$MUT2" | grep -q 'return 1' && ok "M2 mutation applied" || bad "M2 mutation applied"
	commit_cmd() { printf "git -C '%s' -c commit.gpgsign=false commit -q --allow-empty -m x" "$1"; }
	# (6) item 1: .git/hooks/pre-commit -> ../../scripts/pre-commit (usual ln -s install)
	L6="$FH/work/lnk-hookfile"
	mkrepo "$L6"
	mkdir -p "$L6/scripts"
	printf '#!/bin/sh\nexit 0\n' >"$L6/scripts/pre-commit"
	chmod +x "$L6/scripts/pre-commit"
	ln -s ../../scripts/pre-commit "$L6/.git/hooks/pre-commit"
	mut_case "(6) symlinked hook file" "$L6" "$MUT1" "MK=$T/PWNED-l6; $hook scripts/pre-commit" \
		"$(commit_cmd "$L6")" "$T/PWNED-l6" "symlinked git control file"
	command rm -rf "$L6"
	# (7) item 2: .git/hooks itself -> ../githooks
	L7="$FH/work/lnk-hookdir"
	mkrepo "$L7"
	mkdir -p "$L7/githooks"
	printf '#!/bin/sh\nexit 0\n' >"$L7/githooks/post-commit"
	chmod +x "$L7/githooks/post-commit"
	command rm -rf "$L7/.git/hooks"
	ln -s ../githooks "$L7/.git/hooks"
	mut_case "(7) symlinked .git/hooks dir" "$L7" "$MUT1" "MK=$T/PWNED-l7; $hook githooks/post-commit" \
		"$(commit_cmd "$L7")" "$T/PWNED-l7" "symlinked git control file"
	command rm -rf "$L7"
	# (8) item 3: .git/config -> ../conf/repo.gitconfig
	L8="$FH/work/lnk-config"
	mkrepo "$L8"
	mkdir -p "$L8/conf"
	mv "$L8/.git/config" "$L8/conf/repo.gitconfig"
	ln -s ../conf/repo.gitconfig "$L8/.git/config"
	git -C "$L8" status >/dev/null 2>&1 && ok "(8) fixture: host git accepts the layout" || bad "(8) fixture: host git accepts the layout"
	mut_case "(8) symlinked .git/config" "$L8" "$MUT1" "MK=$T/PWNED-l8; $fsmon conf/repo.gitconfig" \
		"git -C '$L8' status" "$T/PWNED-l8" "symlinked git control file"
	command rm -rf "$L8"
	# (9) item 3: .git/commondir -> ../cd.txt (a workspace file naming the common dir)
	L9="$FH/work/lnk-commondir"
	mkrepo "$L9"
	git -C "$L9" -c commit.gpgsign=false commit -q --allow-empty -m i
	printf '.\n' >"$L9/cd.txt"
	ln -s ../cd.txt "$L9/.git/commondir"
	git -C "$L9" status >/dev/null 2>&1 && ok "(9) fixture: host git accepts the layout" || bad "(9) fixture: host git accepts the layout"
	mut_case "(9) symlinked commondir file" "$L9" "$MUT1" \
		"MK=$T/PWNED-l9; mkdir -p evil/gcd && cp -r .git/objects .git/refs .git/HEAD evil/gcd/ && $fsmon evil/gcd/config && printf '%s\n' \"\$PWD/evil/gcd\" > cd.txt" \
		"git -C '$L9' status" "$T/PWNED-l9" "symlinked git control file"
	command rm -rf "$L9"
	# (10) core.hooksPath dir whose entry is a symlink into the rw workspace
	L10="$FH/work/lnk-hookspath"
	mkrepo "$L10"
	mkdir -p "$L10/.githooks" "$L10/scripts"
	printf '#!/bin/sh\nexit 0\n' >"$L10/scripts/pc.sh"
	chmod +x "$L10/scripts/pc.sh"
	ln -s ../scripts/pc.sh "$L10/.githooks/pre-commit"
	git -C "$L10" config core.hooksPath .githooks
	mut_case "(10) hooksPath entry symlink" "$L10" "$MUT1" "MK=$T/PWNED-l10; $hook scripts/pc.sh" \
		"$(commit_cmd "$L10")" "$T/PWNED-l10" "symlinked git control file"
	command rm -rf "$L10"
	# (11) include target is a symlink at the root (re-pointable from inside)
	L11="$FH/work/lnk-include"
	mkrepo "$L11"
	mkdir -p "$L11/conf"
	printf '[user]\n\tname = t\n' >"$L11/conf/real.cfg"
	ln -s conf/real.cfg "$L11/inc.cfg"
	git -C "$L11" config include.path ../inc.cfg
	mut_case "(11) include target symlink" "$L11" "$MUT2" \
		"MK=$T/PWNED-l11; $fsmon evil.cfg && rm inc.cfg && ln -s evil.cfg inc.cfg" \
		"git -C '$L11' status" "$T/PWNED-l11" "goes through a symlink"
	git -C "$L11" config --unset include.path
	# a config file outside the workspace that is a symlink INTO it refuses (global config)
	ln -s "$L11/conf/real.cfg" "$T/outcfg"
	out="$( (HOME="$FH" GIT_CONFIG_GLOBAL="$T/outcfg" pa_sandbox_build_argv "$L11") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(11b) host config symlinked into the workspace refused rc" "1" "$rc"
	expect_has "(11b) refusal message" "leads into the workspace" "$out"
	# ... and one pointing elsewhere outside is followed and accepted
	printf '[user]\n\tname = t\n' >"$T/realcfg"
	ln -sf "$T/realcfg" "$T/outcfg"
	(HOME="$FH" GIT_CONFIG_GLOBAL="$T/outcfg" pa_sandbox_build_argv "$L11") >/dev/null 2>&1 && ok "(11c) host config symlinked outside the workspace accepted" || bad "(11c) host config symlinked outside the workspace accepted"
	# a hook symlink inside .git that points OUTSIDE the workspace is accepted
	printf '#!/bin/sh\nexit 0\n' >"$T/outhook"
	ln -s "$T/outhook" "$L11/.git/hooks/pre-push"
	(HOME="$FH" pa_sandbox_build_argv "$L11") >/dev/null 2>&1 && ok "(11d) hook symlink to outside the workspace accepted" || bad "(11d) hook symlink to outside the workspace accepted"
	command rm -rf "$L11" "$T/outcfg" "$T/realcfg" "$T/outhook"

	# (12) item 4: keys that were missing from the old command-key list; every value word
	# is now protected. MUTATION = run_mut_drop of the new ro bind (host_case).
	V12="$FH/work/cfg-allvalues"
	mkrepo "$V12"
	git -C "$V12" -c commit.gpgsign=false commit -q --allow-empty -m i
	mkdir -p "$V12/tools"
	for s in trailer proxy dkc lfs sendmail; do printf '#!/bin/sh\nexit 1\n' >"$V12/tools/$s.sh"; done
	chmod +x "$V12"/tools/*.sh
	bad12='printf "#!/bin/sh\ntouch %s\nexit 1\n" "$MK" >'
	git -C "$V12" config trailer.sob.command ./tools/trailer.sh
	host_case "(12a) trailer.sob.command" "$V12" "$V12/tools/trailer.sh" "MK=$T/PWNED-v1; $bad12 tools/trailer.sh" \
		"echo x | git -C '$V12' interpret-trailers --trailer sob=x" "$T/PWNED-v1"
	git -C "$V12" config core.gitProxy tools/proxy.sh
	host_case "(12b) core.gitProxy" "$V12" "$V12/tools/proxy.sh" "MK=$T/PWNED-v2; $bad12 tools/proxy.sh" \
		"timeout 20 git -C '$V12' fetch -q git://pa.invalid/x" "$T/PWNED-v2"
	git -C "$V12" config gpg.format ssh
	git -C "$V12" config gpg.ssh.defaultKeyCommand tools/dkc.sh
	host_case "(12c) gpg.ssh.defaultKeyCommand" "$V12" "$V12/tools/dkc.sh" "MK=$T/PWNED-v3; $bad12 tools/dkc.sh" \
		"timeout 20 git -C '$V12' commit -q -S --allow-empty -m s" "$T/PWNED-v3"
	# git-lfs and git-send-email are not installed here: assert the referenced script is
	# read-only inside (mutation: writable without the bind)
	git -C "$V12" config lfs.customtransfer.x.path tools/lfs.sh
	git -C "$V12" config sendemail.sendmailCmd 'sh tools/sendmail.sh'
	for s in lfs sendmail; do
		run_mut_drop "$V12" "$V12/tools/$s.sh" "echo PWN >> tools/$s.sh" >/dev/null 2>&1 || true
		grep -q PWN "$V12/tools/$s.sh" && ok "MUTATION ((12d) $s): script writable without its bind" || bad "MUTATION ((12d) $s): script writable without its bind"
		printf '#!/bin/sh\nexit 1\n' >"$V12/tools/$s.sh"
		run_ws "$V12" "echo PWN >> tools/$s.sh 2>/dev/null; true" >/dev/null 2>&1 || true
		! grep -q PWN "$V12/tools/$s.sh" && ok "(12d) $s script named by its config value is read-only" || bad "(12d) $s script named by its config value is read-only"
	done
	command rm -rf "$V12"
	# (13) item 5: a bare word (no `/`) that exists relative to the root: sh fsmon.sh
	B13="$FH/work/cfg-bareword"
	mkrepo "$B13"
	printf 'exit 1\n' >"$B13/fsmon.sh"
	git -C "$B13" config core.fsmonitor 'sh fsmon.sh'
	host_case "(13) core.fsmonitor = sh fsmon.sh (bare word)" "$B13" "$B13/fsmon.sh" \
		"MK=$T/PWNED-b13; printf 'touch %s\nexit 1\n' \"\$MK\" > fsmon.sh" "git -C '$B13' status" "$T/PWNED-b13"
	# a word after $(...) is tried relative to the root as well
	mkdir -p "$B13/tools"
	printf 'exit 1\n' >"$B13/tools/x.sh"
	git -C "$B13" config core.fsmonitor 'sh "$(git rev-parse --show-toplevel)/tools/x.sh"'
	(HOME="$FH" pa_sandbox_build_argv "$B13") >/dev/null 2>&1 && ok "(13b) real profile builds (control)" || bad "(13b) real profile builds (control)"
	run_ws "$B13" 'echo PWN >> tools/x.sh 2>/dev/null; true' >/dev/null 2>&1 || true
	! grep -q PWN "$B13/tools/x.sh" && ok "(13b) \$(...)/tools/x.sh is read-only inside" || bad "(13b) \$(...)/tools/x.sh is read-only inside"
	command rm -rf "$B13"
	# (14) exclusion rules: obvious non-paths do not refuse and add no read-only entries
	X14="$FH/work/cfg-nonpaths"
	mkrepo "$X14"
	mkdir -p "$X14/mirror"
	git -C "$X14" config core.autocrlf false
	git -C "$X14" config core.bigFileThreshold 512m
	git -C "$X14" config pack.threads 4
	git -C "$X14" config remote.origin.url https://example.invalid/o/r.git
	git -C "$X14" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
	git -C "$X14" config remote.up.url git@example.invalid:o/r.git
	git -C "$X14" config branch.main.merge refs/heads/main
	git -C "$X14" config alias.ahead '!git log origin/main..HEAD'
	git -C "$X14" config alias.dm 'diff origin/main'
	git -C "$X14" config user.signingkey 'key::ssh-ed25519 AAAAC3Nza/C1lZDI1+NTE5'
	git -C "$X14" config safe.directory "$X14"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$X14") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(14) true/number/https/refspec/scp/range/key::/root/origin-ref values: builds rc" "0" "$rc"
	expect_lacks "(14) no read-only entries announced" "read-only inside" "$out"
	# file:// is a local path: protected
	git -C "$X14" config remote.loc.url "file://$X14/mirror"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$X14") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(14b) file:// url builds rc" "0" "$rc"
	expect_has "(14b) file:// target announced read-only" "mirror" "$out"
	# a word with / whose top-level dir is missing refuses (accepted false refusal)
	git -C "$X14" config alias.co '!git checkout upstream/main'
	out="$( (HOME="$FH" pa_sandbox_build_argv "$X14") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(14c) missing word with / (upstream/main, no such remote or dir) refuses rc" "1" "$rc"
	command rm -rf "$X14"

	# ---- Checker attempt 12, items 1-3.
	# (15) item 1: a MISSING bare word a shell/interpreter opens relative to the current
	# directory (`sh fsmon.sh`) is handled like ./fsmon.sh. M3: that rule removed.
	MUT3="$T/pa-sandbox.mut-interp"
	sed 's/ || "\$2" == i \]\] || continue/ ]] || continue/' "$PA_SANDBOX" >"$MUT3"
	! grep -q '"\$2" == i \]\]' "$MUT3" && ok "M3 mutation applied" || bad "M3 mutation applied"
	P15="$FH/work/cfg-missing-bare"
	mkrepo "$P15"
	git -C "$P15" config core.fsmonitor 'sh fsmon.sh'
	mut_case "(15) core.fsmonitor = sh fsmon.sh, fsmon.sh missing" "$P15" "$MUT3" \
		"MK=$T/PWNED-p15; printf 'touch %s\nexit 1\n' \"\$MK\" > fsmon.sh" "git -C '$P15' status" "$T/PWNED-p15" "does not exist and sits directly under"
	# in a nested repo the missing word is covered by its top-level ancestor (like ./x)
	git -C "$P15" config --unset core.fsmonitor
	mkdir -p "$P15/vendor"
	git init -q "$P15/vendor/dep"
	git -C "$P15/vendor/dep" config core.fsmonitor 'sh hook.sh'
	host_case "(15b) nested repo: core.fsmonitor = sh hook.sh, hook.sh missing" "$P15" "$P15/vendor/dep/hook.sh" \
		"MK=$T/PWNED-p15b; printf 'touch %s\nexit 1\n' \"\$MK\" > vendor/dep/hook.sh" "git -C '$P15/vendor/dep' status" "$T/PWNED-p15b"
	command rm -rf "$P15/vendor"
	# other interpreter positions refuse too; an expansion as the file refuses
	for v in 'python3 -m fsmon' 'sh < fsmon.sh' 'env FOO=1 bash fsmon.sh' 'timeout 5 sh fsmon.sh' 'sh $HOOK'; do
		git -C "$P15" config core.fsmonitor "$v"
		out="$( (HOME="$FH" pa_sandbox_build_argv "$P15") 2>&1 )" && rc=0 || rc=$?
		expect_eq "(15c) core.fsmonitor = $v (missing) refused rc" "1" "$rc"
	done
	expect_has "(15c) expansion message" "cannot tell which file" "$out"
	git -C "$P15" config --unset core.fsmonitor
	# command names and arguments of other programs: missing is fine (PATH / not opened as code)
	mkdir -p "$P15/tools"
	printf 'exit 0\n' >"$P15/tools/clean.sh"
	git -C "$P15" config core.editor vim
	git -C "$P15" config core.pager 'less -R'
	git -C "$P15" config pager.diff 'lumen diff'
	git -C "$P15" config user.name 'Yusuke Kato'
	git -C "$P15" config credential.helper '!gh auth git-credential'
	git -C "$P15" config alias.la 'log --pretty="format:%an <%ae> (%h)" --date=short'
	git -C "$P15" config alias.eu '!f() { git ls-files --unmerged | cut -f2 | sort -u ; }; vim `f`'
	git -C "$P15" config filter.x.clean 'sh tools/clean.sh %f'
	out="$( (HOME="$FH" pa_sandbox_build_argv "$P15") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(15d) missing command names / non-interpreter arguments build rc" "0" "$rc"
	command rm -rf "$P15"

	# (16) item 2: a bare repo already in the workspace (not named .git) is protected like
	# .git. Host `git push` from a repo OUTSIDE the workspace runs its post-receive hook.
	B16="$FH/work/bare-in-ws"
	mkrepo "$B16"
	git init -q --bare "$B16/mirror.git"
	O16="$T/outside-16"
	mkrepo "$O16"
	git -C "$O16" -c commit.gpgsign=false commit -q --allow-empty -m i
	git -C "$O16" remote add loc "$B16/mirror.git"
	host_case "(16) bare repo ws/mirror.git, host push runs post-receive" "$B16" "$B16/mirror.git" \
		"MK=$T/PWNED-b16; $hook mirror.git/hooks/post-receive && chmod +x mirror.git/hooks/post-receive" \
		"git -C '$O16' push -q loc HEAD:refs/heads/x" "$T/PWNED-b16"
	# nested bare repo: its top-level ancestor is read-only too; its config is scanned
	mkdir -p "$B16/sub"
	git init -q --bare "$B16/sub/m.git"
	run_mut_drop "$B16" "$B16/sub/m.git" 'echo "[evil]" >> sub/m.git/config' >/dev/null 2>&1 || true
	grep -q '^\[evil\]' "$B16/sub/m.git/config" && ok "MUTATION: nested bare repo config writable without its bind" || bad "MUTATION: nested bare repo config writable without its bind"
	sed -i '/^\[evil\]/d' "$B16/sub/m.git/config"
	out="$(run_ws "$B16" 'echo "[evil]" >> sub/m.git/config 2>/dev/null; true')"
	! grep -q '^\[evil\]' "$B16/sub/m.git/config" && ok "(16b) nested bare repo config is read-only inside" || bad "(16b) nested bare repo config is read-only inside" "$out"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$B16") 2>&1 )" || true
	expect_has "(16b) nested bare repo ancestor announced" "sub/" "$out"
	git -C "$B16/sub/m.git" config core.hooksPath .missing-hooks
	out="$( (HOME="$FH" pa_sandbox_build_argv "$B16") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(16c) bare repo config is scanned (missing hooksPath inside it is under the ro repo) rc" "0" "$rc"
	git -C "$B16/sub/m.git" config core.fsmonitor 'sh ../../fsmon.sh'
	out="$( (HOME="$FH" pa_sandbox_build_argv "$B16") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(16c) bare repo config naming a missing root file refuses rc" "1" "$rc"
	command rm -rf "$B16/sub"
	# a stray HEAD file without objects/ refs/ commondir is not a git dir
	mkdir -p "$B16/docs"
	printf 'x\n' >"$B16/docs/HEAD"
	command rm -rf "$B16/mirror.git"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$B16") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(16d) stray HEAD file builds rc" "0" "$rc"
	expect_lacks "(16d) stray HEAD file adds no read-only entries" "read-only inside" "$out"
	command rm -rf "$B16" "$O16"

	# (17) item 3: a hard-linked git control file whose other name stays writable inside.
	# M4: the hard-link check removed.
	MUT4="$T/pa-sandbox.mut-hardlink"
	sed 's/^\tif \[\[ \${#hl\[@\]} -gt 0 \]\]; then$/\tif false; then/' "$PA_SANDBOX" >"$MUT4"
	grep -q '^	if false; then$' "$MUT4" && ok "M4 mutation applied" || bad "M4 mutation applied"
	H17="$FH/work/hardlink-hook"
	mkrepo "$H17"
	mkdir -p "$H17/scripts"
	printf '#!/bin/sh\nexit 0\n' >"$H17/scripts/pre-commit"
	chmod +x "$H17/scripts/pre-commit"
	ln "$H17/scripts/pre-commit" "$H17/.git/hooks/pre-commit"
	mut_case "(17) hard-linked .git/hooks/pre-commit" "$H17" "$MUT4" "MK=$T/PWNED-h17; $hook scripts/pre-commit" \
		"$(commit_cmd "$H17")" "$T/PWNED-h17" "hard-linked git control file"
	command rm -f "$H17/.git/hooks/pre-commit"
	# a config-referenced script and an include file, hard-linked to a writable name
	mkdir -p "$H17/tools"
	printf 'exit 1\n' >"$H17/tools/fsmon.sh"
	ln "$H17/tools/fsmon.sh" "$H17/scripts/f.sh"
	git -C "$H17" config core.fsmonitor 'sh tools/fsmon.sh'
	out="$( (HOME="$FH" pa_sandbox_build_argv "$H17") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(17b) hard-linked config-referenced script refused rc" "1" "$rc"
	git -C "$H17" config --unset core.fsmonitor
	printf '[user]\n\tname = t\n' >"$H17/.gitconfig"
	ln "$H17/.gitconfig" "$H17/scripts/copy.cfg"
	git -C "$H17" config include.path ../.gitconfig
	out="$( (HOME="$FH" pa_sandbox_build_argv "$H17") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(17c) hard-linked include file refused rc" "1" "$rc"
	command rm -f "$H17/scripts/copy.cfg" "$H17/scripts/f.sh"
	# the other name in an rw state dir refuses; outside every writable path is accepted
	ln "$H17/.gitconfig" "$FH/.prime/agent/sessions/copy.cfg"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$H17") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(17d) hard link into an rw state dir refused rc" "1" "$rc"
	command rm -f "$FH/.prime/agent/sessions/copy.cfg"
	ln "$H17/.gitconfig" "$T/outside-17.cfg"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$H17") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(17e) hard link only outside writable paths accepted rc" "0" "$rc"
	command rm -rf "$H17" "$T/outside-17.cfg"

	# ---- Checker attempt 13, items 1-2.
	# mut_host: a mutated pa-sandbox lets the sandbox plant what host git later runs/trusts;
	# the real profile builds and the same attack is blocked.
	mut_host() { # <label> <workspace> <mutated pa-sandbox> <attack sh> <host cmd> <marker>
		local lbl="$1" ws="$2" msb="$3" atk="$4" hc="$5" mk="$6"
		command cp -a "$ws" "$ws.pristine"
		# shellcheck source=/dev/null # mutated copy of pa-sandbox
		( cd "$ws"; export HOME="$FH"; source "$msb"; pa_sandbox_build_argv "$ws" 2>/dev/null && "${PA_BWRAP_ARGV[@]}" sh -c "$atk" ) >/dev/null 2>&1 || true
		(eval "$hc") >/dev/null 2>&1 || true
		[[ -e "$mk" ]] && ok "MUTATION ($lbl, check removed): host git runs/trusts the attacker's file" || bad "MUTATION ($lbl, check removed): host git runs/trusts the attacker's file"
		command rm -rf "$ws" "$mk"
		command cp -a "$ws.pristine" "$ws"
		command rm -rf "$ws.pristine"
		out="$( (HOME="$FH" pa_sandbox_build_argv "$ws") 2>&1 )" && rc=0 || rc=$?
		expect_eq "$lbl: real profile builds rc" "0" "$rc"
		run_ws "$ws" "$atk" >/dev/null 2>&1 || true
		(eval "$hc") >/dev/null 2>&1 || true
		[[ ! -e "$mk" ]] && ok "$lbl: blocked" || bad "$lbl: blocked"
		command rm -f "$mk"
	}
	# M5: git dirs under modules/ and worktrees/* not enumerated
	MUT5="$T/pa-sandbox.mut-subctx"
	sed 's|^\t\t_sub_ctx "\$g" "\$c" "\$2"$|\t\t: # MUTATION|' "$PA_SANDBOX" >"$MUT5"
	grep -q ': # MUTATION' "$MUT5" && ok "M5 mutation applied" || bad "M5 mutation applied"
	GS="git -c protocol.file.allow=always -c commit.gpgsign=false"
	SRC18="$T/subsrc-18"
	mkrepo "$SRC18"
	git -C "$SRC18" -c commit.gpgsign=false commit -q --allow-empty -m s
	# (18) item 1: deinitialised submodule; its git dir .git/modules/sub has a relative
	# core.hooksPath; host `git submodule update --init` runs post-checkout from sub/.githooks
	S18="$FH/work/deinit-sub"
	mkrepo "$S18"
	git -C "$S18" -c commit.gpgsign=false commit -q --allow-empty -m i
	$GS -C "$S18" submodule add -q "$SRC18" sub
	$GS -C "$S18" commit -q -m sub
	git -C "$S18/sub" config core.hooksPath .githooks
	$GS -C "$S18" submodule deinit -q -f sub
	[[ -d "$S18/.git/modules/sub" && ! -e "$S18/sub/.git" ]] && ok "(18) fixture: deinitialised submodule keeps .git/modules/sub" || bad "(18) fixture: deinitialised submodule keeps .git/modules/sub"
	mut_host "(18) deinit'ed submodule core.hooksPath" "$S18" "$MUT5" \
		"MK=$T/PWNED-s18; mkdir -p sub/.githooks && $hook sub/.githooks/post-checkout && chmod +x sub/.githooks/post-checkout" \
		"$GS -C '$S18' submodule update -q --init" "$T/PWNED-s18"
	# (18b) name != path: .gitmodules maps the name libx to vendor/x
	$GS -C "$S18" submodule add -q --name libx "$SRC18" vendor/x
	$GS -C "$S18" commit -q -m libx
	git -C "$S18/vendor/x" config core.hooksPath .githooks
	$GS -C "$S18" submodule deinit -q -f vendor/x
	mut_host "(18b) submodule name libx -> path vendor/x (.gitmodules)" "$S18" "$MUT5" \
		"MK=$T/PWNED-s18b; mkdir -p vendor/x/.githooks && $hook vendor/x/.githooks/post-checkout && chmod +x vendor/x/.githooks/post-checkout" \
		"$GS -C '$S18' submodule update -q --init vendor/x" "$T/PWNED-s18b"
	# (18c) nested submodule git dir modules/sub/modules/inner (recursion; root sub/inner).
	# The host runs above re-initialised sub and vendor/x: deinit them again.
	$GS -C "$S18" submodule deinit -q -f --all
	[[ ! -e "$S18/sub/.git" && ! -e "$S18/vendor/x/.git" ]] && ok "(18c) fixture: submodules deinitialised again" || bad "(18c) fixture: submodules deinitialised again"
	git -C "$S18/.git/modules/sub" config --unset core.hooksPath
	git -C "$S18/.git/modules/libx" config --unset core.hooksPath
	git init -q --bare "$S18/.git/modules/sub/modules/inner"
	git -C "$S18/.git/modules/sub/modules/inner" config core.hooksPath .h
	out="$(run_mut_drop "$S18" "$S18/sub" 'mkdir -p sub/inner/.h' 2>&1)" || true
	[[ -d "$S18/sub/inner/.h" ]] && ok "MUTATION ((18c) nested module, sub/ bind dropped): hooks dir creatable" || bad "MUTATION ((18c) nested module, sub/ bind dropped): hooks dir creatable" "$out"
	command rm -rf "$S18/sub/inner"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$S18") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(18c) nested submodule git dir: builds rc" "0" "$rc"
	expect_has "(18c) its root's top-level ancestor announced read-only" "sub/" "$out"
	run_ws "$S18" 'mkdir -p sub/inner/.h 2>/dev/null; true' >/dev/null 2>&1 || true
	[[ ! -e "$S18/sub/inner/.h" ]] && ok "(18c) nested submodule hooksPath cannot be created" || bad "(18c) nested submodule hooksPath cannot be created"
	command rm -rf "$S18/.git/modules/sub/modules"
	# (18d) refusals: a .gitmodules path leaving the root, a symlinked dir under modules/
	git -C "$S18" config --file .gitmodules submodule.libx.path ../out
	out="$( (HOME="$FH" pa_sandbox_build_argv "$S18") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(18d) submodule path ../out refused rc" "1" "$rc"
	expect_has "(18d) refusal message" "cannot tell the worktree" "$out"
	git -C "$S18" config --file .gitmodules submodule.libx.path vendor/x
	mkdir -p "$T/outmod-18"
	ln -s "$T/outmod-18" "$S18/.git/modules/lnk"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$S18") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(18d) symlinked dir under modules/ refused rc" "1" "$rc"
	command rm -rf "$S18" "$T/outmod-18" "$SRC18"
	# (18e) worktrees/*: a linked worktree inside the workspace whose .git gitfile is gone;
	# its config.worktree sets a relative core.hooksPath. The sandbox re-creates the gitfile
	# and the hooks; host git in that worktree runs them.
	W18="$FH/work/wt-gone"
	mkrepo "$W18"
	git -C "$W18" -c commit.gpgsign=false commit -q --allow-empty -m i
	git -C "$W18" config extensions.worktreeConfig true
	git -C "$W18" worktree add -q --detach "$W18/wt/a"
	git -C "$W18/wt/a" config --worktree core.hooksPath .githooks
	command rm -f "$W18/wt/a/.git"
	mut_host "(18e) worktree admin dir .git/worktrees/a (gitfile gone)" "$W18" "$MUT5" \
		"MK=$T/PWNED-w18; printf 'gitdir: %s\n' \"\$PWD/.git/worktrees/a\" > wt/a/.git && mkdir -p wt/a/.githooks && $hook wt/a/.githooks/pre-commit && chmod +x wt/a/.githooks/pre-commit" \
		"$(commit_cmd "$W18/wt/a")" "$T/PWNED-w18"
	# an admin dir without a gitdir file: its worktree is unknown -> refuse
	command rm -f "$W18/.git/worktrees/a/gitdir"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$W18") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(18e) worktree admin dir without gitdir refused rc" "1" "$rc"
	command rm -rf "$W18"

	# (19) item 2: a ONE-WORD config value is a path even when missing (no key list of path
	# keys). M6: that rule removed.
	MUT6="$T/pa-sandbox.mut-oneword"
	sed 's|\[\[ \$sw -eq 1 && |[[ 0 -eq 1 \&\& |' "$PA_SANDBOX" >"$MUT6"
	grep -q '\[\[ 0 -eq 1 && "\$w" == w:' "$MUT6" && ok "M6 mutation applied" || bad "M6 mutation applied"
	# (19a) gpg.ssh.allowedSignersFile = allowed_signers (missing): host trusts the attacker key
	A19="$FH/work/allowed-signers"
	mkrepo "$A19"
	git -C "$A19" config gpg.format ssh
	git -C "$A19" config gpg.ssh.allowedSignersFile allowed_signers
	ssh-keygen -q -t ed25519 -N '' -f "$T/atk19" -C atk
	mut_case "(19a) gpg.ssh.allowedSignersFile = allowed_signers" "$A19" "$MUT6" \
		"echo 't@example.invalid $(cat "$T/atk19.pub")' > allowed_signers" \
		"git -C '$A19' -c user.signingkey='$T/atk19' commit -q -S --allow-empty -m s && [ \"\$(git -C '$A19' log -1 --format=%G?)\" = G ] && touch '$T/PWNED-a19'" \
		"$T/PWNED-a19" "does not exist and sits directly under"
	command rm -f "$T/PWNED-a19"
	command rm -rf "$A19"
	# (19b) http.sslCAInfo = ca.pem (missing): host git trusts the attacker CA (local TLS server)
	C19="$FH/work/ssl-cainfo"
	mkrepo "$C19"
	git -C "$C19" config http.sslCAInfo ca.pem
	openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$T/tls19.key" -out "$T/tls19.pem" \
		-days 2 -subj /CN=127.0.0.1 -addext subjectAltName=IP:127.0.0.1 >/dev/null 2>&1
	python3 -I -c 'import http.server,ssl,sys
s=http.server.HTTPServer(("127.0.0.1",0),http.server.BaseHTTPRequestHandler)
c=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); c.load_cert_chain(sys.argv[1],sys.argv[2])
s.socket=c.wrap_socket(s.socket,server_side=True); s.timeout=60
open(sys.argv[3]+".tmp","w").write(str(s.server_address[1])); __import__("os").rename(sys.argv[3]+".tmp",sys.argv[3])
for _ in range(6): s.handle_request()' "$T/tls19.pem" "$T/tls19.key" "$T/tls19.port" >/dev/null 2>&1 &
	TLSPID=$!
	for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$T/tls19.port" ]] && break; sleep 0.3; done
	TLSURL="https://127.0.0.1:$(cat "$T/tls19.port" 2>/dev/null)/x"
	lsr19="(GIT_TERMINAL_PROMPT=0 timeout 10 git -C '$C19' ls-remote '$TLSURL' 2>&1 || true) | grep -q 'returned error' && touch '$T/PWNED-c19'"
	(eval "$lsr19") >/dev/null 2>&1 || true
	[[ ! -e "$T/PWNED-c19" ]] && ok "(19b) fixture: without ca.pem the TLS server is not trusted" || bad "(19b) fixture: without ca.pem the TLS server is not trusted"
	command rm -f "$T/PWNED-c19"
	mut_case "(19b) http.sslCAInfo = ca.pem" "$C19" "$MUT6" "cat '$T/tls19.pem' > ca.pem" "$lsr19" "$T/PWNED-c19" \
		"does not exist and sits directly under"
	kill "$TLSPID" 2>/dev/null || true
	command rm -rf "$C19" "$T/PWNED-c19" "$T"/tls19.*
	# (19c) init.templateDir = tmpl in the host GLOBAL config (missing): host `git init` run
	# in the workspace root (re-init) copies the attacker's hooks into .git/hooks
	I19="$FH/work/templatedir"
	mkrepo "$I19"
	printf '[init]\n\ttemplateDir = tmpl\n' >"$T/global-19.cfg"
	GIT_CONFIG_GLOBAL="$T/global-19.cfg" mut_case "(19c) global init.templateDir = tmpl" "$I19" "$MUT6" \
		"MK=$T/PWNED-i19; mkdir -p tmpl/hooks && $hook tmpl/hooks/pre-commit && chmod +x tmpl/hooks/pre-commit" \
		"cd '$I19' && git init -q && $(commit_cmd "$I19")" \
		"$T/PWNED-i19" "does not exist and sits directly under"
	command rm -rf "$I19" "$T/PWNED-i19" "$T/global-19.cfg"
	# (19d) legitimate one-word / command values still build: command names, person names,
	# e-mail, enums, remote/branch names, GPG key id, insteadOf, aliases
	P19="$FH/work/oneword-ok"
	mkrepo "$P19"
	git -C "$P19" config core.editor vim
	git -C "$P19" config gpg.program gpg
	git -C "$P19" config user.name kpango
	git -C "$P19" config user.email kpango@example.invalid
	git -C "$P19" config --add user.name 'Yusuke Kato'
	git -C "$P19" config credential.helper '!gh auth git-credential'
	git -C "$P19" config credential.username kpango
	git -C "$P19" config user.signingkey 89013853239E4E9A
	git -C "$P19" config push.default tracking
	git -C "$P19" config pull.ff only
	git -C "$P19" config color.ui auto
	git -C "$P19" config diff.colorMoved default
	git -C "$P19" config init.defaultBranch main
	git -C "$P19" config remote.origin.url https://example.invalid/x.git
	git -C "$P19" config branch.main.remote origin
	git -C "$P19" config url.https://example.invalid/.insteadOf git@example.invalid
	git -C "$P19" config alias.st status
	git -C "$P19" config alias.rbm 'rebase main'
	git -C "$P19" config merge.graphify.name 'graphify graph.json union merge'
	out="$( (HOME="$FH" pa_sandbox_build_argv "$P19") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(19d) command names / names / enums / key id / insteadOf build rc" "0" "$rc"
	expect_lacks "(19d) no read-only entries announced" "read-only inside" "$out"
	# an unknown key with a one-word value is a path (fail closed): refused when missing
	git -C "$P19" config tool.x.cfg conf
	out="$( (HOME="$FH" pa_sandbox_build_argv "$P19") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(19d) unknown key, missing one-word value refused rc" "1" "$rc"
	command rm -rf "$P19"

	# ---- Checker attempt 14, items 1-3, the hex rule; url.<base>.insteadOf, :(optional).
	# (20a) item 1: branch.<b>.remote naming no configured remote is a path for git push.
	# M7: a remote name is never a path and no URL host git resolves it to counts as local.
	# M14 (the protection of every remote name's local URL / path, (20a4)); M7 and M12 include it
	# because that loop also covers their cases
	m14=(-e "s/_cand \"\\\$t\" i \"URL of remote '\\\$n'\" \"\\\$2\" || return 1/:/"
		-e "s/_cand \"\\\$n\" i \"remote name '\\\$n' (host git uses it as a path)\" \"\\\$2\" || return 1/:/")
	MUT7="$T/pa-sandbox.mut-remote"
	sed "${m14[@]}" -e 's/^\t\t\(branch\.\*\.remote | .* | extensions\.partialclone\)) return 1 ;;$/\t\t\1) return 0 ;;/' \
		-e 's/_rurl "\$u" && rq/false \&\& rq/' "$PA_SANDBOX" >"$MUT7"
	grep -q 'extensions.partialclone) return 0 ;;' "$MUT7" && grep -q 'false && rq\[' "$MUT7" && ! grep -q "URL of remote '\$n'" "$MUT7" && ok "M7 mutation applied" || bad "M7 mutation applied"
	G20="$FH/work/branch-remote"
	mkrepo "$G20"
	git -C "$G20" symbolic-ref HEAD refs/heads/main
	git -C "$G20" -c commit.gpgsign=false commit -q --allow-empty -m i
	git -C "$G20" config branch.main.remote backup
	git -C "$G20" config branch.main.merge refs/heads/main
	mut_case "(20a) branch.main.remote = backup (no such remote)" "$G20" "$MUT7" \
		"MK=$T/PWNED-g20; git init -q --bare backup && $hook backup/hooks/pre-receive && chmod +x backup/hooks/pre-receive" \
		"git -C '$G20' push -q" "$T/PWNED-g20" "does not exist and sits directly under"
	command rm -rf "$G20/backup" "$T/PWNED-g20"
	# a remote with only remote.<name>.fetch is still a path for git; with a url it is a name
	git -C "$G20" config remote.backup.fetch '+refs/heads/*:refs/remotes/backup/*'
	out="$( (HOME="$FH" pa_sandbox_build_argv "$G20") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(20a) remote name with only remote.<name>.fetch refused rc" "1" "$rc"
	git -C "$G20" config remote.backup.url https://example.invalid/x.git
	out="$( (HOME="$FH" pa_sandbox_build_argv "$G20") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(20a) configured remote name builds rc" "0" "$rc"
	git -C "$G20" config --remove-section remote.backup
	git -C "$G20" config --unset branch.main.remote
	for kv in branch.main.pushRemote remote.pushDefault checkout.defaultRemote extensions.partialClone; do
		git -C "$G20" config "$kv" backup
		out="$( (HOME="$FH" pa_sandbox_build_argv "$G20") 2>&1 )" && rc=0 || rc=$?
		expect_eq "(20a) $kv = backup (no such remote) refused rc" "1" "$rc"
		git -C "$G20" config --unset "$kv"
	done
	command rm -rf "$G20"
	# (20a2) a remote.<name>.url KEY that host git does not apply or that resets the list:
	# git still uses the name as the URL ./backup (Checker attempt 15). M7 as above.
	for md in empty reset incif wt; do
		mkrepo "$G20"
		git -C "$G20" symbolic-ref HEAD refs/heads/main
		git -C "$G20" -c commit.gpgsign=false commit -q --allow-empty -m i
		case "$md" in
		empty) git -C "$G20" config remote.backup.url '' ;;
		reset)
			git -C "$G20" config remote.backup.url /nonexistent/elsewhere.git
			git -C "$G20" config --add remote.backup.url ''
			;;
		incif)
			git -C "$G20" config --file "$G20/.git/other.inc" remote.backup.url /nonexistent/elsewhere.git
			git -C "$G20" config 'includeIf.gitdir:/nonexistent/.path' other.inc
			;;
		wt) git -C "$G20" config --file "$G20/.git/config.worktree" remote.backup.url /nonexistent/elsewhere.git ;;
		esac
		git -C "$G20" config branch.main.remote backup
		git -C "$G20" config branch.main.merge refs/heads/main
		mut_case "(20a2) remote.backup.url $md, branch.main.remote = backup" "$G20" "$MUT7" \
			"MK=$T/PWNED-g20; git init -q --bare backup && $hook backup/hooks/pre-receive && chmod +x backup/hooks/pre-receive" \
			"git -C '$G20' push -q" "$T/PWNED-g20" "does not exist and sits directly under"
		command rm -rf "$G20" "$T/PWNED-g20"
	done
	# legitimate: a real remote, one rewritten to https by insteadOf, one rewritten to a local
	# path outside the workspace (protected as that path) all build
	mkrepo "$G20"
	git -C "$G20" config remote.origin.url https://example.invalid/x.git
	git -C "$G20" config remote.gh.url gh:o/r
	git -C "$G20" config url.https://example.invalid/.insteadOf gh:
	git -C "$G20" config remote.mir.url https://pa-mirror.invalid/r
	git -C "$G20" config url./srv/pa-mirror/.insteadOf https://pa-mirror.invalid/
	[[ "$(git -C "$G20" remote get-url gh)|$(git -C "$G20" remote get-url mir)" == "https://example.invalid/o/r|/srv/pa-mirror/r" ]] &&
		ok "(20a2) fixture: insteadOf rewrites as expected" || bad "(20a2) fixture: insteadOf rewrites as expected"
	for rn in origin gh mir; do
		git -C "$G20" config branch.main.remote "$rn"
		out="$( (HOME="$FH" pa_sandbox_build_argv "$G20") 2>&1 )" && rc=0 || rc=$?
		expect_eq "(20a2) branch.main.remote = $rn (resolved by host git) builds rc" "0" "$rc"
	done
	command rm -rf "$G20"
	# a remote that only git knows (legacy .git/remotes/<name>, no config key) with a missing
	# local URL in the workspace: that URL is protected (its ancestor ro), M7 leaves it writable
	mkrepo "$G20"
	git -C "$G20" symbolic-ref HEAD refs/heads/main
	git -C "$G20" -c commit.gpgsign=false commit -q --allow-empty -m i
	mkdir -p "$G20/.git/remotes" "$G20/mirror"
	printf 'URL: mirror/r\n' >"$G20/.git/remotes/mir"
	git -C "$G20" config branch.main.remote mir
	for sb in "$MUT7" "$PA_SANDBOX"; do
		# shellcheck source=/dev/null # pa-sandbox or its mutated copy
		( cd "$G20"; export HOME="$FH"; source "$sb"; pa_sandbox_build_argv "$G20" 2>/dev/null && "${PA_BWRAP_ARGV[@]}" sh -c \
			"MK=$T/PWNED-l20; git init -q --bare mirror/r && $hook mirror/r/hooks/pre-receive && chmod +x mirror/r/hooks/pre-receive" ) >/dev/null 2>&1 || true
		git -C "$G20" push -q mir main >/dev/null 2>&1 || true
		if [[ "$sb" == "$MUT7" ]]; then
			[[ -e "$T/PWNED-l20" ]] && ok "MUTATION ((20a2) legacy remotes/ file, local URL unprotected): host git runs the attacker's code" ||
				bad "MUTATION ((20a2) legacy remotes/ file, local URL unprotected): host git runs the attacker's code"
		else
			[[ ! -e "$T/PWNED-l20" ]] && ok "(20a2) legacy remotes/ file: local URL in the workspace is read-only" ||
				bad "(20a2) legacy remotes/ file: local URL in the workspace is read-only"
		fi
		command rm -rf "$G20/mirror/r" "$T/PWNED-l20"
	done
	command rm -rf "$G20"
	# (20a4) a remote name no remote-name KEY names, used by an explicit `git push <name>` or by
	# a legacy remotes/ file for a plain `git push` (Checker attempt 16): every name host git
	# may know (remote.<n>.* sections, remotes/*, branches/*) is resolved and its local URL /
	# the name as a path protected. M14: that protection removed.
	MUT14="$T/pa-sandbox.mut-rnames"
	sed "${m14[@]}" "$PA_SANDBOX" >"$MUT14"
	! grep -q "URL of remote '\$n'\|remote name '\$n'" "$MUT14" && grep -q "URL of remote '\$n'" "$PA_SANDBOX" && ok "M14 mutation applied" || bad "M14 mutation applied"
	for md in fetchonly empty reset incif wt remotes-default branches-explicit; do
		mkrepo "$G20"
		git -C "$G20" symbolic-ref HEAD refs/heads/main
		git -C "$G20" -c commit.gpgsign=false commit -q --allow-empty -m i
		hc="git -C '$G20' push -q backup HEAD:refs/heads/main"
		case "$md" in
		empty) git -C "$G20" config remote.backup.url '' ;;
		reset)
			git -C "$G20" config remote.backup.url /nonexistent/elsewhere.git
			git -C "$G20" config --add remote.backup.url ''
			;;
		incif)
			git -C "$G20" config --file "$G20/.git/other.inc" remote.backup.url /nonexistent/elsewhere.git
			git -C "$G20" config 'includeIf.gitdir:/nonexistent/.path' other.inc
			;;
		wt) git -C "$G20" config --file "$G20/.git/config.worktree" remote.backup.url /nonexistent/elsewhere.git ;;
		remotes-default)
			mkdir -p "$G20/.git/remotes"
			printf 'URL: backup\nPush: refs/heads/main:refs/heads/main\n' >"$G20/.git/remotes/origin"
			hc="git -C '$G20' push -q"
			;;
		branches-explicit)
			mkdir -p "$G20/.git/branches"
			printf 'backup#main\n' >"$G20/.git/branches/backup"
			hc="git -C '$G20' push -q backup"
			;;
		esac
		[[ "$md" == remotes-* || "$md" == branches-* ]] || git -C "$G20" config remote.backup.fetch '+refs/heads/*:refs/remotes/backup/*'
		mut_case "(20a4) remote name without a remote-name key: $md" "$G20" "$MUT14" \
			"MK=$T/PWNED-g20; git init -q --bare backup && $hook backup/hooks/pre-receive && chmod +x backup/hooks/pre-receive" \
			"$hc" "$T/PWNED-g20" "does not exist and sits directly under"
		command rm -rf "$G20" "$T/PWNED-g20"
	done
	# legitimate: remotes that resolve to remote URLs (https, insteadOf to https, a legacy
	# remotes/ file with an https URL) and no remote-name key build
	mkrepo "$G20"
	git -C "$G20" config remote.origin.url https://example.invalid/x.git
	git -C "$G20" config remote.gh.url gh:o/r
	git -C "$G20" config url.https://example.invalid/.insteadOf gh:
	mkdir -p "$G20/.git/remotes"
	printf 'URL: https://example.invalid/y.git\n' >"$G20/.git/remotes/up"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$G20") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(20a4) https / insteadOf-to-https / legacy https remotes build rc" "0" "$rc"
	# remotes/ and branches/ sit in the read-only git dir: the sandbox cannot add a remote file
	# shellcheck source=/dev/null
	out="$( cd "$G20"; export HOME="$FH"; source "$PA_SANDBOX"; pa_sandbox_build_argv "$G20" 2>/dev/null && "${PA_BWRAP_ARGV[@]}" sh -c \
		"printf 'URL: backup\n' > .git/remotes/origin && echo WROTE-R; mkdir .git/branches && echo WROTE-B" 2>&1 )" || true
	expect_lacks "(20a4) sandbox cannot add a legacy remotes/ file" "WROTE-R" "$out"
	expect_lacks "(20a4) sandbox cannot create branches/" "WROTE-B" "$out"
	# enumeration fails closed: a symlink inside / as remotes/ refuses
	# (targets outside the workspace: only the legacy-dir scan refuses them)
	printf 'URL: https://example.invalid/z.git\n' >"$T/outside-remote"
	mkdir -p "$T/outside-branches"
	ln -s "$T/outside-remote" "$G20/.git/remotes/lnk"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$G20") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(20a4) symlink in .git/remotes refused rc" "1" "$rc"
	expect_has "(20a4) symlink in .git/remotes refusal message" "legacy remote dir" "$out"
	command rm -f "$G20/.git/remotes/lnk"
	command rm -rf "$G20/.git/branches"
	ln -s "$T/outside-branches" "$G20/.git/branches"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$G20") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(20a4) symlinked .git/branches refused rc" "1" "$rc"
	expect_has "(20a4) symlinked .git/branches refusal message" "legacy remote dir" "$out"
	command rm -rf "$T/outside-remote" "$T/outside-branches"
	command rm -rf "$G20"
	# (20a5) remote groups (Checker attempt 17): every word of a remotes.<group> value is a
	# remote name `git fetch <group>` / `git remote update [<group>]` resolves (./backup when
	# no such remote), and a group with fewer than 2 members makes `git fetch <group>` use
	# the group name itself. The attacker's repo planted there is fetched by host git.
	# M15: group members / names not collected; M16: a 1-member group name treated as expanded.
	MUT15="$T/pa-sandbox.mut-groups"
	sed -e 's/^\(\t*\)rn\[\$w\]="\${rn\[\$w\]:-3}"$/\1:/' -e 's/^\(\t*\)rn\[\$n\]="\${rn\[\$n\]:-3}"$/\1:/' "$PA_SANDBOX" >"$MUT15"
	! grep -q ':-3}"$' "$MUT15" && grep -q 'rn\[\$w\]="\${rn\[\$w\]:-3}"' "$PA_SANDBOX" && ok "M15 mutation applied" || bad "M15 mutation applied"
	MUT16="$T/pa-sandbox.mut-grpcount"
	sed 's/\[\[ \$gm -ge 2 \]\] && continue/[[ $gm -ge 1 ]] \&\& continue/' "$PA_SANDBOX" >"$MUT16"
	grep -q '\[\[ \$gm -ge 1 \]\] && continue' "$MUT16" && ok "M16 mutation applied" || bad "M16 mutation applied"
	git init -q --bare "$T/origin-g.git"
	atk_repo() { printf "git init -q %s && git -C %s -c user.name=a -c user.email=a@b -c commit.gpgsign=false commit -q --allow-empty -m ATTACKER-G" "$1" "$1"; }
	got_atk() { printf "%s; cut -f1 '%s/.git/FETCH_HEAD' | xargs git -C '%s' log --no-walk --format=%%s | grep -q ATTACKER-G && touch '%s'" "$1" "$2" "$2" "$T/PWNED-g5"; }
	for md in two one-update one-fetch default tabs multi; do
		mkrepo "$G20"
		git -C "$G20" -c commit.gpgsign=false commit -q --allow-empty -m i
		git -C "$G20" remote add origin "$T/origin-g.git"
		gmut="$MUT15" dir=backup hc="git -C '$G20' fetch -q grp" msg="remote name 'backup'"
		case "$md" in
		two) git -C "$G20" config remotes.grp "origin backup" ;;
		one-update)
			git -C "$G20" config remotes.grp backup
			hc="git -C '$G20' remote update grp" msg="(host git uses it as a path)"
			;;
		one-fetch)
			git -C "$G20" config remotes.grp origin
			gmut="$MUT16" dir=grp msg="remote name 'grp'"
			;;
		default)
			git -C "$G20" config remotes.default "backup"
			hc="git -C '$G20' remote update" msg="(host git uses it as a path)"
			;;
		tabs) git -C "$G20" config remotes.grp "$(printf 'origin\n\tbackup')" ;;
		multi)
			git -C "$G20" config --add remotes.grp origin
			git -C "$G20" config --add remotes.grp backup
			;;
		esac
		mut_case "(20a5) remote group: $md" "$G20" "$gmut" "$(atk_repo "$dir")" \
			"$(got_atk "$hc" "$G20")" "$T/PWNED-g5" "$msg"
		command rm -rf "$G20" "$T/PWNED-g5"
	done
	# the group is only in an includeIf whose condition is false now: host git sees no member,
	# so `git fetch grp` uses ./grp (the union still protects the member names)
	mkrepo "$G20"
	git -C "$G20" remote add origin https://example.invalid/x.git
	git -C "$G20" config remote.up.url https://example.invalid/y.git
	git -C "$G20" config --file "$G20/.git/grp.inc" remotes.grp "origin up"
	git -C "$G20" config 'includeIf.gitdir:/nonexistent/.path' grp.inc
	out="$( (HOME="$FH" pa_sandbox_build_argv "$G20") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(20a5) group only in an inactive includeIf: name refused rc" "1" "$rc"
	expect_has "(20a5) group only in an inactive includeIf: refusal message" "remote name 'grp'" "$out"
	command rm -rf "$G20"
	# legitimate: groups of https remotes only (named, default, nested group of 2+) build
	mkrepo "$G20"
	git -C "$G20" remote add origin https://example.invalid/x.git
	git -C "$G20" config remote.up.url https://example.invalid/y.git
	git -C "$G20" config remotes.all "origin up"
	git -C "$G20" config remotes.default "origin	up"
	git -C "$G20" config remotes.outer "all origin"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$G20") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(20a5) groups of https remotes build rc" "0" "$rc"
	expect_lacks "(20a5) groups of https remotes: nothing read-only" "read-only inside" "$out"
	command rm -rf "$G20" "$T/origin-g.git"
	# (20a3) `sh origin/x` is an interpreter argument even when origin is a real remote (the
	# remote-tracking exemption is for git's own words). M13: the exemption applies.
	MUT13="$T/pa-sandbox.mut-remref"
	sed 's/\[\[ "\$2" != i && "\$rel" == \*\/\* && -n "\${rem/[[ "$rel" == *\/* \&\& -n "${rem/' "$PA_SANDBOX" >"$MUT13"
	! grep -q '"\$2" != i && "\$rel"' "$MUT13" && ok "M13 mutation applied" || bad "M13 mutation applied"
	mkrepo "$G20"
	git -C "$G20" config remote.origin.url https://example.invalid/x.git
	git -C "$G20" config alias.rr '!sh origin/run.sh'
	mut_case "(20a3) alias.rr = !sh origin/run.sh with a real origin remote" "$G20" "$MUT13" \
		"mkdir -p origin && printf 'touch $T/PWNED-r20\n' > origin/run.sh" \
		"git -C '$G20' rr" "$T/PWNED-r20" "origin/run.sh"
	command rm -rf "$G20" "$T/PWNED-r20"
	# (20b) item 2: an EXISTING path value whose name contains , or = ; a missing one refuses.
	# M8: neither the whole value nor the word with its = , kept is a candidate.
	MUT8="$T/pa-sandbox.mut-whole"
	sed -e 's|_wx "\$t" && wl+=("w:\$wx")|:|' -e 's#\[\[ "\$p" == "\$t" \]\] || _wadd "\$p" e#:#' "$PA_SANDBOX" >"$MUT8"
	! grep -q 'wl+=("w:' "$MUT8" && ! grep -q '_wadd "\$p" e' "$MUT8" && ok "M8 mutation applied" || bad "M8 mutation applied"
	ssh-keygen -q -t ed25519 -N '' -f "$T/atk20" -C atk
	ssh-keygen -q -t ed25519 -N '' -f "$T/own20" -C own
	sv="git -c user.signingkey='$T/atk20' commit -q -S --allow-empty -m s && [ \"\$(git log -1 --format=%G?)\" = G ]"
	for sf in 'signers,v2' 'signers=v2'; do
		C20="$FH/work/signers-sep"
		mkrepo "$C20"
		git -C "$C20" config gpg.format ssh
		git -C "$C20" config gpg.ssh.allowedSignersFile "$sf"
		echo "t@example.invalid $(cat "$T/own20.pub")" >"$C20/$sf"
		mut_host "(20b) existing allowedSignersFile '$sf'" "$C20" "$MUT8" \
			"echo 't@example.invalid $(cat "$T/atk20.pub")' >> '$sf'" \
			"cd '$C20' && $sv && touch '$T/PWNED-c20'" "$T/PWNED-c20"
		command rm -f "$C20/$sf"
		out="$( (HOME="$FH" pa_sandbox_build_argv "$C20") 2>&1 )" && rc=0 || rc=$?
		expect_eq "(20b) missing one-word allowedSignersFile '$sf' refused rc" "1" "$rc"
		command rm -rf "$C20"
	done
	# (20c) item 3: an attached option value (ssh -Fsshconf, existing). M9: no -Xvalue candidate.
	MUT9="$T/pa-sandbox.mut-optval"
	sed 's|\[\[ "\$w" =~ ^-\[A-Za-z0-9\]\[^=\] \]\] && _wx|false \&\& _wx|' "$PA_SANDBOX" >"$MUT9"
	grep -q 'false && _wx "\${w:2}"' "$MUT9" && ok "M9 mutation applied" || bad "M9 mutation applied"
	F20="$FH/work/ssh-attached"
	mkrepo "$F20"
	printf 'Host *\n  User git\n' >"$F20/sshconf"
	git -C "$F20" config core.sshCommand 'ssh -Fsshconf'
	git -C "$F20" remote add origin ssh://pa.invalid/x.git
	mut_host "(20c) core.sshCommand = ssh -Fsshconf (existing)" "$F20" "$MUT9" \
		"printf 'Host *\n  ProxyCommand sh -c \"touch $T/PWNED-f20; exit 1\"\n' > sshconf" \
		"cd '$F20' && HOME='$FH' timeout 20 git fetch -q" "$T/PWNED-f20"
	command rm -rf "$F20"
	# (20d) the option / key-id exemption does not apply to path-type keys. M10: it does.
	MUT10="$T/pa-sandbox.mut-hexpath"
	sed 's/^\t\tgc.repackfilterto | \*file | \*path | \*dir | \*.ssl\* | \*.template) return 1 ;;$/\t\tgc.repackfilterto) return 1 ;;/' "$PA_SANDBOX" >"$MUT10"
	! grep -q '\*.template) return 1' "$MUT10" && ok "M10 mutation applied" || bad "M10 mutation applied"
	X20="$FH/work/hex-signers"
	mkrepo "$X20"
	git -C "$X20" config gpg.format ssh
	git -C "$X20" config gpg.ssh.allowedSignersFile deadbeef
	mut_case "(20d) gpg.ssh.allowedSignersFile = deadbeef" "$X20" "$MUT10" \
		"echo 't@example.invalid $(cat "$T/atk20.pub")' > deadbeef" \
		"cd '$X20' && $sv && touch '$T/PWNED-x20'" "$T/PWNED-x20" "does not exist and sits directly under"
	command rm -f "$T/PWNED-x20"
	# (20e) git-config(1) `:(optional)path`. M11: the prefix is not dropped.
	MUT11="$T/pa-sandbox.mut-optional"
	sed 's|t="\${t#:(optional)}"|:|' "$PA_SANDBOX" >"$MUT11"
	! grep -q '#:(optional)' "$MUT11" && ok "M11 mutation applied" || bad "M11 mutation applied"
	git -C "$X20" config gpg.ssh.allowedSignersFile ':(optional)signers'
	mut_case "(20e) gpg.ssh.allowedSignersFile = :(optional)signers" "$X20" "$MUT11" \
		"echo 't@example.invalid $(cat "$T/atk20.pub")' > signers" \
		"cd '$X20' && $sv && touch '$T/PWNED-o20'" "$T/PWNED-o20" "does not exist and sits directly under"
	command rm -rf "$X20" "$T/PWNED-o20"
	# (20f) url.<base>.insteadOf with a relative base (the path is in the KEY).
	# M12: the base is not checked.
	MUT12="$T/pa-sandbox.mut-insteadof"
	sed "${m14[@]}" -e 's/\[\[ -z "\$n" || (/[[ 1 || (/' "$PA_SANDBOX" >"$MUT12"
	grep -q '\[\[ 1 || (' "$MUT12" && ! grep -q "URL of remote '\$n'" "$MUT12" && ok "M12 mutation applied" || bad "M12 mutation applied"
	U20="$FH/work/insteadof"
	mkrepo "$U20"
	git -C "$U20" symbolic-ref HEAD refs/heads/main
	git -C "$U20" -c commit.gpgsign=false commit -q --allow-empty -m i
	git -C "$U20" config remote.origin.url https://pa.invalid/x
	git -C "$U20" config url.backup.insteadOf https://pa.invalid/
	mut_case "(20f) url.backup.insteadOf (relative base)" "$U20" "$MUT12" \
		"MK=$T/PWNED-u20; git init -q --bare backupx && $hook backupx/hooks/pre-receive && chmod +x backupx/hooks/pre-receive" \
		"git -C '$U20' push -q origin main" "$T/PWNED-u20" "url.<base>.insteadOf"
	command rm -rf "$U20/backupx" "$T/PWNED-u20"
	git -C "$U20" config --unset url.backup.insteadOf
	git -C "$U20" config url./srv/pa-mirror/.insteadOf https://pa.invalid/
	git -C "$U20" config url.git@example.invalid:.insteadOf https://example.invalid/
	out="$( (HOME="$FH" pa_sandbox_build_argv "$U20") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(20f) absolute outside base / URL base build rc" "0" "$rc"
	git -C "$U20" config "url.$T/.insteadOf" https://pa.invalid/y
	out="$( (HOME="$FH" pa_sandbox_build_argv "$U20") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(20f) base that is a prefix of the workspace refused rc" "1" "$rc"
	command rm -rf "$U20"
	# (20g) Checker attempt 33: an absolute insteadOf / pushInsteadOf base whose `..` leaves a
	# writable workspace directory (<ws>/sub/../../b/ normalises to outside the workspace, but
	# inside, sub can become a symlink and the base then names <ws>/b). No remote uses the
	# rewritten prefix: the host types `foo:bar` itself. M19: the base's `..` hops are not queued.
	MUT19="$T/pa-sandbox.mut-insteadof-dots"
	sed "s/for d in \"\\\${wdot\\[@\\]}\"; do gdot+=(\"\\\$d\"\\\$'\\\\t'\"\\\$k in the config of/: # MUTATION &/" "$PA_SANDBOX" >"$MUT19"
	grep -q ': # MUTATION for d in' "$MUT19" && ok "M19 mutation applied" || bad "M19 mutation applied"
	V20="$FH/work/insteadof-dots"
	mkrepo "$V20"
	git -C "$V20" symbolic-ref HEAD refs/heads/main
	git -C "$V20" -c commit.gpgsign=false commit -q --allow-empty -m i
	mkdir -p "$V20/sub"
	vatk="MK=$T/PWNED-v20; rmdir sub && mkdir -p evil/x && ln -s evil/x sub && git init -q --bare b/bar && $hook b/bar/hooks/pre-receive && chmod +x b/bar/hooks/pre-receive"
	vmsg="goes through '$V20/sub', which the sandbox can write"
	git -C "$V20" config "url.$V20/sub/../../b/.insteadOf" foo:
	mut_case "(20g) url.<ws>/sub/../../b/.insteadOf" "$V20" "$MUT19" "$vatk" \
		"git -C '$V20' push -q foo:bar HEAD:refs/heads/x" "$T/PWNED-v20" "$vmsg"
	git -C "$V20" config --unset "url.$V20/sub/../../b/.insteadOf"
	git -C "$V20" config "url.$V20/sub/../../b/.pushInsteadOf" foo:
	mut_case "(20g) url.<ws>/sub/../../b/.pushInsteadOf" "$V20" "$MUT19" "$vatk" \
		"git -C '$V20' push -q foo:bar HEAD:refs/heads/x" "$T/PWNED-v20" "$vmsg"
	git -C "$V20" config --unset "url.$V20/sub/../../b/.pushInsteadOf"
	git -C "$V20" config "url.file://$V20/sub/../../b/.insteadOf" foo:
	mut_case "(20g) url.file://<ws>/sub/../../b/.insteadOf" "$V20" "$MUT19" "$vatk" \
		"git -C '$V20' push -q foo:bar HEAD:refs/heads/x" "$T/PWNED-v20" "$vmsg"
	git -C "$V20" config --unset "url.file://$V20/sub/../../b/.insteadOf"
	# several `..`: sub/x is the first writable directory left
	mkdir -p "$V20/sub/x"
	git -C "$V20" config "url.$V20/sub/x/../../../b/.insteadOf" foo:
	mut_case "(20g) url.<ws>/sub/x/../../../b/.insteadOf" "$V20" "$MUT19" \
		"MK=$T/PWNED-v20; command rm -r sub && mkdir -p evil/p/q/x && ln -s evil/p/q sub && git init -q --bare evil/b/bar && $hook evil/b/bar/hooks/pre-receive && chmod +x evil/b/bar/hooks/pre-receive" \
		"git -C '$V20' push -q foo:bar HEAD:refs/heads/x" "$T/PWNED-v20" "goes through '$V20/sub/x', which the sandbox can write"
	git -C "$V20" config --unset "url.$V20/sub/x/../../../b/.insteadOf"
	# legitimate: `..` only outside the workspace, or leaving a protected (ro) directory
	git -C "$V20" config "url.$FH/work/nowhere/../b/.insteadOf" foo:
	git -C "$V20" config "url.file://$FH/work/nowhere/../b/.pushInsteadOf" foo:
	git -C "$V20" config "url.$V20/.git/../../b/.insteadOf" bar:
	out="$( (HOME="$FH" pa_sandbox_build_argv "$V20") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(20g) insteadOf bases with \`..\` outside the workspace / leaving .git build rc" "0" "$rc"
	command rm -rf "$V20"
	# (20h) survey of the same branch: an EMPTY base leaves the typed suffix, a path relative to
	# the current directory (M20: an empty base is skipped); an absolute base with `a..b` in a
	# component is a local path too (M21: the old revision-range exclusion of _wx skips it)
	MUT20="$T/pa-sandbox.mut-insteadof-empty"
	sed 's/if \[\[ -z "\$t" \]\] || _rurl "\$t"; then/if _rurl "$t"; then/' "$PA_SANDBOX" >"$MUT20"
	grep -q '^				if _rurl "\$t"; then$' "$MUT20" && ok "M20 mutation applied" || bad "M20 mutation applied"
	MUT21="$T/pa-sandbox.mut-insteadof-range"
	sed 's/if \[\[ -z "\$t" \]\] || _rurl "\$t"; then/if [[ -z "$t" ]] || _wx "$t"; then/' "$PA_SANDBOX" >"$MUT21"
	grep -q '|| _wx "\$t"; then$' "$MUT21" && ok "M21 mutation applied" || bad "M21 mutation applied"
	V21="$FH/work/insteadof-empty"
	mkrepo "$V21"
	git -C "$V21" symbolic-ref HEAD refs/heads/main
	git -C "$V21" -c commit.gpgsign=false commit -q --allow-empty -m i
	git -C "$V21" config url..insteadOf foo:
	mut_case "(20h) url..insteadOf (empty base)" "$V21" "$MUT20" \
		"MK=$T/PWNED-v21; git init -q --bare bar && $hook bar/hooks/pre-receive && chmod +x bar/hooks/pre-receive" \
		"git -C '$V21' push -q foo:bar HEAD:refs/heads/x" "$T/PWNED-v21" "url.<base>.insteadOf base ''"
	git -C "$V21" config --unset url..insteadOf
	git -C "$V21" config "url.$V21/a..b/.insteadOf" foo:
	mut_case "(20h) url.<ws>/a..b/.insteadOf" "$V21" "$MUT21" \
		"MK=$T/PWNED-v21; git init -q --bare a..b/bar && $hook a..b/bar/hooks/pre-receive && chmod +x a..b/bar/hooks/pre-receive" \
		"git -C '$V21' push -q foo:bar HEAD:refs/heads/x" "$T/PWNED-v21" "url.<base>.insteadOf base '$V21/a..b/'"
	git -C "$V21" config --unset "url.$V21/a..b/.insteadOf"
	git -C "$V21" config url./srv/a..b/.insteadOf foo:
	out="$( (HOME="$FH" pa_sandbox_build_argv "$V21") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(20h) absolute outside base with a..b build rc" "0" "$rc"
	command rm -rf "$V21"
	# (20i) survey: core.worktree was only a base, never walked itself. A nested repo whose
	# core.worktree <ws>/sub/../../<outside> leaves the writable sub/: inside, sub becomes a
	# symlink, the worktree turns into <ws>/outwt and a planted submodule .git file there (the
	# nested index has a gitlink m) makes host `git status` run its fsmonitor. M22: not queued.
	MUT22="$T/pa-sandbox.mut-worktree-dots"
	sed "s/for d in \"\\\${wdot\\[@\\]}\"; do gdot+=(\"\\\$d\"\\\$'\\\\t'\"core.worktree in the config of/: # MUTATION &/" "$PA_SANDBOX" >"$MUT22"
	grep -q ': # MUTATION for d in' "$MUT22" && ok "M22 mutation applied" || bad "M22 mutation applied"
	V22="$FH/work/worktree-dots"
	mkrepo "$V22"
	git -C "$V22" -c commit.gpgsign=false commit -q --allow-empty -m i
	mkdir -p "$V22/sub" "$V22/vendor" "$FH/work/outwt-v22"
	git init -q "$V22/vendor/dep"
	git -C "$V22/vendor/dep" config core.worktree "$V22/sub/../../outwt-v22"
	git -C "$V22/vendor/dep" update-index --add --cacheinfo "160000,$(git -C "$V22" rev-parse HEAD),m"
	mut_case "(20i) core.worktree <ws>/sub/../../outside" "$V22" "$MUT22" \
		"MK=$T/PWNED-v22; rmdir sub && mkdir -p evil/x outwt-v22/m && ln -s evil/x sub && git init -q --bare evilgd && $fsmon evilgd/config && git -C evilgd config core.bare false && printf 'gitdir: %s/evilgd\n' \"\$PWD\" > outwt-v22/m/.git" \
		"git -C '$V22/vendor/dep' status" "$T/PWNED-v22" "core.worktree in the config of '$V22/vendor/dep/.git': '$V22/sub/../../outwt-v22' goes through '$V22/sub'"
	# legitimate: `..` only outside the workspace
	git -C "$V22/vendor/dep" config core.worktree "$FH/work/nowhere/../outwt-v22"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$V22") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(20i) core.worktree with \`..\` outside the workspace build rc" "0" "$rc"
	command rm -rf "$V22" "$FH/work/outwt-v22"

	# interpreter dir and guard tree: the bind is what protects (mutation: rw bind -> writable)
	run_mut_drop "$REPO" "$FH/.data/uv/python/cpy" 'echo X > "$HOME/.data/uv/python/cpy/bin/mut-new"' >/dev/null || true
	[[ -e "$FH/.data/uv/python/cpy/bin/mut-new" ]] && ok "MUTATION: interpreter dir writable when its bind is rw" || bad "MUTATION: interpreter dir writable when its bind is rw"
	command rm -f "$FH/.data/uv/python/cpy/bin/mut-new"
	run_mut_drop "$REPO" "$DOT/agent" 'echo X >> "$HOME/dotfiles/agent/security-rules.json"' >/dev/null || true
	! cmp -s "$DOT/agent/security-rules.json" "$REAL_ROOT/agent/security-rules.json" && ok "MUTATION: guard rules writable when the agent/ bind is rw" || bad "MUTATION: guard rules writable when the agent/ bind is rw"
	command cp "$REAL_ROOT/agent/security-rules.json" "$DOT/agent/security-rules.json"

	# git inside the sandbox ignores system config
	out="$(run_ws "$REPO" 'echo "$GIT_CONFIG_NOSYSTEM"')"
	expect_eq "GIT_CONFIG_NOSYSTEM=1 inside the sandbox" "1" "$(printf '%s' "$out" | tail -n1)"

	# the host mcp catalog + daemon-workers cannot be changed (catalog ro, daemon-workers a
	# sandbox-private tmpfs); telemetry stays writable
	for hp in mcp-service-catalog.v2.json daemon-workers/w1/supervisor-config daemon-workers/new-worker; do
		run_ws "$REPO" "echo ATTACK > \"\$HOME/.prime/agent/$hp\" 2>/dev/null; true" >/dev/null || true
		! grep -q ATTACK "$FH/.prime/agent/$hp" 2>/dev/null && ok "agent $hp cannot be written" || bad "agent $hp cannot be written"
	done
	run_mut_rw 'echo ATTACK > "$HOME/.prime/agent/mcp-service-catalog.v2.json"; echo ATTACK > "$HOME/.prime/agent/daemon-workers/w1/supervisor-config"' >/dev/null
	grep -q ATTACK "$FH/.prime/agent/mcp-service-catalog.v2.json" && grep -q ATTACK "$FH/.prime/agent/daemon-workers/w1/supervisor-config" \
		&& ok "MUTATION (agent dir rw): mcp catalog + daemon-workers writable" || bad "MUTATION (agent dir rw): mcp catalog + daemon-workers writable"
	printf 'TRUSTED\n' >"$FH/.prime/agent/mcp-service-catalog.v2.json"
	printf 'TRUSTED\n' >"$FH/.prime/agent/daemon-workers/w1/supervisor-config"
	command rm -f "$FH/.prime/agent/daemon-workers/new-worker"
	run_ws "$REPO" 'echo t >> "$HOME/.prime/agent/telemetry.jsonl"' >/dev/null
	grep -q '^t$' "$FH/.prime/agent/telemetry.jsonl" && ok "telemetry.jsonl stays writable" || bad "telemetry.jsonl stays writable"

	# global harness memory and cron schedules are NOT writable from inside
	for hp in harness/harness_state.json cron-jobs.json harness/new-state; do
		run_ws "$REPO" "echo ATTACK > \"\$HOME/.prime/agent/$hp\" 2>/dev/null; true" >/dev/null || true
		! grep -q ATTACK "$FH/.prime/agent/$hp" 2>/dev/null && ok "agent $hp cannot be written" || bad "agent $hp cannot be written"
	done
	run_mut_rw 'echo ATTACK > "$HOME/.prime/agent/cron-jobs.json"; mkdir -p "$HOME/.prime/agent/harness"; echo ATTACK > "$HOME/.prime/agent/harness/harness_state.json"' >/dev/null
	grep -q ATTACK "$FH/.prime/agent/cron-jobs.json" && grep -q ATTACK "$FH/.prime/agent/harness/harness_state.json" \
		&& ok "MUTATION (agent dir rw): harness+cron writable" || bad "MUTATION (agent dir rw): harness+cron writable"
	printf '[]\n' >"$FH/.prime/agent/cron-jobs.json"
	printf '{}\n' >"$FH/.prime/agent/harness/harness_state.json"

	# ---- T9b: the prime-agent daemon runs inside. The agent dir is a sandbox-private tmpfs
	# holding every host entry ro-bound at its own path; daemon-workers/ and rlm-ledger/ are
	# empty private tmpfs dirs.
	run_mut_repl() { # <op> <path> <new op> <sh-snippet>: profile with `<op> <path>` turned into `<new op> <path> <path>`
		(
			cd "$REPO"
			export HOME="$FH"
			pa_sandbox_build_argv "$REPO" 2>/dev/null
			local -a mut=()
			local i=0
			while [[ $i -lt ${#PA_BWRAP_ARGV[@]} ]]; do
				if [[ "${PA_BWRAP_ARGV[$i]}" == "$1" && "${PA_BWRAP_ARGV[$((i + 1))]:-}" == "$2" ]]; then
					mut+=("$3" "$2" "$2")
					i=$((i + 2))
					continue
				fi
				mut+=("${PA_BWRAP_ARGV[$i]}")
				i=$((i + 1))
			done
			"${mut[@]}" sh -c "$4"
		) 2>&1
	}
	A9="$FH/.prime/agent"
	mkdir -p "$A9/rlm-ledger"
	printf 'HOSTLEDGER\n' >"$A9/rlm-ledger/host.jsonl"
	alist9() { find "$A9" -mindepth 1 \( -path "$A9/sessions" -o -path "$A9/session-artifacts" -o -path "$A9/session-leases" -o -path "$A9/logs" -o -path "$A9/swarm" \) -prune -o -printf '%P %y\n' | LC_ALL=C sort; }
	sums9() { find -L "$A9" \( -path "$A9/sessions" -o -path "$A9/session-artifacts" -o -path "$A9/session-leases" -o -path "$A9/logs" -o -path "$A9/swarm" \) -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum; }
	tree9="$(alist9)"
	sum9="$(sums9)"
	# (T9b a) what the daemon writes (measured with prime-agent 0.10.0: the mkdir locks
	# settings.json.lock/ auth.json.lock/, the atomic-write temp of the mcp catalog, a new
	# auth.json / catalog when the host has none, daemon-workers/<socket hash>/, rlm-ledger/)
	# works inside
	snip9='A="$HOME/.prime/agent"
mkdir "$A/settings.json.lock" "$A/auth.json.lock" && rmdir "$A/settings.json.lock" "$A/auth.json.lock" && echo LOCKS-OK
mkdir "$A/settings.json.lock" && echo LOCK-LEFT
mkdir -p "$A/daemon-workers/1bd3a68af19a" && echo cfg > "$A/daemon-workers/1bd3a68af19a/supervisor-config" && echo r > "$A/rlm-ledger/x.jsonl" && echo DW-OK
echo "LIST:$(ls -A "$A/daemon-workers" "$A/rlm-ledger" | tr "\n" " ")"
cat "$A/daemon-workers/w1/supervisor-config" "$A/rlm-ledger/host.jsonl" 2>/dev/null | grep -q -e TRUSTED -e HOSTLEDGER && echo HOST-VISIBLE
echo x > "$A/mcp-service-catalog.v2.42-0.tmp" && mkdir "$A/models-new" && echo NEW-OK'
	out="$(run_ws "$REPO" "$snip9")"
	expect_has "(T9b a) mkdir locks settings.json.lock/ auth.json.lock/ work inside" "LOCKS-OK" "$out"
	expect_has "(T9b a) daemon-workers/ and rlm-ledger/ are writable inside" "DW-OK" "$out"
	expect_has "(T9b a) new names (catalog temp, new dir) can be created inside" "NEW-OK" "$out"
	expect_lacks "(T9b a) host daemon-workers/ and rlm-ledger/ entries are hidden inside" "HOST-VISIBLE" "$out"
	expect_lacks "(T9b a) host daemon-workers/w1 not listed inside" "w1" "$out"
	expect_eq "(T9b a) host agent dir tree unchanged (no lock, worker dir, ledger, temp, new name)" "$tree9" "$(alist9)"
	expect_eq "(T9b a) host agent dir file contents unchanged" "$sum9" "$(sums9)"
	# ... and it is gone with the sandbox: a second run starts empty, without the left-over lock
	out="$(run_ws "$REPO" 'A="$HOME/.prime/agent"; echo "N:$(ls -A "$A/daemon-workers" | wc -l):$(ls -A "$A/rlm-ledger" | wc -l)"; test -e "$A/models-new" && echo LEFTOVER; test -e "$A/settings.json.lock" && echo LOCK-LEFTOVER; true')"
	expect_has "(T9b a) private dirs start empty in the next run" "N:0:0" "$out"
	expect_lacks "(T9b a) a new name of one run is gone in the next" "LEFTOVER" "$out"
	# MUTATIONS: the private tmpfs is what keeps the daemon's writes off the host ...
	run_mut_repl --tmpfs "$A9/daemon-workers" --bind 'mkdir -p "$HOME/.prime/agent/daemon-workers/1bd3a68af19a"' >/dev/null || true
	[[ -d "$A9/daemon-workers/1bd3a68af19a" ]] && ok "MUTATION (daemon-workers bound rw): the worker dir reaches the host" || bad "MUTATION (daemon-workers bound rw): the worker dir reaches the host"
	command rm -rf "$A9/daemon-workers/1bd3a68af19a"
	run_mut_rw 'mkdir "$HOME/.prime/agent/settings.json.lock"' >/dev/null || true
	[[ -d "$A9/settings.json.lock" ]] && ok "MUTATION (agent root bound rw): a lock dir reaches the host" || bad "MUTATION (agent root bound rw): a lock dir reaches the host"
	command rm -rf "$A9/settings.json.lock"
	# ... and with the old read-only root (T9) the daemon's lock cannot be taken (EROFS, the
	# daemon then fails closed: "The daemon model allowlist could not be read")
	out="$(run_mut_root --ro-bind 'mkdir "$HOME/.prime/agent/settings.json.lock" 2>&1 || echo LOCK-FAILED')" || true
	expect_has "MUTATION (agent root read-only, as in T9): the settings lock fails" "LOCK-FAILED" "$out"
	# (T9b b) the real files are not writable, removable, renamable or replaceable inside either
	# (each is a read-only mount point); a planted link to them gives no write access
	snip9b='A="$HOME/.prime/agent"
for p in settings.json auth.json models.json AGENTS.md skills/s.md agents/a.md machines/m.json bin/prime-shell-guard.sh mcp-service-catalog.v2.json; do
  (printf "ATTACK\n" >> "$A/$p") 2>/dev/null && echo "WROTE:$p"
  mv "$A/$p" "$A/$p.moved" 2>/dev/null && echo "MOVED:$p"
  rm -f "$A/$p" 2>/dev/null; test -e "$A/$p" || echo "REMOVED:$p"
  ln -sfn /dev/null "$A/$p" 2>/dev/null; test "$(readlink "$A/$p")" = /dev/null && echo "RELINKED:$p"
done
for d in skills agents machines bin kernel-venv; do mv "$A/$d" "$A/$d.moved" 2>/dev/null && echo "MOVED:$d"; done
ln -s settings.json "$A/via-link" && { (printf "ATTACK\n" >> "$A/via-link") 2>/dev/null && echo WROTE:via-link; }
ln -s "$A/auth.json" "$A/auth.json.lock" && { (printf "ATTACK\n" >> "$A/auth.json.lock") 2>/dev/null && echo WROTE:lock-link; }
(printf "ATTACK\n" >> "$A/settings.json") 2>&1 | grep -o -m1 -e "Read-only file system" -e "Device or resource busy"
cat "$A/settings.json" "$A/auth.json" "$A/AGENTS.md" "$A/skills/s.md" "$A/models.json"'
	out="$(run_ws "$REPO" "$snip9b")"
	for w in WROTE: MOVED: REMOVED: RELINKED:; do
		expect_lacks "(T9b b) inside: no real agent-dir file $w" "$w" "$out"
	done
	expect_has "(T9b b) inside: a write to settings.json fails with EROFS" "Read-only file system" "$out"
	expect_has "(T9b b) inside: the real files still read TRUSTED" "$(printf 'TRUSTED\nTRUSTED\nTRUSTED\nTRUSTED\nTRUSTED')" "$out"
	expect_eq "(T9b b) host agent dir tree unchanged" "$tree9" "$(alist9)"
	expect_eq "(T9b b) host agent dir file contents unchanged" "$sum9" "$(sums9)"
	# ---- The agent-dir entry list is taken when the profile is built and used by every later
	# bwrap run of it (two guard probes, the real run). The host daemon creates and removes
	# short-lived entries meanwhile.
	run_ws_with() { # <pa-sandbox copy> <sh-snippet>: profile built by that copy
		(
			cd "$REPO"
			export HOME="$FH"
			# shellcheck source=/dev/null # pa-sandbox or a mutated copy
			source "$1"
			pa_sandbox_build_argv "$REPO" 2>/dev/null
			"${PA_BWRAP_ARGV[@]}" sh -c "$2"
		) 2>&1
	}
	race9() { # <pa-sandbox copy> <sh-snippet>: build, remove race-dir/ race-file on the host, probe the guard, run
		(
			cd "$REPO"
			export HOME="$FH"
			# shellcheck source=/dev/null # pa-sandbox or a mutated copy
			source "$1"
			pa_sandbox_build_argv "$REPO" 2>/dev/null || exit 90
			rmdir "$A9/race-dir"
			command rm -f "$A9/race-file"
			pa_sandbox_verify_guard || {
				r=$?
				printf '%s\n' "${PA_SANDBOX_SETUP_ERR:-}"
				exit $((90 + r))
			}
			"${PA_BWRAP_ARGV[@]}" sh -c "$2"
		) 2>&1
	}
	# (T9b d) an entry listed at build time but removed on the host before bwrap runs is skipped
	# (--ro-bind-try): the launch works, and inside the name is a tmpfs-only one
	mkdir "$A9/race-dir"
	: >"$A9/race-file"
	snipr='A="$HOME/.prime/agent"
test -e "$A/race-dir" || test -e "$A/race-file" || echo ABSENT
mkdir "$A/race-dir" && echo IN >"$A/race-dir/f" && echo IN >"$A/race-file" && echo RECREATED'
	out="$(race9 "$PA_SANDBOX" "$snipr")" && rc=0 || rc=$?
	expect_eq "(T9b d) entry removed after listing: launch rc" "0" "$rc"
	expect_has "(T9b d) entry removed after listing: absent inside" "ABSENT" "$out"
	expect_has "(T9b d) entry removed after listing: its name can be created inside" "RECREATED" "$out"
	[[ ! -e "$A9/race-dir" && ! -e "$A9/race-file" ]] && ok "(T9b d) a name created inside does not reach the host" || bad "(T9b d) a name created inside does not reach the host"
	# MUTATION: with plain --ro-bind per entry bwrap aborts, reported as a bwrap setup error
	MUT9R="$T/pa-sandbox.mut-robind"
	sed 's|--ro-bind-try "\$agent_dir/\$name"|--ro-bind "$agent_dir/$name"|' "$PA_SANDBOX" >"$MUT9R"
	! grep -q 'ro-bind-try "\$agent_dir/\$name"' "$MUT9R" && grep -q 'ro-bind-try "\$agent_dir/\$name"' "$PA_SANDBOX" && ok "(T9b d) mutation applied (per-entry --ro-bind)" || bad "(T9b d) mutation applied (per-entry --ro-bind)"
	mkdir "$A9/race-dir"
	: >"$A9/race-file"
	out="$(race9 "$MUT9R" 'echo RAN')" && rc=0 || rc=$?
	expect_eq "MUTATION (per-entry --ro-bind): entry removed after listing fails the guard probe as a setup error (rc 2)" "92" "$rc"
	expect_has "MUTATION (per-entry --ro-bind): reason says the probe did not run" "the guard probe did not run" "$out"
	expect_has "MUTATION (per-entry --ro-bind): reason carries bwrap's message" "Can't find source path" "$out"
	expect_lacks "MUTATION (per-entry --ro-bind): not blamed on the guard" "guard probe failed" "$out"
	rmdir "$A9/race-dir" 2>/dev/null || true
	command rm -f "$A9/race-file"
	# (T9b d) the host recreating such a name while the sandbox runs is not affected by the
	# sandbox's own entry of that name
	mkdir "$A9/race-dir"
	: >"$A9/race-file"
	command rm -f "$REPO/race9.started" "$REPO/race9.sig"
	race9 "$PA_SANDBOX" 'A="$HOME/.prime/agent"; : > race9.started; i=0
while [ ! -e race9.sig ] && [ $i -lt 400 ]; do sleep 0.05; i=$((i + 1)); done
echo ATTACK >"$A/race-file"; mkdir -p "$A/race-dir" && echo ATTACK >"$A/race-dir/f"; ls -A "$A/race-dir"; echo DONE-INSIDE' >"$T/race9c.out" &
	race9pid=$!
	for _ in $(seq 1 200); do [[ -e "$REPO/race9.started" ]] && break; sleep 0.05; done
	printf 'HOST\n' >"$A9/race-file"
	mkdir "$A9/race-dir"
	printf 'HOST\n' >"$A9/race-dir/f"
	: >"$REPO/race9.sig"
	wait "$race9pid" || true
	expect_has "(T9b d) host recreates a removed name during the run: sandbox wrote its own" "DONE-INSIDE" "$(cat "$T/race9c.out")"
	expect_eq "(T9b d) host recreates a removed name during the run: host copies unchanged" "HOST HOST" "$(cat "$A9/race-file" "$A9/race-dir/f" | tr '\n' ' ' | sed 's/ $//')"
	command rm -rf "$A9/race-dir" "$A9/race-file" "$REPO/race9.started" "$REPO/race9.sig"
	# (T9b e) lock names (*.lock, *.lock.*) the host has are not bound: the sandboxed daemon can take
	# its own private lock; the host's lock entries are not visible inside and stay as they are
	mkdir "$A9/settings.json.lock"
	printf 'HOSTLOCK\n' >"$A9/kernel-venv.bootstrap.lock"
	printf 'HOSTLOCK\n' >"$A9/kernel-venv.bootstrap.lock.candidate-1-x"
	snipl='A="$HOME/.prime/agent"
mkdir "$A/settings.json.lock" && rmdir "$A/settings.json.lock" && echo LOCK-TAKEN
cat "$A/kernel-venv.bootstrap.lock" "$A/kernel-venv.bootstrap.lock.candidate-1-x" 2>/dev/null | grep -q HOSTLOCK && echo HOST-LOCK-VISIBLE
echo mine >"$A/kernel-venv.bootstrap.lock" && echo FILE-LOCK-TAKEN'
	out="$(run_ws "$REPO" "$snipl")"
	expect_has "(T9b e) host's settings.json.lock/ not bound: the sandbox takes its own lock" "LOCK-TAKEN" "$out"
	expect_lacks "(T9b e) host's lock files not visible inside" "HOST-LOCK-VISIBLE" "$out"
	expect_has "(T9b e) host's kernel-venv.bootstrap.lock not bound: a private one can be written" "FILE-LOCK-TAKEN" "$out"
	[[ -d "$A9/settings.json.lock" && "$(cat "$A9/kernel-venv.bootstrap.lock" "$A9/kernel-venv.bootstrap.lock.candidate-1-x")" == $'HOSTLOCK\nHOSTLOCK' ]] && ok "(T9b e) host lock entries unchanged" || bad "(T9b e) host lock entries unchanged"
	# MUTATION: bound read-only like other entries, the host's lock is frozen inside
	MUT9L="$T/pa-sandbox.mut-lockbind"
	sed '/\[\[ "\$name" == \*\.lock || "\$name" == \*\.lock\.\* \]\] && continue/d' "$PA_SANDBOX" >"$MUT9L"
	! grep -q '== \*\.lock\.\* \]\] && continue' "$MUT9L" && grep -q '== \*\.lock\.\* \]\] && continue' "$PA_SANDBOX" && ok "(T9b e) mutation applied (lock names bound)" || bad "(T9b e) mutation applied (lock names bound)"
	out="$(run_ws_with "$MUT9L" "$snipl")" || true
	expect_lacks "MUTATION (lock names bound): the sandbox cannot take the settings lock" "LOCK-TAKEN" "$out"
	expect_has "MUTATION (lock names bound): the host's lock file is visible inside" "HOST-LOCK-VISIBLE" "$out"
	command rm -rf "$A9/settings.json.lock" "$A9/kernel-venv.bootstrap.lock" "$A9/kernel-venv.bootstrap.lock.candidate-1-x"
	# (T9b f) full launches (pa_sandbox_main: build, scrub, guard probes, run) while the host keeps
	# creating and removing a lock dir, a catalog temp file and another short-lived dir
	STUB9="$T/stub9b"
	mkdir -p "$STUB9"
	printf '#!/bin/sh\necho STUB-RAN\n' >"$STUB9/prime-agent"
	chmod +x "$STUB9/prime-agent"
	: >"$T/race9.on"
	(
		while [[ -e "$T/race9.on" ]]; do
			mkdir "$A9/settings.json.lock" "$A9/race-loop-dir" 2>/dev/null || true
			: >"$A9/mcp-service-catalog.v2.json.9.tmp"
			rmdir "$A9/settings.json.lock" "$A9/race-loop-dir" 2>/dev/null || true
			command rm -f "$A9/mcp-service-catalog.v2.json.9.tmp"
		done
	) &
	loop9=$!
	n9=0
	for i9 in $(seq 1 20); do
		out="$( (cd "$REPO"; export HOME="$FH" PATH="$STUB9:$PATH"; pa_sandbox_main) 2>&1 )" && rc=0 || rc=$?
		printf '%s\n' "$out" >>"$T/churn9.out"
		if [[ $rc -eq 0 && "$out" == *STUB-RAN* ]]; then
			n9=$((n9 + 1))
		else
			printf '     launch %s: rc=%s %s\n' "$i9" "$rc" "$(printf '%s' "$out" | tail -n 2)"
		fi
	done
	command rm -f "$T/race9.on"
	wait "$loop9" || true
	rmdir "$A9/settings.json.lock" "$A9/race-loop-dir" 2>/dev/null || true
	command rm -f "$A9/mcp-service-catalog.v2.json.9.tmp"
	expect_eq "(T9b f) 20 launches while the host churns lock/temp entries: all succeed" "20" "$n9"
	# an entry the churn removes while the HOME symlink scan walks it is gone, not unreadable
	expect_lacks "(T9b f) churn: no 'could not be read' warning for vanished entries" "could not be read" "$(cat "$T/churn9.out")"
	command rm -f "$T/churn9.out"
	# a listing error (agent dir not readable) still refuses
	chmod u-r "$A9"
	out="$( (cd "$REPO"; export HOME="$FH"; pa_sandbox_build_argv "$REPO") 2>&1 )" && rc=0 || rc=$?
	chmod u+r "$A9"
	expect_eq "(T9b f) unreadable agent dir: refused" "1" "$rc"
	expect_has "(T9b f) unreadable agent dir: message" "cannot list $A9" "$out"
	# (T9b g) a bwrap setup failure (a bound path vanished between bwrap's check and its mount)
	# is retried with a fresh profile, in a guard probe and in the real run; nothing inside ran
	# before. A bwrap shim makes the chosen invocations fail exactly like that (a missing
	# source path), then passes through.
	BWSHIM="$T/bwshim"
	mkdir -p "$BWSHIM"
	REALBWRAP="$(command -v bwrap)"
	cat >"$BWSHIM/bwrap" <<SHIMEOF
#!/bin/bash
case " \$* " in
*" --info-fd "*) k=main ;;
*" bash -c "*) k=probe ;;
*) exec "$REALBWRAP" "\$@" ;;
esac
n=\$((\$(cat "$T/bw.\$k" 2>/dev/null || echo 0) + 1))
echo "\$n" >"$T/bw.\$k"
if [ "\$n" -le "\$(cat "$T/bw.fail.\$k" 2>/dev/null || echo 0)" ]; then
	if [ "\$k" = main ] && [ -s "$T/bw.mode" ]; then exec "$T/bwfake" "\$(cat "$T/bw.mode")"; fi
	exec "$REALBWRAP" --ro-bind "$T/bw-gone" "$T/bw-gone" "\$@"
fi
if [ "\$k" = main ] && [ -s "$T/bw.prevrun" ]; then
	# what the previous (failed) attempt left when pa-sandbox starts over
	{ [ -e "\$(cat "$T/bw.prevrun")" ] && printf 'RUNDIR-LEFT ' || printf 'RUNDIR-GONE '
	kill -0 "\$(cat "$T/bw.helper")" 2>/dev/null && echo CHILD-ALIVE || echo CHILD-GONE; } >"$T/bw.prevcheck"
fi
exec "$REALBWRAP" "\$@"
SHIMEOF
	chmod +x "$BWSHIM/bwrap"
	# bwfake <mode>: a real run whose bwrap setup fails AFTER the host-side watcher has recorded
	# the child's namespace ids (the case churn hits when bwrap's mount loses its race): a child
	# in its own user+ipc namespace is announced on --info-fd, the watcher records it and
	# releases --block-fd, then the "setup" fails with bwrap's own message, nothing ran inside.
	#   ids: the child is gone by then; ids-alive: it is still alive (the sweep must kill it);
	#   survivor: a host-side respawner keeps entering that namespace for 8 s, so the sweep
	#   cannot empty it (a member stays alive).
	#   zombie:<s>: bwzombie instead announces a child that has exited but is not reaped (no
	#   /proc/<pid>/ns/ipc, /proc/<pid> still there), keeps it so for <s> seconds without
	#   touching --block-fd, then reaps it and fails like bwrap's setup (the exit window a
	#   real setup failure has for about 0.6 ms, made long).
	cat >"$T/bwfake" <<FAKEEOF
#!/bin/bash
run=\$(dirname "\$(readlink /proc/self/fd/4)")
echo "\$run" >"$T/bw.prevrun"
case "\$1" in zombie:*) exec python3 -I "$T/bwzombie" "\${1#zombie:}" "$T" ;; esac
unshare -U --ipc sleep 30 </dev/null >/dev/null 2>&1 3>&- 4>&- 8>&- &
hp=\$!
echo "\$hp" >"$T/bw.helper"
for _ in \$(seq 1 250); do
	[ "\$(readlink /proc/\$hp/ns/user 2>/dev/null)" != "\$(readlink /proc/self/ns/user)" ] && break
	sleep 0.02
done
printf '{\\n    "child-pid": %s\\n}\\n' "\$hp" >&7
exec 7>&-
read -r -N 1 -u 8 _
tr '\\n' ' ' <"\$run/record" >"$T/bw.rec" 2>/dev/null
case "\$1" in
ids) kill -9 "\$hp"; wait "\$hp" 2>/dev/null ;;
survivor)
	(
		exec 5</proc/\$hp/ns/user 6</proc/\$hp/ns/ipc
		end=\$((SECONDS + 8))
		while [ \$SECONDS -lt \$end ]; do
			nsenter --user=/proc/self/fd/5 --ipc=/proc/self/fd/6 --preserve-credentials sleep 1 &
			sleep 0.02
		done
		wait
	) </dev/null >/dev/null 2>&1 3>&- 4>&- 8>&- &
	echo \$! >"$T/bw.respawner"
	;;
esac
echo "bwrap: Can't bind mount /oldroot$T/bw-gone on /newroot$T/bw-gone: No such file or directory" >&2
exit 1
FAKEEOF
	chmod +x "$T/bwfake"
	cat >"$T/bwzombie" <<'ZOMBIEEOF'
import os, sys, time
hold, out = float(sys.argv[1]), sys.argv[2]
pid = os.fork()
if pid == 0:
    os._exit(0)
with open(out + "/bw.helper", "w") as f:
    f.write("%d\n" % pid)
def state():
    with open("/proc/%d/stat" % pid) as f:
        return f.read().rsplit(")", 1)[1].split()[0]
while state() != "Z":
    time.sleep(0.005)
os.write(7, b'{\n    "child-pid": %d\n}\n' % pid)
os.close(7)
time.sleep(hold)
try:
    os.readlink("/proc/%d/ns/ipc" % pid)
    ns = "NS-READABLE"
except OSError:
    ns = "NS-GONE"
with open(out + "/bw.zstate", "w") as f:
    f.write("%s %s\n" % (state(), ns))
os.waitpid(pid, 0)
sys.stderr.write("bwrap: Can't bind mount /oldroot%s/bw-gone on /newroot%s/bw-gone: No such file or directory\n" % (out, out))
sys.exit(1)
ZOMBIEEOF
	printf '#!/bin/sh\necho ran >>"$PWD/stub9g.count"\necho STUB-RAN\nexit 3\n' >"$STUB9/prime-agent"
	main9g() { # <failing probe runs> <failing real runs>
		command rm -f "$T"/bw.probe "$T"/bw.main "$REPO/stub9g.count"
		echo "$1" >"$T/bw.fail.probe"
		echo "$2" >"$T/bw.fail.main"
		out="$( (cd "$REPO"; export HOME="$FH" PATH="$BWSHIM:$STUB9:$PATH"; pa_sandbox_main) 2>&1 )" && rc=0 || rc=$?
		runs9="$(wc -l 2>/dev/null <"$REPO/stub9g.count" || echo 0)"
	}
	main9g 1 0
	expect_eq "(T9b g) setup failure in a guard probe: retried, prime-agent's rc" "3" "$rc"
	expect_eq "(T9b g) setup failure in a guard probe: prime-agent ran once" "1" "$runs9"
	expect_has "(T9b g) setup failure in a guard probe: retry announced" "retrying" "$out"
	main9g 0 1
	expect_eq "(T9b g) setup failure in the real run: retried, prime-agent's rc" "3" "$rc"
	expect_eq "(T9b g) setup failure in the real run: prime-agent ran once" "1" "$runs9"
	expect_has "(T9b g) setup failure in the real run: bwrap's message shown" "Can't find source path $T/bw-gone" "$out"
	expect_eq "(T9b g) setup failure in the real run: 2 real runs" "2" "$(cat "$T/bw.main")"
	main9g 0 9
	expect_eq "(T9b g) setup failing every time: rc after 3 launches" "1" "$rc"
	expect_eq "(T9b g) setup failing every time: 3 real runs, prime-agent never ran" "3 0" "$(cat "$T/bw.main") $runs9"
	main9g 9 0
	expect_eq "(T9b g) probe setup failing every time: rc" "1" "$rc"
	expect_has "(T9b g) probe setup failing every time: message" "cannot start the sandbox (bwrap rc=1; the guard probe did not run" "$out"
	expect_lacks "(T9b g) probe setup failing every time: not blamed on the guard" "guard probe failed" "$out"
	# prime-agent itself failing with bwrap-like stderr is NOT retried (it ran: the shim marked it)
	printf '#!/bin/sh\necho ran >>"$PWD/stub9g.count"\necho "bwrap: Can'"'"'t find source path /x" >&2\nexit 1\n' >"$STUB9/prime-agent"
	main9g 0 0
	expect_eq "(T9b g) prime-agent printing a bwrap-like error: not retried" "1 1" "$rc $runs9"
	expect_lacks "(T9b g) prime-agent printing a bwrap-like error: no retry announced" "retrying" "$out"
	# (T9b g) the setup failure of the real run comes AFTER the watcher recorded the child's
	# namespace ids (bwfake above): those ids are swept, and only a clean sweep starts over
	printf '#!/bin/sh\necho ran >>"$PWD/stub9g.count"\necho STUB-RAN\nexit 3\n' >"$STUB9/prime-agent"
	main9k() { # <pa-sandbox copy> <bwfake mode> <failing real runs>
		command rm -f "$T"/bw.probe "$T"/bw.main "$T"/bw.prevrun "$T"/bw.prevcheck "$T"/bw.helper "$T"/bw.rec "$T"/bw.respawner "$T"/bw.zstate "$REPO/stub9g.count"
		echo 0 >"$T/bw.fail.probe"
		echo "$3" >"$T/bw.fail.main"
		echo "$2" >"$T/bw.mode"
		out="$( (cd "$REPO"; export HOME="$FH" PATH="$BWSHIM:$STUB9:$PATH"
			# shellcheck source=/dev/null # pa-sandbox or a mutated copy
			source "$1"; pa_sandbox_main) 2>&1 )" && rc=0 || rc=$?
		runs9="$(wc -l 2>/dev/null <"$REPO/stub9g.count" || echo 0)"
		bwmain9="$(cat "$T/bw.main" 2>/dev/null || echo 0)"
	}
	recre9='^ipc:\[[0-9]+\] user:\[[0-9]+\] $'
	main9k "$PA_SANDBOX" ids 1
	[[ "$(cat "$T/bw.rec" 2>/dev/null)" =~ $recre9 ]] && ok "(T9b g) ids recorded, then setup failure: the watcher had recorded valid ids" || bad "(T9b g) ids recorded, then setup failure: the watcher had recorded valid ids" "$(cat "$T/bw.rec" 2>/dev/null)"
	expect_eq "(T9b g) ids recorded, then setup failure: swept and retried, prime-agent ran once, its rc, 2 real runs" "3 1 2" "$rc $runs9 $bwmain9"
	expect_has "(T9b g) ids recorded, then setup failure: retry announced" "retrying" "$out"
	expect_has "(T9b g) ids recorded, then setup failure: bwrap's message shown" "Can't bind mount /oldroot$T/bw-gone" "$out"
	expect_eq "(T9b g) ids recorded, then setup failure: before the retry the previous run dir and child are gone" "RUNDIR-GONE CHILD-GONE" "$(cat "$T/bw.prevcheck" 2>/dev/null)"
	main9k "$PA_SANDBOX" ids-alive 1
	expect_eq "(T9b g) ids recorded, child still alive: swept and retried, prime-agent ran once, its rc, 2 real runs" "3 1 2" "$rc $runs9 $bwmain9"
	expect_eq "(T9b g) ids recorded, child still alive: the sweep killed it before the retry" "RUNDIR-GONE CHILD-GONE" "$(cat "$T/bw.prevcheck" 2>/dev/null)"
	main9k "$PA_SANDBOX" ids 9
	expect_eq "(T9b g) ids recorded, setup failing every time: rc after 3 launches, prime-agent never ran" "1 0 3" "$rc $runs9 $bwmain9"
	main9k "$PA_SANDBOX" survivor 1
	expect_eq "(T9b g) ids recorded, a member survives the sweep: rc 70, no retry, prime-agent never ran" "70 0 1" "$rc $runs9 $bwmain9"
	expect_lacks "(T9b g) ids recorded, a member survives the sweep: no retry announced" "retrying" "$out"
	expect_has "(T9b g) ids recorded, a member survives the sweep: reported" "still alive in the sandbox" "$out"
	rsp9="$(cat "$T/bw.respawner" 2>/dev/null || true)"
	for _ in $(seq 1 200); do [[ -n "$rsp9" ]] && kill -0 "$rsp9" 2>/dev/null || break; sleep 0.1; done
	read -ra rec9 <<<"$(cat "$T/bw.rec" 2>/dev/null)"
	for _ in $(seq 1 60); do [[ -z "$(pa_sandbox_members "${rec9[0]:-x}" "${rec9[1]:-x}")" ]] && break; sleep 0.1; done
	expect_eq "(T9b g) survivor case: no member left after the respawner stopped" "" "$(pa_sandbox_members "${rec9[0]:-x}" "${rec9[1]:-x}")"
	# (T9b g) the watcher reads the child while it is exiting (exited, not reaped yet): it waits
	# for the reap before releasing --block-fd, records `exited`, and the launch is retried
	main9k "$PA_SANDBOX" zombie:2 1
	expect_eq "(T9b g) child exiting when read: it was a zombie for the whole hold" "Z NS-GONE" "$(cat "$T/bw.zstate" 2>/dev/null)"
	expect_eq "(T9b g) child exiting when read: waited, retried, prime-agent ran once, its rc, 2 real runs" "3 1 2" "$rc $runs9 $bwmain9"
	expect_has "(T9b g) child exiting when read: retry announced" "retrying" "$out"
	expect_lacks "(T9b g) child exiting when read: no identity warning" "was not recorded" "$out"
	expect_eq "(T9b g) child exiting when read: before the retry the previous run dir and child are gone" "RUNDIR-GONE CHILD-GONE" "$(cat "$T/bw.prevcheck" 2>/dev/null)"
	# not reaped within the watcher's bound (250 polls, >= 5 s): nothing recorded, rc 70, no retry
	main9k "$PA_SANDBOX" zombie:15 1
	expect_eq "(T9b g) child unreaped past the watcher's bound: it was a zombie for the whole hold" "Z NS-GONE" "$(cat "$T/bw.zstate" 2>/dev/null)"
	expect_eq "(T9b g) child unreaped past the watcher's bound: rc 70, no retry, prime-agent never ran" "70 0 1" "$rc $runs9 $bwmain9"
	expect_has "(T9b g) child unreaped past the watcher's bound: reported" "was not recorded" "$out"
	expect_lacks "(T9b g) child unreaped past the watcher's bound: no retry announced" "retrying" "$out"
	# MUTATION: no wait for the reap (attempt 4's code): rc 70, no retry
	MUT9W="$T/pa-sandbox.mut-nowait"
	sed 's|for ((i = 0; i < 250; i++)); do # exit wait|for ((i = 0; i < 1; i++)); do # MUTATION exit wait|' "$PA_SANDBOX" >"$MUT9W"
	grep -q 'i < 1; i++)); do # MUTATION exit wait' "$MUT9W" && ! grep -q 'i < 250' "$MUT9W" && ok "(T9b g) mutation applied (no wait for the reap)" || bad "(T9b g) mutation applied (no wait for the reap)"
	main9k "$MUT9W" zombie:2 1
	expect_eq "MUTATION (no wait for the reap): rc 70, no retry, prime-agent never ran, 1 real run" "70 0 1" "$rc $runs9 $bwmain9"
	expect_lacks "MUTATION (no wait for the reap): no retry announced" "retrying" "$out"
	expect_has "MUTATION (no wait for the reap): reported" "was not recorded" "$out"
	command rm -f "$MUT9W"
	# MUTATION: the ids-recorded case not treated as a setup failure (attempt 3's code): rc 1, no retry
	MUT9N="$T/pa-sandbox.mut-noidsretry"
	sed 's|^\t\t\t\tsetupfail=2 # ids recorded.*|\t\t\t\t: # MUTATION|' "$PA_SANDBOX" >"$MUT9N"
	grep -q ': # MUTATION' "$MUT9N" && ! grep -q 'setupfail=2' "$MUT9N" && ok "(T9b g) mutation applied (no retry when ids were recorded)" || bad "(T9b g) mutation applied (no retry when ids were recorded)"
	main9k "$MUT9N" ids 1
	expect_eq "MUTATION (no retry when ids were recorded): rc 1, prime-agent never ran, 1 real run" "1 0 1" "$rc $runs9 $bwmain9"
	expect_lacks "MUTATION (no retry when ids were recorded): no retry announced" "retrying" "$out"
	command rm -f "$MUT9N" "$T"/bw.mode "$T"/bw.prevrun "$T"/bw.prevcheck "$T"/bw.helper "$T"/bw.rec "$T"/bw.respawner "$T"/bw.zstate "$T"/bwzombie
	# (T9b g) PA_SANDBOX_PASS_ENV=TMPDIR passes /tmp (usable inside), never pa-sandbox's private
	# temp dir (absent inside); a caller's other TMPDIR is reported, not passed
	printf '#!/bin/sh\necho "TD=[$TMPDIR]"\nf=$(mktemp) && echo MKTEMP-OK && rm -f "$f"\n' >"$STUB9/prime-agent"
	mkdir -p "$REPO/.t9td"
	main9td() { # <pa-sandbox copy> <PA_SANDBOX_PASS_ENV>
		out="$( (cd "$REPO"; export HOME="$FH" PATH="$STUB9:$PATH" TMPDIR="$REPO/.t9td" PA_SANDBOX_PASS_ENV="$2"
			# shellcheck source=/dev/null # pa-sandbox or a mutated copy
			source "$1"; pa_sandbox_main) 2>&1 )" && rc=0 || rc=$?
	}
	main9td "$PA_SANDBOX" "TERM TMPDIR"
	expect_eq "(T9b g) PASS_ENV=TMPDIR: rc" "0" "$rc"
	expect_has "(T9b g) PASS_ENV=TMPDIR: TMPDIR is /tmp inside" "TD=[/tmp]" "$out"
	expect_has "(T9b g) PASS_ENV=TMPDIR: mktemp works inside" "MKTEMP-OK" "$out"
	expect_has "(T9b g) PASS_ENV=TMPDIR: the caller's TMPDIR is reported as not passed" "TMPDIR is /tmp inside the sandbox (its own tmpfs), not '$REPO/.t9td'" "$out"
	main9td "$PA_SANDBOX" ""
	expect_has "(T9b g) no PASS_ENV: TMPDIR unset inside" "TD=[]" "$out"
	expect_lacks "(T9b g) no PASS_ENV: no TMPDIR warning" "TMPDIR is /tmp inside" "$out"
	MUT9D="$T/pa-sandbox.mut-passtmpdir"
	grep -v 'PA_BWRAP_ARGV+=(--setenv TMPDIR /tmp) && continue' "$PA_SANDBOX" >"$MUT9D"
	! grep -q 'setenv TMPDIR /tmp' "$MUT9D" && ok "(T9b g) mutation applied (TMPDIR passed as is)" || bad "(T9b g) mutation applied (TMPDIR passed as is)"
	main9td "$MUT9D" "TERM TMPDIR"
	expect_has "MUTATION (TMPDIR passed as is): the private temp dir's path is passed" "TD=[/tmp/pa-sandbox." "$out"
	expect_lacks "MUTATION (TMPDIR passed as is): mktemp fails inside" "MKTEMP-OK" "$out"
	command rm -rf "$MUT9D" "$REPO/.t9td"
	# (T9b h) PRIVATE TEMP DIR: the run state pa-sandbox decides on (record, started, bwrap.err,
	# info) never follows $TMPDIR into a path the sandbox can reach. TMPDIR is pointed at the
	# workspace, an rw state dir and a ro-bound extra path; the stub (exit 1) forges a bwrap setup
	# failure in every dir it can reach (started emptied, bwrap.err "bwrap: forged", record
	# `exited`), also through any /proc/<pid>/fd it can open, and must still run only once.
	TD9=("$REPO/.t9h" "$A9/sessions/.t9h" "$T/roex9/t")
	mkstub9h() { # <stub path>
		{
			printf '#!/bin/sh\necho ran >>"$PWD/stub9h.count"\n'
			printf 'for d in "%s" "%s" "%s"; do echo "LS:$d:[$(ls -A "$d" | tr "\\n" " ")]"; done\n' "${TD9[@]}"
			printf 'for d in "%s"/* "%s"/*/* "%s"/* "%s"/*/* "%s"/* "%s"/*/* /tmp /tmp/* /tmp/*/*; do\n' "${TD9[0]}" "${TD9[0]}" "${TD9[1]}" "${TD9[1]}" "${TD9[2]}" "${TD9[2]}"
			printf '  [ -d "$d" ] || continue\n'
			printf '  : >"$d/started" 2>/dev/null; echo "bwrap: forged" >"$d/bwrap.err" 2>/dev/null; echo exited >"$d/record" 2>/dev/null\n'
			printf 'done\n'
			printf 'for f in /proc/[0-9]*/fd/*; do\n'
			printf '  case "$(readlink "$f" 2>/dev/null)" in\n'
			printf '  */started | */bwrap.err | */record | */info | */block) (echo "bwrap: forged" >"$f") 2>/dev/null && echo "FDWRITE:$f" ;;\n'
			printf '  esac\ndone\nexit 1\n'
		} >"$1"
		chmod +x "$1"
	}
	mkstub9h "$STUB9/prime-agent"
	main9h() { # <pa-sandbox copy> <TMPDIR> [RO_EXTRA]
		command rm -rf "$REPO/stub9h.count" "${TD9[@]}"
		mkdir -p "${TD9[@]}"
		out="$( (cd "$REPO"; export HOME="$FH" PATH="$STUB9:$PATH" TMPDIR="$2" PA_SANDBOX_RO_EXTRA="${3:-}"
			# shellcheck source=/dev/null # pa-sandbox or a mutated copy
			source "$1"; pa_sandbox_main) 2>&1 )" && rc=0 || rc=$?
		runs9="$(wc -l 2>/dev/null <"$REPO/stub9h.count" || echo 0)"
	}
	for i9 in 0 1 2; do
		main9h "$PA_SANDBOX" "${TD9[$i9]}" "$T/roex9"
		expect_eq "(T9b h) TMPDIR=${TD9[$i9]}: forged setup failure, prime-agent ran once, its rc" "1 1" "$runs9 $rc"
		expect_lacks "(T9b h) TMPDIR=${TD9[$i9]}: no retry" "retrying" "$out"
		expect_has "(T9b h) TMPDIR=${TD9[$i9]}: no pa-sandbox file there" "LS:${TD9[$i9]}:[]" "$out"
		expect_lacks "(T9b h) TMPDIR=${TD9[$i9]}: no run-state file reachable through /proc/<pid>/fd" "FDWRITE" "$out"
	done
	# MUTATION: run state back under $TMPDIR (and the check gone): the forged setup failure is
	# believed, prime-agent runs 3 times
	MUT9T="$T/pa-sandbox.mut-tmpdir"
	sed -e 's|mktemp -d /tmp/pa-sandbox\.XXXXXXXXXX|mktemp -d|' -e 's@^\t\tpa_sandbox_tmp_hidden "\$PA_SANDBOX_TMP" || return 1$@\t\t: # MUTATION@' "$PA_SANDBOX" >"$MUT9T"
	grep -q ': # MUTATION' "$MUT9T" && ! grep -q 'mktemp -d /tmp/pa-sandbox' "$MUT9T" && ok "(T9b h) mutation applied (run state under \$TMPDIR, no check)" || bad "(T9b h) mutation applied (run state under \$TMPDIR, no check)"
	main9h "$MUT9T" "${TD9[0]}"
	expect_eq "MUTATION (run state under \$TMPDIR=workspace): the sandbox forges a setup failure, prime-agent runs 3 times" "3" "$runs9"
	expect_has "MUTATION (run state under \$TMPDIR=workspace): retry announced" "retrying" "$out"
	# refusal: a profile that would show the private temp dir inside (/tmp or the root bound) refuses
	for ex9 in /tmp /; do
		main9h "$PA_SANDBOX" "${TD9[0]}" "$ex9"
		expect_eq "(T9b h) PA_SANDBOX_RO_EXTRA=$ex9 (private temp dir visible inside): refused rc, prime-agent never ran" "1 0" "$rc $runs9"
		expect_has "(T9b h) PA_SANDBOX_RO_EXTRA=$ex9: message" "private temp dir" "$out"
	done
	# the check on its own: with the private temp dir forced back under $TMPDIR (location
	# mutated, check kept), a TMPDIR the sandbox can reach is refused before anything runs
	MUT9L="$T/pa-sandbox.mut-location"
	sed 's|mktemp -d /tmp/pa-sandbox\.XXXXXXXXXX|mktemp -d|' "$PA_SANDBOX" >"$MUT9L"
	! grep -q 'mktemp -d /tmp/pa-sandbox' "$MUT9L" && ok "(T9b h) mutation applied (private temp dir under \$TMPDIR, check kept)" || bad "(T9b h) mutation applied (private temp dir under \$TMPDIR, check kept)"
	printf '#!/bin/sh\necho ran >>"$PWD/stub9h.count"\nls -d "%s"/*/run.* >/dev/null 2>&1 && echo RUNDIR-VISIBLE\nexit 0\n' "${TD9[2]}" >"$STUB9/prime-agent"
	for i9 in 0 1 2; do
		main9h "$MUT9L" "${TD9[$i9]}" "$T/roex9"
		expect_eq "(T9b h) check: private temp dir under TMPDIR=${TD9[$i9]} refused, prime-agent never ran" "1 0" "$rc $runs9"
		expect_has "(T9b h) check: TMPDIR=${TD9[$i9]}: message" "private temp dir" "$out"
	done
	# MUTATION: location mutated AND the check gone: the run dir is visible inside
	main9h "$MUT9T" "${TD9[2]}" "$T/roex9"
	expect_eq "MUTATION (no visibility check, TMPDIR in a ro-bound path): starts" "0 1" "$rc $runs9"
	expect_has "MUTATION (no visibility check, TMPDIR in a ro-bound path): run dir visible inside" "RUNDIR-VISIBLE" "$out"
	main9h "$PA_SANDBOX" "${TD9[2]}" "$T/roex9"
	expect_eq "(T9b h) TMPDIR in a ro-bound path: starts" "0 1" "$rc $runs9"
	expect_lacks "(T9b h) TMPDIR in a ro-bound path: run dir not visible inside" "RUNDIR-VISIBLE" "$out"
	command rm -f "$MUT9L"
	ls -d /tmp/pa-sandbox.* >/dev/null 2>&1 && bad "(T9b h) no private temp dir left in /tmp" "$(ls -d /tmp/pa-sandbox.*)" || ok "(T9b h) no private temp dir left in /tmp"
	command rm -rf "$REPO/stub9h.count" "${TD9[@]}" "$T/roex9"
	# pa_sandbox_tmp_hidden on hand-made profiles
	ln -s /tmp "$T/tmplink9"
	hid9() { # <label> <want rc> <argv...>
		local l="$1" w="$2" r=0
		shift 2
		PA_BWRAP_ARGV=(bwrap "$@" --)
		pa_sandbox_tmp_hidden /tmp/pa-sandbox.abc >/dev/null 2>&1 || r=$?
		expect_eq "(T9b h) tmp_hidden: $l" "$w" "$r"
	}
	hid9 "root ro + tmpfs /tmp: hidden" 0 --ro-bind / / --tmpfs /tmp --dir /tmp/pa-sandbox --bind /tmp/other /tmp/other
	hid9 "root ro, no tmpfs over it: visible" 1 --ro-bind / /
	hid9 "tmpfs before the root bind: visible" 1 --tmpfs /tmp --ro-bind / /
	hid9 "bind source an ancestor: visible" 1 --ro-bind / / --tmpfs /tmp --bind /tmp /x
	hid9 "bind dest inside: visible" 1 --ro-bind / / --tmpfs /tmp --ro-bind /var /tmp/pa-sandbox.abc/run
	hid9 "bind source a symlink to /tmp: visible" 1 --ro-bind / / --tmpfs /tmp --ro-bind-try "$T/tmplink9" /y
	hid9 "unknown option: refused" 1 --ro-bind / / --tmpfs /tmp --frob x
	command rm -f "$T/tmplink9"
	# (T9b i) a failed sweep is reported (rc 70), also when started is empty and when bwrap
	# reports a setup error, unless the record says nothing started. A host-side bwrap shim
	# tampers with the run dir after the real run (the sandbox itself cannot reach it, T9b h).
	TSHIM9="$T/tshim9"
	mkdir -p "$TSHIM9"
	cat >"$TSHIM9/bwrap" <<SHIMEOF
#!/bin/bash
case " \$* " in
*" --info-fd "*) ;;
*) exec "$REALBWRAP" "\$@" ;;
esac
"$REALBWRAP" "\$@"
rc=\$?
d="\$(dirname "\$(readlink /proc/\$\$/fd/7)")"
case "\$(cat "$T/tshim9.mode")" in
junk) : >"\$d/started"; printf 'junk\njunk\n' >"\$d/record"; exit 0 ;;
junkfail) : >"\$d/started"; printf 'junk\njunk\n' >"\$d/record"; echo "bwrap: forged" >"\$d/bwrap.err"; exit 1 ;;
norecord) : >"\$d/started"; command rm -f "\$d/record"; exit 0 ;;
esac
exit \$rc
SHIMEOF
	chmod +x "$TSHIM9/bwrap"
	printf '#!/bin/sh\necho ran >>"$PWD/stub9h.count"\nexit 0\n' >"$STUB9/prime-agent"
	main9i() { # <pa-sandbox copy> <mode>
		command rm -f "$REPO/stub9h.count"
		echo "$2" >"$T/tshim9.mode"
		out="$( (cd "$REPO"; export HOME="$FH" PATH="$TSHIM9:$STUB9:$PATH"
			# shellcheck source=/dev/null # pa-sandbox or a mutated copy
			source "$1"; pa_sandbox_main) 2>&1 )" && rc=0 || rc=$?
		runs9="$(wc -l 2>/dev/null <"$REPO/stub9h.count" || echo 0)"
	}
	main9i "$PA_SANDBOX" junk
	expect_eq "(T9b i) record unreadable, started empty, exit 0: rc 70" "70" "$rc"
	expect_has "(T9b i) record unreadable: identity warning" "sandbox namespace identity 'junk' 'junk' unusable" "$out"
	expect_has "(T9b i) record unreadable: tainted message" "sandbox processes could not be cleaned up; state may be tainted" "$out"
	main9i "$PA_SANDBOX" junkfail
	expect_eq "(T9b i) record unreadable + bwrap-like setup error: rc 70, no retry, ran once" "70 1" "$rc $runs9"
	expect_lacks "(T9b i) record unreadable + bwrap-like setup error: no retry announced" "retrying" "$out"
	main9i "$PA_SANDBOX" norecord
	expect_eq "(T9b i) record missing although a child was created: rc 70" "70" "$rc"
	expect_has "(T9b i) record missing: message" "sandbox namespace identity was not recorded" "$out"
	main9i "$PA_SANDBOX" none
	expect_eq "(T9b i) untouched run: rc 0, quiet" "0 1" "$rc $runs9"
	expect_lacks "(T9b i) untouched run: no sweep warning" "namespace identity" "$out"
	expect_lacks "(T9b i) untouched run: not reported tainted" "tainted" "$out"
	# MUTATION: the attempt-2 rule (no sweep failure reported while started is empty) hides it
	MUT9S="$T/pa-sandbox.mut-quietsweep"
	sed 's@^\t\tif \[\[ \$setupfail -eq 1 \]\]; then$@\t\tif [[ $setupfail -eq 1 || ! -s "$PA_SANDBOX_RUNDIR/started" ]]; then # MUTATION@' "$PA_SANDBOX" >"$MUT9S"
	grep -q '# MUTATION' "$MUT9S" && ok "(T9b i) mutation applied (sweep skipped when started is empty)" || bad "(T9b i) mutation applied (sweep skipped when started is empty)"
	main9i "$MUT9S" junk
	expect_eq "MUTATION (sweep skipped when started is empty): the unreadable record goes unreported, rc 0" "0" "$rc"
	command rm -rf "$TSHIM9" "$T/tshim9.mode" "$REPO/stub9h.count" "$MUT9T" "$MUT9S"
	command rm -f "$REPO/stub9g.count"
	expect_eq "(T9b d-f) host agent dir tree unchanged" "$tree9" "$(alist9)"
	expect_eq "(T9b d-f) host agent dir file contents unchanged" "$sum9" "$(sums9)"
	command rm -rf "$A9/rlm-ledger"

	# ---- Checker attempt 18, item 1: HOME SYMLINKS. The host runs / reads files that the
	# user's HOME links into the workspace (a dotfiles checkout: ~/.toolrc -> <ws>/toolrc).
	MUTH="$T/pa-sandbox.mut-homelinks"
	sed 's|^\t_hprot() { # <path>.*$|&\n\t\treturn 0|' "$PA_SANDBOX" >"$MUTH"
	grep -A1 '^	_hprot() {' "$MUTH" | grep -q 'return 0' && ok "MH mutation applied" || bad "MH mutation applied"
	HW="$FH/work/home-links"
	mkrepo "$HW"
	git -C "$HW" -c commit.gpgsign=false commit -q --allow-empty -m i
	mkdir -p "$HW/conf.d" "$HW/systemd/user" "$HW/deep/lnk" "$HW/deep/real" "$HW/free" "$T/hl-ext" "$FH/.config/systemd/user"
	printf ': rc\n' >"$HW/toolrc"
	printf ': init\n' >"$HW/conf.d/init.sh"
	printf ': multi\n' >"$HW/deep/real/multi.sh"
	printf ': mid\n' >"$HW/deep/real/mid.sh"
	printf ': evil-target\n' >"$HW/free/evil.sh"
	printf '[Service]\nExecStart=/bin/true\n' >"$HW/systemd/user/pa.service"
	printf 'outside\n' >"$T/hl-ext/outside.txt"
	ln -s ../real/mid.sh "$HW/deep/lnk/mid.sh"           # a symlink INSIDE the workspace on the way
	ln -s "$HW/toolrc" "$FH/.toolrc"                       # file symlink
	ln -s "$HW/conf.d" "$FH/.config/foo"                   # directory symlink
	ln -s "$HW/deep/real/multi.sh" "$T/hl-ext/multi.sh"    # outside symlink ...
	ln -s "$T/hl-ext/multi.sh" "$FH/.multi.sh"             # ... reached from HOME (2 hops)
	ln -s "$HW/deep/lnk/mid.sh" "$FH/.mid.sh"              # through the in-workspace symlink
	ln -s "$HW/systemd/user/pa.service" "$FH/.config/systemd/user/pa.service"
	ln -s "$T/hl-ext/outside.txt" "$FH/.outside.txt"       # outside the workspace: no effect
	hostunit() { sh -c "$(sed -n 's/^ExecStart=//p' "$FH/.config/systemd/user/pa.service")"; }
	mut_host "(H1) ~/.toolrc -> <ws>/toolrc" "$HW" "$MUTH" "echo 'touch $T/PWNED-h1' >> toolrc" \
		"sh '$FH/.toolrc'" "$T/PWNED-h1"
	mut_host "(H2) ~/.config/foo -> <ws>/conf.d (directory)" "$HW" "$MUTH" "echo 'touch $T/PWNED-h2' > conf.d/init.sh" \
		"sh '$FH/.config/foo/init.sh'" "$T/PWNED-h2"
	mut_host "(H3) ~/.multi.sh -> outside symlink -> <ws>/deep/real/multi.sh" "$HW" "$MUTH" "echo 'touch $T/PWNED-h3' > deep/real/multi.sh" \
		"sh '$FH/.multi.sh'" "$T/PWNED-h3"
	mut_host "(H4) ~/.mid.sh -> <ws>/deep/lnk/mid.sh (an in-workspace symlink) re-pointed" "$HW" "$MUTH" \
		"echo 'touch $T/PWNED-h4' > free/evil.sh && ln -sfn ../../free/evil.sh deep/lnk/mid.sh" \
		"sh '$FH/.mid.sh'" "$T/PWNED-h4"
	mut_host "(H5) systemd user unit symlink" "$HW" "$MUTH" \
		"printf '[Service]\\nExecStart=touch $T/PWNED-h5\\n' > systemd/user/pa.service" "hostunit" "$T/PWNED-h5"
	out="$(run_ws "$HW" 'for f in toolrc conf.d/init.sh conf.d/new.sh deep/real/multi.sh systemd/user/pa.service; do echo x >> "$f" || echo "DENIED $f"; done; ln -sfn x deep/lnk/mid.sh || echo "DENIED lnk"' 2>&1)" || true
	for f in toolrc conf.d/init.sh conf.d/new.sh deep/real/multi.sh systemd/user/pa.service lnk; do
		expect_has "(H) real profile: $f not writable" "DENIED $f" "$out"
	done
	expect_has "(H) real profile: refused with EROFS" "Read-only file system" "$out"
	out="$(run_ws "$HW" "echo w >> free/evil.sh && echo w >> '$T/hl-ext/outside.txt'; echo done" 2>&1)" || true
	[[ "$(tail -n1 "$HW/free/evil.sh")" == w ]] && ok "(H) unreferenced workspace file stays writable" || bad "(H) unreferenced workspace file stays writable" "$out"
	grep -q '^w$' "$T/hl-ext/outside.txt" && bad "(H) HOME link outside the workspace: target not exposed rw" || ok "(H) HOME link outside the workspace: target not exposed rw"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$HW"; printf '%s\n' "${PA_BWRAP_ARGV[@]}") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(H) build rc" "0" "$rc"
	expect_lacks "(H) outside target not bound" "$T/hl-ext" "$out"
	expect_has "(H) stderr names the HOME links" "host file(s) reached through HOME" "$out"
	expect_has "(H) stderr example" "$FH/.toolrc -> toolrc" "$out"
	# refusals: a HOME link to the workspace root, to a missing entry directly under it
	ln -s "$HW" "$FH/.whole"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$HW") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(H6) HOME link to the workspace root refused rc" "1" "$rc"
	expect_has "(H6) message" "workspace root itself" "$out"
	command rm -f "$FH/.whole"
	ln -s "$HW/not-yet" "$FH/.notyet"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$HW") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(H7) dangling HOME link directly under the root refused rc" "1" "$rc"
	expect_has "(H7) message" "missing directly under the workspace root" "$out"
	command rm -f "$FH/.notyet"
	ln -s "$HW/free/not-yet.sh" "$FH/.notyet2"
	out="$(run_ws "$HW" 'echo x > free/not-yet.sh || echo DENIED' 2>&1)" || true
	expect_has "(H8) dangling nested HOME link: its top-level dir is ro" "DENIED" "$out"
	[[ ! -e "$HW/free/not-yet.sh" ]] && ok "(H8) dangling target not created" || bad "(H8) dangling target not created"
	command rm -f "$FH/.notyet2"
	out="$( (HOME="$FH" PA_SANDBOX_MAX_HOME_LINKS=2 pa_sandbox_build_argv "$HW") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(H9) too many HOME symlinks refused rc" "1" "$rc"
	expect_has "(H9) message" "PA_SANDBOX_MAX_HOME_LINKS" "$out"
	# bind mount of a workspace file on a HOME path (a container setup): needs a mount ns
	if unshare --user --map-root-user --mount true 2>/dev/null; then
		printf '[core]\n' >"$HW/gitconfig"
		: >"$FH/.gitconfig-bm"
		bmc='mount --bind "$2/gitconfig" "$3/.gitconfig-bm" && source "$1" && HOME="$3" PA_SANDBOX_ALLOW_HOST_PROC=1 pa_sandbox_build_argv "$2" && printf "%s\n" "${PA_BWRAP_ARGV[@]}"'
		out="$(unshare --user --map-root-user --mount "$BASH" -c "$bmc" _ "$PA_SANDBOX" "$HW" "$FH" 2>&1)" && rc=0 || rc=$?
		expect_eq "(H10) bind-mounted HOME file: build rc" "0" "$rc"
		expect_has "(H10) bind mount source in the workspace is ro-bound" "$HW/gitconfig" "$out"
		out="$(unshare --user --map-root-user --mount "$BASH" -c "$bmc" _ "$MUTH" "$HW" "$FH" 2>&1)" || true
		expect_lacks "(H10) MUTATION: bind mount source not ro-bound" "$HW/gitconfig" "$out"
		command rm -f "$HW/gitconfig" "$FH/.gitconfig-bm"
	else
		printf 'note: unshare unavailable; (H10) bind-mount case skipped\n'
	fi
	# ---- Checker attempt 30: a HOME link whose path enters a real workspace directory and leaves
	# it again through `..` (resolved as text). Inside, the directory can be replaced by a symlink,
	# so the host would read a file the sandbox wrote: refused (checked per hop, before `..`).
	MUTD="$T/pa-sandbox.mut-homedot"
	sed 's|^\t_hdot() { # <dir>.*$|&\n\t\treturn 0|' "$PA_SANDBOX" >"$MUTD"
	grep -A1 '^	_hdot() {' "$MUTD" | grep -q 'return 0' && ok "MD mutation applied" || bad "MD mutation applied"
	mkdir -p "$HW/sub/sub2" "$T/hl-ext"
	command rm -rf "$FH/work/c39-out"
	dotatk="rm -rf sub && mkdir -p d1/d2/sub2 c39-out && ln -s d1/d2 sub" # sub/.. is now d1
	dotref() { # <label> <home link name> <link target> <attack sh> <host cmd> <marker>: refused, and with
		# the check removed (mutation) the attack reaches the host
		local lbl="$1" ln="$FH/$2"
		ln -sfn "$3" "$ln"
		out="$( (HOME="$FH" pa_sandbox_build_argv "$HW") 2>&1 )" && rc=0 || rc=$?
		expect_eq "$lbl: refused rc" "1" "$rc"
		expect_has "$lbl: message" "goes through '$HW/sub" "$out"
		expect_has "$lbl: message names the cause" "which the sandbox can write (a directory there could be replaced by a symlink" "$out"
		command cp -a "$HW" "$HW.pristine"
		# shellcheck source=/dev/null # mutated copy of pa-sandbox
		( cd "$HW"; export HOME="$FH"; source "$MUTD"; pa_sandbox_build_argv "$HW" 2>/dev/null && "${PA_BWRAP_ARGV[@]}" sh -c "$dotatk && $4" ) >/dev/null 2>&1 || true
		(eval "$5") >/dev/null 2>&1 || true
		[[ -e "$6" ]] && ok "MUTATION ($lbl, check removed): the host reads the sandbox's file" || bad "MUTATION ($lbl, check removed): the host reads the sandbox's file"
		command rm -rf "$HW" "$6" "$FH/work/c39-out"
		command cp -a "$HW.pristine" "$HW"
		command rm -rf "$HW.pristine"
		command rm -f "$ln"
	}
	dotref "(H11) ~/.toolrc -> <ws>/sub/../../c39-out/x" .toolrc "$HW/sub/../../c39-out/x" \
		"echo 'touch $T/PWNED-h11' > c39-out/x" "sh '$FH/.toolrc'" "$T/PWNED-h11"
	dotref "(H12) ~/.zshrc -> <ws>/sub/../../c39-out/x" .zshrc "$HW/sub/../../c39-out/x" \
		"echo 'touch $T/PWNED-h12' > c39-out/x" "sh '$FH/.zshrc'" "$T/PWNED-h12"
	dotref "(H13) ~/.toolrc -> <ws>/sub/sub2/../../../c39-out/x (several ..)" .toolrc "$HW/sub/sub2/../../../c39-out/x" \
		"echo 'touch $T/PWNED-h13' > c39-out/x" "sh '$FH/.toolrc'" "$T/PWNED-h13"
	ln -sfn "$HW/sub/../../c39-out/x" "$T/hl-ext/hop"
	dotref "(H14) ~/.toolrc -> outside symlink -> <ws>/sub/../../c39-out/x (chain)" .toolrc "$T/hl-ext/hop" \
		"echo 'touch $T/PWNED-h14' > c39-out/x" "sh '$FH/.toolrc'" "$T/PWNED-h14"
	command rm -f "$T/hl-ext/hop"
	dotref "(H15) ~/.cross -> <ws>/sub/../free/evil.sh (target in the workspace, other top-level dir)" .cross "$HW/sub/../free/evil.sh" \
		"mkdir -p d1/free && echo 'touch $T/PWNED-h15' > d1/free/evil.sh" \
		"sh '$FH/.cross'" "$T/PWNED-h15"
	# accepted as before: `..` that stays inside the ro top-level dir of the target, `..` outside the
	# workspace, and a relative in-workspace symlink climbing out (its top-level dir is ro-bound)
	ln -s "$HW/deep/real/../real/mid.sh" "$FH/.same"
	ln -s "$T/hl-ext/../hl-ext/outside.txt" "$FH/.outdot"
	ln -s ../../../../hl-ext-up/x "$HW/deep/lnk/up"
	ln -s "$HW/deep/lnk/up" "$FH/.up"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$HW") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(H16) .. within the target's ro top-level dir / outside the workspace / ro symlink climbing out: build rc" "0" "$rc"
	expect_lacks "(H16) no refusal" "refusing" "$out"
	out="$(run_ws "$HW" 'echo x >> deep/real/mid.sh || echo DENIED-mid; ln -sfn x deep/lnk/up || echo DENIED-up; echo w >> free/evil.sh && echo WROTE-free' 2>&1)" || true
	expect_has "(H16) .. target inside its top-level dir is read-only" "DENIED-mid" "$out"
	expect_has "(H16) climbing in-workspace symlink is read-only" "DENIED-up" "$out"
	expect_has "(H16) unreferenced top-level dir stays writable" "WROTE-free" "$out"
	command rm -f "$FH/.same" "$FH/.outdot" "$FH/.up" "$HW/deep/lnk/up"
	command rm -f "$FH/.toolrc" "$FH/.config/foo" "$FH/.multi.sh" "$FH/.mid.sh" "$FH/.outside.txt" "$FH/.config/systemd/user/pa.service"
	command rm -rf "$HW" "$T/hl-ext"

	# ---- Checker attempt 31: `..` IN GIT PATHS. A git config path (core.hooksPath, include.path, ...)
	# that enters a real workspace directory and leaves it again through `..` is refused like a HOME
	# link (_hdot, shared); with the check removed (MD mutation) host git runs the sandbox's code.
	GD="$FH/work/gitdot"
	GX="$FH/work/gd-ext" # outside the workspace
	mkrepo "$GD"
	git -C "$GD" -c commit.gpgsign=false commit -q --allow-empty -m i
	mkdir -p "$GD/tools" "$GD/hooks" "$GD/sub/x" "$GD/sub/hooks2" "$GD/free"
	printf '#!/bin/sh\nexit 0\n' >"$GD/hooks/pre-commit"
	chmod +x "$GD/hooks/pre-commit"
	printf '[user]\n\tname = t\n' >"$GD/hooks/inc.cfg"
	gdatk="rmdir tools && mkdir -p x/y x/hooks && ln -s x/y tools" # tools/.. is now x
	# (GD1) Repro 1: core.hooksPath = tools/../hooks (relative to the worktree root)
	git -C "$GD" config core.hooksPath tools/../hooks
	mut_case "(GD1) core.hooksPath tools/../hooks" "$GD" "$MUTD" \
		"MK=$T/PWNED-gd1; $gdatk && $hook x/hooks/pre-commit && chmod +x x/hooks/pre-commit" \
		"$(commit_cmd "$GD")" "$T/PWNED-gd1" "goes through '$GD/tools', which the sandbox can write"
	expect_has "(GD1) message names the key" "core.hooksPath in the config of" "$out"
	git -C "$GD" config --unset core.hooksPath
	# (GD2) Repro 2: include.path = <ws>/tools/../hooks/inc.cfg (absolute)
	git -C "$GD" config include.path "$GD/tools/../hooks/inc.cfg"
	mut_case "(GD2) include.path <ws>/tools/../hooks/inc.cfg" "$GD" "$MUTD" \
		"MK=$T/PWNED-gd2; $gdatk && $fsmon x/hooks/inc.cfg" \
		"git -C '$GD' status" "$T/PWNED-gd2" "goes through '$GD/tools', which the sandbox can write"
	expect_has "(GD2) message names the include" "include in $GD/.git/config" "$out"
	git -C "$GD" config --unset include.path
	# (GD3) several `..`: core.hooksPath = sub/x/../../hooks
	git -C "$GD" config core.hooksPath sub/x/../../hooks
	mut_case "(GD3) core.hooksPath sub/x/../../hooks (several ..)" "$GD" "$MUTD" \
		"MK=$T/PWNED-gd3; rmdir sub/x && mkdir -p sub/a/b/c sub/a/hooks && ln -s a/b/c sub/x && $hook sub/a/hooks/pre-commit && chmod +x sub/a/hooks/pre-commit" \
		"$(commit_cmd "$GD")" "$T/PWNED-gd3" "goes through '$GD/sub/x', which the sandbox can write"
	git -C "$GD" config --unset core.hooksPath
	# (GD4) through an rw state path: include.path = <agent>/sessions/d/../../x.cfg (x.cfg itself is
	# in the ro agent dir); the mutation accepts it
	mkdir -p "$FH/.prime/agent/sessions/d"
	git -C "$GD" config include.path "$FH/.prime/agent/sessions/d/../../x.cfg"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$GD") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(GD4) .. leaving an rw state dir refused rc" "1" "$rc"
	expect_has "(GD4) message" "goes through '$FH/.prime/agent/sessions/d', which the sandbox can write" "$out"
	# shellcheck source=/dev/null # mutated copy of pa-sandbox
	( export HOME="$FH"; source "$MUTD"; pa_sandbox_build_argv "$GD" ) >/dev/null 2>&1 && ok "(GD4) MUTATION: accepted without the check" || bad "(GD4) MUTATION: accepted without the check"
	git -C "$GD" config --unset include.path
	command rm -rf "$FH/.prime/agent/sessions/d"
	# (GD5) a symlinked git control file whose target leaves a workspace dir through `..` (it then
	# lands outside the workspace)
	mkdir -p "$GX"
	printf '#!/bin/sh\nexit 0\n' >"$GX/pc"
	ln -s "$GD/tools/../../gd-ext/pc" "$GD/.git/hooks/pre-push"
	[[ "$(realpath -m "$GD/tools/../../gd-ext/pc")" == "$GX/pc" ]] && ok "(GD5) fixture: target lands outside" || bad "(GD5) fixture: target lands outside"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$GD") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(GD5) symlinked hook leaving a workspace dir through .. refused rc" "1" "$rc"
	expect_has "(GD5) message" "symlinked git control file '$GD/.git/hooks/pre-push'" "$out"
	command rm -f "$GD/.git/hooks/pre-push"
	# accepted as before: `..` inside the target's ro top-level dir, from inside the ro .git, outside
	# the workspace only
	printf '[user]\n\tname = t\n' >"$GD/inc2.cfg"
	mkdir -p "$GX/a"
	printf '[user]\n\tname = t\n' >"$GX/inc.cfg"
	git -C "$GD" config core.hooksPath sub/x/../hooks2
	git -C "$GD" config --add include.path ../inc2.cfg
	git -C "$GD" config --add include.path "$GX/a/../inc.cfg"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$GD") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(GD6) .. within the ro top-level dir / from .git / outside the workspace: build rc" "0" "$rc"
	expect_lacks "(GD6) no refusal" "refusing" "$out"
	out="$(run_ws "$GD" 'touch sub/hooks2/x || echo DENIED-sub; echo w >> inc2.cfg || echo DENIED-inc2; touch free/w && echo WROTE-free' 2>&1)" || true
	expect_has "(GD6) top-level dir of the hooks dir is read-only" "DENIED-sub" "$out"
	expect_has "(GD6) include target is read-only" "DENIED-inc2" "$out"
	expect_has "(GD6) unreferenced top-level dir stays writable" "WROTE-free" "$out"
	git -C "$GD" config --unset core.hooksPath
	git -C "$GD" config --unset-all include.path
	# (GD7) accepted: a nested repo's core.hooksPath = ../../hooks leaves vendor/dep and vendor/,
	# which are read-only because of ANOTHER protected path (vendor/dep/.git, ANCESTORS)
	mkrepo "$GD/vendor/dep"
	git -C "$GD/vendor/dep" config core.hooksPath ../../hooks
	out="$( (HOME="$FH" pa_sandbox_build_argv "$GD") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(GD7) nested repo hooksPath climbing out of its ro top-level dir: build rc" "0" "$rc"
	expect_lacks "(GD7) no refusal" "refusing" "$out"
	out="$(run_ws "$GD" 'touch vendor/x || echo DENIED-vendor' 2>&1)" || true
	expect_has "(GD7) vendor/ is read-only" "DENIED-vendor" "$out"
	command rm -rf "$GD/vendor"
	# ---- Checker attempt 32: _pp deduplicated config words on their NORMALISED path, so
	# `tools/../hooks/x.sh` counted as done once `hooks/x.sh` was protected and its `..` was never
	# walked. MP restores that normalised key; MR skips a `..` word that normalises to the root.
	MUTP="$T/pa-sandbox.mut-pdone"
	sed 's|pdone\[\$1\]|pdone[$(realpath -s -m -- "$1")]|g' "$PA_SANDBOX" >"$MUTP"
	grep -q 'pdone\[$(realpath -s -m -- "$1")\]=1' "$MUTP" && ok "MP mutation applied" || bad "MP mutation applied"
	MUTR="$T/pa-sandbox.mut-pproot"
	sed 's@^\(\t*\)\[\[ "\$1/" == \*/\.\./\* \]\] || return 0$@\1return 0 # MUTATION@' "$PA_SANDBOX" >"$MUTR"
	grep -q 'return 0 # MUTATION' "$MUTR" && ok "MR mutation applied" || bad "MR mutation applied"
	printf 'exit 0\n' >"$GD/hooks/x.sh"
	gpatk="MK=$T/PWNED-gp; $gdatk && printf 'touch %s\n' \"\$MK\" > x/hooks/x.sh"
	# (GP1) the repro: alias.a names hooks/x.sh first, alias.b the same file through tools/..
	git -C "$GD" config alias.a '!sh hooks/x.sh'
	git -C "$GD" config alias.b '!sh tools/../hooks/x.sh'
	mut_case "(GP1) alias.b tools/../hooks/x.sh after alias.a hooks/x.sh" "$GD" "$MUTP" \
		"$gpatk" "git -C '$GD' b" "$T/PWNED-gp" "goes through '$GD/tools', which the sandbox can write"
	expect_has "(GP1) message names the key and the spelling" "alias.b in the config of '$GD/.git': '$GD/tools/../hooks/x.sh'" "$out"
	# (GP2) the same two words in the other order (alias.b first)
	git -C "$GD" config --unset alias.a
	git -C "$GD" config --unset alias.b
	git -C "$GD" config alias.b '!sh tools/../hooks/x.sh'
	git -C "$GD" config alias.a '!sh hooks/x.sh'
	out="$( (HOME="$FH" pa_sandbox_build_argv "$GD") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(GP2) reversed order refused rc" "1" "$rc"
	expect_has "(GP2) message" "goes through '$GD/tools', which the sandbox can write" "$out"
	git -C "$GD" config --unset alias.a
	git -C "$GD" config --unset alias.b
	# control: alias.a alone is accepted
	git -C "$GD" config alias.a '!sh hooks/x.sh'
	out="$( (HOME="$FH" pa_sandbox_build_argv "$GD") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(GP) control: alias.a hooks/x.sh alone builds rc" "0" "$rc"
	# (GP3) another git dir: the top repo (walked first) names <ws>/hooks/x.sh, a nested repo
	# names <ws>/tools/../hooks/x.sh (pdone is shared across git dirs)
	git -C "$GD" config alias.a "!sh $GD/hooks/x.sh"
	mkrepo "$GD/vendor/dep"
	git -C "$GD/vendor/dep" config alias.b "!sh $GD/tools/../hooks/x.sh"
	mut_case "(GP3) nested repo alias.b <ws>/tools/../hooks/x.sh after the top repo's <ws>/hooks/x.sh" "$GD" "$MUTP" \
		"$gpatk" "git -C '$GD/vendor/dep' b" "$T/PWNED-gp" "goes through '$GD/tools', which the sandbox can write"
	expect_has "(GP3) message names the nested repo" "alias.b in the config of '$GD/vendor/dep/.git'" "$out"
	command rm -rf "$GD/vendor"
	git -C "$GD" config --unset alias.a
	# (GP4) a word that reaches the worktree root through `..` (skipped as the root before):
	# `cd -P tools/..` (physical) then runs hooks/x.sh relative to what tools/.. names
	git -C "$GD" config alias.c '!cd -P tools/.. && sh hooks/x.sh'
	mut_case "(GP4) alias.c cd -P tools/.. (normalises to the root)" "$GD" "$MUTR" \
		"$gpatk" "git -C '$GD' c" "$T/PWNED-gp" "goes through '$GD/tools', which the sandbox can write"
	git -C "$GD" config --unset alias.c
	command rm -f "$GD/hooks/x.sh"
	# (HN) a HOME link pa-sandbox cannot resolve refuses (it was silently accepted): a newline in
	# the link target or in the link's own path, a loop
	MUTN="$T/pa-sandbox.mut-homenl"
	sed 's|^\(\t*\)if \[\[ \$hr -ne 0 \]\]; then$|\1if false; then # MUTATION|' "$PA_SANDBOX" >"$MUTN"
	grep -q 'if false; then # MUTATION' "$MUTN" && ok "MN mutation applied" || bad "MN mutation applied"
	ln -s "$GD/free/a"$'\n'"b" "$FH/.nlrc"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$GD") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(HN1) HOME link with a newline in its target refused rc" "1" "$rc"
	expect_has "(HN1) message" "$FH/.nlrc cannot be resolved" "$out"
	mut_host_nl() { # the MN mutation accepts it and leaves free/ writable: the host runs the file
		command cp -a "$GD" "$GD.pristine"
		# shellcheck source=/dev/null # mutated copy of pa-sandbox
		( cd "$GD"; export HOME="$FH"; source "$MUTN"; pa_sandbox_build_argv "$GD" 2>/dev/null && "${PA_BWRAP_ARGV[@]}" sh -c "printf 'touch %s\n' '$T/PWNED-hn1' > 'free/a
b'" ) >/dev/null 2>&1 || true
		sh "$FH/.nlrc" >/dev/null 2>&1 || true
		[[ -e "$T/PWNED-hn1" ]] && ok "MUTATION (HN1, check removed): the host runs the sandbox's file" || bad "MUTATION (HN1, check removed): the host runs the sandbox's file"
		command rm -rf "$GD" "$T/PWNED-hn1"
		command cp -a "$GD.pristine" "$GD"
		command rm -rf "$GD.pristine"
	}
	mut_host_nl
	command rm -f "$FH/.nlrc"
	ln -s "$GD/free/f" "$FH/.nl"$'\n'"rc"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$GD") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(HN2) HOME link with a newline in its own path refused rc" "1" "$rc"
	expect_has "(HN2) message" "cannot be resolved" "$out"
	command rm -f "$FH/.nl"$'\n'"rc"
	ln -s "$FH/.loop2" "$FH/.loop1"
	ln -s "$FH/.loop1" "$FH/.loop2"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$GD") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(HN3) HOME symlink loop refused (FALSE REFUSALS) rc" "1" "$rc"
	expect_has "(HN3) message" "cannot be resolved" "$out"
	command rm -f "$FH/.loop1" "$FH/.loop2"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$GD") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(GD) clean fixture builds again rc" "0" "$rc"
	command rm -rf "$GD" "$GX"

	# ---- shell startup files are NOT checked (KNOWN LIMITS, human decision 2026-10-17): a host rc or
	# launch environment that loads workspace files never makes the build refuse, and only a HOME
	# symlink itself is protected (HOME SYMLINKS), not what the file it names loads.
	NW="$FH/work/rc-free"
	mkrepo "$NW"
	git -C "$NW" -c commit.gpgsign=false commit -q --allow-empty -m i
	mkdir -p "$NW/sub" "$NW/zfunc" "$NW/zdot" "$NW/bin"
	printf 'echo ws-sourced\n' >"$NW/sub/x.zsh"
	printf 'echo ws-zshrc\n' >"$NW/zshrc"
	nwb() { # <label>: build for $NW with HOME=$FH must succeed (sets out)
		out="$( (HOME="$FH" pa_sandbox_build_argv "$NW") 2>&1 )" && rc=0 || rc=$?
		expect_eq "$1: build rc" "0" "$rc"
		expect_lacks "$1: no refusal" "refusing" "$out"
	}
	# (N1) the user's own ~/.zshrc / ~/.bashrc (outside the workspace) source a workspace file and put
	# workspace dirs on fpath / PATH: accepted, and the sourced file stays writable inside
	printf 'source %s/sub/x.zsh\nfpath=(%s/zfunc $fpath)\npath=(%s/bin $path)\n' "$NW" "$NW" "$NW" >"$FH/.zshrc"
	command cp "$FH/.zshrc" "$FH/.bashrc"
	nwb "(N1) ~/.zshrc / ~/.bashrc sourcing a workspace file"
	out="$(run_ws "$NW" 'echo w >> sub/x.zsh && echo WROTE' 2>&1)" || true
	expect_has "(N1) the workspace file a host rc sources stays writable (not checked)" "WROTE" "$out"
	# (N2) loads pa-sandbox cannot resolve (the removed analyser refused every workspace for them)
	printf 'DOTFILES_DIR="$(ghq root)/github.com/x/dotfiles"\nsource "$DOTFILES_DIR/zshrc"\nfpath=(${ZCACHE_DIR}/zfunc $fpath)\nsource /dev/stdin <<<"$(fzf --zsh)"\n' >"$FH/.zshrc"
	nwb "(N2) unresolvable loads in ~/.zshrc"
	command rm -f "$FH/.zshrc" "$FH/.bashrc"
	# (N3) launch environment naming workspace paths (ZDOTDIR, BASH_ENV, a relative ENV, INPUTRC, a
	# PATH entry, a relative PATH entry): accepted; the PATH entry is not made read-only
	out="$( (export ZDOTDIR="$NW/zdot" BASH_ENV="$NW/sub/x.zsh" ENV=.envrc INPUTRC="$NW/sub/irc" PATH="$NW/bin:$PATH:."
		HOME="$FH" pa_sandbox_build_argv "$NW") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(N3) launch ZDOTDIR / BASH_ENV / ENV / INPUTRC / PATH naming the workspace: build rc" "0" "$rc"
	out="$( (export PATH="$NW/bin:$PATH"; run_ws "$NW" 'touch bin/planted && echo WROTE') 2>&1 )" || true
	expect_has "(N3) a launch PATH entry in the workspace stays writable (not checked)" "WROTE" "$out"
	# (N4) ~/.zshrc that is itself a HOME symlink into the workspace: a HOME SYMLINKS target
	# (read-only inside), not a refusal
	ln -s "$NW/zshrc" "$FH/.zshrc"
	nwb "(N4) ~/.zshrc -> <ws>/zshrc"
	out="$(run_ws "$NW" 'echo w >> zshrc || echo DENIED' 2>&1)" || true
	expect_has "(N4) the linked startup file is read-only inside (HOME SYMLINKS)" "DENIED" "$out"
	command rm -f "$FH/.zshrc"
	command rm -r -f -- "$NW"
	MUTG="$T/pa-sandbox.mut-gitvar" # a missing git var path is skipped (attempt 19 behaviour)
	sed '/_protect_path "\$hf" "host git config" || return 1/s/.*/\t\t[[ -f "$hf" ]] || continue # MUTATION/' "$PA_SANDBOX" >"$MUTG"
	grep -q 'continue # MUTATION' "$MUTG" && ok "MG mutation applied" || bad "MG mutation applied"
	# GIT_CONFIG_GLOBAL / $XDG_CONFIG_HOME/git/config MISSING at launch, inside the workspace
	GV="$FH/work/gitvar"
	mkrepo "$GV"
	mkdir -p "$GV/conf" "$GV/cfg/git"
	: >"$GV/conf/.keep"
	git -C "$GV" add -A && git -C "$GV" -c commit.gpgsign=false commit -qm i
	export GIT_CONFIG_GLOBAL="$GV/conf/gitconfig"
	mut_host "(R16) GIT_CONFIG_GLOBAL missing at launch" "$GV" "$MUTG" "printf '[core]\\n\\tfsmonitor = touch $T/PWNED-r16; false\\n' > conf/gitconfig" \
		"git -C '$GV' status" "$T/PWNED-r16"
	export GIT_CONFIG_GLOBAL="$GV/gitconfig"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$GV") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(R17) GIT_CONFIG_GLOBAL missing directly under the root refused rc" "1" "$rc"
	expect_has "(R17) message" "does not exist and sits directly under" "$out"
	unset GIT_CONFIG_GLOBAL
	# $XDG_CONFIG_HOME in the workspace: its git/config (missing) is a host global git config, so
	# its top-level directory is read-only (shell startup files there are not checked)
	export XDG_CONFIG_HOME="$GV/cfg"
	mut_host "(R18) \$XDG_CONFIG_HOME/git/config missing at launch" "$GV" "$MUTG" "printf '[core]\\n\\tfsmonitor = touch $T/PWNED-r18; false\\n' > cfg/git/config" \
		"git -C '$GV' status" "$T/PWNED-r18"
	unset XDG_CONFIG_HOME
	export GIT_CONFIG_GLOBAL=/dev/null
	command rm -rf "$GV"

	# (D) ancestors of HOME / agent dir are refused
	for ws in "$T" "$(dirname "$FH")" "$FH" "$FH/.prime" "$FH/.prime/agent" "$FH/.prime/agent/sessions" /; do
		out="$( (HOME="$FH" pa_sandbox_build_argv "$ws") 2>&1 )" && rc=0 || rc=$?
		expect_eq "workspace $ws refused" "1" "$rc"
	done

	# (2) guard reachable inside the sandbox through the dotfiles symlink + verified end to end
	out="$(run_in 'test -r "$HOME/.prime/agent/bin/prime-shell-guard.sh" && echo readable')"
	expect_has "guard symlink target readable inside" "readable" "$out"
	out="$( (cd "$REPO"; export HOME="$FH"; pa_sandbox_build_argv "$REPO" 2>/dev/null; pa_sandbox_verify_guard) 2>&1 )" && rc=0 || rc=$?
	expect_eq "verify_guard passes with symlinked guard" "0" "$rc"
	mv "$DOT/agent/scripts/hooks/decide.py" "$DOT/agent/scripts/hooks/decide.py.off"
	out="$( (cd "$REPO"; export HOME="$FH"; pa_sandbox_build_argv "$REPO" 2>/dev/null; pa_sandbox_verify_guard) 2>&1 )" && rc=0 || rc=$?
	expect_eq "verify_guard fails closed when guard dependency missing" "1" "$rc"
	mv "$DOT/agent/scripts/hooks/decide.py.off" "$DOT/agent/scripts/hooks/decide.py"
	run_in 'echo X >> "$HOME/dotfiles/agent/security-rules.json" || true' >/dev/null
	cmp -s "$DOT/agent/security-rules.json" "$REAL_ROOT/agent/security-rules.json" && ok "guard rules cannot be modified from inside" || bad "guard rules cannot be modified from inside"

	# (4) sockets, /run/user, daemon socket
	out="$(PA_SANDBOX_MASK_PATHS='' run_mut "test -S \"$T/socks/docker.sock\" && echo SOCK-VISIBLE || echo sock-hidden")"
	expect_has "MUTATION (no mask) docker socket is a real socket" "SOCK-VISIBLE" "$out"
	out="$(run_in "test -S \"$T/socks/docker.sock\" && echo SOCK-VISIBLE || echo sock-hidden")"
	expect_has "masked docker socket is not a socket inside (test -S)" "sock-hidden" "$out"
	if [[ -n "$(ls -A /run/user 2>/dev/null)" ]]; then
		out="$(run_in 'ls -A /run/user | wc -l')"
		expect_eq "/run/user emptied" "0" "$(printf '%s' "$out" | tail -n1)"
	fi
	out="$(run_in 'echo "$PRIME_AGENT_DAEMON_SOCKET"')"
	expect_lacks "daemon socket differs from host default" "prime-agent-rust-" "$out"
	out="$(run_in "test -S \"$HOSTTMP/daemon.sock\" && echo REACHABLE || echo unreachable")"
	expect_has "host daemon socket (in /tmp) unreachable inside" "unreachable" "$out"
	run_mut_args() { # <drop-arg...> -- <sh-snippet>: profile minus the given argv pair/single (mutation)
		local -a drop=()
		while [[ "$1" != -- ]]; do drop+=("$1"); shift; done
		shift
		(
			cd "$REPO"
			export HOME="$FH" SSH_AUTH_SOCK=/x/agent AWS_SECRET_ACCESS_KEY=leak GITHUB_TOKEN=leak
			pa_sandbox_build_argv "$REPO" 2>/dev/null
			local -a mut=()
			local i=0 n=${#drop[@]}
			while [[ $i -lt ${#PA_BWRAP_ARGV[@]} ]]; do
				if [[ "${PA_BWRAP_ARGV[$i]}" == "${drop[0]}" && ( $n -eq 1 || "${PA_BWRAP_ARGV[$((i + 1))]}" == "${drop[1]}" ) ]]; then
					i=$((i + n))
					continue
				fi
				if [[ "${PA_BWRAP_ARGV[$i]}" == --dir && "${PA_BWRAP_ARGV[$((i + 1))]}" == /tmp/pa-sandbox ]]; then
					i=$((i + 2)) # cannot create it on the host /tmp (ro /); irrelevant to the mutation
					continue
				fi
				mut+=("${PA_BWRAP_ARGV[$i]}")
				i=$((i + 1))
			done
			"${mut[@]}" sh -c "$1"
		) 2>&1
	}
	out="$(run_mut_args --tmpfs /tmp -- "test -S \"$HOSTTMP/daemon.sock\" && echo REACHABLE || echo unreachable")" || true
	expect_has "MUTATION (no /tmp tmpfs): host daemon socket reachable" "REACHABLE" "$out"
	out="$(run_mut_args --clearenv -- 'env')" || true
	expect_has "MUTATION (no --clearenv): SSH_AUTH_SOCK leaks" "SSH_AUTH_SOCK=" "$out"

	# (5) resolved interpreter of the kernel venv is bound ro; env handling
	out="$(run_in '"$HOME/.prime/agent/kernel-venv/bin/python"')"
	expect_has "kernel-venv python symlink target usable inside" "interp" "$out"
	run_in 'echo X > "$HOME/.data/uv/python/cpy/bin/new" || true' >/dev/null
	[[ ! -e "$FH/.data/uv/python/cpy/bin/new" ]] && ok "interpreter dir is read-only" || bad "interpreter dir is read-only"
	# (T9b c) uv layout: bin/python and pyvenv.cfg `home` go through uv's minor-version symlink
	# (cpython-3.11-x -> cpython-3.11.17-x); the directory holding it is ro-bound, so the venv
	# resolves inside exactly as on the host
	UVP="$FH/.local/share/uv/python"
	KV="$FH/.prime/agent/kernel-venv"
	mkdir -p "$UVP/cpython-3.11.17-x/bin"
	printf '#!/bin/sh\necho uvinterp\n' >"$UVP/cpython-3.11.17-x/bin/python3.11"
	chmod +x "$UVP/cpython-3.11.17-x/bin/python3.11"
	ln -s "$UVP/cpython-3.11.17-x" "$UVP/cpython-3.11-x"
	mv "$KV/bin/python" "$KV/bin/python.t9b-orig"
	ln -s "$UVP/cpython-3.11-x/bin/python3.11" "$KV/bin/python"
	printf 'home = %s\nversion_info = 3.11\n' "$UVP/cpython-3.11-x/bin" >"$KV/pyvenv.cfg"
	snipuv='"$HOME/.prime/agent/kernel-venv/bin/python"; h="$(sed -n "s/^home = //p" "$HOME/.prime/agent/kernel-venv/pyvenv.cfg")"; "$h/python3.11"
echo "LINK:$(readlink "$HOME/.local/share/uv/python/cpython-3.11-x")"
echo X > "$HOME/.local/share/uv/python/new" 2>/dev/null && echo UV-WRITABLE
ln -sfn /tmp "$HOME/.local/share/uv/python/cpython-3.11-x" 2>/dev/null && echo UV-RELINKED
cat "$HOME/.ssh/id_x" 2>/dev/null; true'
	out="$(run_in "$snipuv")"
	expect_eq "(T9b c) uv venv: bin/python and pyvenv.cfg home resolve inside" "uvinterp uvinterp" "$(printf '%s' "$out" | grep -x uvinterp | tr '\n' ' ' | sed 's/ $//')"
	expect_has "(T9b c) uv minor-version symlink visible inside as on the host" "LINK:$UVP/cpython-3.11.17-x" "$out"
	expect_lacks "(T9b c) uv python dir read-only inside" "UV-WRITABLE" "$out"
	expect_lacks "(T9b c) uv minor-version symlink cannot be re-pointed inside" "UV-RELINKED" "$out"
	expect_lacks "(T9b c) HOME stays hidden" "SENTINEL-SECRET" "$out"
	# MUTATION: without the ro bind of the link's directory the venv is broken inside (T13's failure)
	out="$(run_mut_args --ro-bind "$UVP" "$UVP" -- '"$HOME/.prime/agent/kernel-venv/bin/python" 2>/dev/null || echo VENV-BROKEN')" || true
	expect_has "MUTATION (no ro bind of the uv python dir): venv interpreter does not resolve" "VENV-BROKEN" "$out"
	# a link directly in HOME: the link itself is bound (its target at its path), not HOME
	ln -s "$UVP/cpython-3.11.17-x" "$FH/pylink"
	ln -sfn "$FH/pylink/bin/python3.11" "$KV/bin/python"
	printf 'home = %s\n' "$FH/pylink/bin" >"$KV/pyvenv.cfg"
	out="$(run_in "$snipuv")"
	expect_has "(T9b c) link directly under HOME resolves inside" "uvinterp" "$out"
	expect_lacks "(T9b c) link directly under HOME does not expose HOME" "SENTINEL-SECRET" "$out"
	# a way through the writable workspace refuses (the sandbox could re-point it)
	ln -s "$UVP/cpython-3.11.17-x" "$REPO/pylink"
	ln -sfn "$REPO/pylink/bin/python3.11" "$KV/bin/python"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$REPO") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(T9b c) venv interpreter through a workspace symlink: build rc" "1" "$rc"
	expect_has "(T9b c) venv interpreter through a workspace symlink: message" "kernel venv interpreter '$KV/bin/python' goes through the sandbox-writable" "$out"
	command rm -f "$REPO/pylink"
	mkdir -p "$REPO/py/bin"
	command cp "$UVP/cpython-3.11.17-x/bin/python3.11" "$REPO/py/bin/python3.11"
	ln -sfn "$REPO/py/bin/python3.11" "$KV/bin/python"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$REPO") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(T9b c) venv interpreter inside the workspace: build rc" "1" "$rc"
	printf 'home = %s\n' "$REPO/py/bin" >"$KV/pyvenv.cfg"
	ln -sfn "$UVP/cpython-3.11.17-x/bin/python3.11" "$KV/bin/python"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$REPO") 2>&1 )" && rc=0 || rc=$?
	expect_eq "(T9b c) pyvenv.cfg home inside the workspace: build rc" "1" "$rc"
	expect_has "(T9b c) pyvenv.cfg home inside the workspace: message" "kernel venv pyvenv.cfg home '$REPO/py/bin'" "$out"
	command rm -rf "$REPO/py" "$FH/pylink" "$UVP" "$KV/pyvenv.cfg"
	command rm -f "$KV/bin/python"
	mv "$KV/bin/python.t9b-orig" "$KV/bin/python"
	out="$( (cd "$REPO"; export HOME="$FH" PRIME_AGENT_MULTI=$'a\nb=c' PA_SANDBOX_PASS_ENV='*'; pa_sandbox_build_argv "$REPO" 2>/dev/null; "${PA_BWRAP_ARGV[@]}" sh -c 'printf "%s" "$PRIME_AGENT_MULTI"') 2>&1)"
	expect_eq "multi-line PRIME_AGENT_* value survives" $'a\nb=c' "$out"

	# repo == HOME must be refused (would expose everything read-write)
	out="$( (HOME="$FH" pa_sandbox_build_argv "$FH") 2>&1 )" && rc=0 || rc=$?
	expect_eq "refuse repo==HOME rc" "1" "$rc"
	expect_has "refuse repo==HOME msg" "refusing" "$out"

	if [[ "${HOST_PROC_DEGRADED:-0}" == 1 ]]; then
		out="$( (unset PA_SANDBOX_ALLOW_HOST_PROC; HOME="$FH" pa_sandbox_build_argv "$REPO") 2>&1 )" && rc=0 || rc=$?
		expect_eq "no private /proc without opt-in fails closed rc" "1" "$rc"
		expect_has "no private /proc msg" "PA_SANDBOX_ALLOW_HOST_PROC" "$out"
	fi

	# missing guard fails closed
	command rm -f "$FH/.prime/agent/bin/prime-shell-guard.sh"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$REPO") 2>&1 )" && rc=0 || rc=$?
	expect_eq "missing guard fails closed rc" "1" "$rc"
	expect_has "missing guard msg" "prime-shell-guard.sh" "$out"
	out="$( (HOME="$FH" PA_SANDBOX_ALLOW_NO_GUARD=1 pa_sandbox_build_argv "$REPO") 2>&1 )" && rc=0 || rc=$?
	expect_eq "override allows missing guard" "0" "$rc"
	ln -s "$DOT/agent/scripts/prime-shell-guard.sh" "$FH/.prime/agent/bin/prime-shell-guard.sh"

	# missing bwrap fails closed (run as a real command)
	out="$(PATH=/nonexistent-pa "$BASH" "$PA_SANDBOX" --help 2>&1)" && rc=0 || rc=$?
	expect_eq "missing bwrap rc" "127" "$rc"
	expect_has "missing bwrap msg" "bwrap" "$out"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
