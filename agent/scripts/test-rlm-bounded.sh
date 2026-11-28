#!/usr/bin/env bash
# Test rlm-bounded.py: depth cap fail-closed, chunked Map-Reduce (stub backend), ledger JSONL + permissions
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RLM="${RLM_BOUNDED_PATH:-$ROOT/agent/scripts/rlm/rlm-bounded.py}"

TMP="$(cd -P "$(mktemp -d)" && pwd)"
trap 'find "$TMP" -delete' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}
pass() { echo "PASS: $1"; }

# expect_fail <label> <cmd...>: command must exit non-zero
expect_fail() {
    local label="$1"
    shift
    if "$@" >"$TMP/out" 2>"$TMP/err"; then
        fail "$label (expected non-zero exit)"
    fi
    pass "$label"
}

run() { timeout 60 python3 -I -B "$RLM" "$@"; }

# run_raw: like run, but an arg written as "hex:<bytes>" is passed as those raw bytes. The bytes go
# from python's subprocess straight to the script's argv, so no coreutils `timeout` (GNU or uutils,
# whose argv handling for non-UTF-8 differs) and no locale is involved.
run_raw() {
    python3 -I -B -c '
import subprocess, sys
a = [bytes.fromhex(x[4:]) if x.startswith("hex:") else x for x in sys.argv[2:]]
sys.exit(subprocess.run([sys.executable, "-I", "-B", sys.argv[1], *a], timeout=60).returncode)
' "$RLM" "$@"
}

echo "=== RLM Bounded Analyzer Validation ==="

# ~200 KiB context, 4000 lines, 1 in 100 lines contains NEEDLE (=> 40 hits)
python3 -I -B - "$TMP/big.log" <<'PY'
import sys
with open(sys.argv[1], "w") as f:
    for i in range(4000):
        f.write(f"line {i} " + ("NEEDLE found here" if i % 100 == 0 else "ordinary content") + " " + "x" * 30 + "\n")
PY
: >"$TMP/empty.log"
printf 'abc\0def\n' >"$TMP/bin.dat"

export RLM_BACKEND=stub

echo
echo "[ Fail-Closed depth cap ]"
L0="$TMP/ledger-depth"
expect_fail "--max-depth 2 rejected" run --query NEEDLE --context-file "$TMP/big.log" --max-depth 2 --ledger-dir "$L0"
grep -qi "max-depth" "$TMP/err" || fail "depth error message missing"
[ ! -e "$L0/rlm-trace.jsonl" ] || fail "ledger written despite depth rejection (LLM path must not run)"
expect_fail "--max-depth 0 rejected" run --query NEEDLE --context-file "$TMP/big.log" --max-depth 0 --ledger-dir "$L0"
expect_fail "--max-depth abc rejected" run --query NEEDLE --context-file "$TMP/big.log" --max-depth abc --ledger-dir "$L0"

echo
echo "[ Chunked Map-Reduce (stub backend) ]"
L1="$TMP/ledger-ok"
run --query NEEDLE --context-file "$TMP/big.log" --chunk-bytes 16384 --max-chunks 64 --ledger-dir "$L1" --json >"$TMP/res.json"
python3 -I -B - "$TMP/res.json" <<'PY' || fail "map-reduce result mismatch"
import json, sys
r = json.load(open(sys.argv[1]))
assert r["chunks"] > 1, r
assert r["total_hits"] == 40, r
assert r["depth"] == 1 and r["dry_run"] is False, r
PY
pass "multi-chunk map-reduce found 40 hits"

echo
echo "[ Ledger JSONL + permissions ]"
LF="$L1/rlm-trace.jsonl"
[ -f "$LF" ] || fail "ledger file missing"
[ "$(stat -c %a "$L1")" = "700" ] || fail "ledger dir mode $(stat -c %a "$L1") != 700"
[ "$(stat -c %a "$LF")" = "600" ] || fail "ledger file mode $(stat -c %a "$LF") != 600"
pass "ledger dir 0700 / file 0600"
python3 -I -B - "$LF" <<'PY' || fail "ledger content invalid"
import json, sys
lines = open(sys.argv[1]).read().splitlines()
assert len(lines) == 1, lines
e = json.loads(lines[0])
for k in ("timestamp", "depth", "chunks", "model", "query_sha256"):
    assert k in e, k
assert e["model"] == "deepseek-v4.1-flash" and e["depth"] == 1
raw = lines[0]
assert "NEEDLE" not in raw and "ordinary content" not in raw, "context/query leaked into ledger"
PY
pass "ledger entry has required fields, no context/query body"
run --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$L1" --dry-run >/dev/null
[ "$(wc -l <"$LF")" = "2" ] || fail "ledger not appended"
pass "ledger append (dry-run)"

echo
echo "[ Dry-run makes no backend calls ]"
RLM_BACKEND=fail run --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$L1" --dry-run --json >"$TMP/dry.json" ||
    fail "dry-run must not invoke backend"
pass "dry-run independent of backend"

