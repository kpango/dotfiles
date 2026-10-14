---
name: swarm-review
description: Adversarial review of a finished diff through eight specialist lenses, at most 3 in parallel, merged into one pass/fail summary.
version: 1
author: kpango
---

# swarm-review

## What this machine does

`diff-source` (Medium) writes the diff against a base ref to a file. Eight lens states (architecture, code-quality, docs-comment, infra-config, perf-simd, security, shell-config, systems-lang; XHigh, cross-family) each read their `~/.prime/agent/agents/<lens>-adversarial-reviewer.md` checklist and judge only the diff file. They fan out from `diff-source`, bounded by `run.max_parallel: 3` (SWARM.md section 1). A join transition feeds `aggregator` (Medium) once all eight settled; it computes `all_pass` and the failing lens list. The machine does not gate anything itself: the caller reads `summary.all_pass`.

## How to run it

The run call takes only a spec name, so the target is passed through a file the states read:

    import json, os
    d = os.environ.get("PRIME_AGENT_CODING_AGENT_DIR") or os.path.expanduser("~/.prime/agent")
    os.makedirs(d + "/swarm/out/review", exist_ok=True)
    json.dump({"worktree": "/abs/worktree", "base_ref": "main"}, open(d + "/swarm/review.input.json", "w"))
    result = await rlm.factory.run("swarm-review")

One run at a time per machine.

Output ports are captured answer previews capped at about 200 characters, so
every state emits a compact json block and writes the full payload to a file
under `${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/`. Guards branch only on
those json fields, never on prose.

