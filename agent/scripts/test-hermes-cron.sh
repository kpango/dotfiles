#!/usr/bin/env bash
# Test hermes-cron-install.sh with a FAKE hermes (no Hermes install, no gateway, no network):
# manifest validation, generated pre-run gates (regular files, wakeAgent contract), idempotent job creation, --check, --dry-run.
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$ROOT/agent/scripts/bot/hermes-cron-install.sh"

TMP="$(cd -P "$(mktemp -d)" && pwd)"
trap 'find "$TMP" -delete' EXIT

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

# A scratch dotfiles tree: the real manifest + installer, a fake precheck-cron.sh whose answer the test controls.
TREE="$TMP/tree"
mkdir -p "$TREE/agent/scripts/bot" "$TREE/agent/harnesses/hermes/cron"
cp "$ROOT/agent/harnesses/hermes/cron/jobs.json" "$TREE/agent/harnesses/hermes/cron/jobs.json"
cat >"$TREE/agent/scripts/bot/precheck-cron.sh" <<'PC'
#!/usr/bin/env bash
case "${FAKE_PRECHECK:-false}" in
  true) echo '{"action_required": true, "tasks": ["pr-review: 2 open"]}' ;;
  null) echo '{"action_required": null, "error": "gh unavailable"}'; exit 3 ;;
  *) echo '{"action_required": false}' ;;
esac
PC
chmod +x "$TREE/agent/scripts/bot/precheck-cron.sh"

# Fake hermes: `cron list` prints the names recorded by earlier `cron create` calls; every call is logged.
BIN="$TMP/bin"
mkdir -p "$BIN"
cat >"$BIN/hermes" <<'FH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${FAKE_HERMES_LOG:?}"
if [ "${1:-}" = cron ] && [ "${2:-}" = list ]; then
  cat "${FAKE_HERMES_STATE:?}" 2>/dev/null || true
  [ -z "${FAKE_HERMES_EXTRA_LIST:-}" ] || printf '%s\n' "$FAKE_HERMES_EXTRA_LIST"
