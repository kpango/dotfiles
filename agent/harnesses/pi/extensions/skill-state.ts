/**
 * SKILL.state Extension for Pi Coding Agent (arXiv:2608.26263).
 *
 * Exposes the explicit-execution-state runtime as tools + a /state command, plus a
 * default per-turn Σ auto-context injection (below).
 * A skill/agent declares a structured schema once per domain, then drives a
 * long-horizon procedure by emitting ΔΣ patches instead of accumulating history:
 * the runtime validates each patch, applies Σ ⊕ ΔΣ (null-deletion), persists Σ
 * atomically, and DISCARDS the model's reasoning — keeping the prompt footprint
 * bounded (O(1)) across the whole execution horizon.
 *
 * Faithful to the paper's runtime authority split: the deterministic runtime owns
 * schema + validation (lib/skill-state-core.ts), so a malformed patch (bad JSON,
 * wrong type, unknown key) can never corrupt persistent Σ — it rolls back and the
 * model retries. Pi's base agent loop (provided by @earendil-works/pi-coding-agent)
 * cannot be replaced, so SKILL.state is layered as an extension for a skill's own
 * execution state rather than a wholesale runtime rewrite.
 *
 * Default working pattern: a `before_agent_start` turn-hook surfaces a bounded Σ
 * digest each turn (toggle with `/state autocontext on|off`; per-session, not
 * persisted), so the model sees its durable structured state by default without
 * re-reading history. It is injected via the result's `systemPrompt` — which the
 * base loop rebuilds each turn — so Σ is refreshed in place and does NOT accumulate
 * across turns; it AUGMENTS the assembled system prompt (the immutable base loop
 * still owns the transcript, so history is not removed) and is a no-op until a
 * domain declares state and in isolated subagent processes (`PI_SUBAGENT=1`).
 *
 * "opt-in" vs "default": declaring a schema and emitting `ΔΣ` is a choice a skill/
 * model makes (the tools are always available); once any domain has state, the
 * per-turn Σ surfacing is ON by default.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as crypto from "node:crypto";
import type { ExtensionAPI, BeforeAgentStartEvent, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
  type SkillStateSchema,
  type ExecutionState,
  type StatePatch,
  type SchemaField,
  applyPatch,
  permissiveSchema,
  stateFootprintChars,
  validateSchemaFields,
  formatStateDigest,
} from "./lib/skill-state-core";
import { writeFileAtomic } from "./lib/fs-atomic";

/** Advisory soft threshold: Σ growing past this (chars) surfaces a warning in the
 * tool output so an unbounded append/union field is noticed (no rejection). */
const STATE_FOOTPRINT_ADVISORY_CHARS = 100_000;

/** Hard cap on the raw JSON string of a patch/schema argument, checked BEFORE
 * JSON.parse so a single huge (but shallow) payload cannot burn CPU/RAM parsing
 * or blow the event loop. Depth is bounded separately (MAX_STATE_DEPTH); this
 * bounds width/total size. Generous — legitimate ΔΣ/schemas are small. */
const MAX_ARG_JSON_CHARS = 262_144; // 256 KiB

/** Max domain-name length. Symmetric with MAX_ARG_JSON_CHARS: a domain is a store
 * key persisted verbatim, so an unbounded name is a size/DoS vector. Generous. */
const MAX_DOMAIN_CHARS = 256;

function isForbiddenDomain(domain: string): boolean {
  return (
    domain === "__proto__" ||
    domain === "constructor" ||
    domain === "prototype" ||
    domain === "" ||
    domain.length > MAX_DOMAIN_CHARS
  );
}

interface DomainEntry {
  schema: SkillStateSchema;
  state: ExecutionState;
}

type Store = Record<string, DomainEntry>;

function storePathForCwd(cwd: string): string {
  const base = path.join(os.homedir(), ".pi", "agent", "skill-state");
  const id = crypto.createHash("sha256").update(cwd).digest("hex").slice(0, 16);
  return path.join(base, `${id}.json`);
}

