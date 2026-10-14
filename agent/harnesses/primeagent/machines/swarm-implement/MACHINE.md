---
name: swarm-implement
description: Maker/Checker loop for one task (failing tests first, implementation verified by swarm_adapter.verify, cross-family checker that re-verifies, explicit pass/escalated outcome, per-run directory).
version: 1
author: kpango
---

# swarm-implement

## What this machine does

Runs one implementation task as a guarded loop with EXPLICIT terminal states. `init` validates the per-run directory, snapshots the input read-only inside it and returns `{ok, run, sha, base}` (24-hex sha256 prefix of the snapshot, 12-hex base commit); the runtime binds that json into later prompts, so the maker cannot change it. `ok:false` goes straight to `escalate`. `test-maker` (High) writes failing tests only. `maker` (High) first calls `swarm_adapter.budget_guard(<run>, mission=<mission>)`, then implements and runs `swarm_adapter.verify`; `verify.next` decides: `retry` returns to `maker`, `check` goes to `checker`, `escalate` goes to `escalate`. `checker` (XHigh, cross-family) gets no maker output: it verifies the snapshot sha256, re-runs `swarm_adapter.verify` itself from the snapshot's commands, and judges `git diff <base>` plus untracked file contents. `PASS` goes to `done`, `FAIL` back to `maker`, `TAMPER` to `escalate`. Attempt 6 is refused by the budget guard, so five maker attempts is a hard limit that ends in `escalate`. The budget task id is the run name: re-running means a new run directory and a fresh 5-attempt budget, while the mission budget (20) keeps accumulating.

**Outcomes (what the caller sees).** The only success signal is `<run_dir>/outcome.json` with `status` equal to `pass`, written by the `done` state; a run can only be trusted when both the run state is `done` and that file says `pass`.

