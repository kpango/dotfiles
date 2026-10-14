---
name: swarm-implement
description: Maker/Checker loop for one task (failing tests first, implementation verified by swarm_adapter.verify, cross-family checker that re-verifies, explicit pass/escalated outcome, per-run directory).
version: 1
author: kpango
---

# swarm-implement

## What this machine does

Runs one implementation task as a guarded loop with EXPLICIT terminal states. `init` validates the per-run directory, snapshots the input read-only inside it and returns `{ok, run, sha, base}` (24-hex sha256 prefix of the snapshot, 12-hex base commit); the runtime binds that json into later prompts, so the maker cannot change it. `ok:false` goes straight to `escalate`. `test-maker` (High) writes failing tests only. `maker` (High) first calls `swarm_adapter.budget_guard(<run>, mission=<mission>)`, then implements and runs `swarm_adapter.verify`; `verify.next` decides: `retry` returns to `maker`, `check` goes to `checker`, `escalate` goes to `escalate`. `checker` (XHigh, cross-family) gets no maker output: it verifies the snapshot sha256, re-runs `swarm_adapter.verify` itself from the snapshot's commands, and judges `git diff <base>` plus untracked file contents. `PASS` goes to `done`, `FAIL` back to `maker`, `TAMPER` to `escalate`. Attempt 6 is refused by the budget guard, so five maker attempts is a hard limit that ends in `escalate`. The budget task id is the run name: re-running means a new run directory and a fresh 5-attempt budget, while the mission budget (20) keeps accumulating.

**The only success signal is `<run_dir>/outcome.json` with `status` equal to `pass`** (written by the `done` state). A missing file, any other status (`escalated`), or a run that ended without reaching `done` or `escalate` (for example a state emitted unparsable json, so no guard fired; the runtime then marks the run `done`) must be treated as failure. `max_entries: 8` and `max_transitions: 40` are only backstops above the explicit path.

**Residual risk (P-7, CONTEXT.md):** the checker verdict is an LLM judgement, grounded by its own re-run of `swarm_adapter.verify` and the unforgeable bound `init` json, but all agents share one filesystem and one user. A maker could in principle overwrite `outcome.json`, `checker.md` or the tests. Human review of the diff at the gate remains the authority.

## How to run it

The run call takes only a spec name (no input argument). The caller therefore creates a fresh per-run directory, puts the task in it, and writes ONE fixed pointer file that only `init` reads:

    import json, os, uuid
    d = os.environ.get("PRIME_AGENT_CODING_AGENT_DIR") or os.path.expanduser("~/.prime/agent")
    run_dir = f"{d}/swarm/runs/{uuid.uuid4().hex[:12]}"; os.makedirs(run_dir)   # fresh, empty
    json.dump({"mission": "m", "task_spec": "...", "worktree": "/abs/worktree", "commands": ["make test"], "test_commands": ["make test"]}, open(run_dir + "/input.json", "w"))
    json.dump({"run_dir": run_dir}, open(f"{d}/swarm/implement.input.json", "w"))   # pointer, only run_dir
    result = await rlm.factory.run("swarm-implement")

Start runs one at a time: wait until `init` has settled (`rlm.factory.status`) before rewriting the pointer for another run of the same machine. `init` refuses (`ok:false`) when `run_dir` is not directly under `<agent dir>/swarm/runs/`, its name is not 12 hex characters, or it holds anything except `input.json`. Every later state reads and writes only inside that run directory, so files of earlier runs are never read.

Output ports are captured answer previews (the host caps them at 160
characters), so every state emits one compact json block of at most 120
characters and writes everything else to files inside the per-run directory
`${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run id>/`. Guards branch only on those json fields, never on
prose. Machines are deployed by `make primeagent/install` (the T10 task adds
that wiring) and need the factory enabled (`factory.enabled` is already true in
the primeagent settings.json).