elif [ "${1:-}" = cron ] && [ "${2:-}" = create ]; then
  while [ $# -gt 0 ]; do [ "$1" = --name ] && { printf '%s\n' "$2" >>"$FAKE_HERMES_STATE"; break; }; shift; done
fi
FH
chmod +x "$BIN/hermes"
export FAKE_HERMES_LOG="$TMP/hermes.log" FAKE_HERMES_STATE="$TMP/hermes.state"

HH="$TMP/hermes-home"
inst() { DOTFILES_ROOT="$TREE" HERMES_HOME="$HH" PATH="$BIN:$PATH" bash "$INSTALL" "$@"; }

echo "[ --dry-run touches nothing and never calls hermes ]"
: >"$FAKE_HERMES_LOG"
inst --dry-run >"$TMP/dry.out"
[ ! -e "$HH" ] || fail "--dry-run created $HH"
[ ! -s "$FAKE_HERMES_LOG" ] || fail "--dry-run called hermes: $(cat "$FAKE_HERMES_LOG")"
[ "$(grep -c 'would run: hermes cron create' "$TMP/dry.out")" = 3 ] || fail "--dry-run should list 3 jobs"
pass "--dry-run: nothing written, hermes never called, 3 jobs planned"

echo
echo "[ install: gates + jobs ]"
: >"$FAKE_HERMES_LOG"
inst >"$TMP/inst.out"
for t in pr-review ci-failure catalog-drift; do
  g="$HH/scripts/dotfiles-precheck-$t.sh"
  [ -f "$g" ] && [ ! -L "$g" ] || fail "gate for $t is not a regular file"
  [ "$(stat -c %a "$g")" = 700 ] || fail "gate for $t must be mode 0700 (got $(stat -c %a "$g"))"
  grep -q "'$TREE/agent/scripts/bot/precheck-cron.sh' --task '$t' --json" "$g" || fail "gate for $t does not call precheck-cron.sh with its task"
done
[ "$(stat -c %a "$HH/scripts")" = 700 ] || fail "scripts dir must be 0700"
[ "$(grep -c '^cron create ' "$FAKE_HERMES_LOG")" = 3 ] || fail "expected 3 'cron create' calls, got: $(cat "$FAKE_HERMES_LOG")"
grep -q -- "--name dotfiles-pr-review --script dotfiles-precheck-pr-review.sh --deliver local" "$FAKE_HERMES_LOG" || fail "pr-review job arguments wrong"
grep -q "^cron create weekdays at 9am " "$FAKE_HERMES_LOG" || fail "schedule must be the first positional argument"
! grep -q -- "--no-agent" "$FAKE_HERMES_LOG" || fail "jobs must wake the agent (pre-check gate), not run --no-agent"
! grep -q "$HH/scripts" "$FAKE_HERMES_LOG" || fail "--script must be the bare gate name (Hermes resolves it inside ~/.hermes/scripts)"
pass "gates are regular 0700 files; 3 jobs created with the gate name, schedule first, --deliver local"

echo
echo "[ idempotent ]"
: >"$FAKE_HERMES_LOG"
inst >"$TMP/inst2.out"
! grep -q '^cron create ' "$FAKE_HERMES_LOG" || fail "second run must not create jobs again"
grep -q "job exists: dotfiles-ci-failure" "$TMP/inst2.out" || fail "second run should report existing jobs"
pass "re-run creates nothing"

: >"$TMP/hermes.state"
: >"$FAKE_HERMES_LOG"
FAKE_HERMES_EXTRA_LIST="dotfiles-pr-review-2  weekdays" inst >/dev/null
[ "$(grep -c '^cron create ' "$FAKE_HERMES_LOG")" = 3 ] || fail "a job named dotfiles-pr-review-2 must not suppress dotfiles-pr-review"
pass "job-name match respects boundaries (x vs x-2)"

echo
echo "[ gate contract: {\"wakeAgent\": ...} on the last line ]"
g="$HH/scripts/dotfiles-precheck-pr-review.sh"
last() { tail -n 1; }
out="$(FAKE_PRECHECK=true bash "$g")"
[ "$(printf '%s\n' "$out" | last)" = '{"wakeAgent": true}' ] || fail "action required -> last line must be wakeAgent true (got: $out)"
printf '%s\n' "$out" | grep -q '"action_required": true' || fail "the pre-check findings must be printed before the verdict"
out="$(FAKE_PRECHECK=false bash "$g")"
[ "$out" = '{"wakeAgent": false}' ] || fail "nothing to do -> only wakeAgent false (got: $out)"
out="$(FAKE_PRECHECK=null bash "$g" 2>"$TMP/gate.err")"
[ "$out" = '{"wakeAgent": false}' ] || fail "incomplete check must not wake the agent (got: $out)"
grep -q "could not complete" "$TMP/gate.err" || fail "an incomplete check must say so on stderr"
pass "gate: true wakes after printing findings; false / incomplete stay silent (0 tokens)"

echo
echo "[ --check ]"
inst --check >/dev/null || fail "--check should pass right after install"
printf '# tampered\n' >>"$HH/scripts/dotfiles-precheck-ci-failure.sh"
! inst --check >/dev/null 2>&1 || fail "--check must fail on a stale gate"
inst >/dev/null
inst --check >/dev/null || fail "re-install must repair the stale gate"
rm "$HH/scripts/dotfiles-precheck-catalog-drift.sh"
! inst --check >/dev/null 2>&1 || fail "--check must fail on a missing gate"
inst >/dev/null
: >"$TMP/hermes.state"
! inst --check >/dev/null 2>&1 || fail "--check must fail when jobs are not listed"
pass "--check: stale / missing gate and missing jobs are detected"

echo
echo "[ gate is a regular file, never a link ]"
before="$(sha256sum "$TREE/agent/scripts/bot/precheck-cron.sh" | cut -d' ' -f1)"
rm -f "$HH/scripts/dotfiles-precheck-pr-review.sh"
ln -s "$TREE/agent/scripts/bot/precheck-cron.sh" "$HH/scripts/dotfiles-precheck-pr-review.sh"
! inst --check >/dev/null 2>&1 || fail "--check must reject a symlinked gate (Hermes refuses symlink escapes)"
inst >/dev/null
[ ! -L "$HH/scripts/dotfiles-precheck-pr-review.sh" ] || fail "install must replace a symlink with a regular file"
[ "$(sha256sum "$TREE/agent/scripts/bot/precheck-cron.sh" | cut -d' ' -f1)" = "$before" ] || fail "install wrote through the symlink into the repo's precheck-cron.sh"
pass "symlinked gate rejected by --check and replaced by install without writing through it"

echo
echo "[ fail closed ]"
mk_tree_with() { # mk_tree_with <jq filter>: a tree whose manifest is the real one passed through the filter
  local t="$TMP/bad-$RANDOM"
  mkdir -p "$t/agent/scripts/bot" "$t/agent/harnesses/hermes/cron"
  cp "$TREE/agent/scripts/bot/precheck-cron.sh" "$t/agent/scripts/bot/"
  jq "$1" "$TREE/agent/harnesses/hermes/cron/jobs.json" >"$t/agent/harnesses/hermes/cron/jobs.json"
  echo "$t"
}
expect_reject() { # expect_reject <label> <jq filter>
  local t h="$TMP/bad-home-$RANDOM"
  t="$(mk_tree_with "$2")"
  : >"$FAKE_HERMES_LOG"
  if DOTFILES_ROOT="$t" HERMES_HOME="$h" PATH="$BIN:$PATH" bash "$INSTALL" >"$TMP/rej.out" 2>&1; then fail "$1: accepted"; fi
  [ ! -e "$h/scripts" ] || fail "$1: gates were written from a bad manifest"
  ! grep -q '^cron create ' "$FAKE_HERMES_LOG" || fail "$1: jobs were created from a bad manifest"
  pass "$1 rejected before anything is written"
}
expect_reject "unknown task" '.jobs[0].task = "rm-rf"'
expect_reject "name with a space / uppercase" '.jobs[0].name = "Bad Name"'
expect_reject "name starting with a dash" '.jobs[0].name = "-x"'
expect_reject "empty prompt" '.jobs[0].prompt = ""'
expect_reject "control character in the prompt" '.jobs[0].prompt = "a\u0001b"'
expect_reject "non-printable schedule" '.jobs[0].schedule = "every 2h\u0007"'
expect_reject "duplicate names" '.jobs[1].name = .jobs[0].name'
expect_reject "empty jobs array" '.jobs = []'

BADROOT="$TMP/we ird"
mkdir -p "$BADROOT/agent/scripts/bot" "$BADROOT/agent/harnesses/hermes/cron"
cp "$TREE/agent/scripts/bot/precheck-cron.sh" "$BADROOT/agent/scripts/bot/"
cp "$TREE/agent/harnesses/hermes/cron/jobs.json" "$BADROOT/agent/harnesses/hermes/cron/"
! DOTFILES_ROOT="$BADROOT" HERMES_HOME="$TMP/h2" PATH="$BIN:$PATH" bash "$INSTALL" --dry-run >/dev/null 2>&1 || fail "a root path with a space must be refused (it is embedded in a script)"
pass "a root path outside [A-Za-z0-9_./+-] is refused"

NOHERMES="$TMP/nohermes"
mkdir -p "$NOHERMES"
for t in bash jq cat grep mktemp chmod mv mkdir dirname stat tail cmp sed head tr sort; do ln -sf "$(command -v "$t")" "$NOHERMES/$t" 2>/dev/null || true; done
! DOTFILES_ROOT="$TREE" HERMES_HOME="$TMP/h3" PATH="$NOHERMES" bash "$INSTALL" >"$TMP/nh.out" 2>&1 || fail "install without hermes must fail"
grep -q "hermes not found" "$TMP/nh.out" || fail "missing-hermes message absent"
DOTFILES_ROOT="$TREE" HERMES_HOME="$TMP/h3" PATH="$NOHERMES" bash "$INSTALL" --dry-run >/dev/null 2>&1 || fail "--dry-run must work without hermes"
! inst --dry-run --check >/dev/null 2>&1 || fail "--dry-run and --check together must be rejected"
! inst --bogus >/dev/null 2>&1 || fail "unknown argument must be rejected"
pass "missing hermes fails closed (dry-run still works); bad flags rejected"

echo
echo "[ the real manifest ]"
jq -e '[.jobs[].task] | sort == ["catalog-drift","ci-failure","pr-review"]' "$ROOT/agent/harnesses/hermes/cron/jobs.json" >/dev/null || fail "real manifest should cover the three precheck tasks"
jq -e '.jobs | all(.[]; .prompt | test("Do not"))' "$ROOT/agent/harnesses/hermes/cron/jobs.json" >/dev/null || fail "every real job prompt must state what the agent must not do"
jq -e '.jobs | map(select(.task != "catalog-drift")) | all(.[]; .prompt | test("push") and test("Tier B"))' "$ROOT/agent/harnesses/hermes/cron/jobs.json" >/dev/null || fail "PR / CI prompts must forbid pushing and editing Tier B files"
jq -e '.jobs | map(select(.task == "catalog-drift")) | all(.[]; .prompt | test("--fetch"))' "$ROOT/agent/harnesses/hermes/cron/jobs.json" >/dev/null || fail "the catalog-drift prompt must forbid the fetching updater"
bash "$ROOT/agent/scripts/bot/hermes-cron-install.sh" --dry-run >/dev/null || fail "real manifest dry-run failed"
pass "real manifest: three tasks, every prompt states its prohibitions, dry-run clean"

echo
echo "All Hermes cron installer tests passed"
