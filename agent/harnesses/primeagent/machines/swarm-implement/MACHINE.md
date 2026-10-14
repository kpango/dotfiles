---
name: swarm-implement
description: Maker/Checker loop for one task (failing tests first, implementation verified by swarm_adapter.verify, cross-family checker that re-verifies, explicit pass/escalated outcome).
version: 1
author: kpango
---

# swarm-implement

## What this machine does

Runs one implementation task as a guarded loop with EXPLICIT terminal states. `init` snapshots the input file (read-only copy plus its sha256 and the base commit sha, which travel through the runtime as the `init` json, not through any file the maker can edit). `test-maker` (High) writes failing tests only. `maker` (High) first calls `swarm_adapter.budget_guard(task_id)` (the 5-attempt budget lives there), then implements and runs `swarm_adapter.verify`; its `verify.next` decides: `retry` returns to `maker`, `check` goes to `checker`, `escalate` goes to the `escalate` state. `checker` (XHigh, cross-family) gets no maker output: it verifies the snapshot sha256, re-runs `swarm_adapter.verify` itself from the snapshot's commands, and judges `git diff <base sha>` plus untracked file contents. `PASS` goes to `done`, `FAIL` back to `maker`, `TAMPER` (snapshot hash mismatch) to `escalate`. Attempt 6 is refused by the budget guard, so five maker attempts is a hard limit that ends in `escalate`.

**The only success signal is `${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/outcome.json` with `status` equal to `pass`** (written by the `done` state). A missing file, any other status (`escalated`), or a run that ended without reaching `done` or `escalate` (for example a state emitted unparsable json, so no guard fired; the runtime then marks the run `done`) must be treated as failure. Delete `outcome.json` before each run. `max_entries: 8` and `max_transitions: 40` are only backstops above the explicit path.

**Residual risk (P-7):** all agents share one filesystem and one user. A maker could in principle overwrite `outcome.json`, `checker.md` or the worktree's test files, or edit the verify commands' targets. The snapshot hash and the checker's own re-verification raise the cost of forging a pass, they do not make it impossible. Human review of the diff at the gate remains the authority.

## How to run it

The run call takes only a spec name (no input argument), so the input is passed through a file the states read:

    import json, os
    d = os.environ.get("PRIME_AGENT_CODING_AGENT_DIR") or os.path.expanduser("~/.prime/agent")
    os.makedirs(d + "/swarm/out/implement", exist_ok=True)
    json.dump({"task_id": "t1", "mission": "m", "task_spec": "...", "worktree": "/abs/worktree", "commands": ["make test"], "test_commands": ["make test"]}, open(d + "/swarm/implement.input.json", "w"))
    result = await rlm.factory.run("swarm-implement")
    await rlm.factory.status(result["run_id"])

One run per machine at a time (the input and out/ directory are shared).

Output ports are captured answer previews capped at about 200 characters, so
every state emits a compact json block and writes the full payload to a file
under `${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/`. Guards branch only on
those json fields, never on prose.

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
        "prompt": "Orchestrator setup, no judgement. Read ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/implement.input.json (json: task_id, task_spec, worktree, commands[], test_commands[]). Copy it byte-for-byte to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/input.snapshot.json (mkdir -p ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement first) and make that copy read-only (chmod 444). Compute `sha256sum ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/input.snapshot.json` and `git -C <worktree> rev-parse HEAD`. Return only a fenced json block {\"init\": {\"sha\": \"<sha256 hex of the snapshot>\", \"base\": \"<HEAD commit sha>\"}} and no other text.",
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
        "prompt": "Read the snapshot ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/input.snapshot.json (json: task_spec, worktree, test_commands[]). Work only inside its `worktree`. Write FAILING tests only for the task_spec: add or edit test files, touch no non-test code, run test_commands once to confirm they fail for the right reason. Return only a fenced json block {\"tests\": {\"red\": <true|false>}} and no other text. Run context: {init}",
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
        "prompt": "Read the snapshot ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/input.snapshot.json (json: task_id, task_spec, worktree, commands[]). Work only inside its `worktree`. Step 1, before anything else: in the Python REPL run `import swarm_adapter` then `b = await swarm_adapter.budget_guard(task_id)`. If b[\"exit_code\"] != 0 the attempt budget is exhausted: change nothing and return next=\"escalate\" (below). Step 2: implement the task_spec so the new tests pass; never weaken or delete tests. If a checker verdict file ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/checker.md exists from an earlier attempt, read it and fix what it names first. Step 3: `v = await swarm_adapter.verify(commands, worktree)`; write the full result to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/verify.json. Return only a fenced json block {\"verify\": {\"next\": \"retry\"|\"check\"|\"escalate\", \"passed\": <bool>, \"budget\": \"ok\"|\"exceeded\"}} and no other text: next=\"escalate\" when the budget is exceeded, else \"check\" when v[\"passed\"] is true, else \"retry\". Never report passed=true unless verify returned it. Tests: {tests}",
        "name": "swarm-maker",
        "model": "prime-inference/anthropic/claude-sonnet-5",
        "thinking": "high"
      },
      "inputs": [
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
        "prompt": "You are an independent Checker. Trust nothing the maker wrote (its saved verification output, notes, commit messages); you have no maker statement. Context bound by the orchestrator (not forgeable by the maker): {init} = {sha, base}. 1. `sha256sum ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/input.snapshot.json` must equal init.sha; if not, verdict TAMPER. 2. Read ONLY ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/input.snapshot.json for task_spec, worktree, commands[]. 3. Re-run verification yourself: in the Python REPL `import swarm_adapter; v = await swarm_adapter.verify(commands, worktree)`; if v[\"passed\"] is not true the verdict is FAIL. 4. Judge the change against task_spec: `git -C <worktree> diff <init.base>` plus every untracked file from `git -C <worktree> ls-files --others --exclude-standard` (read their contents). Do not use `git diff HEAD`. Check correctness, regressions, missing tests, overreach. Write your reasoning (mast category i-iii, reasons) to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/checker.md. Return only a fenced json block {\"judgement\": {\"verdict\": \"PASS\"|\"FAIL\"|\"TAMPER\"}} and no other text. PASS only if steps 1 and 3 succeeded and step 4 found no defect.",
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
        "prompt": "Write ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/outcome.json with exactly {\"status\": \"pass\"} (mkdir -p ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement; replace any existing file). Return only a fenced json block {\"outcome\": {\"status\": \"pass\"}} and no other text.",
        "name": "swarm-done",
        "model": "opencode-go/qwen3.8-flash"
      },
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
        "prompt": "Write ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/outcome.json with exactly {\"status\": \"escalated\"} (mkdir -p ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement; replace any existing file). Return only a fenced json block {\"outcome\": {\"status\": \"escalated\"}} and no other text.",
        "name": "swarm-escalate",
        "model": "opencode-go/qwen3.8-flash"
      },
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
      "to": "test-maker"
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