echo
echo "[ Edge cases ]"
expect_fail "max-chunks exceeded is fail-closed" run --query NEEDLE --context-file "$TMP/big.log" --chunk-bytes 1024 --max-chunks 2 --ledger-dir "$TMP/l2"
grep -qi "max-chunks" "$TMP/err" || fail "max-chunks error message missing"
expect_fail "missing file rejected" run --query NEEDLE --context-file "$TMP/nope" --ledger-dir "$TMP/l3"
expect_fail "empty file rejected" run --query NEEDLE --context-file "$TMP/empty.log" --ledger-dir "$TMP/l3"
expect_fail "binary file rejected" run --query NEEDLE --context-file "$TMP/bin.dat" --ledger-dir "$TMP/l3"
expect_fail "no backend configured rejected" env -u RLM_BACKEND python3 -I -B "$RLM" --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$TMP/l3"
grep -qi "backend" "$TMP/err" || fail "backend error message missing"

echo
echo "[ Ledger symlink safety ]"
# ledger-dir is a symlink: must be rejected, target untouched
mkdir -m 755 "$TMP/sl-target"
ln -s "$TMP/sl-target" "$TMP/sl-dir"
expect_fail "symlink ledger-dir rejected" run --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$TMP/sl-dir"
[ "$(stat -c %a "$TMP/sl-target")" = "755" ] || fail "symlink target dir mode changed to $(stat -c %a "$TMP/sl-target")"
[ ! -e "$TMP/sl-target/rlm-trace.jsonl" ] || fail "ledger written through symlinked dir"
pass "symlink ledger-dir target untouched"

# ledger file is a pre-planted symlink: must be rejected, victim untouched
mkdir -m 700 "$TMP/sf-dir"
printf 'orig\n' >"$TMP/victim"
chmod 644 "$TMP/victim"
ln -s "$TMP/victim" "$TMP/sf-dir/rlm-trace.jsonl"
expect_fail "symlink ledger file rejected" run --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$TMP/sf-dir"
[ "$(stat -c %a "$TMP/victim")" = "644" ] || fail "victim mode changed to $(stat -c %a "$TMP/victim")"
[ "$(cat "$TMP/victim")" = "orig" ] || fail "victim content modified"
pass "symlink ledger file target untouched"

# ledger-dir is an existing regular file: clean error, no traceback
: >"$TMP/regular-file"
expect_fail "regular-file ledger-dir rejected" run --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$TMP/regular-file"
! grep -q Traceback "$TMP/err" || fail "traceback leaked for regular-file ledger-dir"
grep -qi "ledger" "$TMP/err" || fail "ledger error message missing"
pass "regular-file ledger-dir: clean error"

echo
echo "[ Input validation ]"
expect_fail "invalid UTF-8 query rejected" run_raw --query hex:fffe --context-file "$TMP/big.log" --ledger-dir "$TMP/l4"
! grep -q Traceback "$TMP/err" || fail "traceback leaked for invalid UTF-8 query"
grep -qi "query" "$TMP/err" || fail "query error message missing"
pass "invalid UTF-8 query: clean error"

# oversized file must be rejected from stat() alone (sparse 1 GiB, never read)
truncate -s 1G "$TMP/huge.sparse"
expect_fail "oversized context rejected before read" run --query NEEDLE --context-file "$TMP/huge.sparse" --chunk-bytes 1024 --max-chunks 2 --ledger-dir "$TMP/l4"
grep -qi "max-chunks" "$TMP/err" || fail "oversize error message missing"
! grep -q Traceback "$TMP/err" || fail "traceback leaked for oversized context"

echo
echo "[ Hardening: FIFO / huge limits / parent symlink / hardlink / existing dir ]"
mkfifo "$TMP/fifo"
rc=0
timeout 10 python3 -I -B "$RLM" --query NEEDLE --context-file "$TMP/fifo" --ledger-dir "$TMP/l5" >"$TMP/out" 2>"$TMP/err" || rc=$?
[ "$rc" = "2" ] || fail "FIFO context-file: expected exit 2, got $rc (124 = hang)"
! grep -q Traceback "$TMP/err" || fail "traceback leaked for FIFO"
pass "FIFO context-file rejected without hanging"

rc=0
run --query NEEDLE --context-file "$TMP/big.log" --chunk-bytes 1000000000000 --max-chunks 1000000 --ledger-dir "$TMP/l5" >"$TMP/out" 2>"$TMP/err" || rc=$?
[ "$rc" = "2" ] || fail "huge limits: expected exit 2, got $rc"
! grep -q Traceback "$TMP/err" || fail "traceback leaked for huge limits"
rc=0
run --query NEEDLE --context-file "$TMP/big.log" --chunk-bytes 1$(printf '0%.0s' {1..22}) --ledger-dir "$TMP/l5" >"$TMP/out" 2>"$TMP/err" || rc=$?
[ "$rc" = "2" ] || fail "1e22 chunk-bytes: expected exit 2, got $rc"
! grep -q Traceback "$TMP/err" || fail "traceback leaked for 1e22 chunk-bytes"
pass "huge --chunk-bytes/--max-chunks: clean exit 2"

mkdir "$TMP/preal"
ln -s "$TMP/preal" "$TMP/plink"
expect_fail "symlinked parent of ledger-dir rejected" run --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$TMP/plink/led"
[ -z "$(ls -A "$TMP/preal")" ] || fail "ledger written through symlinked parent"
pass "symlinked parent: nothing written to real side"

