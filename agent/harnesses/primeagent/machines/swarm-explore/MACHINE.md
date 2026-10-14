---
name: swarm-explore
description: Read-only fan-out exploration (split a question into at most 8 shards, explore each cheaply, then dedupe and prioritize, per-run directory).
version: 1
author: kpango
---

# swarm-explore

## What this machine does

`init` validates the per-run directory and snapshots the input. `scope` (Medium) splits the question into at most 8 shards and writes them to `shards.json`. `explorer` (Low) fans out once per shard via `foreach` (max 8, bounded by `max_parallel: 8`), strictly read-only. An explorer never fails: it catches its own errors and always writes `findings-<shard>.json` with `status` ok or error and emits a normal line, because a failed foreach instance would make the runtime start the secretary before the other shards settled. `secretary` (Medium) takes the joined lines (required), reads exactly the shards listed in `shards.json`, and only deduplicates and prioritizes; no new research. The result is `<run_dir>/report.md` plus `report.items`/`report.missing`; no `report.md` means the run did not complete (for example `init` refused, in which case no guard fires and the run ends).

## How to run it

The run call takes only a spec name (no input argument). The caller therefore creates a fresh per-run directory, puts the task in it, and writes ONE fixed pointer file that only `init` reads:

    import json, os, uuid
    d = os.environ.get("PRIME_AGENT_CODING_AGENT_DIR") or os.path.expanduser("~/.prime/agent")
    run_dir = f"{d}/swarm/runs/{uuid.uuid4().hex[:12]}"; os.makedirs(run_dir)   # fresh, empty
    json.dump({"question": "...", "roots": ["/abs/repo"]}, open(run_dir + "/input.json", "w"))
    json.dump({"run_dir": run_dir}, open(f"{d}/swarm/explore.input.json", "w"))   # pointer, only run_dir
    result = await rlm.factory.run("swarm-explore")

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
    "budget_ms": 1800000,
    "failure_policy": "continue",
    "max_parallel": 8,
    "max_transitions": 24
  },
  "states": [
    {
      "id": "init",
      "entry": true,
      "subagent": {
        "prompt": "Orchestrator setup, no judgement. Read the pointer file ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/explore.input.json (json: run_dir). Let R = run_dir. Refuse (ok=false, change nothing) unless R is a directory directly under ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/, its basename matches ^[0-9a-f]{12}$, and it contains exactly one entry, input.json. Otherwise copy R/input.json to R/input.snapshot.json, chmod 444 the copy. Return only a fenced json block {\"init\": {\"ok\": <bool>, \"run\": \"<basename of R>\"}} and no other text.",
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
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Read and write files only inside RUN; never read any other swarm file. Read RUN/input.snapshot.json (json: question, roots[]). Split the question into at most 8 disjoint shards that together cover it (by directory, subsystem or sub-question). Write RUN/shards.json as an object mapping shard id (s1..s8) to a one-sentence scope including the paths to read. Return only a fenced json block {\"shards\": [\"s1\", \"s2\"]} listing the ids (max 8) and no other text. init: {init}",
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
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Read and write files only inside RUN; never read any other swarm file. Read-only exploration of one shard. Look up shard {shard} in RUN/shards.json and the overall question in RUN/input.snapshot.json. Use only reading tools (read, grep, find, git log/show); never edit repo files or run builds. You must never fail: catch every error yourself. ALWAYS write RUN/findings-{shard}.json, as {\"status\": \"ok\", \"findings\": [{\"claim\": str, \"evidence\": \"path:line\", \"confidence\": \"high|medium|low\"}]} on success or {\"status\": \"error\", \"error\": \"<short reason>\"} when you could not finish, then reply with one short line only: `<shard>|ok|<number of findings>` or `<shard>|error|0`. init: {init}",
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
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Read and write files only inside RUN; never read any other swarm file. Aggregate only. Read RUN/shards.json and exactly the files RUN/findings-<shard>.json for the shards listed there (no other findings file); a file with status error or a missing file counts as missing and its shard id goes into the report. No new research, no repo reads. Deduplicate, merge overlapping claims, order by importance. Write RUN/report.md. Return only a fenced json block {\"report\": {\"items\": <count>, \"missing\": <number of missing shards>}} and no other text.\n\ninit: {init}\nShard lines:\n{found}",
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
