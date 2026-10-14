---
name: prime-swarm-loop
description: Linear swarm mission for Prime Agent - scale check, mission init in an isolated worktree, explore, plan, implement each task with a Maker/Checker machine, adversarial review, then stop at a human gate. Use when the user asks for a multi-step code change, "swarm loop", or a mission on a repo where tasks run one after another. Never merges or pushes.
---

# prime-swarm-loop

Governance (tiers, budgets, human gates, Tier B rules) is defined in `~/.prime/agent/SWARM.md`; this file only
sequences the prime-native pieces. Run everything from the Python REPL. Load `swarm-adapter` for the API
(`swarm_adapter.*`); the three machines are `swarm-explore`, `swarm-implement`, `swarm-review` (each MACHINE.md
has its input JSON, run recipe and residual risks - read it before the first run).

## Human-only boundaries (never crossed by this skill)

- Merging into or pushing to the user's main branch or any remote, any deploy, branch deletion and worktree removal
  are human-only; the loop ends at GATE. Committing in the mission worktree, and merging a task worktree branch into
  the mission worktree (`prime-swarm-graph`), is orchestrator work and allowed.
- Tier B governance files are never edited (write-scope check below). If the task needs one, stop and tell the human.
- Mission work happens only in the worktree from `swarm_adapter.worktree_alloc`, never in the main checkout.

## Write-scope check (shared by all prime-swarm-* skills)

