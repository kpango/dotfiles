#!/usr/bin/env bash
# Regression tests for agent/scripts/sandbox/gondolin-run.mjs, agent/scripts/bot/precheck-cron.sh
# and the zshenv telemetry/free-model opt-outs (Work Area 6).
# 様式: test-gen-tool-md.sh 準拠 (mktemp -d 隔離 / section() / [OK]・[FAIL] / total_fail 集計)。
# 実 ~/.hermes・実 ~/.local/bin・gh・ネットワークには触れない (PATH 先頭の stub / --dry-run のみ)。
#
# usage: agent/scripts/test-sandbox-precheck.sh
# exit: 0 = 全テストPASS, 1 = 1件以上FAIL
set -uo pipefail

ROOT="$(CDPATH= cd -P -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GR="$ROOT/agent/scripts/sandbox/gondolin-run.mjs"
PC="$ROOT/agent/scripts/bot/precheck-cron.sh"
total_fail=0
section() { echo; echo "=== $1 ==="; }
check() { # check <desc> <cond: 0=pass>
  local desc="$1" cond="$2"
  if [ "$cond" -eq 0 ]; then
    echo "[OK] $desc"
  else
    echo "[FAIL] $desc"
    total_fail=$((total_fail + 1))
  fi
}
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

WORK="$(mktemp -d)"
cleanup() { [ -n "$WORK" ] && [ -d "$WORK" ] && command rm -r -- "$WORK"; }
trap cleanup EXIT

# Pin gondolin resolution so results do not depend on what the host has installed:
# a nonexistent module = "gondolin not installed". Tests that need gondolin override it (gr()).
NOMOD="$WORK/no-such-gondolin-module.mjs"
export GONDOLIN_RUN_MODULE="$NOMOD"

JS=node
command -v node >/dev/null 2>&1 || JS=bun

section "gondolin-run.mjs (fallback path)"
out="$("$JS" "$GR" --check 2>&1)"; rc=$?
check "--check exits 0" "$rc"
contains "$out" "pa-sandbox"; check "--check reports pa-sandbox backend" $?

out="$("$JS" "$GR" --dry-run -- echo hi 2>&1)"; rc=$?
check "--dry-run exits 0" "$rc"
contains "$out" "backend: pa-sandbox"; check "--dry-run names backend" $?
contains "$out" "echo"; check "--dry-run shows command" $?

# stub pa-sandbox: records argv, one per line
STUB="$WORK/pa-stub"
cat >"$STUB" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PA_STUB_OUT"
env >"$PA_STUB_OUT.env"
STUBEOF
chmod +x "$STUB"
export PA_STUB_OUT="$WORK/argv"
SECRET_TOKEN_T12=leak PA_STUB_OUT="$PA_STUB_OUT" GONDOLIN_RUN_ENV_ALLOW=PA_STUB_OUT \
  GONDOLIN_RUN_PA_SANDBOX="$STUB" "$JS" "$GR" -- echo 'a b;$(touch '"$WORK"'/pwned)' >/dev/null 2>&1
rc=$?
check "run via stub exits 0" "$rc"
[ "$(sed -n 1p "$PA_STUB_OUT")" = "--" ]; check "fallback passes -- first" $?
[ "$(sed -n 3p "$PA_STUB_OUT")" = 'a b;$(touch '"$WORK"'/pwned)' ]; check "args kept as one array element (no shell join)" $?
[ ! -e "$WORK/pwned" ]; check "no shell injection" $?
! grep -q SECRET_TOKEN_T12 "$PA_STUB_OUT.env"; check "non-allowlisted env var not forwarded" $?
grep -q '^PATH=' "$PA_STUB_OUT.env"; check "PATH forwarded (allowlist)" $?

"$JS" "$GR" --dry-run >/dev/null 2>&1; [ $? -ne 0 ]; check "no command -> non-zero" $?
GONDOLIN_RUN_PA_SANDBOX="$WORK/missing" PATH="/nonexistent" "$(command -v "$JS")" "$GR" --check >/dev/null 2>&1
[ $? -ne 0 ]; check "no backend at all -> --check non-zero" $?

section "gondolin-run.mjs (gondolin path; STUB-ONLY: no real QEMU/gondolin on this host)"
# Fake @earendil-works/gondolin module: records every call as one JSON line in $GR_FAKE_LOG.
FAKE="$WORK/fake-gondolin.mjs"
cat >"$FAKE" <<'FAKEEOF'
import { appendFileSync } from "node:fs";
const log = (kind, data) => appendFileSync(process.env.GR_FAKE_LOG, `${kind} ${JSON.stringify(data)}\n`);
export function createHttpHooks(opts) {
  log("hooks", opts);
  if (process.env.GR_FAKE_HOOKS_LEAK) throw new Error(`bad hooks ${Object.values(opts.secrets)[0].value}`);
  const env = {};
  for (const k of Object.keys(opts.secrets ?? {})) env[k] = `PLACEHOLDER_${k}`;
  return { httpHooks: { fake: true }, env, secretManager: {} };
}
export class VM {
  static async create(opts) {
    log("create", opts);
    if (process.env.GR_FAKE_CREATE_FAIL) throw new Error(`boom-create ${process.env.TOK ?? ""}`);
    return new VM();
  }
  async exec(argv) {
    log("exec", argv);
    if (process.env.GR_FAKE_EXEC_THROW) throw new Error(`boom-exec ${process.env.TOK ?? ""}`);
    const leak = process.env.GR_FAKE_ECHO_SECRET ? ` ${process.env.TOK}` : "";
    return {
      exitCode: process.env.GR_FAKE_NOEXIT ? undefined : Number(process.env.GR_FAKE_EXIT ?? 0),
      signal: null, ok: true, stdout: `guest-out${leak}\n`, stderr: leak ? `guest-err${leak}\n` : "",
    };
  }
  async close() {
    log("close", {});
    if (process.env.GR_FAKE_CLOSE_FAIL) throw new Error(`boom-close ${process.env.TOK ?? ""}`);
  }
}
FAKEEOF
QBIN="$WORK/qbin"; mkdir -p "$QBIN"
printf '#!/bin/sh\nexit 0\n' >"$QBIN/qemu-system-x86_64"; chmod +x "$QBIN/qemu-system-x86_64"
export GR_FAKE_LOG="$WORK/fake.log"
gr() { PATH="$QBIN:$PATH" GONDOLIN_RUN_ENV_ALLOW=PA_STUB_OUT GONDOLIN_RUN_MODULE="$FAKE" GONDOLIN_RUN_PA_SANDBOX="$STUB" "$JS" "$GR" "$@"; }
reset_log() { : >"$GR_FAKE_LOG"; command rm -f "$PA_STUB_OUT"; }

