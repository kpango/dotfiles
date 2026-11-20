/**
 * SKILL.state Runtime Core (arXiv:2608.26263, Badhe et al. 2026).
 *
 * Replaces append-only conversational history with an explicit, mutable, schema-
 * validated execution state Σ. At execution step t the model conditions only on
 * (P, Σ_t, O_t): the immutable procedural specification, the structured state,
 * and the latest observation. Intermediate reasoning R_t is discarded after a
 * validated state transition, giving a bounded prompt footprint per turn that is
 * independent of the number of turns t (paper §3.3), instead of the O(t) growth
 * of history-appending runtimes. (Footprint is bounded w.r.t. turn COUNT; the
 * semantic size of Σ still depends on how much the schema retains — see
 * `stateFootprintChars` and the "bounding growing fields" note in SKILL_STATE.md.)
 *
 * This module is the DETERMINISTIC runtime authority: schema ownership and patch
 * validation live here, not in the model, so a malformed ΔΣ can never corrupt the
 * persistent Σ — an invalid patch triggers a rollback (Σ unchanged) so the caller
 * can retry (paper §7). The runtime-owned merge/validation targets the three
 * open-weight failure modes reported in the paper §5.7 (Premature State Overwrite
 * / Deletion 68%, Schema Comprehension / Type Coercion 20%, JSON Syntax 12%):
 *   - additive ⊕ merge with EXPLICIT null-deletion (the model sends only ΔΣ; a
 *     patch that touches one key never drops untouched keys).
 *   - runtime type validation (rejects wrong types and non-finite numbers).
 *   - the caller parses JSON; a syntax error / rejected patch rolls back.
 * Forbidden keys (`__proto__`, `constructor`, `prototype`) are rejected outright
 * so a patch can never reach a prototype-pollution assignment (CWE-1321).
 *
 * Improvement beyond the paper (§7 limitation #4, multi-agent concurrent writes):
 * `mergeConcurrentPatches` gives ⊕ deterministic conflict-resolution semantics so
 * a shared Σ can serve as a multi-agent coordination substrate instead of
 * exchanging quadratic conversational transcripts.
 *
 * Pure logic only — no ExtensionAPI, no I/O — so it is fully unit-testable.
 */

// Canonical/stable JSON serialization is consolidated in ./canonical-json (shared
// with session-journal's idempotency-key hashing). For skill-state's JSON-safe,
// acyclic, depth-pre-guarded values it produces output identical to the former
// private stableStringify, and additionally caps depth as defense-in-depth.
import { canonicalizeJson as stableStringify } from "./canonical-json";

// ---------------------------------------------------------------------------
// State value model
// ---------------------------------------------------------------------------

export type StateScalar = string | number | boolean | null;
export type StateValue = StateScalar | StateValue[] | { [key: string]: StateValue };
/** The structured execution state Σ: a flat-or-nested JSON object. */
export type ExecutionState = { [key: string]: StateValue };

/**
 * A state patch ΔΣ: a dictionary of key mutations. A `null` value DELETES the
 * key (null-deletion semantics of the ⊕ operator, paper §3.2). Every other value
 * sets/replaces (scalars, lists) or deep-merges (maps) the key.
 */
export type StatePatch = { [key: string]: StateValue };

// ---------------------------------------------------------------------------
// Schema (authored once per domain, paper §3.1)
// ---------------------------------------------------------------------------

export type FieldType = "string" | "number" | "boolean" | "list" | "map" | "any";
export const FIELD_TYPES: readonly FieldType[] = ["string", "number", "boolean", "list", "map", "any"];

/** How a list-typed field resolves when a patch (or concurrent patches) write it. */
export type ListMerge = "replace" | "append" | "union";
export const LIST_MERGES: readonly ListMerge[] = ["replace", "append", "union"];

export interface SchemaField {
  type: FieldType;
  /** For `list` fields: how writes combine. Default "replace" (paper's ⊕ replaces). */
  listMerge?: ListMerge;
  /** Optional human description carried for documentation/introspection. */
  description?: string;
}

export interface SkillStateSchema {
  /** Domain identifier; a schema is authored once per domain, reused per task. */
  domain: string;
  fields: Record<string, SchemaField>;
  /**
   * When true, any (non-forbidden) key is accepted as type "any". Used as the
   * safety net for an undeclared domain. Persisted as a plain boolean so the
   * permissive behaviour survives a JSON store round-trip (no live Proxy that
   * would serialize to an empty `fields` and lock the domain out).
   */
  permissive?: boolean;
}

