---
name: prime-swarm-release-gate
description: Final deterministic verification before anything is merged or released - runs the repo's gate commands with swarm_adapter.verify, presents the raw results, and stops for explicit human approval. Use at the end of a swarm mission, or when the human says merge, release, open a PR to main, or ship. It never merges, pushes or deploys itself.
---

# prime-swarm-release-gate

Governance in `~/.prime/agent/SWARM.md`. Reference for which commands a gate normally runs:
`agent/skills/swarm-release-gate/scripts/verify.sh` (read it; do not execute it, it is a Claude-side script).

Human-only boundaries: merging into or pushing to the user's main branch or any remote, and any deploy, are
human-only. This skill NEVER merges, pushes, deploys, tags, force-updates a ref or removes a worktree,
and it never tells anyone it may. It only presents results and stops; the human performs any merge or push
themselves. Tier B governance files are never edited by this skill. Protected paths come from
the dotfiles `agent/write-scope-rules.json` (located as in prime-swarm-loop, never the target repo's copy) (check procedure in `~/.prime/agent/skills/prime-swarm-loop/SKILL.md`); a diff
that touches one is flagged to the human for their own review.

## Steps

1. Identify the commands: the repo's own gate (`Makefile` targets, CI workflow steps, `CLAUDE.md`/`AGENTS.md`
   instructions), the same set the swarm tasks used plus lint/format/type checks the repo has. If you cannot find
   an authoritative list, ask the human; do not invent one.
2. Run them in the mission worktree: `swarm_adapter.verify([...commands], cwd=<worktree>)`. Pass a larger
   `timeout` for slow suites. Branch on `passed` and each result's `exit_code`; a timeout (124), launch failure
   (126/127) or `error` is a failure, not a skip. Never substitute a remembered earlier pass.
3. Pre-merge facts for the human, each from a command you ran now: `git diff --stat <base>`, `git status --short`
   (must be clean apart from the intended change), and the `swarm-review` summary if one exists.
4. Present: per-command `exit_code` with `output_tail` for any failure, the diff stat, open residual risks.
   Any failure: report it and stop; fixing goes back to `prime-swarm-loop` EXECUTE.
5. STOP. Report that the human decides and performs any merge/push/PR themselves. Take no further action on
   silence, or on an earlier "looks fine" for a different state of the tree.