mkdir -m 700 "$TMP/hl-dir"
printf 'orig\n' >"$TMP/hl-victim"
chmod 644 "$TMP/hl-victim"
ln "$TMP/hl-victim" "$TMP/hl-dir/rlm-trace.jsonl"
expect_fail "hardlinked ledger file rejected" run --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$TMP/hl-dir"
[ "$(stat -c %a "$TMP/hl-victim")" = "644" ] || fail "hardlink victim mode changed"
[ "$(cat "$TMP/hl-victim")" = "orig" ] || fail "hardlink victim content modified"
pass "hardlinked ledger file: victim untouched"

mkdir -m 755 "$TMP/exist755"
expect_fail "existing 755 ledger-dir rejected" run --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$TMP/exist755"
[ "$(stat -c %a "$TMP/exist755")" = "755" ] || fail "existing dir was chmod'ed to $(stat -c %a "$TMP/exist755")"
pass "existing 755 dir: rejected, mode unchanged"

echo
echo "[ Attempt-4 hardening ]"
# clean_fail <label> <rc> <expected-msg-regex> [expected-rc=2]: controlled error with the
# expected message on stderr (so usage errors can't masquerade), no traceback
clean_fail() {
    local label="$1" rc="$2" msg="$3" want="${4:-2}"
    [ "$rc" = "$want" ] || fail "$label: expected exit $want, got $rc ($(head -c 200 "$TMP/err"))"
    ! grep -q Traceback "$TMP/err" || fail "$label: traceback leaked"
    grep -q -- "$msg" "$TMP/err" || fail "$label: stderr lacks '$msg': $(head -c 200 "$TMP/err")"
    pass "$label"
}
clean_exit2() { clean_fail "$1" "$2" "$3"; }

# ledger file is a FIFO: must fail fast (ENXIO), not hang
mkdir -m 700 "$TMP/ff-dir"
mkfifo "$TMP/ff-dir/rlm-trace.jsonl"
rc=0
timeout 10 python3 -I -B "$RLM" --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$TMP/ff-dir" >"$TMP/out" 2>"$TMP/err" || rc=$?
clean_exit2 "FIFO ledger file rejected without hanging" "$rc" "ledger"

# ledger parent must exist; only the last component is created
rc=0
run --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$TMP/no-such-parent/led" >"$TMP/out" 2>"$TMP/err" || rc=$?
clean_exit2 "missing ledger parent: clean error" "$rc" "does not exist"
[ ! -e "$TMP/no-such-parent" ] || fail "intermediate directories were created"

# concurrent first-time creation of the ledger dir
mkdir "$TMP/par"
pids=()
for i in $(seq 1 30); do
    python3 -I -B "$RLM" --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$TMP/par/led" --dry-run >/dev/null 2>"$TMP/par/err$i" &
    pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid" || fail "concurrent ledger creation: a worker failed"; done
[ "$(wc -l <"$TMP/par/led/rlm-trace.jsonl")" = "30" ] || fail "concurrent ledger lines != 30"
pass "30 concurrent first-time ledger creations all succeed"

# non-UTF-8 --model / empty --query
rc=0
run_raw --query NEEDLE --model hex:ff --context-file "$TMP/big.log" --ledger-dir "$TMP/l6" >"$TMP/out" 2>"$TMP/err" || rc=$?
clean_exit2 "non-UTF-8 --model" "$rc" "model"
rc=0
run --query "" --context-file "$TMP/big.log" --ledger-dir "$TMP/l6" >"$TMP/out" 2>"$TMP/err" || rc=$?
clean_exit2 "empty --query rejected" "$rc" "query"

# memory pressure: read of a 200 MiB file under ulimit -v must not traceback
truncate -s 200M "$TMP/mem.sparse"
rc=0
(ulimit -v 150000 && python3 -I -B "$RLM" --query NEEDLE --context-file "$TMP/mem.sparse" --chunk-bytes 1048576 --max-chunks 256 --ledger-dir "$TMP/l6") >"$TMP/out" 2>"$TMP/err" || rc=$?
if grep -q "out of memory" "$TMP/err"; then
    clean_exit2 "MemoryError under ulimit -v" "$rc" "out of memory"
else
    echo "SKIP: MemoryError test (no 'out of memory' under ulimit -v: $(head -c 100 "$TMP/err"))"
fi

# backend misbehaviour (injected via the BACKENDS registry)
cat >"$TMP/inject.py" <<'PY'
import importlib.util, os, sys
kind, path, *rest = sys.argv[1:]
spec = importlib.util.spec_from_file_location("rlm", path)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def boom(*a):
    raise RuntimeError("boom")

m.BACKENDS["boom"] = boom
m.BACKENDS["empty"] = lambda *a: {}
m.BACKENDS["badtype"] = lambda *a: {"hits": "x", "first": None}
m.BACKENDS["neg"] = lambda *a: {"hits": -5, "first": "x"}
m.BACKENDS["toomany"] = lambda *a: {"hits": 10**6, "first": "NEEDLE"}
m.BACKENDS["zerofirst"] = lambda *a: {"hits": 0, "first": "x"}
m.BACKENDS["hitsnofirst"] = lambda *a: {"hits": 1, "first": None}
m.BACKENDS["surrogate"] = lambda *a: {"hits": 1, "first": "\ud800"}