reset_log
out="$(gr --check 2>&1)"; rc=$?
check "gondolin+qemu: --check exits 0" "$rc"
contains "$out" "backend: gondolin"; check "gondolin+qemu: --check selects gondolin" $?

# deterministic "module present, qemu absent": PATH has no qemu-system-* (empty dir)
NOQ="$WORK/noq"; mkdir -p "$NOQ"
out="$(PATH="$NOQ" GONDOLIN_RUN_MODULE="$FAKE" GONDOLIN_RUN_PA_SANDBOX="$STUB" "$(command -v "$JS")" "$GR" --check 2>&1)"
contains "$out" "detected"; check "module without qemu: reported as detected/unavailable" $?
contains "$out" "backend: pa-sandbox"; check "module without qemu: --check selects pa-sandbox" $?
! contains "$out" "backend: gondolin"; check "module without qemu: gondolin not selected" $?
out="$(gr --check --backend pa-sandbox 2>&1)"
contains "$out" "backend: pa-sandbox"; check "--backend pa-sandbox: --check follows the explicit choice" $?

reset_log
ARGS=(echo 'a b' 'x"y' $'l1\nl2')
out="$(SECRET_TOKEN_T12=leak gr -- "${ARGS[@]}" 2>&1)"; rc=$?
check "gondolin run exits 0" "$rc"
contains "$out" "guest-out"; check "guest stdout forwarded" $?
grep -qxF 'exec ["/bin/sh","-c","exec -- \"$@\"","sh","echo","a b","x\"y","l1\nl2"]' "$GR_FAKE_LOG"; check "argv passed as array (spaces/quotes/newline intact)" $?
grep -q '^hooks {"allowedHosts":\[\]' "$GR_FAKE_LOG"; check "allowedHosts defaults to [] (deny all)" $?
! grep '^create ' "$GR_FAKE_LOG" | grep -q SECRET_TOKEN_T12; check "host env not forwarded to guest" $?
grep -q '^close ' "$GR_FAKE_LOG"; check "vm.close called" $?
[ ! -e "$PA_STUB_OUT" ]; check "pa-sandbox not used when gondolin selected" $?

reset_log
GR_FAKE_EXIT=7 gr -- true >/dev/null 2>&1; [ $? -eq 7 ]; check "guest exit code propagated" $?
grep -q '^close ' "$GR_FAKE_LOG"; check "close called after non-zero exit" $?

reset_log
GR_FAKE_EXEC_THROW=1 gr -- true >/dev/null 2>&1; [ $? -ne 0 ]; check "exec throw -> non-zero" $?
grep -q '^close ' "$GR_FAKE_LOG"; check "close called after exec throw" $?

reset_log
gr --allow-host api.example.com --allow-host b.example.com -- true >/dev/null 2>&1
grep -q '^hooks {"allowedHosts":\["api.example.com","b.example.com"\]' "$GR_FAKE_LOG"; check "--allow-host sets explicit allowedHosts" $?

reset_log
out="$(TOK=sekrit-value gr --secret TOK@h1.example,h2.example -- true 2>&1)"; rc=$?
check "secret run exits 0" "$rc"
grep '^hooks ' "$GR_FAKE_LOG" | grep -q '"TOK":{"hosts":\["h1.example","h2.example"\],"value":"sekrit-value"}'; check "secret read from host env and given to createHttpHooks" $?
! grep '^create ' "$GR_FAKE_LOG" | grep -q sekrit-value; check "secret value absent from VM.create (guest sees placeholder only)" $?
grep '^create ' "$GR_FAKE_LOG" | grep -q PLACEHOLDER_TOK; check "guest env carries placeholder" $?
! contains "$out" "sekrit-value"; check "secret value never printed" $?

reset_log
(unset TOK; gr --secret TOK@h1.example -- true) >/dev/null 2>&1; [ $? -ne 0 ]; check "missing secret env -> non-zero" $?
[ ! -s "$GR_FAKE_LOG" ]; check "missing secret: no VM created" $?

reset_log
out="$(TOK=sekrit-value gr --dry-run --secret TOK@h1.example -- echo hi 2>&1)"; rc=$?
check "gondolin --dry-run exits 0" "$rc"
contains "$out" "backend: gondolin"; check "gondolin --dry-run names backend" $?
! contains "$out" "sekrit-value"; check "dry-run hides secret value" $?
[ ! -s "$GR_FAKE_LOG" ]; check "dry-run creates no VM" $?