export interface ValidationResult {
  valid: boolean;
  errors: string[];
}

export interface ApplyResult {
  ok: boolean;
  /** On success: Σ ⊕ ΔΣ. On failure: the ORIGINAL Σ (rollback), unchanged. */
  state: ExecutionState;
  errors: string[];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Keys that must never be written — they alias the object prototype (CWE-1321). */
export const FORBIDDEN_KEYS: readonly string[] = ["__proto__", "constructor", "prototype"];
function isForbiddenKey(k: string): boolean {
  return k === "__proto__" || k === "constructor" || k === "prototype";
}

/** True only for a *plain* object (prototype is Object.prototype or null) — not a
 * Date/RegExp/Map/class instance, which would otherwise deep-merge to nothing. */
function isPlainObject(v: unknown): v is { [key: string]: StateValue } {
  if (typeof v !== "object" || v === null || Array.isArray(v)) return false;
  const proto = Object.getPrototypeOf(v);
  return proto === Object.prototype || proto === null;
}

function jsTypeToFieldType(v: StateValue): FieldType | "null" {
  if (v === null) return "null";
  if (Array.isArray(v)) return "list";
  if (typeof v === "object") return "map";
  if (typeof v === "string") return "string";
  if (typeof v === "number") return "number";
  if (typeof v === "boolean") return "boolean";
  return "null";
}

/** Deep structural clone via JSON round-trip (state is JSON by construction). */
function cloneState<T>(v: T): T {
  return JSON.parse(JSON.stringify(v)) as T;
}

/**
 * Maximum nesting depth allowed for a patch value. Deeply nested JSON parses
 * fine but the runtime's own recursion (`cloneState` via JSON.stringify,
 * `mergeState`) blows the native stack around ~3k-5k levels, throwing an uncaught
 * RangeError. (`stableStringify` is now `canonicalizeJson`, which is itself
 * depth-capped at 256, but the other recursive paths are not.) Rejecting
 * over-deep values in `validatePatch` turns that crash into a normal,
 * deterministic rollback (well below the crash threshold). Legitimate execution
 * state is shallow; 64 is generous.
 */
export const MAX_STATE_DEPTH = 64;

/** True if `v` nests deeper than `max` levels. Iterative (no recursion), so it
 * cannot itself overflow the stack while measuring a hostile input. */
function exceedsMaxDepth(v: StateValue, max: number): boolean {
  const stack: { value: StateValue; depth: number }[] = [{ value: v, depth: 0 }];
  while (stack.length > 0) {
    const { value, depth } = stack.pop()!;
    if (value === null || typeof value !== "object") continue;
    if (depth >= max) return true;
    if (Array.isArray(value)) {
      for (const el of value) stack.push({ value: el, depth: depth + 1 });
    } else {
      for (const k of Object.keys(value)) stack.push({ value: (value as Record<string, StateValue>)[k], depth: depth + 1 });
    }
  }
  return false;
}

/** True if `v` contains a forbidden key (`__proto__`/`constructor`/`prototype`)
 * at ANY nesting level. Iterative + depth-capped so a hostile input can neither
 * overflow the stack nor run unbounded. validatePatch only inspects top-level
 * keys for type checking; this closes the nested-key gap so a patch can never
 * carry an attacker-chosen prototype-aliasing key into persisted Σ (even as inert
 * data). */
function containsForbiddenKeyDeep(v: StateValue, max = MAX_STATE_DEPTH): boolean {
  const stack: { value: StateValue; depth: number }[] = [{ value: v, depth: 0 }];
  while (stack.length > 0) {
    const { value, depth } = stack.pop()!;
    if (value === null || typeof value !== "object") continue;
    if (depth >= max) continue; // depth is enforced separately by exceedsMaxDepth
    if (Array.isArray(value)) {
      for (const el of value) stack.push({ value: el, depth: depth + 1 });
    } else {
      for (const k of Object.keys(value)) {
        if (isForbiddenKey(k)) return true;
        stack.push({ value: (value as Record<string, StateValue>)[k], depth: depth + 1 });
      }
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Schema-declaration validation (used by the declare tool)
// ---------------------------------------------------------------------------

/**
 * Validate a raw `fields` declaration so a typo'd schema (e.g. type "strnig")
 * is rejected at declare-time instead of silently rejecting every later patch
 * with a confusing "expected undefined" error.
 */
export function validateSchemaFields(fields: unknown): ValidationResult {
  const errors: string[] = [];
  if (!isPlainObject(fields)) {
    return { valid: false, errors: ["schema fields must be a JSON object"] };
  }
  // Depth-cap the whole declaration so a pathologically nested field descriptor
  // (e.g. a huge `description`) cannot crash JSON.stringify at save time — the
  // same crash class the patch path guards via exceedsMaxDepth.
  if (exceedsMaxDepth(fields as StateValue, MAX_STATE_DEPTH)) {
    return { valid: false, errors: [`schema nests deeper than the ${MAX_STATE_DEPTH}-level limit`] };
  }
  // Symmetric with validatePatch: reject a forbidden key nested anywhere in a
  // field descriptor (e.g. a `description` value), so the declare path can never
  // persist an attacker-chosen prototype-aliasing key either.
  if (containsForbiddenKeyDeep(fields as StateValue)) {
    return { valid: false, errors: ["schema contains a forbidden nested key (__proto__/constructor/prototype)"] };
  }
  for (const key of Object.keys(fields)) {
    if (isForbiddenKey(key)) {
      errors.push(`field name '${key}' is forbidden`);
      continue;
    }
    const f = (fields as Record<string, unknown>)[key];
    if (!isPlainObject(f)) {
      errors.push(`field '${key}' must be an object with a 'type'`);
      continue;
    }
    const type = (f as any).type;
    if (!FIELD_TYPES.includes(type)) {
      errors.push(`field '${key}' has invalid type ${JSON.stringify(type)} (allowed: ${FIELD_TYPES.join("|")})`);
    }
    const lm = (f as any).listMerge;
    if (lm !== undefined && !LIST_MERGES.includes(lm)) {
      errors.push(`field '${key}' has invalid listMerge ${JSON.stringify(lm)} (allowed: ${LIST_MERGES.join("|")})`);
    }
  }
  return { valid: errors.length === 0, errors };
}

// ---------------------------------------------------------------------------
// Validation (runtime-owned; paper §7 — model cannot corrupt persistent Σ)
// ---------------------------------------------------------------------------

/**
 * Validate a patch ΔΣ against a schema. Strict on purpose: forbidden keys are
 * always rejected; a `null` (deletion) is always accepted for ANY key (so an
 * orphan key left by a narrowed schema can still be pruned); unknown keys and
 * type mismatches are otherwise rejected so structured-output errors surface as
 * a rollback rather than silently corrupting Σ. Number fields require a finite
 * number (NaN/Infinity would JSON-serialize to null).
 */
export function validatePatch(schema: SkillStateSchema, patch: StatePatch): ValidationResult {
  const errors: string[] = [];
  if (!isPlainObject(patch)) {
    return { valid: false, errors: ["patch is not a JSON object"] };
  }
  for (const key of Object.keys(patch)) {
    if (isForbiddenKey(key)) {
      errors.push(`key '${key}' is forbidden (prototype pollution)`);
      continue;
    }
    const value = patch[key];
    if (value === null) continue; // deletion is always valid, even for an orphan/unknown key
    // Reject pathologically deep values BEFORE they reach the runtime's own
    // recursion (cloneState/mergeState), which would otherwise
    // throw an uncaught RangeError instead of a clean rollback. Checked for all
    // fields (including permissive/any) since every value is cloned/merged.
    if (exceedsMaxDepth(value, MAX_STATE_DEPTH)) {
      errors.push(`key '${key}' nests deeper than the ${MAX_STATE_DEPTH}-level limit`);
      continue;
    }
    // Reject a forbidden key at ANY nesting depth (not just top level), so an
    // attacker-chosen __proto__/constructor/prototype can never be persisted into
    // Σ as inert data (honors the module's no-prototype-pollution invariant).
    if (containsForbiddenKeyDeep(value)) {
      errors.push(`key '${key}' contains a forbidden nested key (__proto__/constructor/prototype)`);
      continue;
    }
    if (schema.permissive) continue; // permissive domain accepts any non-forbidden key
    const field = schema.fields[key];
    if (!field) {
      errors.push(`unknown key '${key}' not in schema '${schema.domain}'`);
      continue;
    }
    if (field.type === "any") continue; // explicit any accepts any JSON value
    const actual = jsTypeToFieldType(value);
    if (actual !== field.type) {
      errors.push(`key '${key}' expected ${field.type} but got ${actual}`);
      continue;
    }
    if (field.type === "number" && !Number.isFinite(value as number)) {
      errors.push(`key '${key}' number must be finite (got ${String(value)})`);
    }
  }
  return { valid: errors.length === 0, errors };
}

// ---------------------------------------------------------------------------
// ⊕ : Σ ⊕ ΔΣ  (dictionary merge with null-deletion; paper §3.2 eq.4)
// ---------------------------------------------------------------------------

const PERMISSIVE_SUBSCHEMA: SkillStateSchema = { domain: "(nested)", fields: {}, permissive: true };

/** Resolve the field descriptor for a key, honouring a permissive schema. */
function fieldFor(schema: SkillStateSchema, key: string): SchemaField | undefined {
  if (schema.permissive) return { type: "any" };
  return schema.fields[key];
}

/**
 * Apply a validated patch to a state, returning a NEW state (never mutates
 * inputs). Semantics:
 *   - forbidden key                        -> skipped (defensive; validate rejects first)
 *   - value === null                       -> delete the key
 *   - both existing & new are plain maps    -> recursive deep merge
 *   - list field with listMerge append/union -> combine per strategy
 *   - otherwise (scalar / list replace / type change) -> replace
 * Caller must have validated `patch` first (see `applyPatch`).
 */
export function mergeState(
  schema: SkillStateSchema,
  sigma: ExecutionState,
  patch: StatePatch,
): ExecutionState {
  const next = cloneState(sigma);
  for (const key of Object.keys(patch)) {
    if (isForbiddenKey(key)) continue; // never write a prototype-aliasing key
    const value = patch[key];
    if (value === null) {
      delete next[key];
      continue;
    }
    const field = fieldFor(schema, key);
    const existing = next[key];
    if ((field?.type === "map" || field?.type === "any") && isPlainObject(existing) && isPlainObject(value)) {
      // Deep-merge maps so a partial map patch does not drop sibling keys.
      next[key] = mergeState(PERMISSIVE_SUBSCHEMA, existing, value as StatePatch);
    } else if (
      field?.type === "list" &&
      Array.isArray(existing) &&
      Array.isArray(value) &&
      (field.listMerge === "append" || field.listMerge === "union")
    ) {
      next[key] = combineLists(existing, value, field.listMerge);
    } else {
      next[key] = cloneState(value);
    }
  }
  return next;
}

function combineLists(a: StateValue[], b: StateValue[], strategy: ListMerge): StateValue[] {
  if (strategy === "append") return [...a, ...b].map((v) => cloneState(v));
  if (strategy === "replace") return b.map((v) => cloneState(v));
  // union: dedup by stable value identity, preserving first-seen order.
  const seen = new Set<string>();
  const out: StateValue[] = [];
  for (const v of [...a, ...b]) {
    const id = stableStringify(v);
    if (!seen.has(id)) {
      seen.add(id);
      out.push(cloneState(v));
    }
  }
  return out;
}

/**
 * Validate then merge. On invalid patch the ORIGINAL Σ is returned unchanged
 * (rollback), so the caller can retry with a corrected patch — the runtime's
 * rollback-retry contract (paper §7). This is the single entry point callers use.
 */
export function applyPatch(
  schema: SkillStateSchema,
  sigma: ExecutionState,
  patch: StatePatch,
): ApplyResult {
  const v = validatePatch(schema, patch);
  if (!v.valid) {
    return { ok: false, state: sigma, errors: v.errors };
  }
  return { ok: true, state: mergeState(schema, sigma, patch), errors: [] };
}

// ---------------------------------------------------------------------------
// Multi-agent deterministic conflict resolution (improvement, paper §7 #4)
// ---------------------------------------------------------------------------

export interface ConcurrentPatch {
  agentId: string;
  /** Logical/wall-clock ordering timestamp; ties broken by agentId lexically. */
  ts: number;
  patch: StatePatch;
}

export interface ConcurrentMergeResult {
  merged: StatePatch;
  /** Keys written by more than one agent with differing values. */
  conflicts: string[];
}

/**
 * Merge concurrent patches from multiple agents into a single deterministic
 * patch, giving the ⊕ operator the conflict-resolution semantics the paper
 * leaves as future work (§7 #4). Writers are ordered by (ts asc, agentId asc),
 * then folded per key:
 *   - scalar / map / list-replace -> last write wins.
 *   - list union/append -> fold in order; a `null` write RESETS the accumulator
 *     to a deletion, and later non-null writes rebuild from empty (temporal
 *     delete semantics), so a mid-sequence delete is honoured.
 * A key is a conflict iff >1 agent writes it with differing stable values.
 * Order-independent: the same set of patches always yields the same result.
 * Feed the result through `applyPatch` to update Σ.
 */
export function mergeConcurrentPatches(
  schema: SkillStateSchema,
  patches: ConcurrentPatch[],
): ConcurrentMergeResult {
  const ordered = [...patches].sort(
    (a, b) => (a.ts - b.ts) || (a.agentId < b.agentId ? -1 : a.agentId > b.agentId ? 1 : 0),
  );

  const byKey = new Map<string, { agentId: string; ts: number; value: StateValue }[]>();
  for (const p of ordered) {
    for (const key of Object.keys(p.patch)) {
      if (isForbiddenKey(key)) continue; // validate would reject; keep merged clean
      if (!byKey.has(key)) byKey.set(key, []);
      byKey.get(key)!.push({ agentId: p.agentId, ts: p.ts, value: p.patch[key] });
    }
  }

  const merged: StatePatch = {};
  const conflicts: string[] = [];
  for (const key of [...byKey.keys()].sort()) {
    const writes = byKey.get(key)!;

    // Guard BEFORE any recursive stableStringify/combineLists runs: if any write's
    // value is over-deep, surface that raw value so the downstream validatePatch
    // rejects it (depth error -> whole patch rolls back) instead of blowing the
    // native stack inside cloneState/mergeState (which are not depth-capped;
    // stableStringify=canonicalizeJson is, but the fold clones/merges too).
    const deep = writes.find((w) => w.value !== null && exceedsMaxDepth(w.value, MAX_STATE_DEPTH));
    if (deep) {
      merged[key] = deep.value;
      // Only a genuine multi-agent contention is a "conflict" (per this type's
      // contract). We avoid comparing an over-deep value by string, so use
      // writer count as the multi-agent signal; a lone over-deep writer is not a
      // conflict (it will still roll the whole patch back downstream).
      if (writes.length > 1) conflicts.push(key);
      continue;
    }

    const distinct = new Set(writes.map((w) => stableStringify(w.value)));
    if (distinct.size > 1) conflicts.push(key);

    const field = fieldFor(schema, key);
    if (field?.type === "list" && (field.listMerge === "union" || field.listMerge === "append")) {
      // Temporal fold over the deterministic write order. A `null` write RESETS to
      // a deletion and later arrays rebuild from empty (temporal delete). If ANY
      // write to this key is a non-array, non-null value (type-invalid for a list
      // field), that raw value is surfaced as the merged result so the downstream
      // applyPatch/validatePatch rejects the WHOLE patch (rollback) — it is never
      // coerced to null and never silently dropped, so a single type-invalid
      // concurrent write (even sandwiched between valid ones) can no longer
      // silently delete or lose another agent's valid union/append contributions.
      let cur: StateValue = null;
      let invalid: StateValue | undefined = undefined;
      for (const w of writes) {
        if (w.value === null) {
          cur = null;
        } else if (Array.isArray(w.value)) {
          const base = Array.isArray(cur) ? (cur as StateValue[]) : [];
          cur = combineLists(base, w.value, field.listMerge);
        } else {
          invalid = w.value; // remember any type-invalid write, regardless of position
        }
      }
      merged[key] = invalid !== undefined ? invalid : cur;
    } else {
      merged[key] = writes[writes.length - 1].value; // last-writer-wins
    }
  }
  return { merged, conflicts };
}

// ---------------------------------------------------------------------------
// Footprint (the bounded per-turn invariant, paper §3.3)
// ---------------------------------------------------------------------------

/** Serialized character size of Σ — the quantity SKILL.state keeps bounded w.r.t.
 * the number of turns. Advisory only (nothing enforces a cap); authors bound
 * append/union fields themselves (see SKILL_STATE.md limitations). */
export function stateFootprintChars(sigma: ExecutionState): number {
  return JSON.stringify(sigma).length;
}

/**
 * Build the SKILL.state prompt inputs A_t = (P, Σ_t, O_t). Intermediate reasoning
 * is intentionally absent — this is the whole point of the architecture. Returned
 * as a compact string block suitable for injection before model generation.
 */
export function formatExecutionContext(
  spec: string,
  sigma: ExecutionState,
  observation: string,
): string {
  return [
    "## SKILL.state Execution Context",
    "### P (immutable specification)",
    spec.trim(),
    "### Σ (current execution state)",
    "```json",
    JSON.stringify(sigma, null, 2),
    "```",
    "### O (latest observation)",
    observation.trim(),
  ].join("\n");
}

/**
 * Permissive schema for an undeclared domain: accepts any non-forbidden key as
 * type "any". Represented with a plain `permissive` flag (no Proxy) so it
 * survives a JSON store round-trip. Faithful callers should declare an explicit
 * schema (paper §3.1) — this is a safety net, not the norm.
 */
export function permissiveSchema(domain: string): SkillStateSchema {
  return { domain, fields: {}, permissive: true };
}

/** Default char budget for the per-turn Σ digest auto-injected into context. Kept
 * far below STATE_FOOTPRINT_ADVISORY_CHARS because this block is (re)injected on
 * every turn, so it must stay small even when Σ itself is large. */
export const STATE_DIGEST_MAX_CHARS = 8_192;

/** Cap on how many domains the per-turn digest will serialize. Bounds worst-case
 * per-turn CPU (the hook runs every turn, default-ON) so a session with a large
 * number of declared domains cannot make digest construction scale with domain
 * count — the rest are counted as omitted WITHOUT being serialized. */
export const MAX_DIGEST_DOMAINS = 32;

/**
 * Render a bounded, deterministic digest of the current execution state across
 * domains, for auto-injection into the prompt each turn. This makes Σ the DEFAULT
 * thing the model sees (paper §3.2: the model reasons over the current structured
 * state, not the full history) — layered additively on Pi's immutable base loop,
 * which still owns the transcript, so this augments context rather than replacing
 * it. Domains are sorted by name for determinism; empty/forbidden domains are
 * skipped; whole per-domain blocks are dropped (never split) once the char budget
 * is reached, with a trailing note of how many were omitted.
 */
export function formatStateDigest(
  entries: { domain: string; sigma: ExecutionState }[],
  maxChars: number = STATE_DIGEST_MAX_CHARS,
): string {
  const nonEmpty = entries
    .filter((e) => e.sigma && typeof e.sigma === "object" && Object.keys(e.sigma).length > 0)
    .sort((a, b) => (a.domain < b.domain ? -1 : a.domain > b.domain ? 1 : 0));
  if (nonEmpty.length === 0) return "";
  const header =
    "## SKILL.state — current execution state (Σ)\n" +
    "This is your durable structured state for the active skill(s). Treat it as the " +
    "sufficient statistic for the next step and update it via `skill_state_update` " +
    "instead of re-deriving from earlier turns.";
  // Reserve room for a possible trailing omission note so the WHOLE returned string
  // (header + blocks + note + join newlines) stays within maxChars — the note itself
  // is otherwise unbudgeted and would push the total past the cap.
  // maxChars is assumed >= header.length + NOTE_RESERVE (always true for the sole
  // production caller, which uses STATE_DIGEST_MAX_CHARS); smaller custom budgets
  // still return the header + a (truncated) note without throwing.
  const NOTE_RESERVE = 128;
  const blockBudget = maxChars - NOTE_RESERVE;
  const blocks: string[] = [header];
  let used = header.length;
  let omitted = 0;
  let processed = 0;
  for (const e of nonEmpty) {
    // Stop once the budget is effectively full or the per-turn domain cap is hit:
    // domains skipped HERE are omitted WITHOUT serializing. (A domain that passes
    // this guard but then overflows the per-block budget is still stringified once,
    // so the number of JSON.stringify calls is bounded by MAX_DIGEST_DOMAINS — a
    // constant independent of the total declared-domain count.)
    if (used >= blockBudget || processed >= MAX_DIGEST_DOMAINS) {
      omitted++;
      continue;
    }
    processed++;
    const block = `### Σ [${e.domain}]\n\`\`\`json\n${JSON.stringify(e.sigma, null, 2)}\n\`\`\``;
    // +1 accounts for the join newline; drop whole blocks (never split) past budget,
    // keeping NOTE_RESERVE chars free in case an omission note is later appended.
    if (used + block.length + 1 > blockBudget) {
      omitted++;
      continue;
    }
    blocks.push(block);
    used += block.length + 1;
  }
  if (omitted > 0) {
    const note = `_(+${omitted} more domain(s) omitted to bound context footprint; use \`/state show <domain>\`.)_`;
    // Guaranteed to fit: NOTE_RESERVE >= note.length + newline for realistic omitted
    // counts; a pathological count is truncated rather than overflowing the budget.
    blocks.push(note.length + 1 <= NOTE_RESERVE ? note : note.slice(0, NOTE_RESERVE - 2));
  }
  return blocks.join("\n");
}
