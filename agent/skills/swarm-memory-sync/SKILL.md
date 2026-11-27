---
name: swarm-memory-sync
description: "Distill generalizable learnings from trajectory logs/@fix_plan.md into persistent memory via memory-guard.sh. Triggers: GATE/PLAN or `/swarm-memory-sync`."
allowed-tools: [Read, Grep, Glob, Bash, Write, Edit]
user-invocable: true
disable-model-invocation: false
---

# swarm-memory-sync — Distilling domain knowledge (paired with swarm-evolve)

Before starting, run `~/.claude/skills/_swarm-common/load.sh core --once` to read the shared summary (do not read the
full 63KB SWARM.md; read a section only when needed, using the line ranges in CORE.md's index with `offset`/`limit`).
If already loaded in this context a stub is returned; use `--force` after context compaction.

## Position

Distinct in axis from `swarm-evolve` (SWARM.md §5, which evolves the Skills' own behavior
policy -- see the frontmatter description for the differences/boundary). This skill is purely
about recording domain knowledge, which is reversible and low-risk (a mistaken write can
always be corrected via a follow-up write), so it does not require human approval -- for the
same reason `disable-model-invocation: false` (in contrast to `swarm-evolve`, which is
restricted to `true` due to its high-alert level), so that `swarm-loop` Phase 2/5's internal
calls are not blocked even when triggered by natural-language phrasing.

Note that the raw logs of the Haiku exploration swarm / Maker / Checker themselves are never
used as direct input to this skill. These are already summarized into trajectory logs /
`@fix_plan.md` via `swarm-secretary`'s structured reports and `swarm-implement`'s completion
handling; this skill extracts only the further-generalizable parts from that summary
(preserving the Observation Masking principle, an SWARM.md invariant).

## Triggers and input sources

1. **Internal call from `swarm-loop` Phase 5 GATE** (the normal path): input is this mission's
   newly appended trajectory-log lines + the entire `## Escalations / Learnings` section of
   `@fix_plan.md` + the Root Causes from `## Secretary Report`.
2. **Internal call from `swarm-loop` Phase 2 PLAN** (end of an Interactive design interview):
   at this point the trajectory log / `@fix_plan.md` learnings are not yet recorded, so the
   input is instead the immediately preceding dialogue turns themselves (the human's design
   decisions, preferences, constraint answers). Because the volume is small, an enumerated
   listing like the retroactive pass is unnecessary -- steps 2-5 below can be applied on the
   spot, one entry at a time.
3. **Explicit human invocation of `/swarm-memory-sync`** (retroactive processing, any time):
   input is the entire trajectory log of the target repository, or a human-specified date
   range.

## Procedure

1. **Candidate extraction** -- enumerate "learning" entries one at a time from the input
   source.
2. **Generalizability judgment** (apply the global CLAUDE.md auto-memory operating criteria
   as-is; do not invent new criteria):
   - Exclude: code patterns / architecture / file paths (discoverable by reading the current
     code), git history, the debugging resolution steps themselves (a commit message
     suffices), content already covered in CLAUDE.md, transient state of an in-progress task,
     mission-local circumstances that apply only to this one mission.
   - Include: general facts / corrections / rationale about this project, this human, and
     these tools that should change behavior in future sessions (not limited to `swarm-loop`
     -- ordinary conversation too).
   - When in doubt, use the test: "would the same mistake / same rework recur next time
     without this memory?"
3. **Four types** (use the existing `~/.claude/memory/` types as-is; do not invent new
   categories): `user` / `feedback` / `project` / `reference`. Follow each type's existing
   operating rules (documented in the global CLAUDE.md) for the classification criteria.
4. **Duplicate check (deterministic, mandatory)** (prefer extending existing memory over
   proliferating new entries):

   ```bash
   ~/.claude/skills/swarm-memory-sync/scripts/memory-guard.sh <topic-keyword> [<topic-keyword> ...]
   ```

   Pass keywords representing the topic; this searches local Claude auto-memory
   (`~/.claude/projects/*/memory/*.md`) and Hermes memory (`~/.hermes/memories/*.md`) and
   prints structured JSON results (`{"results": [...], "backend": "local-memory"}`) on success.
   (`supermemory.sh` and `--ingest`/`--status` were retired in M1.) This is the deterministic
   groundwork so that the "no duplicate" judgment is not left to the LLM's memory / subjective
   impression alone -- do not ignore the output and write a new entry regardless.
   - **An empty `results` array is a valid response, NOT proof of an exhaustive duplicate
     search.** It only means this particular query matched nothing in the searched local stores;
     it is not a guarantee that no related memory exists anywhere. Treat it as weak evidence, not
     as a green light on its own -- still consider whether related phrasing/keywords might
     surface a match.
   - **A failed check (non-zero exit, no stdout) must block the write.** Do not proceed to
     write on a guard failure, and do not treat a failure as equivalent to "no duplicate found."
   - If a plausible existing match is found, prefer folding the new content into that existing
     topic file rather than writing a near-duplicate entry.

5. **Write**:
   - Write the candidate memory directly to the appropriate native persistent memory store
     (`~/.claude/projects/<project>/memory/` for Claude auto-memory, `~/.hermes/memories/*.md` for
     Hermes, or `~/.omp/agent/memory/` for OMP), preserving Markdown structure and metadata
     frontmatter (`name` / `description` / `type`) where applicable.
   - Do not use retired `--ingest` or `--status` flags on `memory-guard.sh` (they exit 1 since
     `supermemory` was removed in M1).
   - Corrections to previously recorded knowledge are **immutable and append-only**: write a
     new, clearly dated entry describing the correction (e.g. a note prefixed with today's
     date explaining what changed and why) rather than mutating or deleting prior content.
     Continuously rewriting the same free-form text in place risks drifting the recorded
     knowledge away from ground truth over successive edits (arXiv:2605.12978); append-only
     dated corrections avoid this drift by construction, since nothing is overwritten.
6. **Completion report** -- report how many entries were extracted, how many were written,
   and how many were rejected as
   "not generalizable." Include 1-2 example rejection reasons (for transparency of the
   judgment criteria, so a human can verify them directly in place of the "mechanization" step
   of the trajectory-log three-stage learning model).

## Retroactive processing (migrating an entire existing trajectory log)

On explicit human invocation, read the entire target trajectory log and apply the above
procedure entry by entry. If `memory-guard.sh` already surfaces similar existing content,
prefer folding/updating rather than creating a near-duplicate. Because this can involve a large
number of entries, present the "list of memories to write in this pass" in conversation before
writing (for visibility, not to request approval -- the procedure itself completes without
human approval).

## Handling unresolved status / missing results

If `memory-guard.sh` fails outright, treat the duplicate check as **unresolved** and report it
as such -- do not claim success or fail open into an unchecked write.

## Handoff Contract

形式・規則・stats 記録: `~/.claude/skills/_swarm-common/load.sh handoff`（HANDOFF.md、正典）。`from: swarm-memory-sync`。
完了条件（`status: done` の定義）: 蒸留した知見の書き込み(memory-guard.sh 経由)と未解決分の明示が済んだ

## Prohibitions

- Changing SKILL.md / hooks / SWARM.md themselves (boundary conditions are in the frontmatter
  description)
- Recording non-generalizable content (judgment criteria follow the global CLAUDE.md-based
  criteria in step 2 -- this exists to prevent memory bloat)
- Writing without going through `memory-guard.sh` (do not skip the mandatory deterministic
  duplicate check that exists to prevent creating new entries that duplicate existing memory)
- Recording things discoverable by reading the code, or traceable via git history
- Transcribing the raw trial-and-error logs of the Haiku exploration swarm / Maker / Checker
  verbatim (only structured reports / final learnings are in scope)
- `allowed-tools`'s `Edit`/`Write` are not mechanically scoped to writes under any particular
  directory (there is no hook-level enforcement here comparable to `swarm-meta`'s
  `harness-lint.sh` WRITE_SCOPE). Limiting writes to native persistent memory directories
  after running `memory-guard.sh` is a procedural constraint
  defined by this document, not a runtime-enforced one -- staying within it is the
  responsibility of the executor (Maker/human).

## Provenance note

An earlier draft of this content was written via a Bash-based bypass of the Tier B
write-scope hook rather than the sanctioned Edit path. The version actually committed here
was independently re-reviewed and re-applied through the sanctioned write-scope-grant path
instead. See git history for this file (commits around `e56cb46a`/`c9495873` in the
supermemory-migration mission) for the full incident record and review detail, not this
comment -- a mission's `@fix_plan.md` is an ephemeral, non-committed scratch file and is not
a durable reference to rely on once that mission's worktree is gone.
