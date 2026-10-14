"""Deterministic regression tests for the swarm factory machines.

Runs the real FactoryExecutor from the installed prime-agent runtime with fake
rlm.spawn/collect (no model calls, no network, no files written by the states).
Usage: python3 -I sim_machines.py [MACHINES_DIR]   (default: this directory)
Exit status is non-zero when any scenario fails.
"""

import asyncio
import json
import os
import re
import sys
import traceback
from pathlib import Path

RUNTIME_SRC = Path(os.environ.get("PRIME_RUNTIME_SRC") or Path.home() / ".local/share/prime-agent/prime-agent-runtime/src")
sys.path.insert(0, str(RUNTIME_SRC))
import rlm  # noqa: E402
from rlm import factory  # noqa: E402

HERE = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent
CAP = factory.ANSWER_CAPTURE_CAP
SUFFIX = re.compile(r"(-i\d+|-a\d+)+$")


def fence(obj):
    return "```json\n" + json.dumps(obj) + "\n```"


def load(name):
    path = HERE / name / "MACHINE.md"
    machine, errors = factory.parse_machine_file(path.read_text(encoding="utf-8"), source=str(path))
    assert machine is not None, errors
    return machine


class Sim:
    """answers: child base name -> callable(call_number) -> (status, answer)."""

    def __init__(self, answers):
        self.answers = answers
        self.calls = {}
        self.prompts = {}
        self.spawned = {}
        self.running = set()
        self.max_running = 0
        self.counter = 0

    async def spawn(self, prompt, *, name=None, model=None, thinking=None):
        self.counter += 1
        cid = f"c{self.counter}"
        base = SUFFIX.sub("", name)
        self.spawned[cid] = base
        self.prompts.setdefault(base, []).append(prompt)
        self.running.add(cid)
        self.max_running = max(self.max_running, len(self.running))
        return rlm.RLMSpawnHandle(rlm_child_id=cid, name=name, session_dir=Path("/tmp"), model=model or "")

    async def collect(self, ids, timeout_ms=None):
        out = []
        for cid in ids:
            base = self.spawned[cid]
            n = self.calls[base] = self.calls.get(base, 0) + 1
            status, answer = self.answers[base](n)
            self.running.discard(cid)
            out.append(
                rlm.RLMChildResult(
                    rlm_child_id=cid, session_name=base, session_dir=None, status=status,
                    settled=True, answer_preview=answer if status == "done" else None,
                    error=None if status == "done" else "boom", duration_ms=1,
                    tool_use_count=0, replied_since_task=None,
                )
            )
        return out

    async def run(self, machine_name):
        async def host_request(kind, payload=None):
            return {}

        rlm.spawn, rlm.collect, rlm.host_request = self.spawn, self.collect, host_request
        ex = factory.FactoryExecutor(harness=object())
        res = await ex.run_machine(load(machine_name))
        run = ex._runs[res["run_id"]]
        for _ in range(5000):
            if run.state != "running":
                break
            await asyncio.sleep(0.001)
        self.run_obj = run
        self.state = run.state
        return self

    def entered(self, state_id):
        st = self.run_obj.states.get(state_id)
        return bool(st and st.entries_used)

    def entries(self, state_id):
        st = self.run_obj.states.get(state_id)
        return st.entries_used if st else 0


def ok(answer):
    return lambda n: ("done", answer)


def seq(*answers):
    """Return answers in order; the last one repeats."""
    return lambda n: ("done", answers[min(n, len(answers)) - 1])


INIT = fence({"init": {"sha": "a" * 64, "base": "b" * 40}})
TESTS = fence({"tests": {"red": True}})


def verify(nxt, passed=False, budget="ok"):
    return fence({"verify": {"next": nxt, "passed": passed, "budget": budget}})


def judge(v):
    return fence({"judgement": {"verdict": v}})


OUTCOME_DONE = fence({"outcome": {"status": "pass"}})
OUTCOME_ESC = fence({"outcome": {"status": "escalated"}})