reset_log
GR_FAKE_CREATE_FAIL=1 gr -- true >"$WORK/cf.out" 2>"$WORK/cf.err"; rc=$?
[ "$rc" -ne 0 ]; check "VM.create failure -> non-zero" $?
grep -q "pa-sandbox" "$WORK/cf.err"; check "VM.create failure message points to --backend pa-sandbox" $?
[ ! -e "$PA_STUB_OUT" ]; check "VM.create failure does NOT fall back silently" $?

reset_log
gr --backend pa-sandbox -- echo hi >/dev/null 2>&1
[ "$(sed -n 1p "$PA_STUB_OUT")" = "--" ]; check "--backend pa-sandbox forces fallback even if gondolin usable" $?
[ ! -s "$GR_FAKE_LOG" ]; check "--backend pa-sandbox does not touch gondolin" $?

GONDOLIN_RUN_PA_SANDBOX="$STUB" "$JS" "$GR" --backend gondolin --check >/dev/null 2>&1
[ $? -ne 0 ]; check "--backend gondolin without gondolin -> non-zero (no silent fallback)" $?

# --- fail-closed: pa-sandbox gives no egress/secret isolation, so those options must hard-fail ---
reset_log
out="$(TOK=valid-secret-1 gr --backend pa-sandbox --secret TOK@h1.example -- touch "$WORK/ran1" 2>&1)"; rc=$?
[ "$rc" -eq 2 ]; check "pa-sandbox + --secret -> exit 2" $?
[ ! -e "$WORK/ran1" ] && [ ! -e "$PA_STUB_OUT" ]; check "pa-sandbox + --secret: command not run" $?
contains "$out" "egress"; check "pa-sandbox + --secret: message explains missing egress/secret isolation" $?
out="$(gr --backend pa-sandbox --allow-host h1.example -- touch "$WORK/ran2" 2>&1)"; rc=$?
[ "$rc" -eq 2 ]; check "pa-sandbox + --allow-host -> exit 2" $?
[ ! -e "$WORK/ran2" ] && [ ! -e "$PA_STUB_OUT" ]; check "pa-sandbox + --allow-host: command not run" $?
out="$(TOK=valid-secret-1 gr --backend pa-sandbox --dry-run --secret TOK@h1.example -- true 2>&1)"; rc=$?
[ "$rc" -eq 2 ]; check "pa-sandbox + --secret + --dry-run -> exit 2" $?
# auto fallback (no qemu / no module) must fail the same way
out="$(TOK=valid-secret-1 GONDOLIN_RUN_PA_SANDBOX="$STUB" GONDOLIN_RUN_ENV_ALLOW=PA_STUB_OUT "$JS" "$GR" --secret TOK@h1.example -- touch "$WORK/ran3" 2>&1)"; rc=$?
[ "$rc" -eq 2 ]; check "auto fallback to pa-sandbox + --secret -> exit 2" $?
[ ! -e "$WORK/ran3" ] && [ ! -e "$PA_STUB_OUT" ]; check "auto fallback + --secret: command not run" $?
out="$(GONDOLIN_RUN_PA_SANDBOX="$STUB" GONDOLIN_RUN_ENV_ALLOW=PA_STUB_OUT "$JS" "$GR" --allow-host h1.example -- touch "$WORK/ran4" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$WORK/ran4" ] && [ ! -e "$PA_STUB_OUT" ]; check "auto fallback + --allow-host -> exit 2, not run" $?

# leading-dash command must not be parsed as an exec option
reset_log
gr -- -foo >/dev/null 2>&1
grep -qxF 'exec ["/bin/sh","-c","exec -- \"$@\"","sh","-foo"]' "$GR_FAKE_LOG"; check "leading-dash command passed after exec --" $?

# empty / blank --allow-host rejected
reset_log
gr --allow-host "" -- true >/dev/null 2>&1; [ $? -eq 2 ]; check "empty --allow-host -> exit 2" $?
gr --allow-host "   " -- true >/dev/null 2>&1; [ $? -eq 2 ]; check "blank --allow-host -> exit 2" $?
[ ! -s "$GR_FAKE_LOG" ]; check "bad --allow-host: no VM created" $?

# gondolin --dry-run applies the same secret env check as a real run
reset_log
(unset TOK; gr --dry-run --secret TOK@h1.example -- true) >/dev/null 2>&1; [ $? -ne 0 ]; check "gondolin --dry-run with unset secret env -> non-zero" $?

# --- attempt 4: secret scrubbing, close failure, --check parity, secret name/host validation ---
reset_log
out="$(TOK=sekrit-value GR_FAKE_CREATE_FAIL=1 gr --secret TOK@h1.example -- true 2>&1)"; rc=$?
[ "$rc" -ne 0 ]; check "VM.create failure with secret in error -> non-zero" $?
! contains "$out" "sekrit-value"; check "VM.create error text: secret value scrubbed" $?
contains "$out" "***"; check "VM.create error text: placeholder *** shown" $?
out="$(TOK=sekrit-value GR_FAKE_HOOKS_LEAK=1 gr --secret TOK@h1.example -- true 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ! contains "$out" "sekrit-value"; check "createHttpHooks error text: secret value scrubbed" $?
out="$(TOK=sekrit-value GR_FAKE_EXEC_THROW=1 gr --secret TOK@h1.example -- true 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ! contains "$out" "sekrit-value"; check "exec error text: secret value scrubbed" $?

reset_log
out="$(TOK=sekrit-value GR_FAKE_CLOSE_FAIL=1 GR_FAKE_EXIT=7 gr --secret TOK@h1.example -- true 2>&1)"; rc=$?
[ "$rc" -eq 7 ]; check "close failure keeps the exec exit code (7)" $?
! contains "$out" "sekrit-value"; check "close warning: secret scrubbed" $?
! contains "$out" "    at "; check "close failure: no stack trace" $?
[ "$(printf '%s\n' "$out" | grep -c 'close')" -eq 1 ]; check "close failure: exactly one warning line" $?

