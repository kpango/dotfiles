#!/usr/bin/env bash
# agent/ 基盤の再現可能ベンチマーク。計測値は全て実測(期待値のハードコードなし)。
#
#   --hooks            agent/hooks/{claude,agy} の合成 stdin で実行可能な hook shim、decide.py(デーモンなし)、
#                      decide.dispatch(ベンチプロセス内)、decide_daemon.py 経由(fast path / --query)の
#                      p50/p95 レイテンシ(ms)を測る。デーモンは一時ディレクトリのソケット +
#                      AGENT_DECIDE_ALLOW_UNMANAGED=1 で起動し、終了時に必ず止める(実 $XDG_RUNTIME_DIR 不使用)。
#                      副作用のある hook(session-*, post-write, swarm-* 等)は計測対象外(出力に理由を載せる)。
#   --suite            agent/benchmarks/vald-suite.yaml の W1..W10 決定論 check を実行し PASS/FAIL/SKIP を報告。
#                      前提(needs)欠落は SKIP(理由付き)であり PASS ではない。
#   --suite-file FILE  --suite で読む定義ファイルを差し替える(テスト用)
#   --quick            hooks: 反復回数を削減 / suite: quick: true の workload のみ
#   --json             stdout へ機械可読 JSON のみを出力
# どちらも未指定なら --hooks --suite。exit: FAIL(計測不能・check 失敗・suite 定義不正)があれば非0、SKIP のみなら 0。
# YAML は PyYAML 非依存の厳格な最小リーダー(対応構文は vald-suite.yaml 冒頭に記載)。
set -euo pipefail

ROOT="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../.." && pwd)"
export BENCH_ROOT="$ROOT"
command -v python3 >/dev/null 2>&1 || { echo "python3 not found" >&2; exit 2; }

PY=$(cat <<'PYEOF'
import atexit, json, os, re, shutil, signal, subprocess, sys, tempfile, time

ROOT = os.environ["BENCH_ROOT"]
HOOKS = os.path.join(ROOT, "agent", "scripts", "hooks")
DECIDE = os.path.join(HOOKS, "decide.py")
DAEMON = os.path.join(HOOKS, "decide_daemon.py")
PYB = ["python3", "-I", "-B"]


def run(cmd, timeout, env=None, cwd=None, stdin=None):
    """子を新セッションで起動し、タイムアウト時はプロセスグループごと kill する。"""
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, cwd=cwd,
                         start_new_session=True)
    try:
        out, _ = p.communicate(None if stdin is None else stdin.encode(), timeout=timeout)
        return p.returncode, out.decode(errors="replace"), False
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, _ = p.communicate()
        return -9, out.decode(errors="replace"), True


