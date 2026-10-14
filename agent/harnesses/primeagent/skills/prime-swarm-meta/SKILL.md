---
name: prime-swarm-meta
description: Chooses between prime-swarm-loop and prime-swarm-graph for a goal using the deterministic harness-select script, then follows the chosen skill. Use when the user gives a coding goal for a repo and has not said whether to run sequentially or as a DAG, or asks which swarm harness to use.
---

# prime-swarm-meta

A selector, not an executor. Governance is in `~/.prime/agent/SWARM.md`.

Human-only boundaries: merging into or pushing to the user's main branch or any remote, and any deploy, are
human-only; Tier B governance files are never edited by this skill or the skills it selects.
Protected (Tier B) paths come from `agent/write-scope-rules.json`; apply the write-scope check in
`~/.prime/agent/skills/prime-swarm-loop/SKILL.md` before ANY file edit (prompt contract, no write hook in prime).

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
2. Run it with bash(): `bash "<script>" "<goal text>" <repo-root>` (add `--profile-only` only if you just want the
   repo profile). It uses no model and decides from repo signals plus its registry.
3. Parse its JSON (`profile`, `recommendation`, `registry_matches`): use `recommendation.harness`, never your own
   opinion; `recommendation.scale` seeds SCALE and `recommendation.rationale` (a list of rule strings) is the
   reason. Map `swarm-loop` -> `prime-swarm-loop`, `swarm-graph` -> `prime-swarm-graph`. Any other value or a
   non-zero exit: report the raw output to the human and default to `prime-swarm-loop`.
4. State the choice and its reason (the `rationale` entries) to the human, then read the chosen skill and follow it
   from its first step. Ignore `lenses`: they name Claude agents; prime reviews use the `swarm-review` machine.

`prime-swarm-graph` runs its first compile with `fit=True`; exit 2 (`UNFIT_FALLBACK_LOOP`) there moves the run to
`prime-swarm-loop`. That is handled inside `prime-swarm-graph`, not here.
