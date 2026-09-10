# SKILL.state — Explicit Execution State for Pi Skills

Authoring reference for the SKILL.state runtime (extension `skill-state.ts`,
core `lib/skill-state-core.ts`). Based on **SKILL.state: Scalable Long-Horizon
Agent Skills** (arXiv:2608.26263v3, Badhe et al., Google, 2026).

## Why

Conventional agent runtimes append every observation, action, and reasoning
trace to an ever-growing conversation, giving `O(T²)` cumulative tokens and
"context-poisoning" over long horizons (obsolete facts overpower fresh
observations). SKILL.state replaces that append-only history with an explicit,
mutable, schema-validated **execution state `Σ`**. At each step the model
conditions only on

```
A_t = (P, Σ_t, O_t)
```

the immutable procedural specification `P`, the current structured state `Σ_t`,
and the latest observation `O_t`. Intermediate reasoning `R_t` is discarded after
a validated state transition, so the per-turn prompt footprint is bounded w.r.t.
the **number of turns** (`O(1)` in turn count) rather than growing with the
transcript. Caveat: this bounds footprint against conversation length, not against
Σ's own semantic size — a `replace`-typed schema stays truly `O(1)`, but
`append`/`union` list fields grow with the items they retain, so the author must
bound them (see Limitations). Cumulative tokens then grow ~`O(T)` (vs `O(T²)` for
history-appending runtimes) as long as Σ is kept bounded.

Pi's base agent loop is provided by `@earendil-works/pi-coding-agent` and cannot
be replaced, so SKILL.state is layered as an **extension** a skill uses for its own
execution state — not a wholesale runtime rewrite. Declaring a schema and emitting
`ΔΣ` is a choice the skill/model makes (the tools are always available); once any
domain has state, the per-turn Σ surfacing (below) is **on by default**.

## Tools

| Tool                  | Purpose                                                                                                  |
| --------------------- | ------------------------------------------------------------------------------------------------------- |
| `skill_state_declare` | Declare a domain's state schema once (paper §3.1). `fields` = JSON `{name: {type, listMerge?}}`.         |
| `skill_state_update`  | Apply a `ΔΣ` patch (`Σ ⊕ ΔΣ`). `patch` = JSON object; a `null` value deletes a key. `reasoning` is discarded. |
| `skill_state_get`     | Read the current `Σ` (the sufficient statistic for the next step).                                       |

Slash command `/state [list|show <domain>|clear [domain]|autocontext [on|off|status]]`
inspects/manages state and toggles the per-turn auto-context.

**Auto-context (default ON).** A `before_agent_start` hook surfaces a bounded `Σ`
digest each turn so Σ is the default thing the model sees. It is injected via the
event result's `systemPrompt` — which the base loop **rebuilds every turn** — so Σ is
refreshed in place and does NOT accumulate O(t) copies in the transcript (it augments
the assembled system prompt; the immutable base loop still owns the transcript, so
history is not removed). The digest is capped (`STATE_DIGEST_MAX_CHARS`, whole
per-domain blocks dropped past budget) and is a no-op with no declared state and in
isolated subagent processes (`PI_SUBAGENT=1`). Toggle per session with `/state
autocontext off` (the toggle is in-memory, not persisted across sessions).

## Schema

A schema is authored **once per domain** (reused across all tasks in that
domain). Fields:

```json
{
  "discovered_flags":  { "type": "list",   "listMerge": "union" },
  "tested_hypotheses": { "type": "list",   "listMerge": "append" },
  "active_files":      { "type": "list",   "listMerge": "replace" },
  "working_dir":       { "type": "string" },
  "cmd_summary":       { "type": "map" },
  "attempt":           { "type": "number" }
}
```

Field `type`: `string` | `number` | `boolean` | `list` | `map` | `any`.
`listMerge` (list fields only): `replace` (default) | `append` | `union` (dedup).

## The `⊕` merge operator (Σ ⊕ ΔΣ)

- `value === null` → **delete** the key (null-deletion semantics).
- both existing and new are maps → **deep-merge** (sibling keys preserved).
- list field with `append`/`union` → combine per strategy.
- otherwise → replace.