def kbd(*a):
    raise KeyboardInterrupt

def marker(*a):
    open(os.environ["RLM_MARKER"], "w").close()
    return {"hits": 0, "first": None}

def exit0(*a):
    sys.exit(0)

def raiseexit(*a):
    raise SystemExit

def slow(*a):
    import time
    if os.environ.get("RLM_READY"):
        open(os.environ["RLM_READY"], "w").close()
    time.sleep(float(os.environ.get("RLM_SLOW_SECONDS", "5")))
    return {"hits": 0, "first": None}

m.BACKENDS["exit0"] = exit0
m.BACKENDS["raiseexit"] = raiseexit
m.BACKENDS["slow"] = slow
m.BACKENDS["fabricated"] = lambda mod, q, c: {"hits": 1, "first": "FABRICATED NEEDLE not in chunk"}
m.BACKENDS["noquery"] = lambda mod, q, c: {"hits": 1, "first": c.splitlines()[0]}
m.BACKENDS["kbd"] = kbd
m.BACKENDS["marker"] = marker
os.environ["RLM_BACKEND"] = kind
sys.argv = ["rlm-bounded.py"] + rest
sys.exit(m.main())
PY
inject() {
    local kind="$1"
    shift
    python3 -I -B "$TMP/inject.py" "$kind" "$RLM" "$@"
}
for kind in boom empty badtype; do
    rc=0
    inject "$kind" --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$TMP/l6" >"$TMP/out" 2>"$TMP/err" || rc=$?
    case "$kind" in boom) msg="RuntimeError: boom" ;; *) msg="invalid result" ;; esac
    clean_exit2 "backend '$kind' failure" "$rc" "$msg"
done

# a line longer than --chunk-bytes would force a mid-line split: reject
python3 -I -B - "$TMP/longline.txt" <<'PY'
import sys
open(sys.argv[1], "w").write("x" * 995 + "NEEDLE" + "y" * 100 + "\n")
PY
rc=0
run --query NEEDLE --context-file "$TMP/longline.txt" --chunk-bytes 1000 --ledger-dir "$TMP/l6" >"$TMP/out" 2>"$TMP/err" || rc=$?
clean_exit2 "line longer than --chunk-bytes rejected" "$rc" "line longer than --chunk-bytes"
grep -q "chunk-bytes" "$TMP/err" || fail "long-line message must mention --chunk-bytes"

# chunks == max-chunks succeeds; the post-split chunk-count guard is exercised separately below
python3 -I -B - "$TMP/six.txt" <<'PY'
import sys
open(sys.argv[1], "w").write("NEEDLE-1\n" * 6)
PY
run --query NEEDLE --context-file "$TMP/six.txt" --chunk-bytes 18 --max-chunks 3 --ledger-dir "$TMP/l7" --json >"$TMP/res.json"
python3 -I -B - "$TMP/res.json" <<'PY' || fail "exact max-chunks result mismatch"
import json, sys
r = json.load(open(sys.argv[1]))
assert r["chunks"] == 3 and r["total_hits"] == 6, r
PY
rc=0
run --query NEEDLE --context-file "$TMP/six.txt" --chunk-bytes 18 --max-chunks 2 --ledger-dir "$TMP/l7" >"$TMP/out" 2>"$TMP/err" || rc=$?
clean_exit2 "max-chunks + 1 rejected (pre-read size guard)" "$rc" "max-chunks"

# 4 lines / 28 bytes, 10-byte chunks => 4 chunks; 28 <= 3*10 so the size pre-check passes and
# the post-split chunk-count guard is the one that must fire
python3 -I -B - "$TMP/four.txt" <<'PY'
import sys
open(sys.argv[1], "w").write("NEEDLE\n" * 4)
PY
rc=0
run --query NEEDLE --context-file "$TMP/four.txt" --chunk-bytes 10 --max-chunks 3 --ledger-dir "$TMP/l7" >"$TMP/out" 2>"$TMP/err" || rc=$?
clean_exit2 "post-split chunk count > max-chunks rejected" "$rc" "needs 4 chunks"

# --context-file symlink rejected
ln -s "$TMP/big.log" "$TMP/ctx-link"
expect_fail "symlink --context-file rejected" run --query NEEDLE --context-file "$TMP/ctx-link" --ledger-dir "$TMP/l6"

# --json is pure ASCII (C1 controls / DEL escaped)
printf 'NEEDLE \xc2\x9b \x7f end\n' >"$TMP/ctrl.txt"
run --query NEEDLE --context-file "$TMP/ctrl.txt" --ledger-dir "$TMP/l7" --json >"$TMP/res.json"
python3 -I -B - "$TMP/res.json" <<'PY' || fail "--json output not ASCII-safe"
import sys
b = open(sys.argv[1], "rb").read().rstrip(b"\n")
assert all(0x20 <= c < 0x7F for c in b), b
PY
pass "--json output is printable ASCII only"

