---
name: swarm-meta
description: Deterministic profile assessment and meta-harness selector for SWARM execution (chooses between swarm-loop and swarm-graph).
---

# SWARM Meta-Harness

**Goal:**
{{input}}

Read `~/.pi/agent/skills/swarm-meta/SKILL.md` (canonical source: `agent/skills/swarm-meta/SKILL.md`
in the dotfiles repo, symlinked here) and follow its protocol verbatim for the goal above (M0 PROFILE
→ M1 SELECT → M2 DISPATCH → M3 RECORD → M4 EVOLVE-FEED). Do not summarize or re-derive the routing
logic from memory — the SKILL.md content is the single source of truth for the `harness-select.sh`/
`harness-lint.sh`/`harness-record.sh` script contracts and the Tier A/Tier B governance boundary; a
condensed restatement here would drift from it over time (2026-09-04,
claude-hooks-full-agent-consolidation mission: this file previously duplicated a condensed copy of
the SKILL.md protocol steps).