function loadStore(file: string): Store {
  // Null-prototype target so a `domain` like "__proto__"/"constructor" indexes an
  // own (absent) slot instead of walking Object.prototype — store[domain] then
  // returns undefined rather than a truthy prototype object, avoiding a crash in
  // read paths (defense in depth alongside the isForbiddenDomain guards).
  const empty = (): Store => Object.assign(Object.create(null), {}) as Store;
  try {
    if (!fs.existsSync(file)) return empty();
    const parsed = JSON.parse(fs.readFileSync(file, "utf-8"));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return empty();
    return Object.assign(Object.create(null), parsed) as Store;
  } catch {
    // Torn/corrupt store must not crash the session; start clean.
    return empty();
  }
}

function saveStore(file: string, store: Store): void {
  const dir = path.dirname(file);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  // Consolidated onto the shared atomic-write helper (sibling temp + rename) so
  // there is a single durable-write implementation across the Pi extensions.
  writeFileAtomic(file, JSON.stringify(store));
}

export default function (pi: ExtensionAPI) {
  // Auto-context is ON by default: SKILL.state becomes the DEFAULT working pattern
  // by surfacing a bounded Σ digest so the model sees its durable structured state
  // without re-reading history. Injected via the result's `systemPrompt` (which the
  // base loop REBUILDS every turn) rather than `message` (which is appended to the
  // persistent transcript) — so Σ is refreshed in place each turn and does NOT
  // accumulate O(t) copies in history. It augments the assembled system prompt (it
  // cannot remove the transcript, which the immutable base loop owns) and degrades
  // to a no-op when no domain has declared state.
  let autocontextEnabled = true;

  pi.on("before_agent_start", async (event: BeforeAgentStartEvent, ctx: ExtensionContext) => {
    if (!autocontextEnabled) return;
    // Skip in isolated subagent processes (mirrors auto-memory): they run with
    // --no-context-files and a tight token budget, so auto-injecting the parent's
    // Σ would defeat that isolation.
    if (process.env.PI_SUBAGENT === "1") return;
    const cwd = (ctx && typeof ctx.cwd === "string" && ctx.cwd) || process.cwd();
    let digest: string;
    try {
      const store = loadStore(storePathForCwd(cwd));
      const entries = Object.keys(store)
        .filter((d) => !isForbiddenDomain(d))
        .map((d) => ({ domain: d, sigma: store[d]?.state ?? {} }));
      digest = formatStateDigest(entries);
    } catch {
      return; // never let a store read/format failure block a turn
    }
    if (!digest) return;
    const base = typeof event?.systemPrompt === "string" ? event.systemPrompt : "";
    return { systemPrompt: base ? `${base}\n\n${digest}` : digest };
  });

  // Declare or replace a domain schema (authored once per domain, paper §3.1).
  pi.registerTool({
    name: "skill_state_declare",
    description:
      "SKILL.state: declare a structured execution-state schema for a domain (authored once per domain). Enables ΔΣ patches to be validated by the deterministic runtime. `fields` is a JSON object of {fieldName: {type: string|number|boolean|list|map|any, listMerge?: replace|append|union}}.",
    parameters: Type.Object({
      domain: Type.String({ description: "Domain identifier the schema is authored for." }),
      fields: Type.String({ description: "JSON object mapping field names to {type, listMerge?} descriptors." }),
    }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      return runDeclare(ctx.cwd, params.domain, params.fields);
    },
    handler: async (args, ctx) => runDeclare(ctx.cwd, args.domain, args.fields),
  });

  // Apply a ΔΣ patch. Reasoning is accepted for the model's own within-step
  // deduction but DISCARDED immediately (never persisted) — paper §3.2.
  pi.registerTool({
    name: "skill_state_update",
    description:
      "SKILL.state: apply a ΔΣ patch to a domain's execution state (Σ ⊕ ΔΣ, null value deletes a key). `patch` is a JSON object. Invalid JSON / unknown key / wrong type rolls back with no state change so you can retry. Any `reasoning` is used only within this step and is discarded (not persisted).",
    parameters: Type.Object({
      domain: Type.String({ description: "Target domain (must be declared, else a permissive schema is used)." }),
      patch: Type.String({ description: "JSON object of key mutations. A null value deletes that key." }),
      reasoning: Type.Optional(Type.String({ description: "Within-step reasoning; discarded after the transition." })),
    }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      return runUpdate(ctx.cwd, params.domain, params.patch);
    },
    handler: async (args, ctx) => runUpdate(ctx.cwd, args.domain, args.patch),
  });

  // Read the current Σ for a domain (the sufficient statistic for the next step).
  pi.registerTool({
    name: "skill_state_get",
    description: "SKILL.state: read the current execution state Σ for a domain as JSON.",
    parameters: Type.Object({
      domain: Type.String({ description: "Domain whose Σ to read." }),
    }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      return runGet(ctx.cwd, params.domain);
    },
    handler: async (args, ctx) => runGet(ctx.cwd, args.domain),
  });

  pi.registerCommand("state", {
    description:
      "Inspect SKILL.state execution state (/state [list|show <domain>|clear [domain]|autocontext [on|off|status]])",
    handler: async (args, ctx) => {
      const parts = (args || "").trim().split(/\s+/).filter(Boolean);
      const action = (parts[0] || "list").toLowerCase();

      if (action === "autocontext") {
        const sub = (parts[1] || "status").toLowerCase();
        if (sub === "on") autocontextEnabled = true;
        else if (sub === "off") autocontextEnabled = false;
        ctx.ui?.notify(
          `SKILL.state auto-context is ${autocontextEnabled ? "ON" : "OFF"} (Σ ${autocontextEnabled ? "is" : "is not"} injected each turn).`,
          "info",
        );
        return;
      }

      const file = storePathForCwd(ctx.cwd);
      const store = loadStore(file);

      if (action === "clear") {
        const domain = parts[1];
        if (domain && isForbiddenDomain(domain)) {
          ctx.ui?.notify(`SKILL.state: domain '${domain}' is forbidden.`, "warning");
          return;
        }
        if (domain) {
          delete store[domain];
        } else {
          for (const k of Object.keys(store)) delete store[k];
        }
        saveStore(file, store);
        ctx.ui?.notify(domain ? `SKILL.state: cleared domain '${domain}'.` : "SKILL.state: cleared all domains.", "info");
        return;
      }

      if (action === "show") {
        const domain = parts[1];
        if (domain && isForbiddenDomain(domain)) {
          ctx.ui?.notify(`SKILL.state: domain '${domain}' is forbidden.`, "warning");
          return;
        }
        const entry = domain ? store[domain] : undefined;
        if (!entry) {
          ctx.ui?.notify(`SKILL.state: no state for domain '${domain ?? "(none)"}'.`, "warning");
          return;
        }
        const shown = entry.state ?? {};
        ctx.ui?.notify(
          [
            `SKILL.state domain '${domain}' (Σ footprint: ${stateFootprintChars(shown)} chars)`,
            "```json",
            JSON.stringify(shown, null, 2),
            "```",
          ].join("\n"),
          "info",
        );
        return;
      }

      // list
      const domains = Object.keys(store);
      if (domains.length === 0) {
        ctx.ui?.notify("SKILL.state: no domains declared yet.", "info");
        return;
      }
      const lines = ["SKILL.state domains:"];
      for (const d of domains) {
        const e = store[d];
        const st = e?.state ?? {};
        lines.push(`• ${d}: ${Object.keys(st).length} keys, Σ footprint ${stateFootprintChars(st)} chars`);
      }
      ctx.ui?.notify(lines.join("\n"), "info");
    },
  });
}

