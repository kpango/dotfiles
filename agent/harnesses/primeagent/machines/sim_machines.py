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
CAP = 120  # host preview cap is 160; every emitted json stays at or below 120 in the worst case
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
        self.polls = {}
        self.numbers = {}
        self.t = 0.0
        self.bump = {}
        self.events = []

    async def spawn(self, prompt, *, name=None, model=None, thinking=None):
        self.counter += 1
        cid = f"c{self.counter}"
        base = SUFFIX.sub("", name)
        self.spawned[cid] = base
        self.prompts.setdefault(base, []).append(prompt)
        self.running.add(cid)
        self.events.append(("spawn", base))
        self.max_running = max(self.max_running, len(self.running))
        return rlm.RLMSpawnHandle(rlm_child_id=cid, name=name, session_dir=Path("/tmp"), model=model or "")

    async def collect(self, ids, timeout_ms=None):
        out = []
        for cid in ids:
            base = self.spawned[cid]
            if cid not in self.numbers:
                self.numbers[cid] = self.calls[base] = self.calls.get(base, 0) + 1
            n = self.numbers[cid]
            got = self.answers[base](n)
            status, answer = got[0], got[1]
            delay = got[2] if len(got) > 2 else 0
            self.polls[cid] = self.polls.get(cid, 0) + 1
            if self.polls[cid] <= delay:
                out.append(rlm.RLMChildResult(
                    rlm_child_id=cid, session_name=base, session_dir=None, status="running",
                    settled=False, answer_preview=None, error=None, duration_ms=1,
                    tool_use_count=0, replied_since_task=None))
                continue
            self.running.discard(cid)
            self.t += self.bump.get(base, 0)
            self.events.append(("settle", base, n, status))
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
        ex = factory.FactoryExecutor(harness=object(), now=lambda: self.t)
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


INIT = fence({"init": {"ok": True, "run": "0123456789ab", "sha": "a" * 24, "base": "b" * 12}})
INIT_REFUSED = fence({"init": {"ok": False, "run": "0123456789ab"}})
PLAIN_INIT = fence({"init": {"ok": True, "run": "0123456789ab"}})
TESTS = fence({"tests": {"red": True}})


def verify(nxt, passed=False, budget="ok"):
    return fence({"verify": {"next": nxt, "passed": passed, "budget": budget}})


def judge(v):
    return fence({"judgement": {"verdict": v}})


OUTCOME_DONE = fence({"outcome": {"status": "pass"}})
OUTCOME_ESC = fence({"outcome": {"status": "escalated"}})