```machine-spec
{
  "run": {
    "budget_ms": 3600000,
    "failure_policy": "escalate",
    "max_parallel": 3,
    "max_transitions": 16
  },
  "states": [
    {
      "id": "diff-source",
      "entry": true,
      "subagent": {
        "prompt": "Read the input file ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/review.input.json (json: worktree, base_ref). Run `git -C <worktree> diff <base_ref>` and write the full diff to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/change.diff (also append `git status --short` untracked files as a list at the end of the file). Return only a fenced json block {\"diff\": {\"file\": \"${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/change.diff\", \"changed_files\": <number>}}.",
        "name": "swarm-diff-source",
        "model": "opencode-go/kimi-k3"
      },
      "outputs": [
        {
          "name": "diff",
          "type": "json"
        }
      ],
      "budget_ms": 300000
    },
    {
      "id": "lens-architecture",
      "subagent": {
        "prompt": "Read ~/.prime/agent/agents/architecture-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file in {diff} (read the file named there; read repo files only when needed to verify a finding). Report every finding, not just severe ones. Write the full result {\"lens\": \"architecture\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/architecture.json (FAIL when there is at least one finding). Return only a fenced json block {\"review\": {\"lens\": \"architecture\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count>, \"file\": \"${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/architecture.json\"}}.",
        "name": "swarm-lens-architecture",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "diff",
          "type": "json",
          "from": "diff-source.diff"
        }
      ],
      "outputs": [
        {
          "name": "review",
          "type": "json"
        }
      ],
      "budget_ms": 900000
    },
    {
      "id": "lens-code-quality",
      "subagent": {
        "prompt": "Read ~/.prime/agent/agents/code-quality-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file in {diff} (read the file named there; read repo files only when needed to verify a finding). Report every finding, not just severe ones. Write the full result {\"lens\": \"code-quality\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/code-quality.json (FAIL when there is at least one finding). Return only a fenced json block {\"review\": {\"lens\": \"code-quality\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count>, \"file\": \"${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/code-quality.json\"}}.",
        "name": "swarm-lens-code-quality",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "diff",
          "type": "json",
          "from": "diff-source.diff"
        }
      ],
      "outputs": [
        {
          "name": "review",
          "type": "json"
        }
      ],
      "budget_ms": 900000
    },
    {
      "id": "lens-docs-comment",
      "subagent": {
        "prompt": "Read ~/.prime/agent/agents/docs-comment-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file in {diff} (read the file named there; read repo files only when needed to verify a finding). Report every finding, not just severe ones. Write the full result {\"lens\": \"docs-comment\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/docs-comment.json (FAIL when there is at least one finding). Return only a fenced json block {\"review\": {\"lens\": \"docs-comment\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count>, \"file\": \"${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/docs-comment.json\"}}.",
        "name": "swarm-lens-docs-comment",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "diff",
          "type": "json",
          "from": "diff-source.diff"
        }
      ],
      "outputs": [
        {
          "name": "review",
          "type": "json"
        }
      ],
      "budget_ms": 900000
    },
    {
      "id": "lens-infra-config",
      "subagent": {
        "prompt": "Read ~/.prime/agent/agents/infra-config-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file in {diff} (read the file named there; read repo files only when needed to verify a finding). Report every finding, not just severe ones. Write the full result {\"lens\": \"infra-config\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/infra-config.json (FAIL when there is at least one finding). Return only a fenced json block {\"review\": {\"lens\": \"infra-config\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count>, \"file\": \"${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/infra-config.json\"}}.",
        "name": "swarm-lens-infra-config",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "diff",
          "type": "json",
          "from": "diff-source.diff"
        }
      ],
      "outputs": [
        {
          "name": "review",
          "type": "json"
        }
      ],
      "budget_ms": 900000
    },
    {
      "id": "lens-perf-simd",
      "subagent": {
        "prompt": "Read ~/.prime/agent/agents/perf-simd-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file in {diff} (read the file named there; read repo files only when needed to verify a finding). Report every finding, not just severe ones. Write the full result {\"lens\": \"perf-simd\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/perf-simd.json (FAIL when there is at least one finding). Return only a fenced json block {\"review\": {\"lens\": \"perf-simd\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count>, \"file\": \"${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/perf-simd.json\"}}.",
        "name": "swarm-lens-perf-simd",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "diff",
          "type": "json",
          "from": "diff-source.diff"
        }
      ],
      "outputs": [
        {
          "name": "review",
          "type": "json"
        }
      ],
      "budget_ms": 900000
    },
    {
      "id": "lens-security",
      "subagent": {
        "prompt": "Read ~/.prime/agent/agents/security-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file in {diff} (read the file named there; read repo files only when needed to verify a finding). Report every finding, not just severe ones. Write the full result {\"lens\": \"security\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/security.json (FAIL when there is at least one finding). Return only a fenced json block {\"review\": {\"lens\": \"security\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count>, \"file\": \"${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/security.json\"}}.",
        "name": "swarm-lens-security",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "diff",
          "type": "json",
          "from": "diff-source.diff"
        }
      ],
      "outputs": [
        {
          "name": "review",
          "type": "json"
        }
      ],
      "budget_ms": 900000
    },
    {
      "id": "lens-shell-config",
      "subagent": {
        "prompt": "Read ~/.prime/agent/agents/shell-config-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file in {diff} (read the file named there; read repo files only when needed to verify a finding). Report every finding, not just severe ones. Write the full result {\"lens\": \"shell-config\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/shell-config.json (FAIL when there is at least one finding). Return only a fenced json block {\"review\": {\"lens\": \"shell-config\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count>, \"file\": \"${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/shell-config.json\"}}.",
        "name": "swarm-lens-shell-config",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "diff",
          "type": "json",
          "from": "diff-source.diff"
        }
      ],
      "outputs": [
        {
          "name": "review",
          "type": "json"
        }
      ],
      "budget_ms": 900000
    },
    {
      "id": "lens-systems-lang",
      "subagent": {
        "prompt": "Read ~/.prime/agent/agents/systems-lang-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file in {diff} (read the file named there; read repo files only when needed to verify a finding). Report every finding, not just severe ones. Write the full result {\"lens\": \"systems-lang\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/systems-lang.json (FAIL when there is at least one finding). Return only a fenced json block {\"review\": {\"lens\": \"systems-lang\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count>, \"file\": \"${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/systems-lang.json\"}}.",
        "name": "swarm-lens-systems-lang",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "diff",
          "type": "json",
          "from": "diff-source.diff"
        }
      ],
      "outputs": [
        {
          "name": "review",
          "type": "json"
        }
      ],
      "budget_ms": 900000
    },
    {
      "id": "aggregator",
      "subagent": {
        "prompt": "Aggregate only; do not re-review. From the eight lens results below compute all_pass (true only when every verdict is PASS) and the list of failing lens names, then write the merged findings of the failing lenses (read their files) to ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/summary.md. Return only a fenced json block {\"summary\": {\"all_pass\": <true|false>, \"failures\": [\"lens\"], \"file\": \"${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/out/review/summary.md\"}}.\n\narchitecture: {architecture}\ncode-quality: {code_quality}\ndocs-comment: {docs_comment}\ninfra-config: {infra_config}\nperf-simd: {perf_simd}\nsecurity: {security}\nshell-config: {shell_config}\nsystems-lang: {systems_lang}",
        "name": "swarm-aggregator",
        "model": "opencode-go/kimi-k3"
      },
      "inputs": [
        {
          "name": "architecture",
          "type": "json",
          "from": "lens-architecture.review"
        },
        {
          "name": "code_quality",
          "type": "json",
          "from": "lens-code-quality.review"
        },
        {
          "name": "docs_comment",
          "type": "json",
          "from": "lens-docs-comment.review"
        },
        {
          "name": "infra_config",
          "type": "json",
          "from": "lens-infra-config.review"
        },
        {
          "name": "perf_simd",
          "type": "json",
          "from": "lens-perf-simd.review"
        },
        {
          "name": "security",
          "type": "json",
          "from": "lens-security.review"
        },
        {
          "name": "shell_config",
          "type": "json",
          "from": "lens-shell-config.review"
        },
        {
          "name": "systems_lang",
          "type": "json",
          "from": "lens-systems-lang.review"
        }
      ],
      "outputs": [
        {
          "name": "summary",
          "type": "json"
        }
      ],
      "budget_ms": 600000
    }
  ],
  "transitions": [
    {
      "from": "diff-source",
      "to": "lens-architecture"
    },
    {
      "from": "diff-source",
      "to": "lens-code-quality"
    },
    {
      "from": "diff-source",
      "to": "lens-docs-comment"
    },
    {
      "from": "diff-source",
      "to": "lens-infra-config"
    },
    {
      "from": "diff-source",
      "to": "lens-perf-simd"
    },
    {
      "from": "diff-source",
      "to": "lens-security"
    },
    {
      "from": "diff-source",
      "to": "lens-shell-config"
    },
    {
      "from": "diff-source",
      "to": "lens-systems-lang"
    },
    {
      "from": [
        "lens-architecture",
        "lens-code-quality",
        "lens-docs-comment",
        "lens-infra-config",
        "lens-perf-simd",
        "lens-security",
        "lens-shell-config",
        "lens-systems-lang"
      ],
      "to": "aggregator"
    }
  ]
}
```
