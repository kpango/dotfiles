---
name: swarm-review
description: Adversarial review of a finished diff through eight specialist lenses, at most 3 in parallel, merged into one pass/fail summary (per-run directory).
version: 1
author: kpango
---

# swarm-review

## What this machine does

`init` validates the per-run directory and snapshots the input. `diff-source` (Medium) writes the diff against the merge-base of `base_ref` and HEAD to `change.diff`, appending the contents of untracked new files. Eight lens states (architecture, code-quality, docs-comment, infra-config, perf-simd, security, shell-config, systems-lang; XHigh, cross-family) each read their `<agent dir>/agents/<lens>-adversarial-reviewer.md` checklist (each lens reads its own agent definition) and judge the diff file; `diff-source` and the lenses read the repo. They fan out from `diff-source`, bounded by `run.max_parallel: 3` (SWARM.md section 1). A join transition feeds `aggregator` (Medium) once all eight settled; it emits `{"summary": {"all_pass", "failed"}}` and writes the details to `<run_dir>/summary.md`. The machine gates nothing itself: the caller reads `summary.all_pass` from the aggregator's json output.

**Success rule.** Success = `rlm.factory.status(run_id)` reports state `done` AND `<run_dir>/summary.md` exists and the aggregator's `summary` json output parsed. ANY other combination (paused, stopped, failed, `done` without the file, or the file present while the run is not `done`) is NOT success: inspect with `await rlm.factory.status(run_id)`, then `await rlm.factory.stop(run_id)` and start a new run directory. For example (not exhaustive): a child error, a per-state `budget_ms` overrun, an unparseable reply, a refused `init`. `resume` after an error pause does not re-run the failed state (verified against the runtime and the simulator), and `stop` leaves the run in state `stopped`.

**Review verdict (separate from run success).** The verdict is the aggregator's `summary.all_pass` json output (read it from the `aggregator` node via `rlm.factory.status(run_id)`): `true` means all lenses passed, `false` means there are findings to act on in `<run_dir>/summary.md`. A `done` run with `all_pass` false is a successful review that found defects, not a run failure.

Run budget arithmetic (critical path with `max_parallel` 3): init 300000 + diff-source 300000 + ceil(8 / 3) = 3 lens waves x 900000 + aggregator 600000 = 3900000 ms, so the run `budget_ms` of 5400000 leaves margin.

## Residual risks

- `diff-source` reads the repo and the lens states read the diff file plus repo files to verify findings; the lens agent definitions are read from `<agent dir>/agents/`. Only the run directory is meant to be written; that is a prompt contract.
- The fixed pointer file `swarm/<machine>.input.json` limits concurrency: start runs of one machine one at a time and wait for `init` to settle.
- Output size is bounded by prompt instructions (one line of compact JSON, fixed-length fields). A model that adds free text can push an answer over the preview cap or break the json; the run may then end in any non-success state (see the success rule).
- Nothing in the runtime sandboxes the child agents: all agents share one filesystem and one user, so every restriction below is a prompt contract, not an enforced guarantee.
- Each lens verdict is an LLM judgement; the aggregator only counts them. `all_pass` is evidence for the human gate, not a replacement for it.


## How to run it

