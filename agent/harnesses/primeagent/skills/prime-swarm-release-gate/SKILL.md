---
name: prime-swarm-release-gate
description: Final deterministic verification before anything is merged or released - runs the repo's gate commands with swarm_adapter.verify, presents the raw results, and stops for explicit human approval. Use at the end of a swarm mission, or when the human says merge, release, open a PR to main, or ship. It never merges, pushes or deploys itself.
---

# prime-swarm-release-gate

Governance in `~/.prime/agent/SWARM.md`. Reference for which commands a gate normally runs:
`agent/skills/swarm-release-gate/scripts/verify.sh` (read it; do not execute it, it is a Claude-side script).

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

This skill NEVER merges, pushes, deploys, tags, force-updates a ref or removes a worktree, and it never tells
anyone it may. It only presents results and stops; the human performs any merge or push themselves. A change
that touches a Tier B path is flagged to the human for their own review.

## Steps

1. Identify the commands: the repo's own gate (`Makefile` targets, CI workflow steps, `CLAUDE.md`/`AGENTS.md`
   instructions), the same set the swarm tasks used plus lint/format/type checks the repo has. If you cannot find
   an authoritative list, ask the human; do not invent one.
2. Run them in the mission worktree: `swarm_adapter.verify([...commands], cwd=<worktree>)`. Pass a larger
   `timeout` for slow suites. Branch on `passed` and each result's `exit_code`; a timeout (124), launch failure
   (126/127) or `error` is a failure, not a skip. Never substitute a remembered earlier pass.
3. Pre-merge facts for the human, each from a call you made now (`<base>` = the mission INIT `base`, `<branch>` =
   its `branch`, `<common_dir>` = its `common_dir`, `<tip>` = the tip the calling skill recorded: `prime-swarm-loop`
   `<tip>`, `prime-swarm-graph` `<mission tip>`; any of them unknown: ask the human, never re-derive it from HEAD or the
   commit history): `hv = await swarm_adapter.verify_merge(<worktree>, <tip>, expect_common_dir=<common_dir>)` must
   succeed with `hv["head"]` equal to `<tip>` (HEAD is still the recorded tip, written from the worktrees the Checkers ran on; the gate commands may run
   anything), then `cs = await swarm_adapter.change_set(<worktree>, <base>, expect_common_dir=<common_dir>)` must
   succeed with `cs["branch"]` equal to `<branch>` (HEAD attached to it, so `<branch>` is at `<tip>`; a detached HEAD
   gives `""`) and lists every changed path with its `in` states (`committed`, `index`, `worktree`, `untracked`: a
   commit cannot hide a change), and `await swarm_adapter.tier_b_hits(<worktree>, list(cs["paths"]), expect_common_dir=<common_dir>)` names the Tier
   B paths among them; plus the `swarm-review` summary if one exists. Then
   `nc = await swarm_adapter.change_set(<worktree>, <tip>, expect_common_dir=<common_dir>)`: every path in
   `nc["paths"]` (`@fix_plan.md` aside) is in the index, working tree or untracked but not in `<tip>` (the `in` states
   against `<base>` cannot show this: a committed change is also `index` and `worktree` there), so the gate commands
   ran on a tree that differs from `<tip>`: list those paths separately and STOP. Show them as two lists: paths
   whose `in` holds `index` or `worktree`, and paths that are only `untracked`. The second list may be ignored build
   or test output of step 2: `change_set` reports `.gitignore`d files as `untracked` too, and no public adapter
   call tells them apart, so this skill cannot drop them; say so and let the human judge. An `error` or
   `exit_code` != 0, or a mismatch, is a failure.
4. Present: the merge target, branch `<branch>` at sha `<tip>` (the full id), and state that this sha is what the
   human merges, not whatever `<branch>` points to later; per-command `exit_code` with `output_tail` for any
   failure; the committed paths and, apart from them, any not-committed ones; the Tier B paths; open residual
   risks. A failing gate command (step 2) or a failed step 3 check: report it and STOP for the human, whichever
   skill called this one. Only when the human explicitly asks for a fix does it go back to `prime-swarm-loop`
   EXECUTE, or, when `prime-swarm-graph` called this skill, to its REPLAN (step 4, counted in its max 2; none
   left: report to the human).
5. STOP. Report that the human decides and performs any merge/push/PR themselves. Take no further action on
   silence, or on an earlier "looks fine" for a different state of the tree.
