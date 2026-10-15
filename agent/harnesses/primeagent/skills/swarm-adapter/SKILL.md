---
name: swarm-adapter
description: Typed async Python API over the existing swarm scripts (budget-guard, graph-compile/status, mission-init, decide.py) plus prime-only worktree allocation, deterministic verify gates and commit/merge-time Tier B checks. Use from the Python REPL when orchestrating swarm missions; it never re-implements script logic.
---

# Swarm Adapter

Thin kernel-side adapter (CONTEXT Q3): logic stays in the existing scripts, which are
called via subprocess. Every function is async and returns a dict. Call from the REPL:

```python
await swarm_adapter.budget_guard("t1", mission="m")      # {exit_code, stdout, stderr}; exit 1 = budget exceeded
await swarm_adapter.fable_grant("t1", mission="m")       # budget-guard.sh --fable
await swarm_adapter.graph_compile(plan, fit=True)        # parsed JSON + exit_code
await swarm_adapter.graph_status(plan)
await swarm_adapter.mission_init("slug", "goal", "mission", targets=None)
wt = await swarm_adapter.worktree_alloc("slug")          # {path, branch, base, common_dir}
await swarm_adapter.verify(["make test"], wt["path"])    # {passed, results[{command, exit_code, output_tail}]}
await swarm_adapter.decide_shell("git status")           # {decision: allow|ask|block, reason}
# commit/merge-time primitives (CONTEXT Q3-a: prime has no write hook). wt = a worktree TOP LEVEL, base = 7-40 hex sha,
# cd = wt_info["common_dir"] from worktree_alloc (REQUIRED keyword expect_common_dir: pins the repository, see below)
cd = wt["common_dir"]
await swarm_adapter.change_set(wt["path"], base, expect_common_dir=cd)    # {paths: {P: {in: [committed|index|worktree|untracked], kind}}, commits, branch}
await swarm_adapter.tier_b_hits(wt["path"], paths, expect_common_dir=cd)  # {hits, rules}; error -> hits = every path (fail-closed)
await swarm_adapter.stage_task(wt["path"], base, expect_common_dir=cd)    # {staged, tier_b, zero_diff, tree, head}; exit_code 3 = Tier B hit
await swarm_adapter.incoming(mission_wt, task_branch, expect_common_dir=cd)  # {paths, sha, head, tree}; feed paths to tier_b_hits
await swarm_adapter.commit_tree(wt["path"], tree, [parent], msg, expect_common_dir=cd)   # {commit}: the object only, no ref moved
await swarm_adapter.update_ref(wt["path"], commit, parent, expect_common_dir=cd)         # {ref}: fast-forward of the swarm-prime/* branch (CAS)
await swarm_adapter.verify_merge(mission_wt, head, expect_common_dir=cd)  # {paths, tier_b, head}; exit_code != 0 -> STOP, report (read-only)
# commit / merge: ONLY the "Commit and merge" blocks below, never `git commit` / `git merge` / `git update-ref`
```

## Commit and merge (caller side)

Commit and merge ONLY with these two blocks, exactly as written (the tests execute them); never `git commit`, `git merge` or
`git update-ref`. Any git command run in the target repository reads the git dir it shares with the maker: `stage_task`'s
`read-tree` drops the index's stat data, so `git commit` re-hashes every file through the clean filter that the shared config +
`<common dir>/info/attributes` select and then runs `git maintenance run --auto` (measured, even
`git -c core.hooksPath=/dev/null commit --no-verify`; pinned by a negative-control test), and any git command that meets a missing
object fetches it from a configured promisor remote, which runs that remote's `uploadpack` command (Checker a10: a maker only has
to point HEAD or a branch at a commit that does not exist). So no step below runs git in the repository: `commit_tree` writes the
commit object from the private shadow repository (Notes, "No git command runs in the target repository"), and `update_ref` moves
the branch in Python (`<ref>.lock`, compare-and-swap) and, with `checkout=True`, updates the real index and working tree with
`read-tree -m -u` in the shadow. Measured with `GIT_TRACE2_EVENT` under every trap of the primitives' tests (hooks, fsmonitor,
filters/drivers named by `<common dir>/info/attributes`, signing, a promisor remote, `include.path`, ...): 0 `child_start`.