| Run state | `outcome.json` | Meaning and what to do |
|---|---|---|
| `done` | `pass` | Success (the checker's PASS, grounded by its own re-run of verify). |
| `done` | `escalated` | The `escalate` state ran: budget guard refused attempt 6, checker `TAMPER`, or the maker chose `escalate`. Failure; hand to a human. |
| `done` | missing | No guard fired. Causes: an `init`, maker or checker reply that is not parseable json (the guard sees a missing port and every comparison fails), or an `init` refusal (`ok:false` goes to `escalate`, which deliberately writes nothing because `run_dir` may be invalid). Failure by the missing-file rule; read the node answers with `await rlm.factory.status(run_id)`. |
| `paused` | missing | The run `failure_policy` is `escalate` (factory.py `_apply_instance_failure`, escalate branch sets `paused` with `pause_reason`). Triggers: a child error, a per-state `budget_ms` overrun (admission to settlement), or a required-input bind failure (for example a `test-maker` reply that is not json, so `maker`'s required `tests` input cannot bind). There is no `escalate` state and no `outcome.json`. Inspect with `await rlm.factory.status(run_id)` (`state`, `pause_reason`, node errors). Do NOT expect `resume` to retry: `await rlm.factory.resume(run_id)` does not re-run the errored entry (retries default to 0); depending on the case it ends the run `failed` at once, or fires the pending transition whose dependent then cannot bind its input and pauses once more (a second `resume` then ends `failed`; simulator `failure_resume_after_pause_ends_failed`). Use `await rlm.factory.stop(run_id)` and start a NEW run directory instead. The run `budget_ms` also pauses the run once when exceeded; that one pause (unlike the failures above) is a deliberate operator decision and `resume` continues past it. |
| `failed` | missing | The run was paused by one of the failures above and then `resume`d (once or twice), or stopped: any errored entry makes the run `failed` when it finalizes. Failure; start a new run directory (new budget). `failed` is not resumable. |

`max_entries: 8` and `max_transitions: 40` are only backstops above the explicit path. `tests.red` is reported but not gated: a test-maker that returns `red:false` still lets the maker proceed, and the checker's own re-verification is the defence (a prompt/LLM contract). Run budget arithmetic (per-state `budget_ms`, measured admission to settlement): init 120000 + test-maker 600000 + 5 x (maker 900000 + checker 900000) + the sixth maker entry that the budget guard refuses 900000 + escalate 60000 = 10680000 ms, so the run `budget_ms` of 12000000 leaves margin and the five-attempt escalation is reached before the run budget could pause the run. The checker's 900000 sits above `swarm_adapter.verify`'s default per-command timeout.

## Residual risks

- Keeping machine state and outputs only inside the run directory is a prompt contract. The worktree is accessed as stated: `test-maker` and `maker` edit it, `checker` reads it.
- The fixed pointer file `swarm/<machine>.input.json` limits concurrency: start runs of one machine one at a time and wait for `init` to settle.
- Output size is bounded by prompt instructions (one line of compact JSON, fixed-length fields). A model that adds free text can push an answer over the preview cap or break the json; depending on the state the run then pauses or ends `done` without the result file (see Outcomes).
- Nothing in the runtime sandboxes the child agents: all agents share one filesystem and one user, so every restriction below is a prompt contract, not an enforced guarantee.
- The checker verdict is an LLM judgement, grounded by its own re-run of `swarm_adapter.verify` and by the runtime-bound `init` json (CONTEXT.md P-7). It is not a guarantee: a maker sharing the filesystem could in principle overwrite `outcome.json`, `checker.md` or the tests. Human review of the diff at the gate remains the authority.
- `swarm_adapter.verify(commands, cwd)` runs the commands sequentially with a default timeout of 600 s per command (swarm-adapter `verify`, `timeout: float = 600`). Both `maker` (900000 ms) and `checker` (900000 ms) run it once per entry, so a gate set whose total runtime approaches 900 s will exceed the state `budget_ms` and pause the run. Size budgets first: sum the gate's command times plus implementation or judging time, then raise the maker and checker `budget_ms` and the implement run `budget_ms` together (the arithmetic in this file and `run_budgets_cover_critical_paths` in the simulator must still hold).


## How to run it

The run call takes only a spec name (no input argument). The caller therefore creates a fresh per-run directory, puts the task in it, and writes ONE fixed pointer file that only `init` reads:

    import json, os, uuid
    d = os.environ.get("PRIME_AGENT_CODING_AGENT_DIR") or os.path.expanduser("~/.prime/agent")
    run_dir = f"{d}/swarm/runs/{uuid.uuid4().hex[:12]}"; os.makedirs(run_dir)   # fresh, empty
    json.dump({"mission": "m", "task_spec": "...", "worktree": "/abs/worktree", "commands": ["make test"], "test_commands": ["make test"]}, open(run_dir + "/input.json", "w"))
    json.dump({"run_dir": run_dir}, open(f"{d}/swarm/implement.input.json", "w"))   # pointer, only run_dir
    result = await rlm.factory.run("swarm-implement")

Start runs one at a time: wait until `init` has settled (`rlm.factory.status`) before rewriting the pointer for another run of the same machine. `init` refuses (`ok:false`) when `run_dir` is not directly under `<agent dir>/swarm/runs/`, its name is not 12 hex characters, or it holds anything except `input.json`. Every later state keeps its machine state and outputs only inside that run directory, so files of earlier runs are not read by prompt contract (see Residual risks).

Output ports are captured answer previews (the host caps them at 160
characters), so every state emits one line of compact JSON of at most 120
characters and writes everything else to files inside the per-run directory
`${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run id>/`. Guards branch only on those json fields, never on
prose. Machines are deployed by `make primeagent/install` (the T10 task adds
that wiring) and need the factory enabled (`factory.enabled` is already true in
the primeagent settings.json).

```machine-spec
{
  "run": {
    "budget_ms": 12000000,
    "failure_policy": "escalate",
    "max_parallel": 3,
    "max_transitions": 40
  },
  "states": [
    {
      "id": "init",
      "entry": true,
      "subagent": {
        "prompt": "Orchestrator setup, no judgement. Read the pointer file ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/implement.input.json (json: run_dir). Let R = run_dir. Accept only if R is a directory directly under ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/, its basename matches ^[0-9a-f]{12}$, and it contains exactly one entry, input.json. If not accepted, change nothing and reply with exactly this constant line, never echoing any part of the input: {\"init\": {\"ok\": false}}. If accepted, copy R/input.json to R/input.snapshot.json, chmod 444 the copy, compute the first 24 hex characters of `sha256sum R/input.snapshot.json` and `git -C <worktree> rev-parse HEAD | cut -c1-12` (worktree from the snapshot). Then reply with one line of compact JSON only (no fence, no other text): {\"init\": {\"ok\": true, \"run\": \"<basename of R>\", \"sha\": \"<24 hex>\", \"base\": \"<12 hex>\"}}.",
        "name": "swarm-init",
        "model": "opencode-go/qwen3.8-flash"
      },
      "outputs": [
        {
          "name": "init",
          "type": "json"
        }
      ],
      "budget_ms": 120000
    },
    {
      "id": "test-maker",
      "subagent": {
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; never read any other swarm file. Read RUN/input.snapshot.json (json: task_spec, worktree, test_commands[]); work only inside its `worktree`. Write FAILING tests only for the task_spec: add or edit test files, touch no non-test code, run test_commands once to confirm they fail for the right reason. Reply with one line of compact JSON only (no fence, no other text): {\"tests\": {\"red\": <true|false>}}. init: {init}",
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
      "budget_ms": 600000
    },
    {
      "id": "maker",
      "subagent": {
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; never read any other swarm file. Read RUN/input.snapshot.json (json: mission, task_spec, worktree, commands[]); work only inside its `worktree`. Step 1, before anything else: in the Python REPL run `import swarm_adapter` then `b = await swarm_adapter.budget_guard(<run>, mission=<mission>)` (task id = the run name, so every run has a fresh 5-attempt budget while the mission budget accumulates). If b[\"exit_code\"] != 0 the budget is exhausted: change nothing and return next=\"escalate\". Step 2: implement the task_spec so the new tests pass; never weaken or delete tests. If RUN/checker.md exists, read it and fix what it names first. Step 3: `v = await swarm_adapter.verify(commands, worktree)`; write the full result to RUN/verify.json. Reply with one line of compact JSON only (no fence, no other text): {\"verify\": {\"next\": \"retry\"|\"check\"|\"escalate\", \"passed\": <bool>, \"budget\": \"ok\"|\"exceeded\"}}: next=\"escalate\" when the budget is exceeded, else \"check\" when v[\"passed\"] is true, else \"retry\". Never report passed=true unless verify returned it. init: {init} tests: {tests}",
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
      "budget_ms": 900000
    },
    {
      "id": "checker",
      "subagent": {
        "prompt": "You are an independent Checker. Trust nothing the maker wrote (its saved verification output, notes, commit messages); you have no maker statement. Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init} (bound by the orchestrator, not forgeable by the maker). Read only RUN/input.snapshot.json. 1. `sha256sum RUN/input.snapshot.json` must start with init.sha (first 24 hex); if not, verdict TAMPER. 2. Take task_spec, worktree, commands[] from the snapshot only. 3. Re-run verification yourself: in the Python REPL `import swarm_adapter; v = await swarm_adapter.verify(commands, worktree)`; if v[\"passed\"] is not true the verdict is FAIL. 4. Judge the change against task_spec: `git -C <worktree> diff <init.base>` plus every untracked file from `git -C <worktree> ls-files --others --exclude-standard` (read their contents). Do not use `git diff HEAD`. Check correctness, regressions, missing tests, overreach. Write your reasoning (mast category i-iii, reasons) to RUN/checker.md (replace it). Reply with one line of compact JSON only (no fence, no other text): {\"judgement\": {\"verdict\": \"PASS\"|\"FAIL\"|\"TAMPER\"}}. PASS only if steps 1 and 3 succeeded and step 4 found no defect. init: {init}",
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
      "budget_ms": 900000
    },
    {
      "id": "done",
      "subagent": {
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; never read any other swarm file. Write RUN/outcome.json with exactly {\"status\": \"pass\"} (replace any existing file). Reply with one line of compact JSON only (no fence, no other text): {\"outcome\": {\"status\": \"pass\"}}. init: {init}",
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
      "budget_ms": 60000
    },
    {
      "id": "escalate",
      "subagent": {
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init} (if init.ok is false, do nothing in the directory and write nothing). Otherwise write RUN/outcome.json with exactly {\"status\": \"escalated\"} (replace any existing file). Reply with one line of compact JSON only (no fence, no other text): {\"outcome\": {\"status\": \"escalated\"}}. init: {init}",
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
      "budget_ms": 60000
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
