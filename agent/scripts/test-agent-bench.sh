#!/usr/bin/env bash
# agent/scripts/bench/run-agent-bench.sh の受け入れテスト。
#   - --hooks --quick / --suite --quick が実行でき exit 0
#   - --json が妥当な JSON(hooks / suite の期待キーを持つ)
#   - 意図的に失敗する workload(--suite-file の一時 suite)で非0終了
#   - 前提欠落の workload は SKIP(PASS ではない)・終了コードは 0
#   - ベンチ終了後に decide_daemon.py プロセスが残らない
# 一時物は全て mktemp -d 配下。実 $XDG_RUNTIME_DIR のソケットには触れない。
#
# usage: agent/scripts/test-agent-bench.sh
# exit: 0 = 全テストPASS, 1 = 1件以上FAIL
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BENCH="$ROOT/agent/scripts/bench/run-agent-bench.sh"
T="$(mktemp -d)"
trap 'command rm -rf "$T"' EXIT

fail=0
ok() { echo "[OK] $1"; }
ng() { echo "[FAIL] $1"; fail=$((fail + 1)); }
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else ng "$1 : expected=[$2] got=[$3]"; fi; }
pyj() { python3 -I -B -c "$@"; }

daemons_before="$(pgrep -fc 'decide_daemon.py --daemon' || true)"

# --- 0. 存在と権限 ---
[[ -x "$BENCH" ]] && ok "run-agent-bench.sh is executable" || ng "run-agent-bench.sh missing or not executable"
[[ -f "$ROOT/agent/benchmarks/vald-suite.yaml" ]] && ok "vald-suite.yaml exists" || ng "vald-suite.yaml missing"
if [[ ! -x "$BENCH" ]]; then
    echo "FAIL: $fail"
    exit 1
fi

# --- 1. --hooks --quick ---
timeout 300 "$BENCH" --hooks --quick >"$T/hooks.out" 2>&1
check "--hooks --quick exits 0" 0 $?
grep -q 'p95' "$T/hooks.out" && ok "--hooks output reports p95" || ng "--hooks output lacks p95"

# --- 2. --suite --quick ---
timeout 600 "$BENCH" --suite --quick >"$T/suite.out" 2>&1
check "--suite --quick exits 0" 0 $?
grep -Eq 'PASS|SKIP' "$T/suite.out" && ok "--suite output has PASS/SKIP lines" || ng "--suite output lacks PASS/SKIP"

# --- 3. --json ---
timeout 300 "$BENCH" --hooks --quick --json >"$T/hooks.json" 2>"$T/hooks.json.err"
check "--hooks --json exits 0" 0 $?
pyj 'import json,sys; d=json.load(open(sys.argv[1])); h=d["hooks"]; assert h and all("p50_ms" in r and "p95_ms" in r and "name" in r for r in h)' "$T/hooks.json" 2>/dev/null \
    && ok "--hooks --json is valid with p50_ms/p95_ms" || ng "--hooks --json invalid"
timeout 600 "$BENCH" --suite --quick --json >"$T/suite.json" 2>"$T/suite.json.err"
check "--suite --json exits 0" 0 $?
pyj 'import json,sys; d=json.load(open(sys.argv[1])); s=d["suite"]; assert s["workloads"] and all(w["status"] in ("PASS","FAIL","SKIP") for w in s["workloads"])' "$T/suite.json" 2>/dev/null \
    && ok "--suite --json is valid with statuses" || ng "--suite --json invalid"

# --- 4. 意図的に失敗する workload -> 非0 ---
cat >"$T/fail.yaml" <<'EOF'
version: 1
workloads:
  - id: WX
    title: "deliberately failing"
    quick: true
    needs: []
    checks:
      - name: always-fails
        cmd: "false"
EOF
timeout 60 "$BENCH" --suite --quick --suite-file "$T/fail.yaml" >"$T/fail.out" 2>&1
rc=$?
[[ $rc -ne 0 ]] && ok "failing workload yields non-zero exit (rc=$rc)" || ng "failing workload yielded rc=0"
grep -q 'FAIL' "$T/fail.out" && ok "failing workload reported FAIL" || ng "FAIL not reported"

# --- 5. 前提欠落 -> SKIP(PASS ではない)・exit 0 ---
cat >"$T/skip.yaml" <<'EOF'
version: 1
workloads:
  - id: WS
    title: "missing prerequisite"
    quick: true
    needs: [bin:definitely-not-a-real-tool-xyz, dir:/nonexistent/path/xyz]
    checks:
      - name: would-pass-if-run
        cmd: "true"
EOF
timeout 60 "$BENCH" --suite --quick --suite-file "$T/skip.yaml" --json >"$T/skip.json" 2>&1
check "missing prerequisite exits 0" 0 $?
pyj 'import json,sys; w=json.load(open(sys.argv[1]))["suite"]["workloads"]; assert len(w)==1 and w[0]["status"]=="SKIP" and w[0]["reason"] and "definitely-not-a-real-tool-xyz" in w[0]["reason"]' "$T/skip.json" 2>/dev/null \
    && ok "missing prerequisite => SKIP with reason (not PASS)" || ng "missing prerequisite not reported as SKIP"

# --- 6. 不正な suite はエラー(PASS 扱いにしない) ---
printf 'not: [valid\n' >"$T/bad.yaml"
timeout 60 "$BENCH" --suite --quick --suite-file "$T/bad.yaml" >"$T/bad.out" 2>&1
[[ $? -ne 0 ]] && ok "malformed suite file is rejected" || ng "malformed suite file accepted"

# --- 7. daemon が残らない ---
sleep 0.3
daemons_after="$(pgrep -fc 'decide_daemon.py --daemon' || true)"
check "no decide_daemon processes left behind" "$daemons_before" "$daemons_after"

echo
if [[ $fail -eq 0 ]]; then echo "ALL PASS"; exit 0; fi
echo "FAIL: $fail"
exit 1