What is committed is exactly the verified tree (`st["tree"]` / `inc["tree"]`) on top of the checked parent(s), so an index or a ref
that a maker's leftover process writes after the check cannot change it; `update_ref` moves nothing unless the branch still is the
checked parent (`st["head"]` / `inc["head"]`), and only ever onto a commit whose first parent is that tip, on a `swarm-prime/*`
branch. Any STOP after `update_ref` = a failed task that a human undoes (the previous tip is the commit's first parent).

**Signing: commits made here are NOT signed.** `gpg.program`, `gpg.format`, `gpg.ssh.program` and `user.signingKey` live in config a
maker can write, and the shadow has none of it (`commit-tree` signs only with `-S`, which is never passed). A repository that
requires signed commits needs a human to sign/re-sign outside the agent. Author/committer: `GIT_AUTHOR_*`/`GIT_COMMITTER_*` of the
environment, else `user.name`/`user.email` of the user's global git config (parsed, includes not followed); never the repository's.

Commit (`st` = `stage_task` result with `exit_code` 0, `msg` = the commit message):

```python
c = await swarm_adapter.commit_tree(wt["path"], st["tree"], [st["head"]], msg, expect_common_dir=cd)  # the object only
if c["exit_code"] != 0:
    raise RuntimeError(f"STOP: commit_tree: {c}")
u = await swarm_adapter.update_ref(wt["path"], c["commit"], st["head"], expect_common_dir=cd)  # branch: st["head"] -> commit
if u["exit_code"] != 0:
    raise RuntimeError(f"STOP: update_ref: {u}")
```

Merge (`inc` = `incoming` result with `exit_code` 0; the block runs `tier_b_hits(mission_wt, inc["paths"])` itself and STOPs, nothing
written, on `exit_code != 0` or any hit). The merge commit's tree IS `incoming`'s merge-tree result; `checkout=True` brings the
mission worktree's index and files along (refused, nothing moved, when a local change or an untracked file is in the way or the
index has staged changes):

```python
tb = await swarm_adapter.tier_b_hits(mission_wt, inc["paths"], expect_common_dir=cd)  # incl. symlink targets (every checkout location)
if tb["exit_code"] != 0 or tb["hits"]:
    raise RuntimeError(f"STOP: tier_b_hits: {tb}")  # Tier B change (or unusable rules): a human decides, nothing merged
c = await swarm_adapter.commit_tree(mission_wt, inc["tree"], [inc["head"], inc["sha"]], msg, expect_common_dir=cd)
if c["exit_code"] != 0:
    raise RuntimeError(f"STOP: commit_tree: {c}")
u = await swarm_adapter.update_ref(mission_wt, c["commit"], inc["head"], checkout=True, expect_common_dir=cd)
if u["exit_code"] != 0:
    raise RuntimeError(f"STOP: update_ref: {u}")  # e.g. the mission HEAD moved since incoming: re-run incoming
vm = await swarm_adapter.verify_merge(mission_wt, inc["head"], expect_common_dir=cd)
if vm["exit_code"] != 0:
    raise RuntimeError(f"STOP: verify_merge: {vm}")
```

## Notes

- `graph_compile` exit codes: 0 OK, 2 UNFIT_FALLBACK_LOOP, 3 CYCLE, 4 MISSING_DEP, 5 VERIFIER_FLOOR,
  6 NO_TASKS, 7 PARSE_ERROR. Branch on `verdict`/`exit_code`, never on prose.
- Script root: the dotfiles repo `agent/skills` found from this skill's real path, else `~/.claude/skills`; always absolute. There is NO env
  override (`SWARM_SCRIPTS_ROOT`/`SWARM_AGENT_DIR` were removed): scripts and decide.py run with the caller's target repo as cwd, so a
  cwd-relative or env-chosen path would let that repo make the adapter execute its own code. A missing script yields `exit_code` 127.
- `worktree_alloc` places worktrees outside the repo: `${SWARM_WORKTREE_DIR:-<repo parent>/.worktrees/<repo>}/<slug>-<UTC ts>`,
  branch `swarm-prime/<slug>-<ts>`. A relative `SWARM_WORKTREE_DIR` is made absolute against the process cwd; a location inside the repo is refused.
- The adapter performs NO destructive operation, so there is no release/remove function. Worktree cleanup is done by the human or by
  `agent/skills/swarm-implement/scripts/worktree-release.sh`, outside the agent.
- `verify` runs every command (no short-circuit); a bare str is one command; `passed` is false for an empty list or a missing `cwd`
  (`error` set). `output_tail` is the last 4000 chars of stdout+stderr. A per-command failure to launch (OSError, null byte, non-str element,
  bad `timeout`) is that command's `exit_code` 126/127 and the others still run.
  A timeout kills the whole process group (`exit_code` 124) and the call returns within `timeout` + 2s per command.
  **Known limit:** a descendant that left the group (`setsid`, `set -m`) is not killed; its still-open output pipe is abandoned
  after 2s (the `output_tail` says so) and the process may outlive the call. If the command itself had already exited on its own, its real `exit_code` is reported (not 124) together with that note.
- **Never raises, by construction:** every public function sits behind one `_boundary` wrapper that turns any Exception into
  `{exit_code: 1, stdout: "", stderr: "", error: "<Type>: <msg>"}` (verify: `{passed: false, results: [], error}`; decide_shell:
  `decision: "block"`, `error`). Inputs are therefore not type-checked individually (non-str task ids, `cwd` pointing at a file, ... yield `error`).