def impl_answers(maker, checker):
    return {
        "swarm-init": ok(INIT), "swarm-test-maker": ok(TESTS), "swarm-maker": maker,
        "swarm-checker": checker, "swarm-done": ok(OUTCOME_DONE), "swarm-escalate": ok(OUTCOME_ESC),
    }


def maker_five_then_budget(first_next, passed=False):
    """Attempts 1-5 emit first_next; attempt 6 is refused by budget_guard."""
    def f(n):
        if n >= 6:
            return "done", verify("escalate", False, "exceeded")
        return "done", verify(first_next, passed)
    return f


RESULTS = []


def scenario(fn):
    async def wrapper():
        try:
            await fn()
            RESULTS.append((fn.__name__, True, ""))
        except Exception:  # noqa: BLE001 - report every failure, keep going
            RESULTS.append((fn.__name__, False, traceback.format_exc(limit=3).strip().splitlines()[-1]))
    wrapper.__name__ = fn.__name__
    return wrapper


@scenario
async def impl_pass_path():
    s = await Sim(impl_answers(ok(verify("check", True)), ok(judge("PASS")))).run("swarm-implement")
    assert s.entered("done") and not s.entered("escalate"), "PASS must end in explicit done"
    assert s.entries("maker") == 1 and s.entries("checker") == 1


@scenario
async def impl_five_verify_failures_escalate():
    s = await Sim(impl_answers(maker_five_then_budget("retry"), ok(judge("PASS")))).run("swarm-implement")
    assert s.entered("escalate") and not s.entered("done"), "5 verify failures must reach escalate"
    assert s.entries("maker") == 6 and not s.entered("checker")


@scenario
async def impl_five_checker_fails_escalate():
    s = await Sim(impl_answers(maker_five_then_budget("check", True), ok(judge("FAIL")))).run("swarm-implement")
    assert s.entered("escalate") and not s.entered("done"), "5 checker FAILs must reach escalate"
    assert s.entries("checker") == 5


@scenario
async def impl_forged_maker_pass_is_not_success():
    # Maker claims passed=true (fake verify.json) but the checker's own re-verify fails.
    s = await Sim(impl_answers(maker_five_then_budget("check", True), ok(judge("FAIL")))).run("swarm-implement")
    assert not s.entered("done") and s.entered("escalate")


@scenario
async def impl_tamper_escalates_immediately():
    s = await Sim(impl_answers(ok(verify("check", True)), ok(judge("TAMPER")))).run("swarm-implement")
    assert s.entered("escalate") and not s.entered("done") and s.entries("maker") == 1


@scenario
async def impl_checker_is_isolated_and_reverifies():
    m = load("swarm-implement").spec
    states = {st["id"]: st for st in m["states"]}
    sources = {i["from"].split(".")[0] for i in states["checker"].get("inputs", [])}
    assert sources == {"init"}, f"checker must bind only init, got {sources}"
    prompt = states["checker"]["subagent"]["prompt"]
    for needle in ("{init}", "input.snapshot.json", "sha256sum", "swarm_adapter.verify", "ls-files --others", "<init.base>"):
        assert needle in prompt, f"checker prompt missing {needle!r}"
    assert "verify.json" not in prompt and "git diff HEAD" not in prompt.replace("Do not use `git diff HEAD`", "")
    assert states["maker"]["subagent"]["prompt"].index("budget_guard") < states["maker"]["subagent"]["prompt"].index("implement the task_spec")
    assert states["maker"].get("max_entries", 1) >= 6, "backstop must sit above the 5-attempt path"


def worst(name, obj):
    return fence({name: obj})