def impl_answers(maker, checker, init=INIT):
    return {
        "swarm-init": ok(init), "swarm-test-maker": ok(TESTS), "swarm-maker": maker,
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
async def impl_refused_run_dir_escalates():
    s = await Sim(impl_answers(ok(verify("check", True)), ok(judge("PASS")), init=INIT_REFUSED)).run("swarm-implement")
    assert s.entered("escalate") and not s.entered("done") and not s.entered("maker")


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
    for needle in ("{init}", "input.snapshot.json", "sha256sum", "swarm_adapter.verify", "ls-files --others", "<init.base>", "swarm/runs/<run>"):
        assert needle in prompt, f"checker prompt missing {needle!r}"
    assert "verify.json" not in prompt and "git diff HEAD" not in prompt.replace("Do not use `git diff HEAD`", "")
    assert states["maker"]["subagent"]["prompt"].index("budget_guard") < states["maker"]["subagent"]["prompt"].index("implement the task_spec")
    assert states["maker"].get("max_entries", 1) >= 6, "backstop must sit above the 5-attempt path"


@scenario
async def prompts_read_only_inside_run_dir():
    """Stale files of earlier runs are never read: only `init` names the fixed pointer; every
    other prompt addresses swarm files exclusively under swarm/runs/<run>."""
    for name in ("swarm-implement", "swarm-explore", "swarm-review"):
        for st in load(name).spec["states"]:
            prompt = st["subagent"]["prompt"]
            for path in re.findall(r"[^\s`'\"]*swarm/[^\s`'\"]*", prompt):
                if st["id"] == "init":
                    assert path.endswith(".input.json") or "/swarm/runs/" in path, f"{name}.init: {path}"
                else:
                    assert "/swarm/runs/<run>" in path, f"{name}.{st['id']} reads outside the run dir: {path}"
            if st["id"] != "init":
                assert "{init}" in prompt, f"{name}.{st['id']} must be given the bound init json (run id)"
                assert re.search(r"out/(implement|explore|review)", prompt) is None, "old shared out/ directory referenced"


def worst(name, obj):
    return json.dumps({name: obj}, separators=(",", ":"))


def init_emit(basename, with_base=True):
    """What a prompt-compliant init agent emits for a caller-chosen run_dir basename."""
    if re.fullmatch(r"[0-9a-f]{12}", basename) is None:
        return json.dumps({"init": {"ok": False}}, separators=(",", ":"))
    body = {"ok": True, "run": basename}
    if with_base:
        body.update(sha="f" * 24, base="e" * 12)
    return json.dumps({"init": body}, separators=(",", ":"))


def variants(obj_text):
    """Compact, spaced, fenced and indent=4 renderings of one emitted json object."""
    obj = json.loads(obj_text)
    return {"compact": obj_text, "spaced": json.dumps(obj), "fenced": "```json\n" + json.dumps(obj) + "\n```",
            "indent4": json.dumps(obj, indent=4)}


@scenario
async def init_reject_emit_is_constant_and_fuzzed_inputs_fit():
    import random
    rng = random.Random(7)
    alphabet = "abcdef0123456789 /\\\"'`{}[]$&;\u00e9\u3042\n\t-_."
    constant = json.dumps({"init": {"ok": False}}, separators=(",", ":"))
    names = ["0123456789ab", "0123456789AB", "", "a" * 11, "a" * 13, "../" * 20]
    names += ["".join(rng.choice(alphabet) for _ in range(n)) for n in range(1, 201) for _ in range(2)]
    for name in names:
        for with_base in (True, False):
            emit = init_emit(name, with_base)
            if re.fullmatch(r"[0-9a-f]{12}", name) is None:
                assert emit == constant, "reject must be the constant line"
            assert len(emit) <= 120, f"{len(emit)} chars for basename {name!r}"
            for kind, text in variants(emit).items():
                assert len(text) <= 160, f"{kind} variant {len(text)} > 160"
                value, err = factory._parse_json_output(text[:160], "init")
                assert err is None and value["ok"] in (True, False), f"{kind}: {err}"
    # the prompts instruct a constant reject and a compact one-line reply
    for name in ("swarm-implement", "swarm-explore", "swarm-review"):
        init_prompt = next(st for st in load(name).spec["states"] if st["id"] == "init")["subagent"]["prompt"]
        assert '{"init": {"ok": false}}' in init_prompt and "never echoing" in init_prompt
    for name in ("swarm-implement", "swarm-explore", "swarm-review"):
        for st in load(name).spec["states"]:
            if any(o["type"] == "json" for o in st.get("outputs", [])):
                assert "one line of compact JSON" in st["subagent"]["prompt"], f"{name}.{st['id']}"


@scenario
async def outputs_fit_under_cap():
    worst_cases = {
        "swarm-implement": {
            "init": worst("init", {"ok": True, "run": "f" * 12, "sha": "f" * 24, "base": "e" * 12}),
            "test-maker": worst("tests", {"red": False}),
            "maker": worst("verify", {"next": "escalate", "passed": False, "budget": "exceeded"}),
            "checker": worst("judgement", {"verdict": "TAMPER"}),
            "done": worst("outcome", {"status": "escalated"}),
            "escalate": worst("outcome", {"status": "escalated"}),
        },
        "swarm-explore": {
            "init": worst("init", {"ok": True, "run": "f" * 12}),
            "scope": worst("shards", [f"s{i}" for i in range(1, 9)]),
            "secretary": worst("report", {"items": 999, "missing": 8}),
            "explorer": "s8|error|99",
        },
        "swarm-review": {
            "init": worst("init", {"ok": True, "run": "f" * 12}),
            "diff-source": worst("diff", {"changed_files": 999}),
            **{f"lens-{x}": worst("review", {"lens": x, "verdict": "FAIL", "findings": 99})
               for x in ("architecture", "code-quality", "docs-comment", "infra-config", "perf-simd", "security", "shell-config", "systems-lang")},
            "aggregator": worst("summary", {"all_pass": False, "failed": 8}),
        },
    }
    for name, cases in worst_cases.items():
        states = {s["id"]: s for s in load(name).spec["states"]}
        for sid, text in cases.items():
            assert len(text) <= CAP, f"{name}.{sid} worst case {len(text)} > {CAP}"
            if text.startswith("{"):
                for kind, v in variants(text).items():
                    assert len(v) <= 160, f"{name}.{sid} {kind} variant {len(v)} > 160"
            for out in states[sid]["outputs"]:
                if out["type"] != "json":
                    continue
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
    answers = {"swarm-init": ok(PLAIN_INIT), "swarm-diff-source": ok(fence({"diff": {"changed_files": 4}})),
               "swarm-aggregator": ok(fence({"summary": {"all_pass": False, "failed": 1}}))}
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
    last_lens = max(i for i, e in enumerate(s.events) if e[0] == "settle" and e[1].startswith("swarm-lens-"))
    agg = next(i for i, e in enumerate(s.events) if e == ("spawn", "swarm-aggregator"))
    assert agg > last_lens, "aggregator started before every lens settled"


def explore_answers(delays):
    """Explorer n settles after delays[n-1] polls; shard 2 reports its own error immediately."""
    def explorer(n):
        line = f"s{n}|error|0" if n == 2 else f"s{n}|ok|4"
        return ("done", line, delays[n - 1])
    return {"swarm-init": ok(PLAIN_INIT), "swarm-scope": ok(fence({"shards": ["s1", "s2", "s3"]})),
            "swarm-explorer": explorer, "swarm-secretary": ok(fence({"report": {"items": 5, "missing": 1}}))}


@scenario
async def explore_all_ok():
    s = await Sim(explore_answers([0, 0, 0])).run("swarm-explore")
    assert s.entered("secretary") and s.calls["swarm-explorer"] == 3


@scenario
async def explore_staggered_settles_wait_for_every_shard():
    s = await Sim(explore_answers([6, 0, 3])).run("swarm-explore")
    assert s.entered("secretary"), f"run state {s.state}"
    explorer_settles = [i for i, e in enumerate(s.events) if e[0] == "settle" and e[1] == "swarm-explorer"]
    secretary = next(i for i, e in enumerate(s.events) if e == ("spawn", "swarm-secretary"))
    assert len(explorer_settles) == 3 and secretary > max(explorer_settles), "secretary started before every shard settled"
    prompt = s.prompts["swarm-secretary"][0]
    for line in ("s1|ok|4", "s2|error|0", "s3|ok|4"):
        assert line in prompt, f"secretary prompt lacks {line!r}"


@scenario
async def explore_explorer_prompt_catches_errors():
    states = {st["id"]: st for st in load("swarm-explore").spec["states"]}
    prompt = states["explorer"]["subagent"]["prompt"]
    assert "Catch every error" in prompt and "ALWAYS write" in prompt and '"status": "error"' in prompt
    assert not states["secretary"]["inputs"][1].get("optional"), "secretary must require the joined input"


@scenario
async def explore_runtime_failure_ends_failed_without_report():
    """A foreach instance that fails at runtime level (child error) fails the entry at once: the
    secretary's required input cannot bind, no secretary child is ever spawned, the run ends failed."""
    answers = explore_answers([6, 0, 3])
    answers["swarm-explorer"] = lambda n: ("error", None, 0) if n == 2 else ("done", f"s{n}|ok|4", [6, 0, 3][n - 1])
    s = await Sim(answers).run("swarm-explore")
    assert s.state == "failed", s.state
    assert ("spawn", "swarm-secretary") not in s.events, "secretary must not run without its required input"
    assert s.run_obj.states["secretary"].entries[0].status == "error"


MARKERS = ("Reply with one line of compact JSON only (no fence, no other text): ",
           "reply with exactly this constant line, never echoing any part of the input: ")


def templates(prompt):
    """Every JSON reply template a prompt tells the agent to emit, in prompt order
    (case-insensitive marker search, then a balanced-brace scan)."""
    found, low = [], prompt.lower()
    for marker in MARKERS:
        pos = 0
        while (i := low.find(marker.lower(), pos)) != -1:
            start = i + len(marker)
            assert prompt[start] == "{", f"no template after marker: {prompt[start:start + 30]!r}"
            depth = 0
            for j in range(start, len(prompt)):
                depth += (prompt[j] == "{") - (prompt[j] == "}")
                if depth == 0:
                    break
            found.append((start, prompt[start:j + 1]))
            pos = j
    return [t for _, t in sorted(found)]


def fill(template, overrides=None):
    """Substitute placeholders with worst-case fixed-length values; overrides picks an alternative by key."""
    overrides = overrides or {}

    def alt(m):
        key, options = m.group(1), re.findall(r'"([^"]*)"', m.group(2))
        return f'"{key}": "{overrides.get(key) or max(options, key=len)}"'

    t = re.sub(r'"(\w+)": ("[^"]*"(?:\|"[^"]*")+)', alt, template)
    t = re.sub(r"<[^<>]*at most (\d+)>", lambda m: m.group(1), t)
    t = re.sub(r"<(?:number|count)[^<>]*>", "999", t)
    t = re.sub(r"<true\|false>|<bool>", "false", t)
    t = t.replace("<basename of R>", "f" * 12).replace("<24 hex>", "f" * 24).replace("<12 hex>", "e" * 12)
    assert "<" not in t and ">" not in t, f"unfilled placeholder in {t!r}"
    return t


def reply_for(machine, state_id, overrides=None, index=-1):
    st = next(x for x in load(machine).spec["states"] if x["id"] == state_id)
    return fill(templates(st["subagent"]["prompt"])[index], overrides)


@scenario
async def every_prompt_template_is_parseable_json():
    for name in ("swarm-implement", "swarm-explore", "swarm-review"):
        for st in load(name).spec["states"]:
            tpls = templates(st["subagent"]["prompt"])
            json_outs = [o["name"] for o in st.get("outputs", []) if o["type"] == "json"]
            if json_outs:
                assert tpls, f"{name}.{st['id']} has no reply template"
            if st["id"] == "init":
                assert len(tpls) == 2, f"{name}.init must carry reject and accept templates, got {tpls}"
            for tpl in tpls:
                text = fill(tpl)
                value, err = factory._parse_json_output(text, tuple(json.loads(text))[0])
                assert err is None, f"{name}.{st['id']}: {err} in {text!r}"
                assert len(json.dumps(json.loads(text), separators=(",", ":"))) <= 120, f"{name}.{st['id']} template too long"
                if st["id"] != "init":
                    assert tuple(json.loads(text))[0] in json_outs, f"{name}.{st['id']} template key not a declared output"


def verbatim(machine, **choices):
    """Answers for every state: its own prompt template, verbatim after placeholder fill."""
    answers = {}
    for st in load(machine).spec["states"]:
        base = st["subagent"]["name"]
        if st["id"] == "explorer":
            answers[base] = lambda n: ("done", f"s{n}|ok|4")
            continue
        tpls = templates(st["subagent"]["prompt"])
        ov = choices.get(st["id"])
        if st["id"] == "init":
            assert len(tpls) == 2, tpls
            text = fill(tpls[1], None)  # the accepted-run reply (second template; the first is the constant reject)
            answers[base] = ok(text)
        else:
            answers[base] = ok(fill(tpls[0], ov))
    return answers


@scenario
async def prompt_templates_drive_pass_and_escalate_paths():
    ph = {"maker": {"next": "check"}, "checker": {"verdict": "PASS"}}
    s = await Sim(verbatim("swarm-implement", **ph)).run("swarm-implement")
    assert s.entered("done") and not s.entered("escalate"), f"PASS path (run {s.state})"
    assert s.run_obj.states["done"].entries[0].outputs["outcome"]["status"] == "pass"
    s = await Sim(verbatim("swarm-implement", maker={"next": "escalate"})).run("swarm-implement")
    assert s.entered("escalate") and not s.entered("done"), "maker escalate"
    assert s.run_obj.states["escalate"].entries[0].outputs["outcome"]["status"] == "escalated"
    s = await Sim(verbatim("swarm-implement", maker={"next": "check"}, checker={"verdict": "TAMPER"})).run("swarm-implement")
    assert s.entered("escalate") and not s.entered("done"), "TAMPER"
    answers = verbatim("swarm-implement", maker={"next": "check"}, checker={"verdict": "PASS"})
    answers["swarm-init"] = ok(reply_for("swarm-implement", "init", index=0))  # constant reject line (first template)
    s = await Sim(answers).run("swarm-implement")
    assert s.entered("escalate") and not s.entered("done") and not s.entered("maker"), "init reject"
    # review and explore: the verbatim templates carry the whole pipeline to the final state
    s = await Sim(verbatim("swarm-review")).run("swarm-review")
    assert s.entered("aggregator"), f"review (run {s.state})"
    s = await Sim(verbatim("swarm-explore")).run("swarm-explore")
    assert s.entered("secretary") and s.state == "done", f"explore (run {s.state})"


@scenario
async def implement_run_budget_covers_five_attempts():
    spec = load("swarm-implement").spec
    b = {st["id"]: st["budget_ms"] for st in spec["states"]}
    need = b["init"] + b["test-maker"] + 5 * (b["maker"] + b["checker"]) + b["maker"] + b["escalate"]
    assert spec["run"]["budget_ms"] >= need, f"run budget {spec['run']['budget_ms']} < {need}"


FREE_TEXT = lambda n: ("done", "All done, looks good to me!")  # noqa: E731


def impl_ok():
    return impl_answers(ok(verify("check", True)), ok(judge("PASS")))


@scenario
async def failure_test_maker_free_text_pauses():
    a = impl_ok()
    a["swarm-test-maker"] = FREE_TEXT
    s = await Sim(a).run("swarm-implement")
    assert s.state == "paused" and not s.entered("done") and not s.entered("escalate"), s.state
    assert ("spawn", "swarm-maker") not in s.events and "tests" in (s.run_obj.pause_reason or ""), s.run_obj.pause_reason


@scenario
async def failure_maker_child_error_pauses():
    a = impl_ok()
    a["swarm-maker"] = lambda n: ("error", None)
    s = await Sim(a).run("swarm-implement")
    assert s.state == "paused" and not s.entered("escalate") and ("spawn", "swarm-checker") not in s.events, s.state


@scenario
async def failure_budget_overrun_pauses():
    s0 = Sim(impl_ok())
    s0.bump["swarm-test-maker"] = 601  # seconds; test-maker budget_ms is 600000
    s = await s0.run("swarm-implement")
    assert s.state == "paused" and "state budget_ms" in (s.run_obj.pause_reason or ""), (s.state, s.run_obj.pause_reason)
    assert ("spawn", "swarm-maker") not in s.events and not s.entered("escalate")


@scenario
async def failure_unparseable_guard_reply_ends_done_without_outcome():
    for who in ("swarm-maker", "swarm-init"):
        a = impl_ok()
        a[who] = FREE_TEXT
        s = await Sim(a).run("swarm-implement")
        assert s.state == "done" and not s.entered("done") and not s.entered("escalate"), (who, s.state)
    a = impl_ok()
    a["swarm-checker"] = FREE_TEXT
    s = await Sim(a).run("swarm-implement")
    assert s.state == "done" and not s.entered("done") and not s.entered("escalate"), s.state


@scenario
async def failure_review_free_text_pauses():
    a = review_answers({})
    a["swarm-diff-source"] = FREE_TEXT
    s = await Sim(a).run("swarm-review")
    assert s.state == "paused" and not any(e[0] == "spawn" and e[1].startswith("swarm-lens-") for e in s.events), "diff-source free text"
    a = review_answers({})
    a["swarm-lens-security"] = FREE_TEXT
    s = await Sim(a).run("swarm-review")
    assert s.state == "paused" and ("spawn", "swarm-aggregator") not in s.events, "lens free text"


@scenario
async def failure_explore_scope_free_text_fails():
    a = explore_answers([0, 0, 0])
    a["swarm-scope"] = FREE_TEXT
    s = await Sim(a).run("swarm-explore")
    assert s.state == "failed" and ("spawn", "swarm-explorer") not in s.events, s.state


@scenario
async def run_budgets_cover_critical_paths():
    import math
    for name, waves_of in (("swarm-explore", None), ("swarm-review", None)):
        spec = load(name).spec
        b = {st["id"]: st["budget_ms"] for st in spec["states"]}
        par = spec["run"]["max_parallel"]
        if name == "swarm-explore":
            need = b["init"] + b["scope"] + math.ceil(8 / par) * b["explorer"] + b["secretary"]
        else:
            lens = max(v for k, v in b.items() if k.startswith("lens-"))
            need = b["init"] + b["diff-source"] + math.ceil(8 / par) * lens + b["aggregator"]
        assert spec["run"]["budget_ms"] >= need, f"{name}: run budget {spec['run']['budget_ms']} < {need}"
    spec = load("swarm-implement").spec
    assert [st["budget_ms"] for st in spec["states"] if st["id"] == "checker"] == [900000]


async def main():
    for fn in (failure_test_maker_free_text_pauses, failure_maker_child_error_pauses, failure_budget_overrun_pauses,
               failure_unparseable_guard_reply_ends_done_without_outcome, failure_review_free_text_pauses,
               failure_explore_scope_free_text_fails, run_budgets_cover_critical_paths, every_prompt_template_is_parseable_json, prompt_templates_drive_pass_and_escalate_paths,
               implement_run_budget_covers_five_attempts, init_reject_emit_is_constant_and_fuzzed_inputs_fit, explore_runtime_failure_ends_failed_without_report, impl_refused_run_dir_escalates, prompts_read_only_inside_run_dir, impl_pass_path,
               impl_five_verify_failures_escalate, impl_five_checker_fails_escalate,
               impl_tamper_escalates_immediately, impl_checker_is_isolated_and_reverifies,
               outputs_fit_under_cap, review_runs_all_lenses_max_three_parallel, explore_all_ok,
               explore_staggered_settles_wait_for_every_shard, explore_explorer_prompt_catches_errors):
        await fn()
    failed = 0
    for name, passed, why in RESULTS:
        print(("PASS " if passed else "FAIL ") + name + ("" if passed else f"  -> {why}"))
        failed += not passed
    sys.exit(1 if failed else 0)


asyncio.run(main())
