---
name: swarm-explore
description: Read-only fan-out exploration (split a question into at most 8 shards, explore each cheaply, then dedupe and prioritize).
version: 1
author: kpango
---

# swarm-explore

## What this machine does

`scope` (Medium) splits the question into at most 8 shards and writes them to a file. `explorer` (Low) fans out once per shard via `foreach` (max 8, bounded by `max_parallel: 8`), strictly read-only, writing findings per shard to a file. `secretary` (Medium) only deduplicates and prioritizes the findings files; it does no new research. One failed shard must not sink the run: `explorer` has `failure_policy: continue`, the guard-less transition still fires after a failed settle, and the secretary's `found` input is optional (null when a shard failed) while it reads the findings files directly. The run is then reported `failed` by the runtime but `out/explore/report.md` exists; the caller reads `report.missing`.

## How to run it

The run call takes only a spec name (no input argument), so the input is passed through a file the states read:

    import json, os
    d = os.environ.get("PRIME_AGENT_CODING_AGENT_DIR") or os.path.expanduser("~/.prime/agent")
    os.makedirs(d + "/swarm/out/explore", exist_ok=True)
    json.dump({"question": "...", "roots": ["/abs/repo"]}, open(d + "/swarm/explore.input.json", "w"))
    result = await rlm.factory.run("swarm-explore")
    await rlm.factory.status(result["run_id"])

One run per machine at a time (the input and out/ directory are shared).

Output ports are captured answer previews capped at about 200 characters, so
every state emits a compact json block and writes the full payload to a file
under `${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/explore/`. Guards branch only on
those json fields, never on prose.

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
      "id": "scope",
      "entry": true,
      "subagent": {
        "prompt": "Read the input file ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/explore.input.json (json: question, roots[]). Split the question into at most 8 disjoint shards that together cover it (by directory, subsystem or sub-question). Write ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/explore/shards.json as an object mapping shard id (s1..s8) to a one-sentence scope including the paths to read. Return only a fenced json block {\"shards\": [\"s1\", \"s2\"]} listing the ids (max 8) and no other text.",
        "name": "swarm-scope",
        "model": "opencode-go/kimi-k3"
      },
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
        "prompt": "Read-only exploration of one shard. Look up shard {shard} in ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/explore/shards.json and the overall question in ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/explore.input.json. Use only reading tools (read, grep, find, git log/show); never edit, write repo files, or run builds. Write findings to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/explore/findings-{shard}.json as a list of {\"claim\": str, \"evidence\": \"path:line\", \"confidence\": \"high|medium|low\"}. Reply with one short line only: `<shard>|<number of findings>`.",
        "name": "swarm-explorer",
        "model": "opencode-go/qwen3.8-flash"
      },
      "inputs": [
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
      "failure_policy": "continue",
      "budget_ms": 900000
    },
    {
      "id": "secretary",
      "subagent": {
        "prompt": "Aggregate only: read every ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/explore/findings-*.json that exists (a failed shard may have none or a partial file; skip it and list its id as missing in the report). No new research, no repo reads. Deduplicate, merge overlapping claims, order by importance. Write ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/explore/report.md. Return only a fenced json block {\"report\": {\"items\": <count>, \"missing\": <count of shards without findings>}} and no other text.\n\nShard lines (may be null when a shard failed):\n{found}",
        "name": "swarm-secretary",
        "model": "opencode-go/kimi-k3"
      },
      "inputs": [
        {
          "name": "found",
          "type": "text",
          "from": "explorer.found",
          "optional": true
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
