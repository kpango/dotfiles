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

# The fixture tree lives OUTSIDE /tmp: the sandbox mounts a tmpfs over /tmp, so a
# fake HOME under /tmp would be hidden by that, not by the HOME tmpfs under test.
PA_TEST_ROOT="${PA_TEST_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}}"
mkdir -p "$PA_TEST_ROOT"
T="$(mktemp -d "$PA_TEST_ROOT/pa-wrappers-test.XXXXXX")"
case "$T" in /tmp/*) echo "fixture root must not be under /tmp: $T" >&2; exit 2 ;; esac
trap 'command rm -rf "$T"' EXIT
FAIL=0 PASS=0

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

	# git: commondir / gitfile redirect attacks, hooks + config write-back
	run_in 'echo "$HOME/.prime/agent" > .git/commondir' >/dev/null
	out="$( (cd "$REPO"; export HOME="$FH"; pa_sandbox_build_argv "$REPO" 2>&1 >/dev/null; "${PA_BWRAP_ARGV[@]}" sh -c 'touch "$HOME/.prime/agent/PLANTED" 2>&1; echo done') 2>&1 )" || true
	[[ ! -e "$FH/.prime/agent/PLANTED" ]] && ok "commondir redirect: agent dir stays unwritable" || bad "commondir redirect: agent dir stays unwritable"
	command rm -f "$REPO/.git/commondir"
	GREPO="$FH/work/gitfile-repo"
	mkdir -p "$GREPO"
	printf 'gitdir: %s\n' "$FH/.prime/agent" >"$GREPO/.git"
	out="$( (HOME="$FH" pa_sandbox_build_argv "$GREPO") 2>&1 )" && rc=0 || rc=$?
	expect_eq "gitfile redirect to agent dir refused rc" "1" "$rc"
	[[ ! -e "$FH/.prime/agent/PLANTED" ]] && ok "gitfile redirect: nothing planted" || bad "gitfile redirect: nothing planted"
	run_in 'echo "#!/bin/sh" > .git/hooks/pre-commit 2>/dev/null; echo "[core]" >> .git/config 2>/dev/null; true' >/dev/null
	[[ ! -e "$REPO/.git/hooks/pre-commit" ]] && ok ".git/hooks is read-only inside" || bad ".git/hooks is read-only inside"
	! grep -q '^\[core\]$' <<<"$(tail -n1 "$REPO/.git/config")" && ok ".git/config is read-only inside" || bad ".git/config is read-only inside"
	# legit linked worktree: common dir bound rw (objects) but hooks/config ro
	WT="$FH/work/wt"
	git -C "$REPO" -c user.email=a@b -c user.name=n commit -q --allow-empty -m init
	git -C "$REPO" worktree add -q "$WT" -b wtbranch
	run_in_wt() { ( cd "$WT"; export HOME="$FH"; pa_sandbox_build_argv "$WT" 2>/dev/null; "${PA_BWRAP_ARGV[@]}" sh -c "$1" ) 2>&1; }
	run_in_wt 'touch "$HOME/work/repo/.git/objects/wt-ok"; echo x > "$HOME/work/repo/.git/hooks/h" 2>/dev/null; echo x >> "$HOME/work/repo/.git/config" 2>/dev/null; true' >/dev/null
	[[ -e "$REPO/.git/objects/wt-ok" ]] && ok "worktree: common dir objects writable" || bad "worktree: common dir objects writable"
	[[ ! -e "$REPO/.git/hooks/h" ]] && ok "worktree: common dir hooks read-only" || bad "worktree: common dir hooks read-only"
	command rm -f "$REPO/.git/objects/wt-ok"

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