# failed runs never write a ledger entry (ledger dir exists and is private)
mkdir -m 700 "$TMP/nl"
expect_no_ledger() { run "$@" --ledger-dir "$TMP/nl" >/dev/null 2>&1 && fail "expected failure: $*"; true; }
expect_no_ledger --query NEEDLE --context-file "$TMP/big.log" --max-depth 2
expect_no_ledger --query NEEDLE --context-file "$TMP/empty.log"
expect_no_ledger --query NEEDLE --context-file "$TMP/bin.dat"
expect_no_ledger --query NEEDLE --context-file "$TMP/nope"
expect_no_ledger --query NEEDLE --context-file "$TMP/big.log" --chunk-bytes 1024 --max-chunks 2
expect_no_ledger --query NEEDLE --context-file "$TMP/longline.txt" --chunk-bytes 1000
expect_no_ledger --query "" --context-file "$TMP/big.log"
expect_no_ledger --query NEEDLE --context-file "$TMP/ctx-link"
[ ! -e "$TMP/nl/rlm-trace.jsonl" ] || fail "ledger written by a failed run"
pass "failed runs leave no ledger entry"

echo
echo "[ Attempt-5 hardening ]"
# backend result validation (guard 1)
for kind in neg toomany zerofirst hitsnofirst surrogate; do
    rc=0
    inject "$kind" --query NEEDLE --context-file "$TMP/six.txt" --ledger-dir "$TMP/l8" >"$TMP/out" 2>"$TMP/err" || rc=$?
    clean_exit2 "backend '$kind' result rejected" "$rc" "invalid result"
done
rc=0
inject kbd --query NEEDLE --context-file "$TMP/six.txt" --ledger-dir "$TMP/l8" >"$TMP/out" 2>"$TMP/err" || rc=$?
clean_fail "KeyboardInterrupt in backend" "$rc" "interrupted" 130

# stdout failures (guard 2): /dev/full and a closed pipe
rc=0
run --query NEEDLE --context-file "$TMP/six.txt" --ledger-dir "$TMP/l8" --json >/dev/full 2>"$TMP/err" || rc=$?
clean_exit2 "stdout=/dev/full" "$rc" "stdout"
! grep -q "Exception ignored" "$TMP/err" || fail "stdout=/dev/full: 'Exception ignored' leaked"
rc=0
python3 -I -B - "$RLM" "$TMP/six.txt" "$TMP/l8" >"$TMP/out" 2>&1 <<'PY' || rc=$?
import os, subprocess, sys
rlm, ctx, led = sys.argv[1:]
r, w = os.pipe()
os.close(r)  # reader gone: the child's write must hit EPIPE
p = subprocess.run(
    [sys.executable, "-I", "-B", rlm, "--query", "NEEDLE", "--context-file", ctx,
     "--ledger-dir", led, "--json"],
    stdout=w, stderr=subprocess.PIPE, env={**os.environ, "RLM_BACKEND": "stub"},
)
sys.stdout.write(f"{p.returncode}\n{p.stderr.decode()}")
PY
[ "$(head -1 "$TMP/out")" = "2" ] || fail "closed pipe: expected exit 2, got $(head -1 "$TMP/out")"
! grep -q "Traceback\|Exception ignored" "$TMP/out" || fail "closed pipe: traceback leaked"
grep -q "stdout" "$TMP/out" || fail "closed pipe: message must mention stdout"
pass "closed stdout pipe: clean exit 2"

# blank --ledger-dir must not write into cwd (guard 3)
mkdir "$TMP/cwd"
for v in "" "   "; do
    rc=0
    (cd "$TMP/cwd" && python3 -I -B "$RLM" --query NEEDLE --context-file "$TMP/six.txt" --ledger-dir "$v") >"$TMP/out" 2>"$TMP/err" || rc=$?
    clean_exit2 "blank --ledger-dir '$v'" "$rc" "ledger-dir"
    [ -z "$(ls -A "$TMP/cwd")" ] || fail "blank --ledger-dir wrote into cwd"
done

# multi-line query (guard 5)
for q in $'a\nb' $'NEEDLE\n' $'a\vb' $'a\rb' $'a\xc2\x85b'; do
    rc=0
    run --query "$q" --context-file "$TMP/six.txt" --ledger-dir "$TMP/l8" >"$TMP/out" 2>"$TMP/err" || rc=$?
    clean_exit2 "multi-line query rejected" "$rc" "single line"
done

# small file + huge limits succeeds under a tight ulimit: read is min(size,limit)+1 (guard 6)
rc=0
(ulimit -v 150000 && python3 -I -B "$RLM" --query NEEDLE --context-file "$TMP/six.txt" --chunk-bytes 67108864 --max-chunks 4096 --ledger-dir "$TMP/l8" --dry-run) >"$TMP/out" 2>"$TMP/err" || rc=$?
if [ "$rc" = "0" ]; then
    pass "small file + huge limits succeeds under ulimit -v"
elif grep -q "out of memory" "$TMP/err"; then
    fail "small file + huge limits hit MemoryError: read must be min(size, limit)+1"
else
    echo "SKIP: python could not start under ulimit -v ($(head -c 100 "$TMP/err"))"
fi

