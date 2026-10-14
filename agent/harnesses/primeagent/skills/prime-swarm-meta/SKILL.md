---
name: prime-swarm-meta
description: Chooses between prime-swarm-loop and prime-swarm-graph for a goal using the deterministic harness-select script, then follows the chosen skill. Use when the user gives a coding goal for a repo and has not said whether to run sequentially or as a DAG, or asks which swarm harness to use.
---

# prime-swarm-meta

A selector, not an executor. Governance is in `~/.prime/agent/SWARM.md`.

Human-only boundaries: merging into or pushing to the user's main branch or any remote, and any deploy, are
human-only; Tier B governance files are never edited by this skill or the skills it selects.
Protected (Tier B) paths come from the dotfiles `agent/write-scope-rules.json` (located as in prime-swarm-loop, never the target repo's copy); apply the write-scope check in
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