out="$(gr --backend pa-sandbox --check --secret SECV@a 2>&1)"; rc=$?
[ "$rc" -eq 2 ]; check "--check: pa-sandbox + --secret -> exit 2 (same as run)" $?
out="$(gr --backend pa-sandbox --check --allow-host a.example 2>&1)"; rc=$?
[ "$rc" -eq 2 ]; check "--check: pa-sandbox + --allow-host -> exit 2" $?
GONDOLIN_RUN_PA_SANDBOX="$STUB" "$JS" "$GR" --check --secret SECV@a >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ]; check "--check: auto falls back to pa-sandbox + --secret -> exit 2" $?
(export SECV=valid-secret-1; gr --check --secret SECV@a) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ]; check "--check: gondolin selected + --secret with env set -> exit 0" $?

out="$(env -u GONDOLIN_RUN_MODULE -u GONDOLIN_RUN_PA_SANDBOX "$JS" "$GR" --check 2>&1)"
! contains "$out" "overridden (test hook)"; check "--check: no override note without test hooks" $?
out="$(gr --check 2>&1)"
contains "$out" "overridden (test hook)"; check "--check: override note when test hooks are set" $?

reset_log
for bad in __proto__ constructor prototype; do
  (export "$bad=valid-secret-1"; gr --secret "$bad@evil.example" -- true) >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ]; check "reserved secret name $bad rejected (exit 2)" $?
done
TOK=valid-secret-1 gr --secret TOK@a.example --secret TOK@b.example -- true >/dev/null 2>&1; [ $? -eq 2 ]; check "duplicate secret name rejected" $?
[ ! -s "$GR_FAKE_LOG" ]; check "invalid secret options: no VM created" $?
for bad in '*' 'a.example*' 'a.*.com' '*.' '*.*'; do
  TOK=valid-secret-1 gr --secret "TOK@$bad" -- true >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ]; check "secret host '$bad' rejected (exit 2)" $?
done
TOK=valid-secret-1 gr --secret 'TOK@*.example.com' -- true >/dev/null 2>&1; [ $? -eq 0 ]; check "secret host '*.example.com' accepted" $?

# --- attempt 5 ---
(unset SECV; gr --check --secret SECV@a) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ]; check "--check: gondolin + unset secret env -> exit 2 (same as run)" $?
(export SECV=; gr --check --secret SECV@a) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ]; check "--check: gondolin + empty secret env -> exit 2" $?
out="$(unset SECV; gr --check --secret SECV@a 2>&1)"
! contains "$out" "backend: gondolin"; check "--check: no 'backend:' success line when the secret check fails" $?

no_echo() { # no_echo <desc> <args...>: must exit 2 and never print the mistaken secret text
  local desc="$1" o r
  shift
  o="$(gr "$@" -- true 2>&1)"; r=$?
  [ "$r" -eq 2 ] && ! contains "$o" SECRETVAL123; check "$desc" $?
}
no_echo "bad --secret NAME=value: value not echoed" --secret TOKEN=SECRETVAL123@h
no_echo "--secret=VALUE (unknown option): not echoed" --secret=SECRETVAL123
no_echo "unknown option: not echoed" --SECRETVAL123
no_echo "unknown backend: not echoed" --backend SECRETVAL123
no_echo "bad secret host: not echoed" --secret 'SECRETVAL123@a*'
no_echo "unset secret env: name not echoed" --secret SECRETVAL123@h
no_echo "duplicate secret: name not echoed" --secret SECRETVAL123@h --secret SECRETVAL123@h
no_echo "reserved secret name: not echoed" --secret '__proto__@SECRETVAL123*'

# scrub: longest value first; guest output scrubbed too
reset_log
out="$(SHORTV=abcd TOK=abcdXYZ-long-tail GR_FAKE_CREATE_FAIL=1 gr --secret SHORTV@h1.example --secret TOK@h1.example -- true 2>&1)"
! contains "$out" "XYZ-long-tail"; check "scrub replaces longer secret first (no suffix of the longer value leaks)" $?
reset_log
out="$(TOK=valid-secret-1 GR_FAKE_ECHO_SECRET=1 gr --secret TOK@h1.example -- true 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ! contains "$out" "valid-secret-1" && contains "$out" "guest-out ***" && contains "$out" "guest-err ***"; check "guest stdout/stderr scrubbed" $?
# short values are refused (not credible secrets; scrubbing them would over-replace)
reset_log
(export TOK=abc; gr --secret TOK@h1.example -- true) >/dev/null 2>&1; [ $? -eq 2 ]; check "secret value shorter than 4 chars -> exit 2" $?
[ ! -s "$GR_FAKE_LOG" ]; check "short secret: no VM created" $?
(export TOK=abcd; gr --secret TOK@h1.example -- true) >/dev/null 2>&1; [ $? -eq 0 ]; check "secret value of 4 chars accepted" $?

# guest exit code normalisation
for v in 256 -1 1.5 abc 1000; do
  out="$(GR_FAKE_EXIT=$v gr -- true 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] && contains "$out" "unexpected exit code from guest" && ! contains "$out" "$v"; check "guest exit '$v' -> exit 1 + notice, value not printed" $?
done
GR_FAKE_EXIT=255 gr -- true >/dev/null 2>&1; [ $? -eq 255 ]; check "guest exit 255 passed through" $?
GR_FAKE_NOEXIT=1 gr -- true >/dev/null 2>&1; [ $? -eq 128 ]; check "guest exit code missing -> 128 (unchanged)" $?