@scenario
async def outputs_fit_under_cap():
    worst_cases = {
        "swarm-implement": {
            "init": worst("init", {"sha": "f" * 64, "base": "e" * 64}),
            "test-maker": worst("tests", {"red": False}),
            "maker": worst("verify", {"next": "escalate", "passed": False, "budget": "exceeded"}),
            "checker": worst("judgement", {"verdict": "TAMPER"}),
            "done": worst("outcome", {"status": "escalated"}),
            "escalate": worst("outcome", {"status": "escalated"}),
        },
        "swarm-explore": {
            "scope": worst("shards", [f"s{i}" for i in range(1, 9)]),
            "secretary": worst("report", {"items": 99999, "missing": 8}),
        },
        "swarm-review": {
            "diff-source": worst("diff", {"changed_files": 999999}),
            **{f"lens-{x}": worst("review", {"lens": x, "verdict": "FAIL", "findings": 99999})
               for x in ("architecture", "code-quality", "docs-comment", "infra-config", "perf-simd", "security", "shell-config", "systems-lang")},
            "aggregator": worst("summary", {"all_pass": False, "failed": 8}),
        },
    }
    for name, cases in worst_cases.items():
        states = {s["id"]: s for s in load(name).spec["states"]}
        for sid, text in cases.items():
            assert len(text) < CAP, f"{name}.{sid} worst case {len(text)} >= {CAP}"
            for out in states[sid]["outputs"]:
                value, err = factory._parse_json_output(text[:CAP], out["name"])
                assert err is None, f"{name}.{sid}: {err}"
        # every json output the machine declares must have a worst case above
        for sid, st in states.items():
            for out in st.get("outputs", []):
                if out["type"] == "json":
                    assert sid in cases, f"{name}.{sid} has no worst-case entry"
    # an over-long field would truncate and break parsing; the documented outputs carry no free text
    for name in worst_cases:
        for st in load(name).spec["states"]:
            assert '"reason"' not in st["subagent"]["prompt"], f"{name}.{st['id']} output must not carry free text"


def review_answers(verdicts):
    answers = {"swarm-diff-source": ok(fence({"diff": {"changed_files": 4}})),
               "swarm-aggregator": ok(fence({"summary": {"all_pass": not any(v == "FAIL" for v in verdicts.values()), "failed": 0}}))}
    for lens in ("architecture", "code-quality", "docs-comment", "infra-config", "perf-simd", "security", "shell-config", "systems-lang"):
        answers[f"swarm-lens-{lens}"] = ok(fence({"review": {"lens": lens, "verdict": verdicts.get(lens, "PASS"), "findings": 0}}))
    return answers


@scenario
async def review_runs_all_lenses_max_three_parallel():
    s = await Sim(review_answers({"security": "FAIL"})).run("swarm-review")
    assert s.entered("aggregator"), "join must fire after all eight lenses"
    assert all(s.entered(f"lens-{x}") for x in ("architecture", "systems-lang", "security"))
    assert s.max_running <= 3, f"max_parallel breached: {s.max_running}"
    prompt = s.prompts["swarm-diff-source"][0]
    assert "merge-base" in prompt and "ls-files --others" in prompt


def explore_answers(fail_shard=None):
    def explorer(n):
        return ("error", "") if fail_shard == n else ("done", f"s{n}|4")
    return {"swarm-scope": ok(fence({"shards": ["s1", "s2", "s3"]})), "swarm-explorer": explorer,
            "swarm-secretary": ok(fence({"report": {"items": 5, "missing": 1 if fail_shard else 0}}))}


@scenario
async def explore_all_ok():
    s = await Sim(explore_answers()).run("swarm-explore")
    assert s.entered("secretary") and s.calls["swarm-explorer"] == 3


@scenario
async def explore_one_failed_shard_still_reports():
    s = await Sim(explore_answers(fail_shard=2)).run("swarm-explore")
    assert s.entered("secretary"), f"secretary must still run after one failed shard (run state {s.state})"
    assert s.calls.get("swarm-secretary") == 1


async def main():
    for fn in (impl_pass_path, impl_five_verify_failures_escalate, impl_five_checker_fails_escalate,
               impl_forged_maker_pass_is_not_success, impl_tamper_escalates_immediately,
               impl_checker_is_isolated_and_reverifies, outputs_fit_under_cap,
               review_runs_all_lenses_max_three_parallel, explore_all_ok, explore_one_failed_shard_still_reports):
        await fn()
    failed = 0
    for name, passed, why in RESULTS:
        print(("PASS " if passed else "FAIL ") + name + ("" if passed else f"  -> {why}"))
        failed += not passed
    sys.exit(1 if failed else 0)


asyncio.run(main())
