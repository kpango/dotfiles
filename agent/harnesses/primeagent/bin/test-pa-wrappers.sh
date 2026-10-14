#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # A&&B||C is the ok/bad reporter idiom; single quotes defer expansion to the sandbox shell
# Tests for pa-auto (gate detection) and pa-sandbox (bwrap profile).
# No network, no paid calls, never touches the real HOME: every case uses a
# fake HOME under a fresh mktemp dir. Sandbox cases run harmless shell commands
# inside the exact bwrap argv that pa-sandbox builds (pa_sandbox_build_argv).
set -euo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PA_AUTO="$HERE/pa-auto"
PA_SANDBOX="$HERE/pa-sandbox"

T="$(mktemp -d "${TMPDIR:-/tmp}/pa-wrappers-test.XXXXXX")"
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
	printf 'guard\n' >"$FH/.prime/agent/bin/prime-shell-guard.sh"
	REPO="$FH/work/repo"
	mkrepo "$REPO"
	printf 'inrepo\n' >"$REPO/.env"
	OUTSIDE="$T/outside-repo"
	mkdir -p "$OUTSIDE"
	printf 'SENTINEL-SECRET\n' >"$OUTSIDE/.env"

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

	for p in .ssh/id_x .aws/credentials .gnupg/key .kube/config .config/gh/hosts.yml .netrc \
		.password-store/s.gpg work/.env outside.txt; do
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

	run_in 'echo state > "$HOME/.prime/agent/state-file"' >/dev/null
	[[ -f "$FH/.prime/agent/state-file" ]] && ok "write to ~/.prime/agent persists" || bad "write to ~/.prime/agent persists"

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
	printf 'guard\n' >"$FH/.prime/agent/bin/prime-shell-guard.sh"

	# missing bwrap fails closed (run as a real command)
	out="$(PATH=/nonexistent-pa "$BASH" "$PA_SANDBOX" --help 2>&1)" && rc=0 || rc=$?
	expect_eq "missing bwrap rc" "127" "$rc"
	expect_has "missing bwrap msg" "bwrap" "$out"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