# option values must not swallow the next option; TLD-wide wildcard; Object.prototype names
reset_log
gr --allow-host --check -- true >/dev/null 2>&1; [ $? -eq 2 ]; check "--allow-host followed by an option -> exit 2" $?
gr --secret --check -- true >/dev/null 2>&1; [ $? -eq 2 ]; check "--secret followed by an option -> exit 2" $?
[ ! -s "$GR_FAKE_LOG" ]; check "option-as-value: no VM created" $?
TOK=valid-secret-1 gr --secret 'TOK@*.com' -- true >/dev/null 2>&1; [ $? -eq 2 ]; check "secret host '*.com' (TLD-wide) rejected" $?
TOK=valid-secret-1 gr --secret 'TOK@*.io' -- true >/dev/null 2>&1; [ $? -eq 2 ]; check "secret host '*.io' (TLD-wide) rejected" $?
# --- attempt 6 ---
# gondolin --dry-run: every printed line is scrubbed (argv and --allow-host both hold the secret value)
reset_log
out="$(TOK=supersecret123 gr --dry-run --secret TOK@api.example.com --allow-host supersecret123 -- curl -H 'Auth: supersecret123' 2>&1)"; rc=$?
[ "$rc" -eq 0 ]; check "gondolin --dry-run with secret in argv/allow-host exits 0" $?
! contains "$out" "supersecret123"; check "gondolin --dry-run output never contains the secret value" $?
contains "$out" 'Auth: ***'; check "gondolin --dry-run: command line shows *** in place of the value" $?
contains "$out" 'allowed hosts: ["***"]'; check "gondolin --dry-run: allowed hosts line scrubbed" $?
contains "$out" "backend: gondolin"; check "gondolin --dry-run still names the backend" $?
[ ! -s "$GR_FAKE_LOG" ]; check "gondolin --dry-run (scrub case) creates no VM" $?

# --allow-host wildcards: same rule as --secret hosts
for bad in '*' '*.com' '*.io' 'a.*.com' 'SECRETVAL123*'; do
  out="$(gr --allow-host "$bad" -- true 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] && contains "$out" "--allow-host #1" && ! contains "$out" SECRETVAL123 && ! contains "$out" "$bad"; check "--allow-host '$bad' rejected (exit 2, position only in message)" $?
done
out="$(gr --allow-host ok.example --allow-host '*' -- true 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && contains "$out" "--allow-host #2"; check "--allow-host '*' as 2nd value reports position #2" $?
[ ! -s "$GR_FAKE_LOG" ]; check "rejected --allow-host: no VM created" $?
reset_log
gr --allow-host '*.example.com' -- true >/dev/null 2>&1; [ $? -eq 0 ]; check "--allow-host '*.example.com' accepted" $?
grep -q '^hooks {"allowedHosts":\["\*.example.com"\]' "$GR_FAKE_LOG"; check "--allow-host '*.example.com' reaches createHttpHooks" $?

# --- attempt 7 ---
# dry-run scrub must also hold for values that JSON.stringify would escape (quote, backslash, newline, tab)
vals=('pa"ss1234' 'pa\ss1234' $'pa\nss1234' $'pa\tss1234')
escs=('pa\"ss1234' 'pa\\ss1234' 'pa\nss1234' 'pa\tss1234')
names=(quote backslash newline tab)
for i in 0 1 2 3; do
  v="${vals[$i]}"; e="${escs[$i]}"
  reset_log
  out="$(TOK="$v" gr --dry-run --secret TOK@api.example.com -- curl -H "X: $v" "$v" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ]; check "dry-run with ${names[$i]}-bearing secret exits 0" $?
  ! contains "$out" "$v" && ! contains "$out" "$e"; check "dry-run: ${names[$i]}-bearing secret absent in raw and JSON-escaped form" $?
  contains "$out" '***'; check "dry-run: ${names[$i]}-bearing secret shown as ***" $?
  out="$(TOK="$v" gr --dry-run --secret TOK@api.example.com --allow-host "$v" -- true 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] && ! contains "$out" "$v" && ! contains "$out" "$e"; check "--allow-host holding a ${names[$i]}-bearing value: rejected, value not echoed" $?
done

# host grammar (both --allow-host and --secret hosts): ASCII host, optional leading wildcard label, optional :port
bads=('＊.com' '*.a. .com' '*.%2a.com' '*.рф' 'bare com' 'a/b.com' 'a.com/path' '*.a.com:abc' 'a.com:99999' ':443' 'a..com' '*.com:443' 'ex%61mple.com' 'ex.com.')
for bad in "${bads[@]}"; do
  out="$(gr --allow-host "$bad" -- true 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] && contains "$out" "--allow-host #1" && ! contains "$out" "$bad"; check "--allow-host '$bad' rejected (position only)" $?
  out="$(TOK=valid-secret-1 gr --secret "TOK@$bad" -- true 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] && contains "$out" "--secret #1" && ! contains "$out" "$bad"; check "--secret host '$bad' rejected (position only)" $?
done
for ok in example.com '*.example.com' api.example.com:443 '*.a.com:443' localhost; do
  reset_log
  gr --allow-host "$ok" -- true >/dev/null 2>&1; [ $? -eq 0 ]; check "--allow-host '$ok' accepted" $?
  TOK=valid-secret-1 gr --secret "TOK@$ok" -- true >/dev/null 2>&1; [ $? -eq 0 ]; check "--secret host '$ok' accepted" $?
done

