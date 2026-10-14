---
name: swarm-explore
description: Read-only fan-out exploration (split a question into at most 8 shards, explore each cheaply, then dedupe and prioritize, per-run directory).
version: 1
author: kpango
---

# swarm-explore

## What this machine does

`init` validates the per-run directory and snapshots the input. `scope` (Medium) splits the question into at most 8 shards and writes them to `shards.json`. `explorer` (Low) fans out once per shard via `foreach` (max 8, bounded by `max_parallel: 8`), strictly read-only. The explorer prompt tells it to catch its own errors and always write `findings-<shard>.json` with `status` ok or error and emit a normal line; this is a prompt contract, not a guarantee. If a foreach instance does fail at runtime level (`budget_ms` exceeded, child error), the runtime settles the entry as failed at once: the secretary's required `found` input cannot bind, the secretary entry errors without ever spawning a child, and the run ends `failed` with no `report.md` (verified by the simulator scenario `explore_runtime_failure_ends_failed_without_report`). `secretary` (Medium) takes the joined lines (required), reads exactly the shards listed in `shards.json`, and only deduplicates and prioritizes; no new research. The result is `<run_dir>/report.md` plus `report.items`/`report.missing`.

**Outcomes (what the caller sees).** The run `failure_policy` is `continue`, so a failure does not pause the run. Run `done` with `report.md`: success. Run `done` without `report.md`: no guard fired (the `init` reply was not parseable json, or `init` refused with `ok:false`); failure. Run `failed` without `report.md`: a child error, a per-state `budget_ms` overrun, or a required-input bind failure (for example a `scope` reply that is not json) errored an entry, so its dependents could not bind (the simulator pins the explorer child error case). Inspect with `await rlm.factory.status(run_id)`; a `failed` run is not resumable, start a new run directory. `await rlm.factory.stop(run_id)` cancels a running run. Run budget arithmetic (critical path): init 120000 + scope 600000 + ceil(8 / max_parallel 8) = 1 explorer wave x 900000 + secretary 600000 = 2220000 ms, so the run `budget_ms` of 3000000 leaves margin.

## Residual risks

- Keeping machine state and outputs only inside the run directory is a prompt contract (the worktree/repo is accessed as stated: `test-maker` and `maker` edit the worktree, `checker` reads it, `diff-source` and the lenses read the repo): nothing in the runtime sandboxes the child agents, and all agents share one filesystem and one user.
- The fixed pointer file `swarm/<machine>.input.json` limits concurrency: start runs of one machine one at a time and wait for `init` to settle.
- Output size is bounded by prompt instructions (one line of compact JSON, fixed-length fields). A model that adds free text can push an answer over the preview cap or break the json; depending on the state the run then pauses or ends `done` without the result file (see Outcomes).
- Explorers catching their own errors and writing `findings-<shard>.json` is a prompt contract. The secretary summarizes what the files say; it is an LLM and can mis-merge. A runtime-level instance failure ends the run `failed` without a report (see Outcomes).


## How to run it

The run call takes only a spec name (no input argument). The caller therefore creates a fresh per-run directory, puts the task in it, and writes ONE fixed pointer file that only `init` reads:

    import json, os, uuid
    d = os.environ.get("PRIME_AGENT_CODING_AGENT_DIR") or os.path.expanduser("~/.prime/agent")
    run_dir = f"{d}/swarm/runs/{uuid.uuid4().hex[:12]}"; os.makedirs(run_dir)   # fresh, empty
    json.dump({"question": "...", "roots": ["/abs/repo"]}, open(run_dir + "/input.json", "w"))
    json.dump({"run_dir": run_dir}, open(f"{d}/swarm/explore.input.json", "w"))   # pointer, only run_dir
    result = await rlm.factory.run("swarm-explore")

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
    "budget_ms": 3000000,
    "failure_policy": "continue",
    "max_parallel": 8,
    "max_transitions": 24
  },
  "states": [
    {
      "id": "init",
      "entry": true,
      "subagent": {
        "prompt": "Orchestrator setup, no judgement. Read the pointer file ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/explore.input.json (json: run_dir). Let R = run_dir. Accept only if R is a directory directly under ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/, its basename matches ^[0-9a-f]{12}$, and it contains exactly one entry, input.json. If not accepted, change nothing and reply with exactly this constant line, never echoing any part of the input: {\"init\": {\"ok\": false}}. If accepted, copy R/input.json to R/input.snapshot.json, chmod 444 the copy. Then reply with one line of compact JSON only (no fence, no other text): {\"init\": {\"ok\": true, \"run\": \"<basename of R>\"}}.",
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
      "id": "scope",
      "subagent": {
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; never read any other swarm file. Read RUN/input.snapshot.json (json: question, roots[]). Split the question into at most 8 disjoint shards that together cover it (by directory, subsystem or sub-question). Write RUN/shards.json as an object mapping shard id (s1..s8) to a one-sentence scope including the paths to read. Reply with one line of compact JSON only (no fence, no other text): {\"shards\": [\"s1\", \"s2\"]} listing the ids (max 8). init: {init}",
        "name": "swarm-scope",
        "model": "opencode-go/kimi-k3"
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
          "name": "shards",
          "type": "json"
        }
      ],
      "budget_ms": 600000
    },
    {
      "id": "explorer",
      "subagent": {
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; never read any other swarm file. Read-only exploration of one shard. Look up shard {shard} in RUN/shards.json and the overall question in RUN/input.snapshot.json. Use only reading tools (read, grep, find, git log/show); never edit repo files or run builds. Catch every error yourself instead of aborting. ALWAYS write RUN/findings-{shard}.json, as {\"status\": \"ok\", \"findings\": [{\"claim\": str, \"evidence\": \"path:line\", \"confidence\": \"high|medium|low\"}]} on success or {\"status\": \"error\", \"error\": \"<short reason>\"} when you could not finish, then reply with one short line only: `<shard>|ok|<number of findings, at most 99>` or `<shard>|error|0`. init: {init}",
        "name": "swarm-explorer",
        "model": "opencode-go/qwen3.8-flash"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        },
        {
          "name": "shard",
          "type": "json",
          "from": "scope.shards"
        }
      ],
      "outputs": [
        {
          "name": "found",
          "type": "text"
        }
      ],
      "foreach": {
        "over": "shard",
        "max": 8
      },
      "budget_ms": 900000
    },
    {
      "id": "secretary",
      "subagent": {
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; never read any other swarm file. Aggregate only. Read RUN/shards.json and exactly the files RUN/findings-<shard>.json for the shards listed there (no other findings file); a file with status error or a missing file counts as missing and its shard id goes into the report. No new research, no repo reads. Deduplicate, merge overlapping claims, order by importance. Write RUN/report.md. Reply with one line of compact JSON only (no fence, no other text): {\"report\": {\"items\": <count, at most 999>, \"missing\": <number of missing shards>}}.\n\ninit: {init}\nShard lines:\n{found}",
        "name": "swarm-secretary",
        "model": "opencode-go/kimi-k3"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        },
        {
          "name": "found",
          "type": "text",
          "from": "explorer.found"
        }
      ],
      "outputs": [
        {
          "name": "report",
          "type": "json"
        }
      ],
      "budget_ms": 600000
    }
  ],
  "transitions": [
    {
      "from": "init",
      "to": "scope",
      "when": {
        "output": "init",
        "path": "ok",
        "op": "eq",
        "value": true
      }
    },
    {
      "from": "scope",
      "to": "explorer"
    },
    {
      "from": "explorer",
      "to": "secretary"
    }
  ]
}
```