The run call takes only a spec name (no input argument). The caller therefore creates a fresh per-run directory, puts the task in it, and writes ONE fixed pointer file that only `init` reads:

    import json, os, uuid
    d = os.environ.get("PRIME_AGENT_CODING_AGENT_DIR") or os.path.expanduser("~/.prime/agent")
    run_dir = f"{d}/swarm/runs/{uuid.uuid4().hex[:12]}"; os.makedirs(run_dir)   # fresh, empty
    json.dump({"worktree": "/abs/worktree", "base_ref": "main"}, open(run_dir + "/input.json", "w"))
    json.dump({"run_dir": run_dir}, open(f"{d}/swarm/review.input.json", "w"))   # pointer, only run_dir
    result = await rlm.factory.run("swarm-review")

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
    "budget_ms": 5400000,
    "failure_policy": "escalate",
    "max_parallel": 3,
    "max_transitions": 16
  },
  "states": [
    {
      "id": "init",
      "entry": true,
      "subagent": {
        "prompt": "Orchestrator setup, no judgement. Read the pointer file ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/review.input.json (json: run_dir). Let R = run_dir. Accept only if R is a directory directly under ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/, its basename matches ^[0-9a-f]{12}$, and it contains exactly one entry, input.json. If not accepted, change nothing and reply with exactly this constant line, never echoing any part of the input: {\"init\": {\"ok\": false}}. If accepted, copy R/input.json to R/input.snapshot.json, chmod 444 the copy. Then reply with one line of compact JSON only (no fence, no other text): {\"init\": {\"ok\": true, \"run\": \"<basename of R>\"}}.",
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
      "id": "diff-source",
      "subagent": {
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; you may read the repo you are told to review. Read RUN/input.snapshot.json (json: worktree, base_ref). Compute `mb=$(git -C <worktree> merge-base <base_ref> HEAD)`. Write to RUN/change.diff the output of `git -C <worktree> diff $mb`, then for every file from `git -C <worktree> ls-files --others --exclude-standard` append a `=== new file: <path> ===` header and the file contents. Reply with one line of compact JSON only (no fence, no other text): {\"diff\": {\"changed_files\": <number of changed plus untracked files, at most 999>}}. init: {init}",
        "name": "swarm-diff-source",
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
          "name": "diff",
          "type": "json"
        }
      ],
      "budget_ms": 300000
    },
    {
      "id": "lens-architecture",
      "subagent": {
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; you may read the repo you are told to review. Read ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/agents/architecture-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file RUN/change.diff (read repo files only when needed to verify a finding). Report every finding, not just severe ones. init: {init} diff: {diff}. Write the full result {\"lens\": \"architecture\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to RUN/architecture.json (FAIL when there is at least one finding). Reply with one line of compact JSON only (no fence, no other text): {\"review\": {\"lens\": \"architecture\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count, at most 99>}}.",
        "name": "swarm-lens-architecture",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        },
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
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; you may read the repo you are told to review. Read ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/agents/code-quality-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file RUN/change.diff (read repo files only when needed to verify a finding). Report every finding, not just severe ones. init: {init} diff: {diff}. Write the full result {\"lens\": \"code-quality\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to RUN/code-quality.json (FAIL when there is at least one finding). Reply with one line of compact JSON only (no fence, no other text): {\"review\": {\"lens\": \"code-quality\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count, at most 99>}}.",
        "name": "swarm-lens-code-quality",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        },
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
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; you may read the repo you are told to review. Read ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/agents/docs-comment-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file RUN/change.diff (read repo files only when needed to verify a finding). Report every finding, not just severe ones. init: {init} diff: {diff}. Write the full result {\"lens\": \"docs-comment\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to RUN/docs-comment.json (FAIL when there is at least one finding). Reply with one line of compact JSON only (no fence, no other text): {\"review\": {\"lens\": \"docs-comment\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count, at most 99>}}.",
        "name": "swarm-lens-docs-comment",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        },
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
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; you may read the repo you are told to review. Read ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/agents/infra-config-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file RUN/change.diff (read repo files only when needed to verify a finding). Report every finding, not just severe ones. init: {init} diff: {diff}. Write the full result {\"lens\": \"infra-config\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to RUN/infra-config.json (FAIL when there is at least one finding). Reply with one line of compact JSON only (no fence, no other text): {\"review\": {\"lens\": \"infra-config\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count, at most 99>}}.",
        "name": "swarm-lens-infra-config",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        },
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
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; you may read the repo you are told to review. Read ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/agents/perf-simd-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file RUN/change.diff (read repo files only when needed to verify a finding). Report every finding, not just severe ones. init: {init} diff: {diff}. Write the full result {\"lens\": \"perf-simd\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to RUN/perf-simd.json (FAIL when there is at least one finding). Reply with one line of compact JSON only (no fence, no other text): {\"review\": {\"lens\": \"perf-simd\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count, at most 99>}}.",
        "name": "swarm-lens-perf-simd",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        },
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
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; you may read the repo you are told to review. Read ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/agents/security-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file RUN/change.diff (read repo files only when needed to verify a finding). Report every finding, not just severe ones. init: {init} diff: {diff}. Write the full result {\"lens\": \"security\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to RUN/security.json (FAIL when there is at least one finding). Reply with one line of compact JSON only (no fence, no other text): {\"review\": {\"lens\": \"security\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count, at most 99>}}.",
        "name": "swarm-lens-security",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        },
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
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; you may read the repo you are told to review. Read ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/agents/shell-config-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file RUN/change.diff (read repo files only when needed to verify a finding). Report every finding, not just severe ones. init: {init} diff: {diff}. Write the full result {\"lens\": \"shell-config\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to RUN/shell-config.json (FAIL when there is at least one finding). Reply with one line of compact JSON only (no fence, no other text): {\"review\": {\"lens\": \"shell-config\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count, at most 99>}}.",
        "name": "swarm-lens-shell-config",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        },
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
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; you may read the repo you are told to review. Read ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/agents/systems-lang-adversarial-reviewer.md and apply it as your checklist. Judge ONLY the diff file RUN/change.diff (read repo files only when needed to verify a finding). Report every finding, not just severe ones. init: {init} diff: {diff}. Write the full result {\"lens\": \"systems-lang\", \"verdict\": \"PASS|FAIL\", \"findings\": [...]} to RUN/systems-lang.json (FAIL when there is at least one finding). Reply with one line of compact JSON only (no fence, no other text): {\"review\": {\"lens\": \"systems-lang\", \"verdict\": \"PASS\"|\"FAIL\", \"findings\": <count, at most 99>}}.",
        "name": "swarm-lens-systems-lang",
        "model": "prime-inference/openai/gpt-6-astra"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        },
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
        "prompt": "Run directory: RUN = ${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}/swarm/runs/<run> where <run> is the `run` field of {init}. Machine state and outputs go only to files inside RUN; you may read the repo you are told to review. Aggregate only; do not re-review. From the eight lens results below compute all_pass (true only when every verdict is PASS) and failed (number of lenses with verdict FAIL), then write the merged findings of the failing lenses (read RUN/<lens>.json) and the failing lens names to RUN/summary.md. Reply with one line of compact JSON only (no fence, no other text): {\"summary\": {\"all_pass\": <true|false>, \"failed\": <number>}}.\n\ninit: {init}\narchitecture: {architecture}\ncode-quality: {code_quality}\ndocs-comment: {docs_comment}\ninfra-config: {infra_config}\nperf-simd: {perf_simd}\nsecurity: {security}\nshell-config: {shell_config}\nsystems-lang: {systems_lang}",
        "name": "swarm-aggregator",
        "model": "opencode-go/kimi-k3"
      },
      "inputs": [
        {
          "name": "init",
          "type": "json",
          "from": "init.init"
        },
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
      "from": "init",
      "to": "diff-source",
      "when": {
        "output": "init",
        "path": "ok",
        "op": "eq",
        "value": true
      }
    },
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
