## prime-agent Execution Model

- The only tool is `ipython`, a persistent Python REPL. `bash(...)`, `await edit.run(...)`,
  `rlm.*` and `await websearch.run(...)` are functions inside it; edit files with `edit.run`, not
  shell redirection.
- Each `bash()` call is its own process: shell state (cwd, exports) does not carry over.
- `async rlm.spawn(prompt, *, name, model=None, thinking=None)` starts a subagent one level deeper.
  It is a coroutine: write `await rlm.spawn(...)` (without `await` no subagent starts). It returns
  a handle once the child is admitted; `name` is required and unique among siblings; the result
  arrives only as an agent message, never as the return value. Spawn depth is capped by
  `rlmMaxDepth` in settings.
- The REPL is not a sandbox: Python in it runs with your full user privileges.
- `agent/scripts/prime-shell-guard.sh` checks every `bash()` command (see Security). It is
  injected through `PRIME_AGENT_BASH_COMMAND_PREFIX`; the settings key `shellCommandPrefix` does
  not reach `bash()`. It is a guardrail, not a boundary: Python code (`open`, `subprocess`) never
  passes through it. For a command you would run any other way, call
  `await swarm_adapter.decide_shell(cmd, cwd)` first; if it returns `block` or `ask`, do not run
  the command and ask the human.
- Autonomous runs and untrusted repositories go only through the `pa-sandbox` wrapper (bwrap
  around the whole prime-agent process). If `command -v pa-sandbox` finds nothing, do not run
  them; ask the human.
- Never create `~/.prime/agent/SYSTEM.md`: it replaces the built-in core prompt that documents
  this REPL.

## Model Tiers

`model` takes a full `provider/model` selector. In code, read
`tiers.<Tier>.model` from `~/.prime/agent/model-routing.json` instead of hard-coding it; the
table below is generated from that file and is for orientation only. `effort` is passed as
`thinking=` (valid levels: off, minimal, low, medium, high, xhigh, max).

<!-- gen:tier-table -->

A rate limit can make `await rlm.spawn(...)` raise `RuntimeError` at admission. Once the child
is admitted, `rlm.spawn` has returned, so a later rate limit or token exhaustion shows up as the
child's error (status `error` in `await rlm.collect(...)` or `await rlm.list_subagents()`). When
either error matches a fallback's trigger, spawn the task again with that fallback selector.
Typical use: Low for bulk reading, Medium for summarising, High for edits (Maker), XHigh for
independent checking (a different model family from High), Max only for design or a stuck-task
diagnosis.

```python
import json, os
with open(os.path.expanduser("~/.prime/agent/model-routing.json"), encoding="utf-8") as f:
    tier = json.load(f)["tiers"]["XHigh"]
h = await rlm.spawn(task_text, name="go-review", model=tier["model"], thinking=tier["effort"])
```

## Providers

<!-- gen:providers -->

Only `prime-inference` and `opencode-go` are authenticated (`~/.prime/agent/auth.json`). Claude
models are reached as `prime-inference/anthropic/*`. Do not pass a selector from any other
provider to `rlm.spawn`.

## Agent Definitions (`~/.prime/agent/agents/<name>.md`)

The shared agent definitions are plain markdown. prime-agent has no agent-type tool, so use one
by spawning it: read the file, drop the YAML front matter, and pass the body plus the concrete task
as `prompt` to `await rlm.spawn(..., model=<tier selector>)`. The front matter `model:` / `tools:` values
are Claude-side settings that prime-agent does not read: pick the tier yourself, and state any
read-only restriction in the prompt.

Read-only reviewers that end with the VERDICT contract:

<!-- gen:verdict-agents -->

Their reply must end with a line that is exactly `VERDICT: PASS` or `VERDICT: FAIL` (FAIL while any
CRITICAL/HIGH finding is unresolved). Treat a missing or malformed VERDICT line as FAIL. Spawn
reviewers on the XHigh tier and tell them not to edit anything.

## Swarm on prime-agent

The swarm workflow runs through prime-only skills; follow each SKILL.md, this file does not
restate them:

- `~/.prime/agent/skills/prime-swarm-meta/SKILL.md` picks loop or graph for a goal.
- `prime-swarm-loop`, `prime-swarm-graph`, `prime-swarm-architect`, `prime-swarm-secretary`,
  `prime-swarm-release-gate` (same `~/.prime/agent/skills/<name>/SKILL.md` layout).
- `~/.prime/agent/skills/swarm-adapter/SKILL.md`: the typed Python API (`swarm_adapter.*`) over the
  existing swarm scripts. Factory machines: `agent/harnesses/primeagent/machines/`.

Commit and merge only with the "Commit and merge" sections in the swarm-adapter SKILL.md
(`commit_tree` + `update_ref`). Never run `git commit`, `git merge` or `git update-ref` in the
repository yourself.

## Context Files

prime-agent loads `~/.prime/agent/AGENTS.md` (this file) and then the `AGENTS.md` of the working
directory and of every ancestor directory up to `/`; it continues past the git root. A worktree
created inside a repository therefore loads that repository's `AGENTS.md` twice. Create worktrees
with `await swarm_adapter.worktree_alloc(slug)`, which places them outside the repository.

## Security

- Never commit secrets, tokens, or credentials. `auth.json` and session credentials are never
  managed in dotfiles; each provider's login flow writes them.
- prime-agent has no write-time check: `edit.run`, Python `open()` and `subprocess` reach every
  file your user can write. Do not write to credential/key
  paths (`~/.ssh/`, `~/.gnupg/`, `~/.aws/`, `~/.kube/config`, `.env*`, `*.pem`/`*.key`/`*.p12`,
  Terraform state/vars, `~/.cargo/credentials`, `~/.npmrc`, `~/.prime/agent/auth.json`); if a task
  needs one, ask the human.
- Destructive commands (recursive `rm`/`chmod`, force-push, piping a download into a shell, mass
  `git add`, production-namespace `kubectl`/`helm` deletes) need the human's confirmation whatever
  decide.py returns for them.
- `~/.prime/agent/settings.json` is a regular file merged by install, not a link to the repo:
  editing it does not change the dotfiles, and install overwrites the repo-owned keys.

`agent/scripts/prime-shell-guard.sh` refuses a `bash()` command when decide.py returns `block` or
`ask` for it. decide.py returns `block` or `ask` only for a command that matches a pattern in
`agent/security-rules.json`, and `allow` for every other command. Generated by running
`agent/scripts/hooks/decide.py` on each command with the request of
`agent/scripts/prime-shell-guard.sh`:

<!-- gen:guard-table -->
