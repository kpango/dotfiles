---
name: prime-swarm-meta
description: Chooses between prime-swarm-loop and prime-swarm-graph for a goal using the deterministic harness-select script, then follows the chosen skill. Use when the user gives a coding goal for a repo and has not said whether to run sequentially or as a DAG, or asks which swarm harness to use.
---

# prime-swarm-meta

A selector, not an executor. Governance is in `~/.prime/agent/SWARM.md`.

## Human-only boundaries

Only the human merges into or pushes to the user's main branch or any remote, deploys, removes a worktree,
deletes a branch, approves a Tier B change and approves the GATE; no prime-swarm-* skill and no machine it starts
does any of these. Tier B = what `swarm_adapter.tier_b_hits(<worktree>, [<repo-relative path>], expect_common_dir=<common_dir>)`
reports from the dotfiles `agent/write-scope-rules.json` next to the adapter, never the target repo's copy:
before any file edit pass the path to it and do not edit on a hit, an `error` or `exit_code` != 0. Commits and
merges happen only through the "Commit and merge (caller side)" blocks of `swarm-adapter/SKILL.md`, on
`swarm-prime/*` branches. The skill text itself runs no git command in the target repository, read-only ones
included (its config and hooks are maker-writable), and reads it only through `swarm_adapter`. Residual risk: the
adapter's seven primitives `change_set`, `tier_b_hits`, `stage_task`, `incoming`, `verify_merge`, `commit_tree` and
`update_ref` are all that its "no git command runs in the target repository" guarantee covers. Steps outside them,
`swarm_adapter.worktree_alloc`, `swarm_adapter.mission_init`, `harness-select.sh`, the `swarm-implement` init
(`rev-parse HEAD`, MACHINE.md) and Checker (`diff <init.base>`, `ls-files`), `swarm-review` (`merge-base`, `diff`,
`ls-files`) and `swarm-explore` (`log`, `show`), run git commands in the target repository, so its config and hooks
can run there; the repo's own gate commands (release gate step 2) are maker-writable too. Maker-written config
(`diff.external`, `textconv`, ...) can shape the output of those git commands, and the Checker verdict and the review
summary rest on that output. A STOP hands the decision to the human; never resume on silence. Governance:
`~/.prime/agent/SWARM.md`.

## Steps

1. Resolve the script exactly as `swarm-adapter` resolves its scripts: an absolute path derived from the adapter
   module's real path, else `~/.claude/skills`. Never a cwd-relative path and never one from the target repo
   (that repo would choose the code you run):

       import os, swarm_adapter; from pathlib import Path
       agent = next((p for p in Path(swarm_adapter.__file__).resolve().parents if p.name == "agent" and (p / "skills").is_dir()), None)
       rel = "swarm-meta/scripts/harness-select.sh"
       cands = ([agent / "skills" / rel] if agent else []) + [Path.home() / ".claude" / "skills" / rel]
       script = next((str(c) for c in cands if c.is_file()), None)  # None: report to the human, use prime-swarm-loop

   Read its usage lines first (`sed -n 1,20p "<script>"`), because flags and output change.
2. Run it from a fresh EMPTY temp dir as cwd and with `PYTHONSAFEPATH=1` (the script runs `python3 -`, which
   would import a planted `json.py` etc. from its cwd; the adapter's own `_sync_run` uses the same defence, but no
   public adapter function runs an arbitrary script). Never run it from the target repo or a shell `cd` there.
   Insert `"--profile-only"` before `goal` only if you just want the repo profile. No model is used:

       import os, subprocess, tempfile
       with tempfile.TemporaryDirectory() as d:
           r = subprocess.run(["bash", script, goal, repo], cwd=d, env={**os.environ, "PYTHONSAFEPATH": "1"}, capture_output=True, text=True, timeout=120)
3. Parse `r.stdout` as JSON (`profile`, `recommendation`, `registry_matches`): use `recommendation.harness`, never your own
   opinion; `recommendation.scale` seeds SCALE and `recommendation.rationale` (a list of rule strings) is the
   reason. Map `swarm-loop` -> `prime-swarm-loop`, `swarm-graph` -> `prime-swarm-graph`. Any other value or a
   non-zero exit: report the raw output to the human and default to `prime-swarm-loop`.
4. State the choice and its reason (the `rationale` entries) to the human, then read the chosen skill and follow it
   from its first step. Ignore `lenses`: they name Claude agents; prime reviews use the `swarm-review` machine.

`prime-swarm-graph` runs its first compile with `fit=True`; exit 2 (`UNFIT_FALLBACK_LOOP`) there moves the run to
`prime-swarm-loop`. That is handled inside `prime-swarm-graph`, not here.
