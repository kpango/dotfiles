---
name: swarm-implement
description: Maker/Checker loop for one task (failing tests first, implementation verified by swarm_adapter.verify, cross-family diff-only checker, at most 5 maker attempts).
version: 1
author: kpango
---

# swarm-implement

## What this machine does

Runs one implementation task as a guarded loop. `test-maker` (High) writes failing tests only. `maker` (High) implements in the task's worktree and must run `swarm_adapter.verify` with the repo's deterministic commands; its `verify.passed` decides the next state (false: back to `maker`, true: on to `checker`). `checker` (XHigh, cross-family) sees only the task spec and `git diff`, never the maker's self-assessment (no debate). A `FAIL` verdict returns to `maker`; `PASS` ends the run (no outgoing transition). The maker is capped by `max_entries: 5` (at most 5 attempts) with `max_transitions: 12` and `failure_policy: escalate` as backstops: the run pauses for the operator instead of spinning. If the maker emits no parsable `verify` json no guard fires and the run ends.

## How to run it

The run call takes only a spec name (no input argument), so the task is passed through a file the states read:

    import json, os
    d = os.environ.get("PRIME_AGENT_CODING_AGENT_DIR") or os.path.expanduser("~/.prime/agent")
    os.makedirs(d + "/swarm/out/implement", exist_ok=True)
    json.dump({"task_spec": "...", "worktree": "/abs/worktree", "commands": ["make test"], "test_commands": ["make test"]},
              open(d + "/swarm/implement.input.json", "w"))
    result = await rlm.factory.run("swarm-implement")
    await rlm.factory.status(result["run_id"])

One run at a time per machine (the input file is shared). Allocate the worktree first with `swarm_adapter.worktree_alloc`.

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
    "max_transitions": 12
  },
  "states": [
    {
      "id": "test-maker",
      "entry": true,
      "subagent": {
        "prompt": "Read the task input file ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/implement.input.json (json: task_spec, worktree, commands[], test_commands[]). All repo work happens inside its `worktree` directory (cd there first); never touch any other checkout. Write FAILING tests only for the task_spec: add or edit test files, touch no non-test code, run the tests once to confirm they fail for the right reason. Return only a fenced json block {\"tests\": {\"files\": [\"relative/path\"], \"red\": <true|false>}} (red=true when the new tests fail).",
        "name": "swarm-test-maker",
        "model": "prime-inference/anthropic/claude-sonnet-5"
      },
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
        "prompt": "Read the task input file ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/implement.input.json (json: task_spec, worktree, commands[], test_commands[]). All repo work happens inside its `worktree` directory (cd there first); never touch any other checkout. Implement the task_spec so the new tests pass. Do not weaken or delete the tests. Then run `import swarm_adapter` in the Python REPL and `v = await swarm_adapter.verify(commands, worktree)` with the input file's `commands`. Write the full verify result as json to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/verify.json. Return only a fenced json block {\"verify\": {\"passed\": <v[\"passed\"] as a boolean>, \"file\": \"<path of verify.json>\"}}. Never claim passed=true unless verify returned it. If a previous checker judgement or verify result is bound below, read the details in ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/checker.md and ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/verify.json and fix those problems first.\n\nTests: {tests}\nPrevious verify: {prev_verify}\nPrevious judgement: {judgement}",
        "name": "swarm-maker",
        "model": "prime-inference/anthropic/claude-sonnet-5",
        "thinking": "high"
      },
      "inputs": [
        {
          "name": "tests",
          "type": "json",
          "from": "test-maker.tests"
        },
        {
          "name": "prev_verify",
          "type": "json",
          "from": "maker.verify",
          "optional": true
        },
        {
          "name": "judgement",
          "type": "json",
          "from": "checker.judgement",
          "optional": true
        }
      ],
      "outputs": [
        {
          "name": "verify",
          "type": "json"
        }
      ],
      "max_entries": 5,
      "budget_ms": 1500000
    },
    {
      "id": "checker",
      "subagent": {
        "prompt": "You are an independent Checker. Read the task input file ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/implement.input.json but use ONLY its `task_spec` and `worktree`. Run `git -C <worktree> diff HEAD` (plus `git -C <worktree> status --short` for untracked files) and judge the diff against the task_spec for correctness, regressions, missing tests and overreach. You have no maker statement; do not look for one. Write your reasoning to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/implement/checker.md. Return only a fenced json block {\"judgement\": {\"verdict\": \"PASS\"|\"FAIL\", \"mast_category\": \"<MAST i-iii or none>\", \"reason\": \"<one sentence, max 100 chars>\"}}.",
        "name": "swarm-checker",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "outputs": [
        {
          "name": "judgement",
          "type": "json"
        }
      ],
      "max_entries": 5,
      "budget_ms": 900000
    }
  ],
  "transitions": [
    {
      "from": "test-maker",
      "to": "maker"
    },
    {
      "from": "maker",
      "to": "maker",
      "when": {
        "output": "verify",
        "path": "passed",
        "op": "eq",
        "value": false
      }
    },
    {
      "from": "maker",
      "to": "checker",
      "when": {
        "output": "verify",
        "path": "passed",
        "op": "eq",
        "value": true
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
    }
  ]
}
```
