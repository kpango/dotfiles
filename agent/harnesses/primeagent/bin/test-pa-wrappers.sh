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
	# run_mut_drop: same profile with the ro bind of <path> turned rw (mutation)
	run_mut_drop() { # <workspace> <ro-path> <sh-snippet>
		(
			cd "$1"
			export HOME="$FH"
			pa_sandbox_build_argv "$1" 2>/dev/null
			local -a mut=()
			local i=0
			while [[ $i -lt ${#PA_BWRAP_ARGV[@]} ]]; do
				if [[ "${PA_BWRAP_ARGV[$i]}" == --ro-bind && "${PA_BWRAP_ARGV[$((i + 1))]}" == "$2" ]]; then
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
	run_ws "$REPO" 'echo x > vendor/dep/.git/config 2>/dev/null; mkdir vendor/dep/.git/hooks2 2>/dev/null; echo ok > vendor/dep/tree-file; true' >/dev/null || true
	[[ ! -e "$REPO/vendor/dep/.git/hooks2" ]] && ok "nested .git is read-only" || bad "nested .git is read-only"
	[[ -f "$REPO/vendor/dep/tree-file" ]] && ok "working-tree files under nested repo stay writable" || bad "working-tree files under nested repo stay writable"
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