# short write -> die (guard 7), exercised by injecting a short os.write
python3 -I -B - "$RLM" "$TMP/six.txt" "$TMP/l9" >"$TMP/out" 2>&1 <<'PY' || true
import importlib.util, os, sys
rlm, ctx, led = sys.argv[1:]
spec = importlib.util.spec_from_file_location("rlm", rlm)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
real = os.write
os.write = lambda fd, b: real(fd, b[: len(b) // 2])  # short write
os.environ["RLM_BACKEND"] = "stub"
sys.argv = ["rlm-bounded.py", "--query", "NEEDLE", "--context-file", ctx, "--ledger-dir", led, "--dry-run"]
sys.exit(m.main())
PY
grep -q "short write" "$TMP/out" || fail "short ledger write not detected: $(head -c 200 "$TMP/out")"
pass "short ledger write is fatal"

# existing 0644 ledger file is rejected and left untouched
mkdir -m 700 "$TMP/pf-dir"
printf 'orig\n' >"$TMP/pf-dir/rlm-trace.jsonl"
chmod 644 "$TMP/pf-dir/rlm-trace.jsonl"
rc=0
run --query NEEDLE --context-file "$TMP/six.txt" --ledger-dir "$TMP/pf-dir" >"$TMP/out" 2>"$TMP/err" || rc=$?
clean_exit2 "existing 0644 ledger file rejected" "$rc" "ledger file"
[ "$(stat -c %a "$TMP/pf-dir/rlm-trace.jsonl")" = "644" ] || fail "0644 ledger file mode changed"
[ "$(cat "$TMP/pf-dir/rlm-trace.jsonl")" = "orig" ] || fail "0644 ledger file modified"

# ledger is validated BEFORE the backend runs (guard 8)
mkdir -m 755 "$TMP/bad-ledger"
rc=0
RLM_MARKER="$TMP/marker" inject marker --query NEEDLE --context-file "$TMP/six.txt" --ledger-dir "$TMP/bad-ledger" >"$TMP/out" 2>"$TMP/err" || rc=$?
clean_exit2 "bad ledger dir rejected before backend" "$rc" "ledger dir"
[ ! -e "$TMP/marker" ] || fail "backend ran although the ledger dir was invalid"
rc=0
RLM_MARKER="$TMP/marker" inject marker --query NEEDLE --context-file "$TMP/six.txt" --ledger-dir "$TMP/l8" >"$TMP/out" 2>"$TMP/err" || rc=$?
[ "$rc" = "0" ] && [ -e "$TMP/marker" ] || fail "marker backend should run with a valid ledger dir"
pass "ledger validated before backend call"

echo
echo "[ Attempt-6 hardening ]"
for kind in exit0 raiseexit; do
    rc=0
    inject "$kind" --query NEEDLE --context-file "$TMP/six.txt" --ledger-dir "$TMP/l10" >"$TMP/out" 2>"$TMP/err" || rc=$?
    clean_exit2 "backend '$kind' is a failure, not a success" "$rc" "backend raised SystemExit"
done

printf 'alpha\nNEEDLE one\n' >"$TMP/mixed.txt"
for kind in fabricated noquery; do
    rc=0
    inject "$kind" --query NEEDLE --context-file "$TMP/mixed.txt" --ledger-dir "$TMP/l10" >"$TMP/out" 2>"$TMP/err" || rc=$?
    clean_exit2 "backend '$kind' first rejected" "$rc" "invalid result from backend"
done

# a legitimate but giant line is output truncated to <= 512 bytes, marked, valid UTF-8
python3 -I -B - "$TMP/giant.txt" <<'PY'
import sys
open(sys.argv[1], "w", encoding="utf-8").write("NEEDLE " + "é" * 3000 + "\n")
PY
run --query NEEDLE --context-file "$TMP/giant.txt" --ledger-dir "$TMP/l10" --json >"$TMP/res.json"
python3 -I -B - "$TMP/res.json" <<'PY' || fail "giant first not truncated correctly"
import json, sys
f = json.load(open(sys.argv[1]))["first_hits"][0]
assert len(f.encode("utf-8")) <= 512, len(f.encode("utf-8"))
assert f.endswith("[truncated]") and f.startswith("NEEDLE éé"), f[:40]
PY
pass "giant first truncated to <= 512 bytes with marker"

# per-chunk timeout: returns in ~1s, not after the 5s the backend sleeps
t0=$(date +%s%N)
rc=0
RLM_CHUNK_TIMEOUT=1 RLM_SLOW_SECONDS=5 inject slow --query NEEDLE --context-file "$TMP/six.txt" --ledger-dir "$TMP/l10" >"$TMP/out" 2>"$TMP/err" || rc=$?
ms=$(((($(date +%s%N)) - t0) / 1000000))
clean_exit2 "slow chunk times out" "$rc" "chunk analysis timed out"
[ "$ms" -lt 3500 ] || fail "timeout exit took ${ms}ms (backend thread must not delay exit)"
pass "timeout exit took ${ms}ms (< 3500)"
rc=0
RLM_CHUNK_TIMEOUT=0 run --query NEEDLE --context-file "$TMP/six.txt" --ledger-dir "$TMP/l10" >"$TMP/out" 2>"$TMP/err" || rc=$?
clean_exit2 "RLM_CHUNK_TIMEOUT=0 rejected" "$rc" "RLM_CHUNK_TIMEOUT"

# SIGINT while a backend is running: prompt exit 130, no traceback
python3 -I -B - "$TMP/inject.py" "$RLM" "$TMP/six.txt" "$TMP/l10" "$TMP/ready" >"$TMP/out" 2>&1 <<'PY' || true
import os, signal, subprocess, sys, time
script, rlm, ctx, led, ready = sys.argv[1:]
env = {**os.environ, "RLM_SLOW_SECONDS": "30", "RLM_READY": ready}
p = subprocess.Popen(
    [sys.executable, "-I", "-B", script, "slow", rlm, "--query", "NEEDLE",
     "--context-file", ctx, "--ledger-dir", led],
    env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
)
for _ in range(100):
    if os.path.exists(ready):
        break
    time.sleep(0.1)
t = time.monotonic()
p.send_signal(signal.SIGINT)
try:
    _, err = p.communicate(timeout=8)
except subprocess.TimeoutExpired:
    p.kill()
    p.communicate()
    print("TIMEOUT")
    sys.exit(0)
print(p.returncode, f"{time.monotonic() - t:.2f}")
sys.stdout.write(err.decode())
PY
read -r irc isecs <"$TMP/out" || true
[ "${irc:-}" = "130" ] || fail "SIGINT: expected rc 130 promptly, got '$(head -c 200 "$TMP/out")'"
! grep -q Traceback "$TMP/out" || fail "SIGINT: traceback leaked"
grep -q "interrupted" "$TMP/out" || fail "SIGINT: 'interrupted' missing"
pass "SIGINT during backend: rc 130 in ${isecs}s"

echo
echo "[ exec backend (real-LLM path): provider-agnostic command, env allowlist, bounds ]"
# A fake backend stands in for `claude -p` & co: no network and no API key is ever involved.
cat >"$TMP/fake.sh" <<'FAKE'
#!/usr/bin/env bash
out="${1:-}"
[ -n "$out" ] && env >"$out"
input="$(cat)"
case "${FAKE_MODE:-ok}" in
  fail) echo "boom" >&2; exit 3 ;;
  sleep) exec sleep 30 ;;
  big) head -c 70000 /dev/zero | tr '\0' 'A' ;;
  binary) printf '\xff\xfe' ;;
  *) if printf '%s' "$input" | grep -q 'NEEDLE found'; then echo "evidence: NEEDLE seen in chunk"; else echo NONE; fi ;;