# --check: every line scrubbed (path and qemu name carry the secret), after the fail-closed checks
mkdir -p "$WORK/sekr1234" "$WORK/qs"
cp "$STUB" "$WORK/sekr1234/pa"
printf '#!/bin/sh\nexit 0\n' >"$WORK/qs/qemu-system-sekr1234"; chmod +x "$WORK/qs/qemu-system-sekr1234"
out="$(TOK=sekr1234 PATH="$WORK/qs:$PATH" GONDOLIN_RUN_MODULE="$FAKE" GONDOLIN_RUN_PA_SANDBOX="$WORK/sekr1234/pa" "$JS" "$GR" --check --secret TOK@h.example 2>&1)"; rc=$?
[ "$rc" -eq 0 ]; check "--check with secret-bearing path/qemu name exits 0" $?
! contains "$out" "sekr1234"; check "--check output never contains the secret value" $?
contains "$out" "/***/pa" && contains "$out" "qemu-system-***"; check "--check: path and qemu name lines show ***" $?
contains "$out" "backend: gondolin"; check "--check still names the backend" $?
out="$(unset TOK; PATH="$WORK/qs:$PATH" GONDOLIN_RUN_MODULE="$FAKE" GONDOLIN_RUN_PA_SANDBOX="$WORK/sekr1234/pa" "$JS" "$GR" --check --secret TOK@h.example 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ! contains "$out" "available (" && ! contains "$out" "backend:"; check "--check: secret check runs before any output (nothing printed on failure)" $?

for bad in PA_SANDBOX_PASS_ENV PA_SANDBOX_ALLOW_NO_GUARD PA_SANDBOX_ALLOW_HOST_PROC GONDOLIN_RUN_PA_SANDBOX GONDOLIN_RUN_MODULE; do
  reset_log
  PA_STUB_OUT="$PA_STUB_OUT" GONDOLIN_RUN_ENV_ALLOW="PA_STUB_OUT,$bad" GONDOLIN_RUN_PA_SANDBOX="$STUB" "$JS" "$GR" -- touch "$WORK/ran5" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && [ ! -e "$WORK/ran5" ] && [ ! -e "$PA_STUB_OUT" ]; check "GONDOLIN_RUN_ENV_ALLOW naming $bad -> exit 2, command not run" $?
done
PA_STUB_OUT="$PA_STUB_OUT" GONDOLIN_RUN_ENV_ALLOW="PA_STUB_OUT" GONDOLIN_RUN_PA_SANDBOX="$STUB" "$JS" "$GR" -- true >/dev/null 2>&1; [ $? -eq 0 ]; check "GONDOLIN_RUN_ENV_ALLOW with an ordinary name still works" $?
for bad in toString hasOwnProperty valueOf isPrototypeOf; do
  (export "$bad=valid-secret-1"; gr --secret "$bad@a.example" -- true) >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ]; check "secret name $bad (Object.prototype) rejected" $?
done

section "precheck-cron.sh"
bash -n "$PC"; check "bash -n" $?
BIN="$WORK/bin"; mkdir -p "$BIN"
mk_gh() { # mk_gh <stdout> <rc>; `gh repo view` answers "main", everything else prints <stdout>
  printf '#!/usr/bin/env bash\nif [ "${1:-}" = auth ]; then exit 0; fi\nif [ "${1:-}" = repo ]; then [ "${GH_STUB_REPO_FAIL:-0}" = 1 ] && exit 1; [ "${GH_STUB_REPO_EMPTY:-0}" = 1 ] && { echo; exit 0; }; echo main; exit 0; fi\nprintf "%%s\\n" "%s"\nexit %s\n' "$1" "$2" >"$BIN/gh"
  chmod +x "$BIN/gh"
}
mk_catalog() { # mk_catalog <rc> [stderr text]
  {
    printf 'import sys\n'
    [ -n "${2:-}" ] && printf 'sys.stderr.write(%s)\n' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1] + "\n"))' "$2")"
    printf 'sys.exit(%s)\n' "$1"
  } >"$WORK/cat.py"
}
mk_catalog 0
export PRECHECK_CATALOG_SCRIPT="$WORK/cat.py"
run_pc() { PATH="$BIN:$PATH" bash "$PC" "$@"; }

