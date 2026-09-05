---
name: swarm-loop
description: Run the autonomous SWARM loop across Scale Assessment, Worktree Isolation, Haiku Exploration, Plan & Interview, Maker/Checker Execution, Checkpoint, Adversarial Review, and Release Gate.
---

# SWARM Loop Autonomous Execution

**Objective:**
{{input}}

Read `~/.pi/agent/skills/swarm-loop/SKILL.md` (canonical source: `agent/skills/swarm-loop/SKILL.md`
in the dotfiles repo, symlinked here) and follow its state machine verbatim for the objective above,
starting at Phase -1 (SCALE Classification). Do not summarize or re-derive the protocol from memory —
the SKILL.md content is the single source of truth for phase order, script names, budget limits, and
the 8-agent Adversarial Review roster; a condensed restatement here would drift from it over time
(2026-09-04, claude-hooks-full-agent-consolidation mission: this file previously duplicated a
condensed copy of the SKILL.md phase list, found stale — e.g. it named "8 adversarial reviewer
agents" without the specific 8 role names SKILL.md tracks).