esac
FAKE
chmod +x "$TMP/fake.sh"
export RLM_BACKEND=exec
export RLM_BACKEND_CMD="[\"bash\",\"$TMP/fake.sh\",\"$TMP/backend-env.out\"]"
export RLM_BACKEND_PASS_ENV=FAKE_MODE
LX="$TMP/ledger-exec"

run --query NEEDLE --context-file "$TMP/big.log" --chunk-bytes 16384 --ledger-dir "$LX" --json >"$TMP/xres.json"
python3 -I -B - "$TMP/xres.json" "$LX/rlm-trace.jsonl" <<'PY' || fail "exec backend result/ledger mismatch"
import json, sys
r = json.load(open(sys.argv[1]))
assert r["backend"] == "exec", r
# NEEDLE is on every 100th line, so every chunk but possibly the short last one answers; the rest say NONE
assert r["chunks"] > 1 and r["chunks"] - 1 <= r["answered_chunks"] <= r["chunks"], r
assert r["answers"][0].startswith("evidence:"), r
assert "total_hits" not in r, r
last = [json.loads(l) for l in open(sys.argv[2])][-1]
assert last["backend"] == "exec" and last["kind"] == "answer" and last["sandbox"] is False, last
assert 1 <= last["max_workers"] <= 8 and last["cell_timeout"] >= 1, last
PY
pass "exec backend: per-chunk answers aggregated, ledger records backend/kind/workers/timeout"

# irrelevant chunks answer NONE and are not reported
printf 'nothing here\nstill nothing\n' >"$TMP/quiet.log"
run --query NEEDLE --context-file "$TMP/quiet.log" --ledger-dir "$LX" --json >"$TMP/qres.json"
python3 -I -B -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["answered_chunks"]==0 and r["answers"]==[], r' "$TMP/qres.json" \
    || fail "NONE answers must not be reported"
pass "exec backend: NONE answers are dropped"

# the child sees only the allowlisted environment
SECRET_TOKEN=do-not-leak run --query NEEDLE --context-file "$TMP/quiet.log" --ledger-dir "$LX" --json >/dev/null
! grep -q SECRET_TOKEN "$TMP/backend-env.out" || fail "a credential leaked into the backend environment"
grep -q '^PATH=' "$TMP/backend-env.out" || fail "PATH missing from the backend environment"
RLM_BACKEND_PASS_ENV=FAKE_MODE,SECRET_TOKEN SECRET_TOKEN=explicitly-named run --query NEEDLE --context-file "$TMP/quiet.log" --ledger-dir "$LX" --json >/dev/null
grep -q '^SECRET_TOKEN=explicitly-named' "$TMP/backend-env.out" || fail "a named variable must be passed through"
pass "exec backend: environment is an allowlist (named variables only)"