def pct(vals, q):
    s = sorted(vals)
    return s[min(len(s) - 1, max(0, -(-q * len(s) // 100) - 1))]


def parse_args(argv):
    o = {"hooks": False, "suite": False, "quick": False, "json": False, "suite_file": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--hooks", "--suite", "--quick", "--json"):
            o[a[2:]] = True
        elif a == "--suite-file" and i + 1 < len(argv):
            i += 1
            o["suite_file"] = argv[i]
        else:
            sys.exit("usage: run-agent-bench.sh [--hooks] [--suite] [--quick] [--json] [--suite-file FILE]")
        i += 1
    if not o["hooks"] and not o["suite"]:
        o["hooks"] = o["suite"] = True
    return o


# ---------------------------------------------------------------- hooks
def bench_hooks(quick):
    tmp = tempfile.mkdtemp(prefix="agent-bench-")
    os.chmod(tmp, 0o700)
    state = {"daemon": None}

    def cleanup():
        d = state["daemon"]
        if d is not None and d.poll() is None:
            try:
                os.killpg(d.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            d.wait()
        shutil.rmtree(tmp, ignore_errors=True)
    atexit.register(cleanup)

    iters, warm = (5, 1) if quick else (30, 3)
    sock = os.path.join(tmp, "d.sock")
    base = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    base.update({"PYTHONDONTWRITEBYTECODE": "1", "AGENT_DECIDE_SOCK": sock, "AGENT_DECIDE_NO_DAEMON": "1", "HOME": os.environ.get("HOME", tmp)})
    req = {"family": "security_shell", "command": "ls -la", "cwd": tmp,
           "rules_file": os.path.join(ROOT, "agent", "security-rules.json"),
           "resolve_command_target": False, "harness": "claude"}
    reqj = json.dumps(req)
    claude_bash = json.dumps({"tool_name": "Bash", "tool_input": {"command": "ls -la"}})
    claude_write = json.dumps({"tool_name": "Write", "tool_input": {"file_path": os.path.join(tmp, "x.txt"), "content": "x"}})
    agy_bash = json.dumps({"toolCall": {"name": "run_command", "args": {"CommandLine": "ls -la"}}})
    hk = os.path.join(ROOT, "agent", "hooks")
    targets = [
        ("claude/security-gate.sh", ["bash", f"{hk}/claude/security-gate.sh"], claude_bash, base),
        ("claude/write-security-gate.sh", ["bash", f"{hk}/claude/write-security-gate.sh"], claude_write, base),
        ("claude/vald-law-gate.sh", ["bash", f"{hk}/claude/vald-law-gate.sh"], claude_bash, base),
        ("claude/rtk-rewrite.sh", ["bash", f"{hk}/claude/rtk-rewrite.sh"], claude_bash, base),
        ("agy/security-gate.sh", ["bash", f"{hk}/agy/security-gate.sh"], agy_bash, base),
        ("agy/vald-law-gate.sh", ["bash", f"{hk}/agy/vald-law-gate.sh"], agy_bash, base),
        ("agy/rtk-rewrite.sh", ["bash", f"{hk}/agy/rtk-rewrite.sh"], agy_bash, base),
        ("decide.py (no daemon, cold process)", PYB + [DECIDE], reqj, base),
    ]
    results = []

    def measure(name, cmd, stdin, env):
        times, rcs = [], set()
        for n in range(warm + iters):
            t0 = time.perf_counter()
            rc, out, to = run(cmd, 15, env=env, cwd=tmp, stdin=stdin)
            dt = (time.perf_counter() - t0) * 1000
            if to:
                return {"name": name, "status": "FAIL", "reason": "timeout (15s)"}
            if n >= warm:
                times.append(dt)
                rcs.add(rc)
        return {"name": name, "status": "OK", "iterations": len(times), "exit_codes": sorted(rcs),
                "p50_ms": round(pct(times, 50), 2), "p95_ms": round(pct(times, 95), 2),
                "min_ms": round(min(times), 2), "max_ms": round(max(times), 2)}

    for name, cmd, stdin, env in targets:
        results.append(measure(name, cmd, stdin, env))

    # ベンチプロセス内の decide.dispatch(プロセス起動コストを含まない純粋な判定時間)
    sys.path.insert(0, HOOKS)
    try:
        import decide
        times = []
        for n in range(warm + iters * 10):
            t0 = time.perf_counter()
            decide.dispatch(dict(req))
            if n >= warm:
                times.append((time.perf_counter() - t0) * 1000)
        results.append({"name": "decide.dispatch (in-bench-process)", "status": "OK", "iterations": len(times),
                        "exit_codes": [], "p50_ms": round(pct(times, 50), 3), "p95_ms": round(pct(times, 95), 3),
                        "min_ms": round(min(times), 3), "max_ms": round(max(times), 3)})
    except Exception as e:  # noqa: BLE001 — 計測不能は FAIL として報告する
        results.append({"name": "decide.dispatch (in-bench-process)", "status": "FAIL", "reason": repr(e)})

    # デーモン(一時ソケット・管理外許可)。必ず cleanup で止める。
    denv = {k: v for k, v in base.items() if not (k.startswith("PYTHON") or k.startswith("LD_"))}  # decide.py rejects a daemon whose environ has PYTHON*/LD_* (-B is already on its argv)
    denv.pop("AGENT_DECIDE_NO_DAEMON", None)
    denv["AGENT_DECIDE_DAEMON"] = "1"  # the daemon fast path is opt-in
    denv["AGENT_DECIDE_ALLOW_UNMANAGED"] = "1"
    state["daemon"] = subprocess.Popen(PYB + [DAEMON, "--daemon"], env=denv, cwd=tmp, start_new_session=True,
                                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    up = False
    for _ in range(100):
        if state["daemon"].poll() is not None:
            break
        rc, _, _ = run(PYB + [DAEMON, "--ping"], 5, env=denv, cwd=tmp)
        if rc == 0:
            up = True
            break
        time.sleep(0.05)
    if up:
        results.append(measure("decide.py via daemon (fast path)", PYB + [DECIDE], reqj, denv))
        results.append(measure("decide_daemon.py --query", PYB + [DAEMON, "--query"], reqj, denv))
    else:
        for n in ("decide.py via daemon (fast path)", "decide_daemon.py --query"):
            results.append({"name": n, "status": "SKIP", "reason": "decide_daemon.py did not start within 5s"})
    run(PYB + [DAEMON, "--stop"], 5, env=denv, cwd=tmp)
    cleanup()
    state["daemon"] = None
    skipped = [{"name": "claude/{session-start,session-end,post-write,pre-compact,stop-failure,post-tool-failure,"
                       "permission-request,user-prompt-submit,swarm-*}.sh, agy/session-start.sh",
                "reason": "side effects (state/log writes, git, network) - not safe to run with synthetic stdin"}]
    return {"quick": quick, "iterations": iters, "warmup": warm, "results": results, "not_benchmarked": skipped}


# ---------------------------------------------------------------- suite
def parse_suite(path):
    """vald-suite.yaml の厳格サブセットリーダー。逸脱は ValueError。"""
    def val(s, ln):
        s = s.strip()
        if s.startswith('"'):
            try:
                v = json.loads(s)
            except ValueError:
                raise ValueError(f"line {ln}: bad quoted string")
            if not isinstance(v, str):
                raise ValueError(f"line {ln}: bad quoted string")
            return v
        if s.startswith("'"):  # prettier prefers 'single' quotes when the text holds "double" ones
            if len(s) < 2 or not s.endswith("'") or re.search(r"(?<!')'(?!')", s[1:-1]):
                raise ValueError(f"line {ln}: bad single-quoted string")
            return s[1:-1].replace("''", "'")
        if s.startswith("["):
            if not s.endswith("]"):
                raise ValueError(f"line {ln}: unterminated list")
            inner = s[1:-1].strip()
            return [x.strip() for x in inner.split(",") if x.strip()]
        if s in ("true", "false"):
            return s == "true"
        if s.isdigit():
            return int(s)
        if re.fullmatch(r"[A-Za-z0-9_.-]+", s):
            return s
        raise ValueError(f"line {ln}: unsupported value {s!r}")

    # prettier (make format) wraps a long `needs: [...]` onto `needs:` + `[` ... `]` lines: join it back.
    src, rows, i = open(path, encoding="utf-8").read().splitlines(), [], 0
    while i < len(src):
        ln, raw = i + 1, src[i]
        if raw.strip() == "needs:" and i + 1 < len(src) and src[i + 1].strip().startswith("["):
            parts = [raw.rstrip()]
            while True:
                i += 1
                parts.append(src[i].strip())
                if src[i].strip().endswith("]") or i + 1 >= len(src):
                    break
            raw = " ".join(parts)
        rows.append((ln, raw))
        i += 1

    version, wls, cur, chk, in_checks = None, None, None, None, False
    for ln, raw in rows:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        ind = len(raw) - len(raw.lstrip(" "))
        s = raw.strip()
        if ind == 0:
            if s == "workloads:":
                wls = []
            elif s.startswith("version:"):
                version = val(s[8:], ln)
            else:
                raise ValueError(f"line {ln}: unexpected top-level {s!r}")
        elif ind == 2 and s.startswith("- ") and wls is not None:
            cur = {"checks": []}
            wls.append(cur)
            in_checks = False
            k, _, v = s[2:].partition(":")
            cur[k.strip()] = val(v, ln)
        elif ind == 4 and cur is not None and not s.startswith("- "):
            k, _, v = s.partition(":")
            k = k.strip()
            if k == "checks":
                if v.strip():
                    raise ValueError(f"line {ln}: checks takes a block list")
                in_checks = True
            else:
                in_checks = False
                cur[k] = val(v, ln)
        elif ind == 6 and in_checks and s.startswith("- "):
            chk = {}
            cur["checks"].append(chk)
            k, _, v = s[2:].partition(":")
            chk[k.strip()] = val(v, ln)
        elif ind == 8 and chk is not None and in_checks:
            k, _, v = s.partition(":")
            chk[k.strip()] = val(v, ln)
        else:
            raise ValueError(f"line {ln}: unexpected structure {s!r}")
    if version != 1 or not wls:
        raise ValueError("version: 1 and a non-empty workloads: list are required")
    for w in wls:
        if not isinstance(w.get("id"), str) or not isinstance(w.get("title"), str) \
                or not isinstance(w.get("quick"), bool) or not isinstance(w.get("needs"), list) or not w["checks"]:
            raise ValueError(f"workload {w.get("id")!r}: id/title/quick/needs/checks required")
        for c in w["checks"]:
            if not isinstance(c.get("name"), str) or not isinstance(c.get("cmd"), str):
                raise ValueError(f"workload {w["id"]}: check needs name and cmd")
    return wls


def bench_suite(path, quick):
    env = dict(os.environ)
    env["ROOT"] = ROOT
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env.setdefault("VALD_DIR", os.path.expanduser("~/go/src/github.com/vdaas/vald"))
    wls = parse_suite(path)
    out, omitted = [], 0
    for w in wls:
        if quick and not w["quick"]:
            omitted += 1
            continue
        missing = []
        for n in w["needs"]:
            kind, _, arg = n.partition(":")
            p = arg
            for k in ("ROOT", "VALD_DIR"):
                p = p.replace("$" + k, env[k])
            if kind == "bin" and not shutil.which(arg):
                missing.append(f"command not found: {arg}")
            elif kind == "dir" and not os.path.isdir(p):
                missing.append(f"directory not found: {p}")
            elif kind == "file" and not os.path.isfile(p):
                missing.append(f"file not found: {p}")
            elif kind == "gopkg":
                d, _, pkg = p.partition("|")
                genv = dict(env, GOFLAGS="-mod=mod", GOPROXY="off")
                rc, o, to = run(["go", "-C", d, "list", "-deps", "-e", "-f",
                                 "{{if .Error}}{{.ImportPath}}{{end}}", pkg], 120, env=genv, cwd=ROOT)
                if rc != 0 or o.strip():
                    missing.append(f"go deps of {pkg} not resolvable offline (module cache incomplete)")
            elif kind not in ("bin", "dir", "file"):
                raise ValueError(f"workload {w["id"]}: unknown needs kind {n!r}")
        r = {"id": w["id"], "title": w["title"], "quick": w["quick"], "checks": []}
        if missing:
            r.update(status="SKIP", reason="; ".join(missing))
            out.append(r)
            continue
        status = "PASS"
        for c in w["checks"]:
            t0 = time.perf_counter()
            rc, o, to = run(["bash", "-c", c["cmd"]], w.get("timeout", 300), env=env, cwd=ROOT)
            cr = {"name": c["name"], "status": "PASS" if rc == 0 else "FAIL", "rc": rc,
                  "seconds": round(time.perf_counter() - t0, 2)}
            if rc != 0:
                cr["output_tail"] = ("TIMEOUT\n" if to else "") + o[-400:]
                status = "FAIL"
            r["checks"].append(cr)
        r["status"] = status
        out.append(r)
    summ = {s: sum(1 for x in out if x["status"] == s) for s in ("PASS", "FAIL", "SKIP")}
    summ["omitted_non_quick"] = omitted
    return {"suite_file": path, "quick": quick, "workloads": out, "summary": summ}


def main():
    o = parse_args(sys.argv[1:])
    res, failed = {}, False
    if o["hooks"]:
        res["hooks_meta"] = bench_hooks(o["quick"])
        res["hooks"] = res["hooks_meta"]["results"]
        failed |= any(r["status"] == "FAIL" for r in res["hooks"])
    if o["suite"]:
        sf = o["suite_file"] or os.path.join(ROOT, "agent", "benchmarks", "vald-suite.yaml")
        try:
            res["suite"] = bench_suite(sf, o["quick"])
            failed |= res["suite"]["summary"]["FAIL"] > 0
        except (ValueError, OSError) as e:
            print(f"suite error: {e}", file=sys.stderr)
            sys.exit(2)
    if o["json"]:
        print(json.dumps(res, indent=2))
    else:
        if "hooks" in res:
            m = res["hooks_meta"]
            print(f"== hooks latency (ms), iterations={m["iterations"]} warmup={m["warmup"]} ==")
            for r in res["hooks"]:
                if r["status"] == "OK":
                    print(f"{r["name"]:<42} p50={r["p50_ms"]:>9} p95={r["p95_ms"]:>9} "
                          f"min={r["min_ms"]:>9} max={r["max_ms"]:>9} rc={r["exit_codes"]}")
                else:
                    print(f"{r["name"]:<42} {r["status"]}: {r.get("reason", "")}")
            for s in m["not_benchmarked"]:
                print(f"not benchmarked: {s["name"]} ({s["reason"]})")
        if "suite" in res:
            print("== suite ==")
            for w in res["suite"]["workloads"]:
                extra = f" ({w["reason"]})" if w["status"] == "SKIP" else ""
                print(f"{w["status"]:<5} {w["id"]:<4} {w["title"]}{extra}")
                for c in w["checks"]:
                    if c["status"] == "FAIL":
                        print(f"      FAIL {c["name"]} rc={c["rc"]}\n{c["output_tail"]}")
            print("summary:", res["suite"]["summary"])
    sys.exit(1 if failed else 0)


main()
PYEOF
)
exec python3 -I -B -c "$PY" "$@"