- Repo layout: `worktree_alloc` supports only a plain checkout (git common dir resolves to exactly `<toplevel>/.git`, which includes linked
  worktrees of it). A submodule or `--separate-git-dir` checkout is refused (`error` "unsupported repository layout"). The worktree dir may be
  neither inside the main checkout nor inside the caller's checkout. Inherited `GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE`/... are
  stripped from every git call (e.g. when run from a git hook).
  Known limit: a *linked* worktree of a `--separate-git-dir` repo is not detected (indistinguishable by layout).
- `graph_compile`/`graph_status`/`mission_init` take `cwd` (default: process cwd).
- `budget_guard(task, mission=, max_attempts=, mission_max=, reset=)` maps to the script's positional/`--mission`/`--mission-max`/`--reset`
  options; `fable_maker(base_task)` is `--fable-maker`. `mission_init(..., depth=, cwd=)` runs in the mission worktree `cwd`.
- `decide_shell(command, cwd=None)` is FAIL-CLOSED: this adapter runs without hooks, so if decide.py or security-rules.json cannot be found
  or run, the result is `decision: "block"` with an `error` field. The agent dir is discovered from this skill's real path (so a symlinked install works).
  It sends harness `"primeagent"`: prime has no human confirm, so decide.py's advisory layer (guard_relax; claude/agy/pi only) must not relax a decision.
- `decide_shell` runs decide.py with its process cwd set to `cwd` (default: process cwd), because the protected-branch rules read the branch of that
  directory; a nonexistent `cwd` yields `block`.
- Every script subprocess gets `PYTHONSAFEPATH=1` and decide.py is launched `python3 -I <abs path>`, so a target repo's own `re.py`/`json.py`
  is never imported.
- `decide_shell` also validates `security-rules.json` itself (same criterion as `agent/scripts/prime-shell-guard.sh`, pinned by a parity test: JSON object whose `shell_command_rules` has >=1 `tier == "block"` rule with a non-empty `all_of`/`any_of`/`any_of_with_branches`) and treats any decide.py reply whose
  reason contains `fail-open` as `block`.
