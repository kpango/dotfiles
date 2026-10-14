#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2030,SC2031  # A&&B||C is the ok/bad reporter idiom; single quotes defer expansion to the sandbox shell
# Tests for pa-auto (gate detection) and pa-sandbox (bwrap profile).
# No network, no paid calls, never touches the real HOME: every case uses a
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
	[[ -f "$FH/.prime/agent/sessions/state-file" && ! -e "$FH/.prime/agent/root-file" ]] && ok "agent dir: state dirs writable, root read-only" || bad "agent dir: state dirs writable, root read-only"

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

	# allowlist: NEW names (present or not) cannot be created in the agent dir
	run_in 'for n in SYSTEM.md machines/evil.md extensions rules keybindings.json mcp.json model-routing.json newdir; do touch "$HOME/.prime/agent/$n" 2>/dev/null || mkdir "$HOME/.prime/agent/$n" 2>/dev/null || true; done' >/dev/null
	for n in SYSTEM.md machines/evil.md extensions rules keybindings.json mcp.json model-routing.json newdir; do
		[[ ! -e "$FH/.prime/agent/$n" ]] && ok "new agent-dir entry $n cannot be created" || bad "new agent-dir entry $n cannot be created"
	done
	# MUTATION: with the agent dir bound rw instead of ro, creation DOES succeed
	run_mut_rw() {
		(
			cd "$REPO"
			export HOME="$FH"
			pa_sandbox_build_argv "$REPO" 2>/dev/null
			local -a mut=()
			local i=0
			while [[ $i -lt ${#PA_BWRAP_ARGV[@]} ]]; do
				if [[ "${PA_BWRAP_ARGV[$i]}" == --ro-bind && "${PA_BWRAP_ARGV[$((i + 1))]}" == "$FH/.prime/agent" ]]; then
					mut+=(--bind)
				else
					mut+=("${PA_BWRAP_ARGV[$i]}")
				fi
				i=$((i + 1))
			done
			"${mut[@]}" sh -c "$1"
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
	mkdir -p "$REPO/store/dep.git" "$REPO/vendor/dep2"
	git init -q --bare "$REPO/store/dep.git"
	ln -s ../../store/dep.git "$REPO/vendor/dep2/.git"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$REPO") 2>&1 )" && rc=0 || rc=$?
	expect_eq "symlinked nested .git refused rc" "1" "$rc"
	expect_has "symlinked nested .git listed" "vendor/dep2/.git" "$out"
	# MUTATION: with the (UNSAFE) override the sandbox starts and the symlink target is writable
	( cd "$REPO"; export HOME="$FH" PA_SANDBOX_ALLOW_GIT_SYMLINKS=1; pa_sandbox_build_argv "$REPO" 2>/dev/null; "${PA_BWRAP_ARGV[@]}" sh -c 'echo "[evil]" >> store/dep.git/config' ) >/dev/null 2>&1 || true
	grep -q '^\[evil\]' "$REPO/store/dep.git/config" && ok "MUTATION (symlink override): linked git dir config is writable" || bad "MUTATION (symlink override): linked git dir config is writable"
	command rm -rf "$REPO/vendor/dep2" "$REPO/store"

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
	sed 's|_rw "$cur/$c" \&\& return 2|: # MUTATION|' "$PA_SANDBOX" >"$MUTSB"
	grep -q ': # MUTATION' "$MUTSB" && ok "(3) mutation applied (writable-symlink refusal removed)" || bad "(3) mutation applied (writable-symlink refusal removed)"
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
	printf 'gitdir: ../../src/../store/gd\n' >"$S3/vendor/gf/.git"
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

	# mcp catalog + daemon-workers are read-only; telemetry stays writable
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