mk_gh 0 0
out="$(run_pc --task pr-review --json)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = '{"action_required": false}' ]; check "no events -> {\"action_required\": false}, exit 0" $?

mk_gh 2 0
out="$(run_pc --task pr-review --json)"; rc=$?
[ "$rc" -eq 0 ]; check "events -> exit 0" $?
contains "$out" '"action_required": true'; check "events -> action_required true" $?

mk_gh "boom" 1
out="$(run_pc --task ci-failure --json 2>/dev/null)"; rc=$?
[ "$rc" -eq 3 ]; check "gh failure -> exit 3" $?
contains "$out" '"action_required": null'; check "gh failure -> null, not false" $?
! contains "$out" '"action_required": false'; check "gh failure never reports false" $?

# gh missing: PATH has only the tools the script needs, without gh
NOGH="$WORK/nogh"; mkdir -p "$NOGH"
for t in bash env python3 sed cat date timeout; do p="$(command -v "$t")" && ln -sf "$p" "$NOGH/$t"; done
out="$(PATH="$NOGH" bash "$PC" --task pr-review --json 2>/dev/null)"; rc=$?
[ "$rc" -eq 3 ] && contains "$out" '"action_required": null' && contains "$out" "gh not installed"; check "gh absent -> exit 3 + null + reason" $?

mk_gh failure 0
out="$(run_pc --task ci-failure --json)"; rc=$?
[ "$rc" -eq 0 ] && contains "$out" '"action_required": true'; check "latest default-branch run failed -> true" $?
mk_gh success 0
out="$(run_pc --task ci-failure --json)"
[ "$out" = '{"action_required": false}' ]; check "latest default-branch run succeeded -> false" $?
mk_gh "" 0
out="$(run_pc --task ci-failure --json)"
[ "$out" = '{"action_required": false}' ]; check "no completed run -> false" $?
# a gh stub that records its args: ci-failure must query only the default branch, 1 completed run
printf '#!/usr/bin/env bash\nif [ "${1:-}" = auth ]; then exit 0; fi\nif [ "${1:-}" = repo ]; then echo main; exit 0; fi\nprintf "%%s\\n" "$*" >>"%s/gh-args"\necho success\n' "$WORK" >"$BIN/gh"; chmod +x "$BIN/gh"
run_pc --task ci-failure --json >/dev/null
grep -q -- '--branch main' "$WORK/gh-args" && grep -q -- '--status completed' "$WORK/gh-args" && grep -q -- '--limit 1' "$WORK/gh-args"; check "ci-failure queries latest completed run on default branch" $?
mk_gh failure 0
out="$(GH_STUB_REPO_FAIL=1 run_pc --task ci-failure --json 2>/dev/null)"; rc=$?
[ "$rc" -eq 3 ] && contains "$out" '"action_required": null'; check "default-branch lookup failure -> exit 3 + null, not false" $?

mk_gh failure 0
out="$(GH_STUB_REPO_EMPTY=1 run_pc --task ci-failure --json 2>/dev/null)"; rc=$?
[ "$rc" -eq 3 ] && contains "$out" '"action_required": null' && ! contains "$out" '"action_required": true'; check "empty default branch name -> exit 3 + null (never true from another branch)" $?

for c in timed_out startup_failure; do
  mk_gh "$c" 0
  out="$(run_pc --task ci-failure --json)"
  contains "$out" '"action_required": true'; check "latest run $c -> true" $?
done
mk_gh cancelled 0
out="$(run_pc --task ci-failure --json)"
[ "$out" = '{"action_required": false}' ]; check "latest run cancelled -> false" $?

# (1) target repo is the dotfiles repo regardless of caller cwd
printf '#!/usr/bin/env bash\nif [ "${1:-}" = auth ]; then exit 0; fi\npwd -P >>"%s/gh-cwd"\nif [ "${1:-}" = repo ]; then echo main; else echo 0; fi\n' "$WORK" >"$BIN/gh"; chmod +x "$BIN/gh"
mkdir -p "$WORK/elsewhere"
(cd "$WORK/elsewhere" && run_pc --task all --json >/dev/null 2>&1)
[ -s "$WORK/gh-cwd" ] && [ "$(sort -u "$WORK/gh-cwd")" = "$ROOT" ]; check "gh runs with cwd = dotfiles repo root, not the caller's cwd" $?

# script outside a dotfiles checkout: ROOT cannot be established -> error, never a silent false
mkdir -p "$WORK/stray/a/b"; cp "$PC" "$WORK/stray/a/b/precheck-cron.sh"
out="$(PATH="$BIN:$PATH" bash "$WORK/stray/a/b/precheck-cron.sh" --task pr-review --json 2>/dev/null)"; rc=$?
[ "$rc" -eq 3 ] && contains "$out" '"action_required": null'; check "ROOT not a dotfiles checkout -> exit 3 + null" $?

# (2) timeout: a hung gh is "could not check", not a hang
printf '#!/usr/bin/env bash\nif [ "${1:-}" = auth ]; then exec sleep 5; fi\necho 0\n' >"$BIN/gh"; chmod +x "$BIN/gh"
start=$SECONDS
out="$(PRECHECK_TIMEOUT=1 run_pc --task pr-review --json 2>/dev/null)"; rc=$?
[ "$rc" -eq 3 ] && contains "$out" '"action_required": null' && contains "$out" "timed out"; check "hung gh -> timed out, exit 3 + null" $?
[ $((SECONDS - start)) -lt 4 ]; check "hung gh does not block beyond the timeout" $?
printf '#!/usr/bin/env python3\nimport time\ntime.sleep(5)\n' >"$WORK/slow.py"
out="$(PRECHECK_TIMEOUT=1 PRECHECK_CATALOG_SCRIPT="$WORK/slow.py" run_pc --task catalog-drift --json 2>/dev/null)"; rc=$?
[ "$rc" -eq 3 ] && contains "$out" '"action_required": null' && contains "$out" "timed out"; check "hung catalog script -> timed out, exit 3 + null" $?

# (4) confirmed hits survive a partial failure
mk_gh boom 1
mk_catalog 1 "FAIL: drift: /x/models.yml"
out="$(run_pc --task all --json 2>/dev/null)"; rc=$?
[ "$rc" -eq 3 ] && contains "$out" '"action_required": null' && contains "$out" '"tasks": ["catalog-drift"]' && contains "$out" '"error"'; check "partial failure: null + exit 3 but confirmed hit kept in tasks" $?

# (5) dry-run JSON is valid even with quotes in the catalog path
out="$(PRECHECK_CATALOG_SCRIPT='/tmp/a"b\c.py' run_pc --task all --dry-run --json)"
printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)'; check "--dry-run JSON parses with special chars in path" $?

mk_catalog 1 "FAIL: drift: /x/models.yml"
out="$(run_pc --task catalog-drift --json)"; rc=$?
[ "$rc" -eq 0 ] && contains "$out" '"action_required": true'; check "catalog drift -> true" $?
mk_catalog 0
out="$(run_pc --task catalog-drift --json)"
[ "$out" = '{"action_required": false}' ]; check "catalog in sync -> false" $?

mk_gh 0 0
out="$(run_pc --task all --json)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = '{"action_required": false}' ]; check "all, no events -> false" $?