Tier B = the paths in the dotfiles `agent/write-scope-rules.json`, located like `swarm-adapter` locates its scripts
(absolute, from the adapter module's real path), else the installed `~/.prime/agent/write-scope-rules.json`. NEVER
read a cwd-relative path or a copy inside the target repo: that repo could plant one that empties Tier B. Neither
file found: treat every edit as protected and ask the human. Before ANY file edit by you or in a task spec you
write, resolve the target's absolute path and test it against `suffix_patterns` and `fixed_absolute_path_patterns`
(fnmatch; `${HOME}` -> home dir, see its `$comment`). On a match: do not edit, refuse, and escalate to the human.
The fixed paths only name the main checkouts and Claude's `.claude/worktrees/*`, but prime worktrees live OUTSIDE
the repo (`worktree_alloc`: `<repo parent>/.worktrees/<repo>/<slug>-<ts>`), so a bare realpath match misses their
`.claude/settings*.json` (`write-scope-lib.sh` protects those copies). `protected` therefore also tests the
main-checkout twin of the path (same repo-relative path under the git common dir's parent); extra candidates can
only add protection. `changed` lists every path a commit would stage (tracked changes incl. deletions and renames,
plus untracked); it runs read-only git, the commit itself goes through `decide_shell`.

    import json, os, fnmatch, subprocess, swarm_adapter; from pathlib import Path
    agent = next((d for d in Path(swarm_adapter.__file__).resolve().parents if d.name == "agent" and (d / "skills").is_dir()), None)
    rules = next((c for c in ([agent / "write-scope-rules.json"] if agent else []) + [Path.home() / ".prime" / "agent" / "write-scope-rules.json"] if c.is_file()), None)  # None: ask the human
    r = json.load(open(rules)); h = os.path.expanduser("~")
    E = {**{k: v for k, v in os.environ.items() if not k.startswith("GIT_")}, "PYTHONSAFEPATH": "1"}
    def git(wd, *a): return subprocess.run(["git", "-C", wd, *a], capture_output=True, text=True, env=E).stdout.rstrip("\n")
    def protected(target):  # True = protected
        p = os.path.realpath(target); c = [p]
        d = next(str(x) for x in [Path(p), *Path(p).parents] if x.is_dir())
        top, common = git(d, "rev-parse", "--show-toplevel"), git(d, "rev-parse", "--path-format=absolute", "--git-common-dir")
        if top and common: c.append(os.path.realpath(os.path.join(os.path.dirname(common), os.path.relpath(p, os.path.realpath(top)))))
        return any(fnmatch.fnmatch(x, g) for x in c for g in r["suffix_patterns"] + [g.replace("${HOME}", h) for g in r["fixed_absolute_path_patterns"]])
    def changed(wt): return [x for a in (("diff", "--no-renames", "--name-only", "-z", "HEAD"), ("ls-files", "--others", "--exclude-standard", "-z")) for x in git(wt, *a).split("\0") if x]
    print(protected("/abs/target"))  # edit check
    print([x for x in changed("/abs/worktree") if protected(os.path.join("/abs/worktree", x))])  # commit check: non-empty = stop

Residual risk: prime has no write hook, so this is a prompt contract, not an enforced gate. Include the list of
protected targets you checked in the GATE report. Put "never edit Tier B (write-scope-rules.json) files" into every
`task_spec`: the maker child runs outside any hook, so the commit step below is the real check.

## Success rule for every machine run

Use each machine's own **Success rule** (MACHINE.md) verbatim: `rlm.factory.status(run_id)` state `done` AND its
output file present (implement: `outcome.json` with `status: pass`). Anything else (paused, stopped, failed,
`done` without the file) is NOT success. Then: `await rlm.factory.status(run_id)`, `await rlm.factory.stop(run_id)`,
and follow the MACHINE.md instruction (fresh run directory, resize budgets, or escalate to the human). Branch on
status/exit codes, never on prose. Start runs of one machine one at a time (shared pointer file).
A refused `init` (`init.ok` false) goes to `escalate`, which writes no file: it is a non-success run (`done`
without `outcome.json`), retried in a fresh run directory like any other, never a spec block.

**Kinds of `escalated`** (implement `outcome.json` is exactly `{"status": "escalated"}` in every case, so tell
them apart from the node outputs in `await rlm.factory.status(run_id)`): the last `checker` output
`judgement.verdict` is `"TAMPER"` = TAMPER (stop the mission, report to the human); the last `maker` output
`verify.budget` is `"exceeded"` = budget exhausted (attempt or mission limit; stop and report, never raise limits).

## States

1. **SCALE** - `interactive` (one small change, no worktree churn) or `mission` (several tasks, or any
   impact-C change per `agent/rules/impact-scope.md`). Unsure: `mission`.
2. **INIT** - `swarm_adapter.worktree_alloc(slug, scale, cwd=<repo>)` then
   `swarm_adapter.mission_init(slug, goal, scale, cwd=<worktree>)`; stop if either result has `error`/non-zero
   `exit_code`. All later steps use the returned worktree path; keep its `base` sha as the review `base_ref`.
3. **EXPLORE** - skip for a known, small target. Otherwise run `swarm-explore` with
   `{"question", "roots": [<worktree>]}`; the report is `<run_dir>/report.md`. Read the report, not raw shards.
   Non-success run: a NEW run directory, at most 3 explore runs in total (it has no `budget_guard`); after the
   3rd, stop and report.
4. **PLAN** - write `@fix_plan.md` in the worktree: tasks with id, spec, deps, and the verification commands
   (the repo's own build/test/lint). If the design is ambiguous or touches a shared contract, grill the human
   first (grill-interview rules (read `~/.prime/agent/skills/grill-interview/SKILL.md` if present, else ask the human directly): one question at a time, 2-4 options with a `[Recommended]` badge) and
   record decisions in `CONTEXT.md` before any edit. For an architectural dead end use `prime-swarm-architect`.
5. **EXECUTE** - for each task in dependency order, run `swarm-implement` with
   `{"mission", "task_spec", "worktree", "commands", "test_commands"}`. Size `budget_ms` first if the gate takes
   long (MACHINE.md Residual risks). One task = one run directory.
   - Budget: the machine already calls `swarm_adapter.budget_guard` (5 attempts per run, 20 per mission). If
     `outcome.json` is `escalated`, branch on its kind (above), stop and report; do not raise limits.
   - Non-success run (Success rule fails, the maker may never have run): retry the task in a NEW run directory,
     at most 3 runs per task in total (the same `attempts` limit as `prime-swarm-graph`); after the 3rd, stop
     and report.
   - After `pass`, `git diff` in the worktree is the evidence to show, not the checker prose. Then commit it (the
     maker does not commit), in this order. (a) Run the commit check of the write-scope snippet on `changed(<worktree>)`:
     any protected path means NO commit; stop and report the paths to the human (the task is `blocked(spec)`: its
     spec led the maker into Tier B). (b) `changed` empty = zero-diff PASS (the code already satisfied the task):
     skip the commit, the task is done. (c) Otherwise stage every path in `changed` by name and
     `git commit -m "<task-id>: <summary>"`, via `swarm_adapter.decide_shell`, so the next task's checker diff
     (`git diff <init.base>`) holds only that task's change; a failed commit: stop and report.
6. **REVIEW** - run `swarm-review` with `{"worktree", "base_ref": <INIT base sha>}` once all tasks pass. Run success (Success rule)
   and verdict are separate: read `summary.all_pass` and `summary.failed`. Non-success run: a NEW run directory, at
   most 3 review runs per review round (no `budget_guard` runs there, so no mission budget either); after the 3rd,
   stop and report. Failed lenses become new tasks (back to EXECUTE, max 2 review rounds), then stop and report.
7. **GATE** - present: task outcomes, `git diff --stat`, review summary, residual risks. Then
   read `~/.prime/agent/skills/prime-swarm-release-gate/SKILL.md` and follow it (or ask the human to run `/skill:prime-swarm-release-gate`). STOP and wait for the human.

## Optional tools (only where they add value)

- `goal.create(...)` only if the human explicitly asked for a persistent goal; never infer one.
- `rlm.spawn(prompt, name=..., model=<selector>)` for ad-hoc read-only helpers. `model` is the exact
  `tiers.<Tier>.model` value from `~/.prime/agent/model-routing.json`: `tiers.Low` for bulk reading,
  `tiers.Medium` for summarising, `tiers.High` for edits (Maker), `tiers.XHigh` for independent checking,
  `tiers.Max` only for design (see `prime-swarm-architect`). Never hard-code a selector.
- Spot Max-tier help on a stuck task: `swarm_adapter.fable_grant(task_id, mission=<mission slug>)` first; allowed
  only when `exit_code` is 0; any other value (1, 2, 127, ...) or an `error` key means denied.
- Shell guard: for any command not run through a machine, `swarm_adapter.decide_shell(cmd, cwd)`; `block` or
  `ask` means do not run it and ask the human.