- `worktree_alloc(..., base_ref="HEAD")` branches from `base_ref` resolved in the caller's `cwd` checkout (not the main repo HEAD); result has `base` (sha).
- `plan_path` (graph_*) and `scale` (mission_init) are optional like the scripts'; task_id/slug/plan_path/stale/base_ref starting with `-` return an error dict.
- Commit/merge-time primitives (CONTEXT Q3-a; prime has no write hook, so these replace the Claude-side write-time guard).
  `change_set`, `tier_b_hits`, `stage_task`, `incoming`, `verify_merge` check; `commit_tree` + `update_ref` are the only way to commit
  and merge (above), and only after branching on `exit_code`/`error`/`tier_b`. Nothing here pushes, resets or rewinds.
  **`exit_code != 0` always means refuse** (no commit/merge), whatever else the dict holds: some failures (bad `wt` type, ...) carry no
  `tier_b`/`paths`, and `hits` on a failure is only the best-effort list of the given paths.
  **No git command runs in the target repository** (T6c attempt 11). Every setting git reads there (shared config, `hooks/`,
  `info/attributes`, refs, `shallow`, `commondir`) is maker-writable, and switching the dangerous ones off one at a time kept missing
  one: a filter driver named `x=y` (`-c` splits it at the first `=`) and a nested repository's own filter ran in a7; a promisor remote
  whose `uploadpack` command runs when a ref names a missing commit ran in a10. Instead:
  - **Location, format and refs are read by Python, never by git**: `<wt>/.git` (a real directory, or a gitfile -> admin dir ->
    `commondir` + the `gitdir` back link), pinned to `expect_common_dir`; `HEAD`, loose `refs/heads/*` and `packed-refs` (every line
    validated; peeled `^` lines skipped) with symrefs followed at most 5 hops, every value a 40-hex sha. The repository format is
    parsed (not executed) from `<common>/config`: `extensions.objectFormat` other than sha1, `extensions.refStorage` other than files
    or a `reftable` dir, and a `shallow` file (the shadow has no shallow list, so ancestry answers could differ) are an `error`.
  - **Every git command runs in a private bare shadow repository** (a mkdtemp dir per call: the adapter's own minimal config, no
    hooks, no `info/attributes`, no refs, `info/exclude` copied from the real one as data) with `GIT_DIR=<shadow>`,
    `GIT_OBJECT_DIRECTORY=<real objects>` (objects and the alternates they list are read there and new objects written there; config
    is read from `GIT_DIR` only, measured with `GIT_TRACE2_CONFIG_PARAMS`), `GIT_INDEX_FILE=<real index>` (or a private one),
    `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, `HOME`/`XDG_CONFIG_HOME` = an empty dir, `GIT_NO_LAZY_FETCH=1` (a missing
    object is an `error`, never a fetch; git >= 2.45 is checked), `GIT_NO_REPLACE_OBJECTS=1`, `GIT_GRAFT_FILE=/dev/null`,
    `GIT_ATTR_SOURCE=<empty tree>`, every other inherited `GIT_*` dropped (`GIT_TRACE*`, `GIT_AUTHOR_*`, `GIT_COMMITTER_*` kept), and
    through `GIT_CONFIG_COUNT` (defense in depth) `core.hooksPath=/dev/null`, `core.fsmonitor=false`, `core.attributesFile=/dev/null`,
    `core.commitGraph=false`, `core.multiPackIndex=false`, `diff.ignoreSubmodules=none`, `gc.auto=0`, `maintenance.auto=false`.
    The git binary is given only shas, never a ref name. It is exec'd by its absolute path, resolved once per process with
    `shutil.which` over the absolute `PATH` entries only (an empty or `.` entry is skipped) and refused if its real path lies in the
    checkout, the main checkout or the temp dir; its cwd is always the call's tmp dir (also with `GIT_WORK_TREE`) and the `PATH` it
    gets has no relative entry, so a `git` file in a working tree is never run.
  - **The working tree is listed and read by Python** (`os.scandir`, symlinks never followed, blobs hashed from the raw bytes, new blobs
    written by `hash-object -w --no-filters` from private copies). Two shadow commands read it with `GIT_WORK_TREE`, where no config or
    attributes can name a command: `check-ignore --no-index` (the `.gitignore` files) and `update_ref(checkout=True)`'s `read-tree -m -u`.
  - Measured with `GIT_TRACE2_EVENT` (pinned by tests): 0 `child_start` events in all seven functions and both "Commit and merge"
    blocks while hooks (also via `core.hooksPath`), `core.fsmonitor`/`pager`/`editor`/`askPass`/`sshCommand`/`gitProxy`/
    `alternateRefsCommand`, `filter.<n>.*`/`diff.<n>.*`/`merge.<n>.driver` (names with `=` included) selected by
    `<common dir>/info/attributes` or `core.attributesFile`, `include.path`, `diff.external`, `credential.helper`, `gpg.program`,
    `gc.auto`, `maintenance.auto`, a promisor remote with `uploadpack` (+ `extensions.partialClone`) and an `objects/info/alternates`
    into another repository all hold a trap, and with HEAD / a branch pointing at a missing commit; the same git commands run against
    the real repository start children (negative controls).
  - Known behaviour changes of the shadow: the global `core.excludesFile` is not applied by `stage_task` (measured: a file ignored only
    there is staged; still Tier B checked); an object a partial clone lacks is an `error`, never fetched. Measured to work as before:
    a split index, and a `--shared` clone whose objects are only in its alternates.
  - **The object store is not trusted: every object a check reads is re-hashed first** (T6c a17). The shared `objects/` is
    maker-writable: a loose object file, a pack whose `.idx` gives an entry another id, or a directory in `objects/info/alternates`
    can serve other content under an existing id. git checks the hash of an object it parses by name (a forged ROOT tree: "hash
    mismatch"), but not of the subtrees `diff-tree` / `ls-tree -r` / `merge-tree` read below it, nor of a blob (measured, git 2.54,
    all three ways: the task's `agent/hooks/claude` subtree with HOOK = EVIL served under base's subtree id made the Tier B change
    vanish, and stage_task, commit_tree, update_ref, incoming, tier_b_hits, the merge and verify_merge all exited 0; `git fsck`
    reports "hash-path mismatch" / "packed ... is corrupt"). So Python re-hashes what `cat-file --batch` returns in the shadow (git's
    own lookup: loose, packed and alternates objects alike; `sha1("<type> <size>\0" + content)` must be the id and the type the one
    named, else `error`): base's and HEAD's commit and every tree they reach (`change_set`, `stage_task`), the tree `stage_task`
    builds, `head`'s and `sha`'s commit and the merge result with every tree they reach (`incoming`), `head`'s and HEAD's
    (`verify_merge`), the parents, the tree and the written commit (`commit_tree`: git keeps an object already stored under the new
    id, so a planted commit was returned with exit 0), both blobs of every diff entry, and every symlink blob whose target is read.
    Trees are walked by Python from the re-hashed content (one `cat-file --batch` per depth level), never from a git listing; an
    object is read once per call; at most 1,000,000 objects and 4 GiB per call, more is an `error`. Cost measured on a clone of
    this dotfiles repository (215 trees per commit): a cold walk 16 ms; medians of 3 with/without: `stage_task` 112/87 ms,
    `incoming` 29/11, `verify_merge` 30/12, `commit_tree` 27/11 ms; vald (735 trees) 30 ms per walk.
    Residual risk: (1) ancestry is not re-hashed, only the commits named above: `merge-base --is-ancestor`, `rev-list --count` and
    merge-tree's merge bases read intermediate commits unchecked (measured: a forged intermediate commit made an unrelated commit an
    "ancestor"); the Tier B checks still diff re-hashed trees, so this can change what is merged, not hide a path from the checked
    diff. (2) Blobs of unchanged paths are not read (an id comparison does not need them): a blob forged under an id base already
    holds is written by every later plain checkout or local clone (measured: `git worktree add`, `git clone`; a `--no-local` clone
    refuses it); that needs no adapter call and no diff shows it. (3) Time of check: a maker process still running can swap an
    object between the re-hash and git's read of it, or after the check; `update_ref(checkout=True)`'s `read-tree -m -u` writes
    blobs into the mission working tree without a re-hash (`verify_merge` re-checks the committed objects afterwards, not the files
    written). (4) `hashlib.sha1` has no collision detection (git's default sha1dc backend does): a planted SHA-1 collision pair would pass.
  - **Submodules cannot hide a change.** `.gitmodules` (`ignore = all`, working tree or committed) and `diff.ignoreSubmodules` make a plain
    `git diff`/`diff-tree` skip a gitlink entry. Every diff-tree here therefore carries `--ignore-submodules=none` (measured with git 2.54:
    `diff.ignoreSubmodules=none` alone does NOT beat `.gitmodules`, only the flag does); `ls-tree`/`ls-files` list a gitlink regardless. A
    nested repository or submodule checkout in the working tree (any `.git` entry below the top level: directory, gitfile or symlink) is
    an `error` of `change_set`/`stage_task`, found by the Python scan before git reads anything of `wt`. In addition a
    gitlink (mode 160000) added, changed or removed in the diff that `stage_task` (base..verified tree), `incoming` (`head` -> the merge result tree) or
    `verify_merge` (`head..HEAD`) reports is an `error` with no `tree`/`paths`: a task result never carries a submodule.
  - **Symlink blobs are resolved inside the tree.** The Tier B check reads the working tree, which an index-injected symlink blob never
    touches. When the final diff adds, changes or removes ANY symlink (mode 120000 on either side, a directory swapped for a
    symlink or back included), EVERY symlink of the tree is resolved again, not only the added ones (T6c a15: an unchanged
    `y -> d/write-scope-rules.json` names `agent/write-scope-rules.json` once a task turns the directory `d` into `d -> agent`;
    inside the tree only symlinks steer a walk, so a diff that touches none resolves nothing). For each, the target string is read from the tree (`cat-file --batch`, re-hashed as above, as bytes, fs-decoded like the tree paths so a non-UTF-8 name matches), resolved from the
    link's directory and checked as one more path: a repository-relative path when it points inside the repository, an absolute one
    (matched as-is, plus its realpath) when it points outside. The path is resolved element by element in the kernel's order (each
    element resolved before the next one, `..` included, applies to it): an element inside the checkout by the TREE (its symlinks
    followed, anything else a plain entry), an element the tree does NOT have (untracked, ignored: a checkout leaves it on disk, T6c
    a16) and an element outside every checkout location (below) by the DISK (lstat; a symlink is read
    and followed, so `<outside symlink>/..` is the parent of its target, as for the kernel: with `~/.claude/skills ->
    <dotfiles>/agent/skills` from `make claude/install`, a link `x -> ../../../../../.claude/skills/../write-scope-rules.json` in the
    main checkout resolves to `<main>/agent/write-scope-rules.json`, T6c a14). Tree and disk hops together: at most 40, else
    `error`; over all links, locations and twin re-walks of one check at most 100000 hops and at most 1000 symlinks in the tree,
    else `error`; an lstat/readlink error other than a missing element is an `error` too. **A process-dependent or special file
    system is an `error`** (T6c a15): the kernel resolves `/proc/self`, `/proc/thread-self`, `/proc/<pid>/{cwd,root,fd}`,
    `/dev/fd`, `/dev/stdin` ... for the process that LOOKS, so what the adapter reads there is only its own view (`x ->
    /proc/self/cwd/../dotfiles/.claude/settings.json` passed every check with the adapter's cwd anywhere and is the main
    checkout's settings.json for a process whose cwd is the main checkout). Refused: an element the walk resolves on disk at or
    below `/proc`, `/dev` or `/sys` (the whole trees, so a container whose `/dev` is a tmpfs is covered), an element whose lstat
    `st_dev` is a mount of type proc / sysfs / devtmpfs / devpts / cgroup(2) / mqueue / debugfs / tracefs / securityfs / pstore /
    bpf / configfs / fusectl / binfmt_misc / efivarfs / selinuxfs / nsfs (from `/proc/self/mountinfo`, read by Python: a /proc
    bind-mounted elsewhere; unreadable mountinfo is an `error`), and a symlink target (tree or disk) that is an absolute path
    starting at or below one of those three prefixes; every element inside a checkout is lstat'ed for these checks, the tree's
    included. **Where tree and disk disagree inside a checkout** (a symlink on disk where the tree has none or another target, a
    directory on disk where the tree has a file or symlink: e.g. a local change in the mission worktree, which `read-tree -m -u` and
    `git merge` keep at a path the merge does not touch, or another worktree that never gets this tree), BOTH are resolved: the
    walk goes on with the tree, and a second walk takes that element and everything below it from disk (T6c a16). Not an error:
    that would refuse every retargeted symlink, since the main checkout's disk still holds the old target. The directories above
    the checkout are taken as named (its realpath is a location of its own, below); an element that does not exist yet is kept
    as a plain name and the walk goes on (the path it would be once created as a directory: safe side). `incoming`/`verify_merge` add these targets to `paths`; `stage_task` reports them in `tier_b` (so `hits`
    can name a path that is not itself in the diff). A target that dangles in the tree is checked under the path it names.
    **Where a relative link points depends on where the tree is checked out** (T6c a13): a prime worktree sits two levels below the
    main checkout's parent, so `x -> ../dotfiles/.claude/settings.json` is harmless in the task/mission worktree and names the main
    checkout's own settings.json after the merge reaches it. Each link is therefore resolved with the tree at EVERY known location:
    the checkout being checked, the main checkout, every linked worktree registered in `<common dir>/worktrees/*/gitdir` (mission and
    task included), and a stand-in for a not-yet-created worktree under each worktree_alloc root (`<repo parent>/.worktrees/<repo>`
    and `$SWARM_WORKTREE_DIR`), each as given and as realpath. **A registration is verified first** (T6c a16: the shared git dir is
    writable, and a hand-written `<common>/worktrees/<n>/gitdir` made any directory a location): each entry must be a real directory
    with `HEAD` and a `commondir` naming this common dir, its `gitdir` must name `<wt>/.git` (`<wt>` no symlink, no special path), and
    that `.git` must be a gitfile naming this admin dir back; else `error` ("forged or broken"; also one caught mid-`git worktree add`:
    retry). An entry without `gitdir` is skipped and one whose `.git` is gone (git's "prunable") stays a location. A registration
    forged consistently in every file is a worktree to git and is used; being a location only adds the tree's view there (the
    disk is still read where the tree has nothing or disagrees). Once the walk outside its location enters one of these locations, it
    stops there and the rest of the path is resolved again from that location with the tree (the twin; also for the final path's
    realpath), reported repository-relative, so it is checked against `<wt>`/`<main checkout>` as well.
    Residual risk: a checkout at a location not on that list (a hand-made worktree or clone elsewhere, another `$SWARM_WORKTREE_DIR`,
    a link that spells out the name of a worktree not created yet) can still resolve a relative link differently; a directory
    symlink to a Tier B directory is a hit only through a path naming a Tier B file below it (a path in the diff or a symlink of
    the tree; the patterns match files). The disk outside the repository is read at check time: a symlink created or changed there
    afterwards (including at an element that did not exist yet) can make an already-checked link resolve elsewhere, and a diff
    that touches no symlink re-walks nothing even if the disk changed; the same holds INSIDE the checkouts (an untracked or ignored
    symlink, a local change, a registration written after the check). Tree and disk are combined per walk only as "the tree" or
    "from one disagreeing element on, the disk" (each further disagreement forks again), not every mix of the two. More walks also
    mean more fail-closed refusals: a symlink loop or special path in ANY view (another worktree's disk included) is an `error`.
    A FUSE or other file system outside that list that answers per process is not recognized.
  - **`expect_common_dir` (REQUIRED keyword, absolute) on all seven**: the git common dir of the repository the caller allocated
    (`worktree_alloc`'s `common_dir`, taken BEFORE the maker ran). `<wt>/.git` is maker-controlled: pointing the gitfile at a decoy
    clone made every git call answer for the decoy (empty change set, `zero_diff`). Now a missing/relative/mismatching value is
    `exit_code != 0` + `error`, as is a symlinked `<wt>/.git` or a git dir that is not this checkout's own admin dir of that repository
    (a linked worktree's `<common>/worktrees/<name>/gitdir` must name this `<wt>/.git`; the main checkout's `.git` must be a real
    directory). Plain layout only: the common dir must be named `.git` and be the real `.git` directory of its parent (the main
    checkout); a linked worktree of a `--separate-git-dir` repo whose git dir is itself named `.git` still cannot be told apart.
  - `change_set(wt, base, expect_common_dir=)`: every path changed since `base` in any state: `committed` (base vs HEAD's tree), `index`
    (base vs the index), `worktree` (base vs the working-tree content of the paths the index has, as `git diff <base>`), `untracked`
    (every working-tree file/symlink the index lacks, **ignored ones included**: they are Tier B checked like any change; only
    `stage_task` leaves them out of the commit). Per-path comparison, so a rename is its old and new path. Blobs are hashed raw (no
    `text`/`eol`/`filter=` conversion): a repository relying on such attributes shows those paths as changed.
    `kind` is `typechange` (file/symlink/gitlink type changed in any column), `file` / `symlink` (what the working tree holds now; a file
    kept after `git rm --cached` is `file`), `gitlink` (a gitlink index entry with nothing in the working tree at that path) or `deleted`
    (nothing there, including beyond a symlinked parent). `commits` = commits in base..HEAD, `branch` = HEAD's branch without
    `refs/heads/` (`""` when detached). A nested repository / submodule checkout or a skip-worktree (sparse checkout) index entry is an
    `error`; so is any git failure, unreadable file or missing object: no `paths`.
    `base` (7-40 hex; `machines/swarm-implement/MACHINE.md` `init.base` is 12) is resolved in the shadow (no refs: an object id prefix
    only) and still refused if any ref/`$GIT_DIR` file of the real repository has that name (a caller's plain git would resolve it
    ref-first) or if the resolved sha does not start with it; only the full sha is used afterwards.
  - `tier_b_hits(wt, paths, expect_common_dir=)`: `paths` is materialised once (a generator/map/filter is fine; it used to be consumed by the
    fail-closed fallback and then hit nothing); a single str/bytes/PathLike instead of a list is an `error` (hits = that path). A repo-relative P hits if `agent/write-scope-rules.json` (both arrays, case-sensitive fnmatch, `${HOME}`
    expanded; parity-tested against `write-scope-lib.sh`) matches ANY of `<wt>/P` unresolved, its realpath, `<main checkout>/P`
    unresolved (main = parent of the git common dir; this is what catches a prime worktree's `.claude/settings*.json`), its realpath.
    Every realpath here is the adapter's own disk walk (`_real`), not `os.path.realpath`: a candidate whose resolution touches
    `/proc`, `/dev`, `/sys` or a special mount (below) is an `error` (T6c a16: `os.path.realpath` answered `/proc/self/cwd` for the
    adapter's cwd, so an ignored `ig/s -> /proc/self/cwd/.claude` in the task worktree passed with the adapter outside every checkout).
    The rules are read only next to this skill (no `~/.prime/agent` fallback); ANY failure (missing/malformed rules, a bad or non-str
    `wt`, a NUL byte, a non-str path) gives `error` with `hits` = every given path that is path-like.
  - `stage_task(wt, base, exclude=("@fix_plan.md",), expect_common_dir=)`: Tier B check first, over the change set | HEAD vs working tree |
    HEAD vs index, **excluded and ignored paths included**. On a hit: `{staged: [], tier_b: [...], zero_diff: false, exit_code: 3}`,
    nothing staged. What is staged: the working tree as `change_set` reads it, minus `exclude` (exact repo-root-relative names: kept at
    HEAD's entry, or left out if HEAD lacks it, whatever the maker staged with `git add -f`; the working tree is never touched) and minus
    ignored files that neither HEAD nor the index has (never committed; `git add` would skip them too). So the commit == the working
    tree for every other path: deletions/renames already committed or `git rm`/`git mv`-ed, `git rm --cached` + keeping the file (staged
    as a change), index-only changes (resynced). It never uses `git add` (it exits 128 on a deletion already committed, and `git add -A`
    is blocked by the `git_add_mass_staging` security rule). Any gitlink in HEAD or the index is an `error` (the working tree cannot hold
    one, so it would be staged as its removal).
    `base` must be an ancestor of HEAD, else `error` before anything is staged: after a maker's `git reset --hard base~1` the tree differs from base's by the reverse of base's own commits (it used to be reported as `zero_diff` true, dropping the task's effect).
    **Build, then verify the RESULT**: new blobs are written by `hash-object -w --no-filters --stdin-paths` from private copies (each
    re-read must still hash as checked), the entries go into a PRIVATE index (`GIT_INDEX_FILE` in a mkdtemp dir, `update-index -z
    --index-info`), `write-tree`. That tree's `diff-tree -r --no-renames base..tree` is Tier B checked together with every earlier path
    (an entry that reached the private index after the pre-check is exit 3 with NO `tree`), every intended entry must be in it, and no
    excluded path may differ from HEAD in it. Only then is the REAL index written, with `read-tree <tree>` (no `-m`/`-u`), and it must
    write back the same tree (else `error`). Every failure before that leaves the real index as the maker left it. `read-tree` drops
    the index's stat data, so the caller's next `git status` re-reads every file. `staged` = HEAD vs that verified tree; `zero_diff` = the
    returned `tree` IS `base`'s own tree (decided on the tree: commits the maker made and undid count as zero, committed changes still in
    the tree do not); `head` = the HEAD commit it was staged on. Commit it ONLY with the "Commit and merge" commit block above
    (`commit_tree(wt, tree, [head])` + `update_ref(wt, commit, head)`): the commit is exactly `tree`, and the branch moves only if it
    still is `head`.
    Side effect of reading raw bytes: no `text`/`eol`/`ident`/`filter=` conversion happens while staging, files are committed as they are on disk.
  - `incoming(mission_wt, branch, expect_common_dir=)`: what a merge of `branch` would change, taken from the merge RESULT:
    `git merge-tree --write-tree <head> <sha>` (the ort merge, no working tree, no ref moved) in the shadow, then
    `diff-tree -r <head> <result tree>`. In the shadow no `merge.<n>.driver` or filter can be selected (`<common dir>/info/attributes`
    can select one and no git option disables it, and blanking a driver in the config still made git attempt the spawn), and the
    result tree is what the merge block commits (`commit_tree(mission_wt, tree, [head, sha])`), so the merge cannot differ from what
    was checked: no up-front refusal of configured drivers is needed any more (a9-a10 refused them because the caller ran `git merge`).
    Repository-level merge settings (`merge.renames`, ...) are not applied (the shadow has none).
    NOT `git diff head...sha`: with several merge bases (criss-cross history) that diff uses only the first base while ort builds a
    virtual one, so it can miss a path the merge changes (measured: a Tier B file went O -> E unseen). A merge that conflicts (or
    unrelated histories) is an `error`: do not merge. `branch` must be an existing `refs/heads/<branch>` (read by Python), `<sha>` is its
    commit and `<head>` the mission worktree's HEAD commit. Returns `{paths, sha, head, tree, exit_code}`.
    `""` (change_set's detached HEAD), `HEAD`, `@`, tags, shas, invalid ref names (`x~0`) and a `-`-leading name are refused.
  - `verify_merge(mission_wt, head, expect_common_dir=)` (READ-ONLY; call it right after the merge): `head` = `incoming`'s `head` (full 40-hex).
    HEAD must be a descendant of `head` (else `error`); `diff-tree -r head HEAD` over the COMMITTED trees (replace refs ignored, submodule
    hiding off) is gitlink-checked and Tier B checked, symlink targets included (above). Returns `{paths, tier_b, head: <HEAD checked>,
    exit_code}`: 0 clean, 3 Tier B hit, other = error (gitlink, not a descendant, git failure). **Anything but 0: STOP and report to a human; do not
    `git reset --hard` (the adapter never destroys, and nothing here undoes the merge for you).**
    Why it exists: the merge commit is checked as committed, independent of how it was made (a9-a10 merged with `git merge`, where a
    `post-merge` hook could replace HEAD, measured). ALWAYS run `verify_merge` before anything builds on the new HEAD.
  - `commit_tree(wt, tree, parents, msg, expect_common_dir=)`: writes the commit object only (1-2 full-sha parents, an existing tree; no
    ref, index or working tree touched) via `commit-tree` in the shadow, into the repository's object store. The written commit's
    parents are read back from git and must be `parents` (`commit-tree` drops a duplicate `-p` with exit 0: `error`). Returns `{commit,
    tree, parents, exit_code}`. Not signed (above).
  - `update_ref(wt, new, old, checkout=False, expect_common_dir=)`: the step that makes the commit the branch tip. HEAD of `wt` must be
    a symbolic ref to `refs/heads/swarm-prime/*` (what `worktree_alloc` creates; detached HEAD or another branch: `error`), `new`'s first
    parent must be `old` (a fast-forward by one commit: history is never rewound or replaced, undo = move it back to that parent), and
    the branch must still be `old`. `new`'s parents are git's own reading (`rev-list --parents -n1` in the shadow), never parsed from
    the object text: git takes only the `parent` lines right after `tree`, and a commit with `parent <old>` after `committer` (plain
    `hash-object -t commit -w` writes one) is a ROOT commit to git, which a header scan took for a child of `old` (T6c a11: the branch
    was replaced, and with `checkout=True` every file deleted). `old` must also be an ancestor of `new` (`merge-base --is-ancestor`).
    Written by Python like git's files backend: every directory below the common dir opened
    `O_NOFOLLOW`, `<ref>.lock` created `O_EXCL` (an existing lock = `error`), the value (loose, else `packed-refs`) re-read and compared
    under the lock, written, renamed over the ref; no reflog entry. The loose ref path must be absent or a regular file (a directory
    there = `error`, checked before anything else happens). Why in the adapter: `git update-ref` reads the shared config (hooks,
    lazy fetch), so there is no git command that can do it safely, and lock-file code in this document would run untested.
    `checkout=True` (the merge): under the lock, after `new` is written into the lock and before the rename, the index must equal
    `old`'s tree, the working tree must hold no nested repository, and `read-tree -m -u old new` in the shadow updates the real index
    and working tree; git's own checks refuse to overwrite a local change or an untracked file and write nothing then. If the rename
    then fails, `read-tree -m -u new old` restores `old`'s index and working tree and the `error` says it did, or that it could not
    (a change made meanwhile: git refuses to overwrite it, they stay at `new`). Every `error` leaves the ref unchanged; an I/O failure
    in the middle of `read-tree -u` can leave the working tree partly updated (`git status` shows it).
  - `wt`/`mission_wt` must be the worktree top level (`error` otherwise); paths are NUL-split and fs-decoded, so newline/non-UTF-8 names work.
- Tests: `uv run --with pytest pytest -q` from this directory.