# dry-run must not call gh
printf '#!/usr/bin/env bash\ntouch "%s/gh-called"\nexit 0\n' "$WORK" >"$BIN/gh"; chmod +x "$BIN/gh"
out="$(run_pc --task all --dry-run --json)"; rc=$?
[ "$rc" -eq 0 ]; check "--dry-run exits 0" $?
[ ! -e "$WORK/gh-called" ]; check "--dry-run does not invoke gh" $?
contains "$out" '"dry_run": true'; check "--dry-run flagged in JSON" $?

run_pc --task bogus >/dev/null 2>&1; [ $? -eq 2 ]; check "unknown task -> exit 2" $?

# --- attempt 4 ---
# GH_REPO / GH_HOST from the caller must not redirect gh
printf '#!/usr/bin/env bash\nif [ "${1:-}" = auth ]; then exit 0; fi\nprintf "%%s|%%s|%%s|%%s\\n" "${GH_REPO-unset}" "${GH_HOST-unset}" "${GIT_DIR-unset}" "${GIT_WORK_TREE-unset}" >>"%s/gh-env"\nif [ "${1:-}" = repo ]; then echo main; else echo 0; fi\n' "$WORK" >"$BIN/gh"; chmod +x "$BIN/gh"
GH_REPO=evil/x GH_HOST=evil.example GIT_DIR=/evil/.git GIT_WORK_TREE=/evil run_pc --task all --json >/dev/null 2>&1
[ -s "$WORK/gh-env" ] && [ "$(sort -u "$WORK/gh-env")" = "unset|unset|unset|unset" ]; check "GH_REPO/GH_HOST/GIT_DIR/GIT_WORK_TREE from the caller are unset before calling gh" $?

# JSON stays valid with control characters
out="$(PRECHECK_CATALOG_SCRIPT=$'/a\nb\tc\001d\\e"f' run_pc --task all --dry-run --json)"
printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)'; check "--dry-run JSON valid with control chars in value" $?
mkdir -p "$WORK/stray2/a/b"; cp "$PC" "$WORK/stray2/a/b/pre"$'\n'$'\001'"cron.sh"
out="$(PATH="$BIN:$PATH" bash "$WORK/stray2/a/b/pre"$'\n'$'\001'"cron.sh" --task pr-review --json 2>/dev/null)"; rc=$?
[ "$rc" -eq 3 ] && printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["action_required"] is None'; check "fail_null JSON valid with control chars in script path" $?

# PRECHECK_TIMEOUT validation
for bad in 0 abc -5 1.5 007x; do
  PRECHECK_TIMEOUT="$bad" run_pc --task pr-review --json >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ]; check "PRECHECK_TIMEOUT='$bad' rejected (exit 2)" $?
done

# oversized gh count must be an error, not a silent false
mk_gh 99999999999999999999999 0
out="$(run_pc --task pr-review --json 2>/dev/null)"; rc=$?
[ "$rc" -eq 3 ] && contains "$out" '"action_required": null'; check "oversized gh count -> exit 3 + null" $?

# CDPATH must not influence ROOT resolution
mk_gh 0 0
mkdir -p "$WORK/cdp/bot"
out="$(cd "$ROOT/agent/scripts" && PATH="$BIN:$PATH" CDPATH="$WORK/cdp" bash bot/precheck-cron.sh --task pr-review --json 2>/dev/null)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = '{"action_required": false}' ]; check "exported CDPATH does not break ROOT resolution" $?

# catalog exit 1: only a drift marker means drift
mk_catalog 1 "FAIL: drift: /x/models.yml"
out="$(run_pc --task catalog-drift --json)"; rc=$?
[ "$rc" -eq 0 ] && contains "$out" '"tasks": ["catalog-drift"]'; check "catalog exit 1 + drift marker -> true" $?
mk_catalog 1 "FAIL: missing: /x/derived.json"
out="$(run_pc --task catalog-drift --json)"
contains "$out" '"action_required": true'; check "catalog exit 1 + missing-derived marker -> true" $?
mk_catalog 1 "FAIL: validation error:
bad schema"
out="$(run_pc --task catalog-drift --json 2>/dev/null)"; rc=$?
[ "$rc" -eq 3 ] && contains "$out" '"action_required": null' && ! contains "$out" '"action_required": true'; check "catalog exit 1 + validation error only -> exit 3 + null" $?
mk_catalog 1 "Traceback (most recent call last):
RuntimeError: boom"
out="$(run_pc --task catalog-drift --json 2>/dev/null)"; rc=$?
[ "$rc" -eq 3 ] && contains "$out" '"action_required": null'; check "catalog exit 1 + uncaught exception -> exit 3 + null" $?
mk_catalog 1 "FAIL: catalog not found: /x"
out="$(run_pc --task catalog-drift --json 2>/dev/null)"; rc=$?
[ "$rc" -eq 3 ]; check "catalog exit 1 + not found -> exit 3" $?
mk_catalog 0

grep -q 'timeout -k 5' "$PC"; check "gh/python3 calls use timeout -k 5" $?

section "zshenv"
[ "$(grep -c '^export DO_NOT_TRACK=1$' "$ROOT/zshenv")" -eq 1 ]; check "DO_NOT_TRACK=1 exported exactly once" $?
[ "$(grep -c '^export OPENCODE_DISABLE_FREE_MODELS=1$' "$ROOT/zshenv")" -eq 1 ]; check "OPENCODE_DISABLE_FREE_MODELS=1 exported exactly once" $?
! grep -n '[[:space:]]$' "$ROOT/zshenv" >/dev/null; check "zshenv has no trailing whitespace" $?

echo
echo "---"
if [ "$total_fail" -gt 0 ]; then
  echo "test-sandbox-precheck: $total_fail 件のFAILあり"
  exit 1
fi
echo "test-sandbox-precheck: 全テストPASS"
exit 0
