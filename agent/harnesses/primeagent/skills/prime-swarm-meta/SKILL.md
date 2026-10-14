---
name: prime-swarm-meta
description: Chooses between prime-swarm-loop and prime-swarm-graph for a goal using the deterministic harness-select script, then follows the chosen skill. Use when the user gives a coding goal for a repo and has not said whether to run sequentially or as a DAG, or asks which swarm harness to use.
---

# prime-swarm-meta

A selector, not an executor. Governance is in `~/.prime/agent/SWARM.md`.

Human-only boundaries: no merge, push or deploy without explicit human approval; Tier B governance files (any
`SKILL.md` under `agent/skills`, hooks, `SWARM.md`) are never edited by this skill or the skills it selects.

## Steps

1. Read the script's usage lines first (`sed -n 1,20p <script>`), because flags and output change:
   `agent/skills/swarm-meta/scripts/harness-select.sh` in the dotfiles repo (also reachable as
   `~/.claude/skills/swarm-meta/scripts/harness-select.sh`; use the first path that exists).
2. Run it with bash(): `harness-select.sh "<goal text>" <repo-root>` (add `--profile-only` only if you just want
   the repo profile). It uses no model and decides from repo signals plus its registry.
3. Parse its JSON (`profile`, `recommendation`, `registry_matches`): use `recommendation.harness`, never your own
   opinion; `recommendation.scale` seeds SCALE and `recommendation.rationale` is the reason. Map
   `swarm-loop` -> `prime-swarm-loop`, `swarm-graph` -> `prime-swarm-graph`. Any other value or a non-zero exit:
   report the raw output to the human and default to `prime-swarm-loop`.
4. State the choice and its reason (one line from `rationale`) to the human, then read the chosen skill and follow
   it from its first step. Ignore `lenses`: they name Claude agents; prime reviews use the `swarm-review` machine.

The result of `graph_compile` can later downgrade a graph run to the loop (exit 2); that is handled inside
`prime-swarm-graph`, not here.