```machine-spec
{
  "run": {
    "budget_ms": 3600000,
    "failure_policy": "escalate",
    "max_parallel": 3,
    "max_transitions": 40
  },
  "states": [
    {
      "id": "init",
      "entry": true,
      "subagent": {
        "prompt": "Orchestrator setup, no judgement. Read the pointer file ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/implement.input.json (json: run_dir). Let R = run_dir. Refuse (ok=false, change nothing) unless R is a directory directly under ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/, its basename matches ^[0-9a-f]{12}$, and it contains exactly one entry, input.json. Otherwise copy R/input.json to R/input.snapshot.json, chmod 444 the copy, compute the first 24 hex characters of `sha256sum R/input.snapshot.json` and `git -C <worktree> rev-parse --short=12 HEAD` (worktree from the snapshot). Return only a fenced json block {\"init\": {\"ok\": <bool>, \"run\": \"<basename of R>\", \"sha\": \"<24 hex>\", \"base\": \"<12 hex>\"}} and no other text.",
        "name": "swarm-init",
        "model": "opencode-go/qwen3.8-flash"
      },
      "outputs": [
        {
          "name": "init",
          "type": "json"
        }
      ],
      "budget_ms": 300000
    },
    {
      "id": "test-maker",
      "subagent": {
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Read and write files only inside RUN; never read any other swarm file. Read RUN/input.snapshot.json (json: task_spec, worktree, test_commands[]); work only inside its `worktree`. Write FAILING tests only for the task_spec: add or edit test files, touch no non-test code, run test_commands once to confirm they fail for the right reason. Return only a fenced json block {\"tests\": {\"red\": <true|false>}} and no other text. init: {init}",
        "name": "swarm-test-maker",
        "model": "prime-inference/anthropic/claude-sonnet-5"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        }
      ],
      "outputs": [
        {
          "name": "tests",
          "type": "json"
        }
      ],
      "budget_ms": 900000
    },
    {
      "id": "maker",
      "subagent": {
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Read and write files only inside RUN; never read any other swarm file. Read RUN/input.snapshot.json (json: mission, task_spec, worktree, commands[]); work only inside its `worktree`. Step 1, before anything else: in the Python REPL run `import swarm_adapter` then `b = await swarm_adapter.budget_guard(<run>, mission=<mission>)` (task id = the run name, so every run has a fresh 5-attempt budget while the mission budget accumulates). If b[\"exit_code\"] != 0 the budget is exhausted: change nothing and return next=\"escalate\". Step 2: implement the task_spec so the new tests pass; never weaken or delete tests. If RUN/checker.md exists, read it and fix what it names first. Step 3: `v = await swarm_adapter.verify(commands, worktree)`; write the full result to RUN/verify.json. Return only a fenced json block {\"verify\": {\"next\": \"retry\"|\"check\"|\"escalate\", \"passed\": <bool>, \"budget\": \"ok\"|\"exceeded\"}} and no other text: next=\"escalate\" when the budget is exceeded, else \"check\" when v[\"passed\"] is true, else \"retry\". Never report passed=true unless verify returned it. init: {init} tests: {tests}",
        "name": "swarm-maker",
        "model": "prime-inference/anthropic/claude-sonnet-5",
        "thinking": "high"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        },
        {
          "name": "tests",
          "type": "json",
          "from": "test-maker.tests"
        }
      ],
      "outputs": [
        {
          "name": "verify",
          "type": "json"
        }
      ],
      "max_entries": 8,
      "budget_ms": 1500000
    },
    {
      "id": "checker",
      "subagent": {
        "prompt": "You are an independent Checker. Trust nothing the maker wrote (its saved verification output, notes, commit messages); you have no maker statement. Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init} (bound by the orchestrator, not forgeable by the maker). Read only RUN/input.snapshot.json. 1. `sha256sum RUN/input.snapshot.json` must start with init.sha (first 24 hex); if not, verdict TAMPER. 2. Take task_spec, worktree, commands[] from the snapshot only. 3. Re-run verification yourself: in the Python REPL `import swarm_adapter; v = await swarm_adapter.verify(commands, worktree)`; if v[\"passed\"] is not true the verdict is FAIL. 4. Judge the change against task_spec: `git -C <worktree> diff <init.base>` plus every untracked file from `git -C <worktree> ls-files --others --exclude-standard` (read their contents). Do not use `git diff HEAD`. Check correctness, regressions, missing tests, overreach. Write your reasoning (mast category i-iii, reasons) to RUN/checker.md (replace it). Return only a fenced json block {\"judgement\": {\"verdict\": \"PASS\"|\"FAIL\"|\"TAMPER\"}} and no other text. PASS only if steps 1 and 3 succeeded and step 4 found no defect. init: {init}",
        "name": "swarm-checker",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        }
      ],
      "outputs": [
        {
          "name": "judgement",
          "type": "json"
        }
      ],
      "max_entries": 8,
      "budget_ms": 1200000
    },
    {
      "id": "done",
      "subagent": {
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Read and write files only inside RUN; never read any other swarm file. Write RUN/outcome.json with exactly {\"status\": \"pass\"} (replace any existing file). Return only a fenced json block {\"outcome\": {\"status\": \"pass\"}} and no other text. init: {init}",
        "name": "swarm-done",
        "model": "opencode-go/qwen3.8-flash"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        }
      ],
      "outputs": [
        {
          "name": "outcome",
          "type": "json"
        }
      ],
      "budget_ms": 120000
    },
    {
      "id": "escalate",
      "subagent": {
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init} (if init.ok is false, do nothing in the directory and write nothing). Otherwise write RUN/outcome.json with exactly {\"status\": \"escalated\"} (replace any existing file). Return only a fenced json block {\"outcome\": {\"status\": \"escalated\"}} and no other text. init: {init}",
        "name": "swarm-escalate",
        "model": "opencode-go/qwen3.8-flash"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        }
      ],
      "outputs": [
        {
          "name": "outcome",
          "type": "json"
        }
      ],
      "budget_ms": 120000
    }
  ],
  "transitions": [
    {
      "from": "init",
      "to": "test-maker",
      "when": {
        "output": "init",
        "path": "ok",
        "op": "eq",
        "value": true
      }
    },
    {
      "from": "init",
      "to": "escalate",
      "when": {
        "output": "init",
        "path": "ok",
        "op": "eq",
        "value": false
      }
    },
    {
      "from": "test-maker",
      "to": "maker"
    },
    {
      "from": "maker",
      "to": "maker",
      "when": {
        "output": "verify",
        "path": "next",
        "op": "eq",
        "value": "retry"
      }
    },
    {
      "from": "maker",
      "to": "checker",
      "when": {
        "output": "verify",
        "path": "next",
        "op": "eq",
        "value": "check"
      }
    },
    {
      "from": "maker",
      "to": "escalate",
      "when": {
        "output": "verify",
        "path": "next",
        "op": "eq",
        "value": "escalate"
      }
    },
    {
      "from": "checker",
      "to": "maker",
      "when": {
        "output": "judgement",
        "path": "verdict",
        "op": "eq",
        "value": "FAIL"
      }
    },
    {
      "from": "checker",
      "to": "done",
      "when": {
        "output": "judgement",
        "path": "verdict",
        "op": "eq",
        "value": "PASS"
      }
    },
    {
      "from": "checker",
      "to": "escalate",
      "when": {
        "output": "judgement",
        "path": "verdict",
        "op": "eq",
        "value": "TAMPER"
      }
    }
  ]
}
```