// ---------------------------------------------------------------------------
// Tool implementations (pure-ish; only touch the on-disk store + core)
// ---------------------------------------------------------------------------

function toolText(text: string) {
  return { content: [{ type: "text" as const, text }] };
}

function runDeclare(cwd: string, domain: string, fieldsJson: string) {
  if (isForbiddenDomain(domain)) {
    return toolText(`SKILL.state declare rolled back: domain '${domain}' is forbidden.`);
  }
  if (fieldsJson.length > MAX_ARG_JSON_CHARS) {
    return toolText(`SKILL.state declare rolled back: 'fields' exceeds ${MAX_ARG_JSON_CHARS} chars.`);
  }
  let fields: Record<string, SchemaField>;
  try {
    const parsed = JSON.parse(fieldsJson);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return toolText(`SKILL.state declare rolled back: 'fields' must be a JSON object.`);
    }
    fields = parsed as Record<string, SchemaField>;
  } catch (e: any) {
    return toolText(`SKILL.state declare rolled back: invalid JSON in 'fields' (${e.message}).`);
  }
  // Validate the schema itself so a typo'd type/listMerge is caught here, not as a
  // confusing permanent rollback on every later patch.
  const sv = validateSchemaFields(fields);
  if (!sv.valid) {
    return toolText(`SKILL.state declare rolled back: ${sv.errors.join("; ")}.`);
  }
  const file = storePathForCwd(cwd);
  const store = loadStore(file);
  const prior = store[domain];
  try {
    store[domain] = { schema: { domain, fields }, state: prior?.state ?? {} };
    saveStore(file, store);
  } catch (e: any) {
    return toolText(`SKILL.state declare rolled back: persist failed (${e?.message ?? String(e)}).`);
  }
  return toolText(
    `SKILL.state: declared schema for domain '${domain}' with ${Object.keys(fields).length} fields. Existing Σ preserved (${Object.keys(store[domain].state).length} keys).`,
  );
}

