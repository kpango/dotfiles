---
name: swarm-explore
description: Read-only fan-out exploration (split a question into at most 8 shards, explore each cheaply, then dedupe and prioritize).
version: 1
author: kpango
---

# swarm-explore

## What this machine does

`scope` (Medium) splits the question into at most 8 shards and writes them to a file. `explorer` (Low) fans out once per shard via `foreach` (max 8, bounded by `max_parallel: 8`), strictly read-only, writing findings per shard to a file. `secretary` (Medium) only deduplicates and prioritizes the findings files; it does no new research. Failure policy is `continue` so one failed shard does not cancel the others.

## How to run it

The run call takes only a spec name, so the question is passed through a file the states read:

    import json, os
    d = os.environ.get("PRIME_AGENT_CODING_AGENT_DIR") or os.path.expanduser("~/.prime/agent")
    os.makedirs(d + "/swarm/out/explore", exist_ok=True)
    json.dump({"question": "...", "roots": ["/abs/repo"]}, open(d + "/swarm/explore.input.json", "w"))
    result = await rlm.factory.run("swarm-explore")

The result is in `swarm/out/explore/report.md`. One run at a time per machine.

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
        "prompt": "Read the input file ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/explore.input.json (json: question, roots[]). Split the question into at most 8 disjoint shards that together cover it (by directory, subsystem or sub-question). Write ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/explore/shards.json as an object mapping shard id (s1..s8) to a one-sentence scope including the paths to read. Return only a fenced json block {\"shards\": [\"s1\", \"s2\"]} listing the ids (max 8).",
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
        "prompt": "Read-only exploration of one shard. Look up shard {shard} in ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/explore/shards.json and the overall question in ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/explore.input.json. Use only reading tools (read, grep, find, git log/show); never edit, write repo files, or run builds. Write findings to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/explore/findings-{shard}.json as a list of {\"claim\": str, \"evidence\": \"path:line\", \"confidence\": \"high|medium|low\"}. Reply with one short line only: `<shard>|<number of findings>|<findings file path>`.",
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
      "budget_ms": 900000
    },
    {
      "id": "secretary",
      "subagent": {
        "prompt": "Aggregate only: read the findings files named in the lines below (and nothing else; no new research, no repo reads). Deduplicate, merge overlapping claims, and order by importance. Write ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/explore/report.md. Return only a fenced json block {\"report\": {\"file\": \"<report path>\", \"items\": <count>}}.\n\nShard lines:\n{found}",
        "name": "swarm-secretary",
        "model": "opencode-go/kimi-k3"
      },
      "inputs": [
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