The merge is **additive**: a patch that touches one key never drops the others.
This is what prevents the paper's dominant open-weight failure mode (§5.7: 68%
"premature state overwrite/deletion") — the model emits only `ΔΣ`, so it cannot
accidentally clobber untouched state.

## Runtime authority & rollback

Schema ownership and validation live in the **deterministic runtime**, not the
model. An invalid patch — malformed JSON (§5.7 12%), wrong type (§5.7 20%), a
forbidden key (`__proto__`/`constructor`/`prototype`), an over-deep value, or an
unknown key **with a non-null value** — is **rejected and rolled back** (Σ
unchanged), and the tool returns an error so the model can retry. (A `null` value
is always accepted as a deletion, even for an unknown/orphan key, so a narrowed
schema can still prune leftover state.) A malformed model output therefore can
never corrupt the persistent `Σ`.

The percentages above are the open-weight (Gemma-4-31B) error-mode shares reported
in the paper's §5.7 error taxonomy, quoted directly (not a derived apportionment).

## Multi-agent (improvement beyond the paper, §7 #4)

The paper leaves concurrent multi-agent writes as future work: a shared `Σ` is a
natural coordination substrate (instead of exchanging `O(n²)` transcripts) but
needs deterministic conflict-resolution in `⊕`. `SharedExecutionState`
(`lib/subagent-mesh-core.ts`) supplies it via `mergeConcurrentPatches`:

- scalar / map / list-`replace` key → **last-writer-wins** by `(ts, agentId)`.
- list `union`/`append` key → combined across all agents.
- contended keys are reported so the coordinator can surface genuine conflicts.

Merging is **order-independent**: every peer converges on the same `Σ` regardless
of message-arrival order.

`SharedExecutionState` is an **opt-in primitive**, not an active default: the mesh
continues to derive state via `CoordinatorEngine.getActiveState` (folding the
message log), and no mesh tool auto-instantiates it yet. It is provided so mesh
coordination code can adopt a shared, schema-validated `Σ` when that is preferable
to re-deriving state from transcripts.

## Declaring a schema in a skill (`## SKILL.state Schema`)

Long-horizon procedural skills declare their execution-state schema in a
`## SKILL.state Schema` section (a `domain` + a fenced JSON `fields` block). This
is the authoring convention used by the major swarm-* skills. Under the Pi harness
SKILL.state is their **default working pattern**: `skill_state_declare` the schema
at the start of a run, then emit `ΔΣ` via `skill_state_update` after each phase
instead of accumulating history. The `skill-state` extension also **auto-injects a
bounded Σ digest into context every turn by default** (a `before_agent_start`
hook; toggle with `/state autocontext off`), so Σ — not the full transcript — is
the sufficient statistic the model reasons over. This is layered on Pi's immutable
base loop, which still owns the transcript, so the digest **augments** context
with Σ rather than replacing history. On harnesses without the `skill_state_*`
tools the section is inert documentation, and any adopted Σ stays subordinate to
each skill's existing source-of-truth state files (e.g. `@fix_plan.md`,
`graph-status.sh`).

## Limitations (paper §7)

Faithful use assumes `Σ` is a **sufficient statistic** for future execution. This
fails when (1) the schema must be discovered dynamically, (2) an earlier
observation's relevance is recognized only later (and was never committed to Σ),
or (3) the task objective is the history itself (auditing/provenance). For those,
keep history or widen the schema; do not discard reasoning blindly.

Two operational caveats specific to this Pi implementation:
- **Bounding growing fields**: `append`/`union` list fields are unbounded by
  design; a long horizon can grow `Σ` (and thus the per-turn footprint) without
  limit. The author must prune them (emit `null` to delete, or periodically
  replace with a compacted list). `skill_state_update` surfaces an advisory when
  the serialized `Σ` exceeds a soft threshold, and `/state show` reports the
  footprint — but nothing enforces a hard cap.
- **Single-writer store**: the on-disk store is a per-cwd JSON document written
  atomically (temp + rename), so a reader never sees a torn file. It has no
  cross-process lock, however, so two processes doing a concurrent
  read-modify-write of the SAME cwd can lose an update (last writer wins). The
  store assumes a single writer per cwd; the multi-agent path is
  `SharedExecutionState` (in-process deterministic merge), not the shared file.
