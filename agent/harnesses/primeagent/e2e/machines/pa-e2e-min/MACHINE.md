---
name: pa-e2e-min
description: Smallest factory machine for the local-ollama E2E (two states, no tools, no files).
version: 1
author: kpango
---

# pa-e2e-min

Used only by `../../run-ollama-e2e.sh`, which copies it into a throwaway HOME. It is NOT deployed by
`make primeagent/install` (that installs `agent/harnesses/primeagent/machines/*` only).

`ping` replies with a constant JSON line; `pong` runs only when the guard `ping.ok == true` holds and
replies with another constant line. Neither state needs a tool, so the run exercises the factory
runtime (spawn, json port parsing, guarded transition, `done`) and nothing else. Both subagents use
the local model `local-ollama/qwen3:4b-instruct`, which the E2E script adds to `allowedModels` in the
throwaway HOME only.

```machine-spec
{
  "run": {
    "budget_ms": 600000,
    "failure_policy": "fail_fast",
    "max_parallel": 1,
    "max_transitions": 4
  },
  "states": [
    {
      "id": "ping",
      "entry": true,
      "subagent": {
        "prompt": "Do not use any tool. Reply with exactly this one line of compact JSON and nothing else (no fence, no other text): {\"ping\": {\"ok\": true}}",
        "name": "pa-e2e-ping",
        "model": "local-ollama/qwen3:4b-instruct"
      },
      "outputs": [
        {
          "name": "ping",
          "type": "json"
        }
      ],
      "budget_ms": 240000
    },
    {
      "id": "pong",
      "subagent": {
        "prompt": "Do not use any tool. Reply with exactly this one line of compact JSON and nothing else (no fence, no other text): {\"pong\": {\"done\": true}}\n\nping: {ping}",
        "name": "pa-e2e-pong",
        "model": "local-ollama/qwen3:4b-instruct"
      },
      "inputs": [
        {
          "name": "ping",
          "type": "json",
          "from": "ping.ping"
        }
      ],
      "outputs": [
        {
          "name": "pong",
          "type": "json"
        }
      ],
      "budget_ms": 240000
    }
  ],
  "transitions": [
    {
      "from": "ping",
      "to": "pong",
      "when": {
        "output": "ping",
        "path": "ok",
        "op": "eq",
        "value": true
      }
    }
  ]
}
```