# failures are clean and fail closed (no traceback, exit non-zero)
FAKE_MODE=fail expect_fail "backend exits non-zero -> rejected" run --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$LX"
grep -q "exited 3" "$TMP/err" || fail "exit status missing from the message"
! grep -q Traceback "$TMP/err" || fail "traceback leaked for a failing backend"
FAKE_MODE=big expect_fail "oversized backend output rejected" run --query NEEDLE --context-file "$TMP/quiet.log" --ledger-dir "$LX"
grep -q "larger than" "$TMP/err" || fail "oversize message missing"
FAKE_MODE=binary expect_fail "non-UTF-8 backend output rejected" run --query NEEDLE --context-file "$TMP/quiet.log" --ledger-dir "$LX"
grep -q "UTF-8" "$TMP/err" || fail "UTF-8 message missing"
pass "exec backend: failing / oversized / non-UTF-8 output are rejected cleanly"

T0=$(date +%s)
FAKE_MODE=sleep expect_fail "--cell-timeout 1 stops a hanging backend" run --query NEEDLE --context-file "$TMP/quiet.log" --ledger-dir "$LX" --cell-timeout 1
T1=$(date +%s)
[ $((T1 - T0)) -le 15 ] || fail "hanging backend was not stopped promptly ($((T1 - T0))s)"
grep -q "timed out" "$TMP/err" || fail "timeout message missing"
pass "--cell-timeout: hanging backend stopped in $((T1 - T0))s"

RLM_BACKEND_CMD='not json' expect_fail "invalid RLM_BACKEND_CMD rejected" run --query NEEDLE --context-file "$TMP/quiet.log" --ledger-dir "$LX"
grep -q "RLM_BACKEND_CMD" "$TMP/err" || fail "RLM_BACKEND_CMD message missing"
RLM_BACKEND_CMD='["bash",""]' expect_fail "empty argv element rejected" run --query NEEDLE --context-file "$TMP/quiet.log" --ledger-dir "$LX"
expect_fail "--model starting with '-' rejected for exec" run --query NEEDLE --context-file "$TMP/quiet.log" --ledger-dir "$LX" --model=-x
pass "exec backend: bad command / model rejected"

echo
echo "[ --max-workers / --require-min-tokens / --sandbox ]"
expect_fail "--max-workers 0 rejected" run --query NEEDLE --context-file "$TMP/quiet.log" --ledger-dir "$LX" --max-workers 0
expect_fail "--max-workers 17 rejected" run --query NEEDLE --context-file "$TMP/quiet.log" --ledger-dir "$LX" --max-workers 17
run --query NEEDLE --context-file "$TMP/big.log" --chunk-bytes 16384 --ledger-dir "$LX" --max-workers 1 --json >"$TMP/w1.json"
python3 -I -B -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["chunks"]-1 <= r["answered_chunks"] <= r["chunks"], r' "$TMP/w1.json" || fail "--max-workers 1 result mismatch"
pass "--max-workers: bounded 1..16, serial run gives the same result"

LG="$TMP/ledger-gate"
expect_fail "below --require-min-tokens: nothing is run" run --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$LG" --require-min-tokens 200000
grep -q "below --require-min-tokens" "$TMP/err" || fail "token gate message missing"
[ ! -e "$LG/rlm-trace.jsonl" ] || fail "ledger written although the token gate rejected the run"
set +e; run --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$LG" --require-min-tokens 200000 >/dev/null 2>&1; grc=$?; set -e
[ "$grc" = "3" ] || fail "token gate must exit 3, got $grc"
run --query NEEDLE --context-file "$TMP/big.log" --ledger-dir "$LG" --require-min-tokens 1000 --json >/dev/null
pass "--require-min-tokens: exit 3 below the threshold, runs above it"

# --sandbox: fail closed without pa-sandbox, wrap argv with it when present
mkdir -p "$TMP/nosb" "$TMP/sb"
for t in python3 timeout bash; do ln -s "$(command -v "$t")" "$TMP/nosb/$t"; done
PATH="$TMP/nosb" expect_fail "--sandbox without pa-sandbox refuses to run" run --query NEEDLE --context-file "$TMP/quiet.log" --ledger-dir "$LX" --sandbox
grep -q "pa-sandbox is not in PATH" "$TMP/err" || fail "pa-sandbox message missing"
cat >"$TMP/sb/pa-sandbox" <<'SB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${SB_LOG:?}"
[ "${1:-}" = "--" ] || exit 64
shift
exec "$@"
SB
chmod +x "$TMP/sb/pa-sandbox"
PATH="$TMP/sb:$PATH" SB_LOG="$TMP/sb.log" RLM_BACKEND_PASS_ENV=FAKE_MODE,SB_LOG run --query NEEDLE --context-file "$TMP/quiet.log" --ledger-dir "$LX" --sandbox --json >/dev/null
grep -q '^-- bash ' "$TMP/sb.log" || fail "the backend command was not wrapped by pa-sandbox -- (got: $(head -c 200 "$TMP/sb.log"))"
python3 -I -B -c 'import json,sys; assert [json.loads(l) for l in open(sys.argv[1])][-1]["sandbox"] is True' "$LX/rlm-trace.jsonl" || fail "ledger must record sandbox=true"
RLM_BACKEND=stub expect_fail "--sandbox with a non-exec backend rejected" run --query NEEDLE --context-file "$TMP/quiet.log" --ledger-dir "$LX" --sandbox
pass "--sandbox: wraps with pa-sandbox --, fails closed when missing, exec-only"

echo
echo "All RLM bounded tests passed"