function runUpdate(cwd: string, domain: string, patchJson: string) {
  if (isForbiddenDomain(domain)) {
    return toolText(`SKILL.state update rolled back (no state change): domain '${domain}' is forbidden.`);
  }
  if (patchJson.length > MAX_ARG_JSON_CHARS) {
    return toolText(`SKILL.state update rolled back (no state change): 'patch' exceeds ${MAX_ARG_JSON_CHARS} chars.`);
  }
  let patch: StatePatch;
  try {
    const parsed = JSON.parse(patchJson);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return toolText(`SKILL.state update rolled back (no state change): 'patch' must be a JSON object.`);
    }
    patch = parsed as StatePatch;
  } catch (e: any) {
    // 12% JSON-syntax failure mode -> rollback, no corruption (paper §5.7 / §7).
    return toolText(`SKILL.state update rolled back (no state change): invalid JSON in 'patch' (${e.message}). Retry with corrected JSON.`);
  }

  const file = storePathForCwd(cwd);
  const store = loadStore(file);
  const entry = store[domain] ?? { schema: permissiveSchema(domain), state: {} };
  // validatePatch (inside applyPatch) rejects over-deep/invalid patches before the
  // recursive merge/clone runs, but wrap defensively so ANY unexpected throw (e.g.
  // a RangeError from a pathological value that slips the depth guard) still
  // degrades to a clean rollback rather than an uncaught exception — honoring the
  // "malformed input never crashes / never corrupts Σ" contract.
  let result: ReturnType<typeof applyPatch>;
  try {
    result = applyPatch(entry.schema, entry.state, patch);
  } catch (e: any) {
    return toolText(`SKILL.state update rolled back (no state change): ${e?.message ?? String(e)}. Retry with a simpler ΔΣ.`);
  }
  if (!result.ok) {
    return toolText(
      `SKILL.state update rolled back (no state change): ${result.errors.join("; ")}. Retry with a corrected ΔΣ.`,
    );
  }
  try {
    store[domain] = { schema: entry.schema, state: result.state };
    saveStore(file, store);
  } catch (e: any) {
    return toolText(`SKILL.state update rolled back (no state change): persist failed (${e?.message ?? String(e)}).`);
  }
  const footprint = stateFootprintChars(result.state);
  const advisory =
    footprint > STATE_FOOTPRINT_ADVISORY_CHARS
      ? `\n⚠ Σ footprint ${footprint} chars exceeds ${STATE_FOOTPRINT_ADVISORY_CHARS}; consider pruning append/union fields (see SKILL_STATE.md limitations).`
      : "";
  return toolText(
    [
      `SKILL.state: applied ΔΣ to domain '${domain}'. Σ now has ${Object.keys(result.state).length} keys (footprint ${footprint} chars).${advisory}`,
      "```json",
      JSON.stringify(result.state, null, 2),
      "```",
    ].join("\n"),
  );
}

function runGet(cwd: string, domain: string) {
  if (isForbiddenDomain(domain)) {
    return toolText(`SKILL.state: domain '${domain}' is forbidden.`);
  }
  const file = storePathForCwd(cwd);
  const store = loadStore(file);
  const entry = store[domain];
  if (!entry) {
    return toolText(`SKILL.state: domain '${domain}' has no state yet.`);
  }
  const shown = entry.state ?? {};
  return toolText(
    [
      `SKILL.state Σ for domain '${domain}' (footprint ${stateFootprintChars(shown)} chars):`,
      "```json",
      JSON.stringify(shown, null, 2),
      "```",
    ].join("\n"),
  );
}

// Exported for unit testing of the on-disk store round-trip.
export { storePathForCwd, loadStore, saveStore, runDeclare, runUpdate, runGet };
export type { Store, DomainEntry };
