import {
  type SkillStateSchema,
  validatePatch,
  mergeState,
  applyPatch,
  mergeConcurrentPatches,
  stateFootprintChars,
  formatExecutionContext,
  permissiveSchema,
  formatStateDigest,
  STATE_DIGEST_MAX_CHARS,
  MAX_DIGEST_DOMAINS,
} from "./skill-state-core";
import { storePathForCwd, loadStore, saveStore, runDeclare, runUpdate, runGet } from "../skill-state";
import { validateSchemaFields } from "./skill-state-core";
// SharedExecutionState lives in subagent-mesh-core (the SKILL.state multi-agent
// facet, paper §7 #4). It is covered HERE, alongside the rest of the SKILL.state
// core, so the whole feature's assertions live in one synchronous top-level suite
// that the deterministic gate (test-pi-extensions.sh, single-file `bun test`)
// executes and counts on every run.
import { SharedExecutionState } from "./subagent-mesh-core";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

let pass = 0;
let fail = 0;
function check(name: string, ok: boolean, detail?: string) {
  if (ok) {
    console.log(`ok: ${name}`);
    pass++;
  } else {
    console.error(`FAIL: ${name}${detail ? ` (${detail})` : ""}`);
    fail++;
  }
}
function textOf(r: { content: { type: string; text: string }[] }): string {
  return r.content.map((c) => c.text).join("\n");
}

// A representative long-horizon schema (shape of the paper's InterCode CTF 5-field
// schema: discovered_flags, tested_hypotheses, active_files, working_dir, cmd_summary).
const ctf: SkillStateSchema = {
  domain: "ctf",
  fields: {
    discovered_flags: { type: "list", listMerge: "union" },
    tested_hypotheses: { type: "list", listMerge: "append" },
    active_files: { type: "list", listMerge: "replace" },
    working_dir: { type: "string" },
    cmd_summary: { type: "map" },
    attempt: { type: "number" },
  },
};

// --- validation ------------------------------------------------------------
check("validatePatch accepts a well-typed patch", validatePatch(ctf, { working_dir: "/tmp", attempt: 3 }).valid);
check("validatePatch rejects unknown key", !validatePatch(ctf, { bogus: 1 }).valid);
check("validatePatch rejects type mismatch (number->string field)", !validatePatch(ctf, { working_dir: 5 }).valid);
check("validatePatch allows null (deletion) for known key", validatePatch(ctf, { working_dir: null }).valid);
check("validatePatch rejects non-object patch", !validatePatch(ctf, [] as any).valid);
check("permissiveSchema accepts any typed value", validatePatch(permissiveSchema("d"), { a: 1, b: "x", c: [1] }).valid);

// --- ⊕ merge: null-deletion + additive (paper §3.2 eq.4; §5.7 68% mode) ----
{
  const s0 = { working_dir: "/root", attempt: 1, discovered_flags: ["flag{a}"] };
  // A patch touching only `attempt` must NOT drop the sibling keys (additive ⊕).
  const s1 = mergeState(ctf, s0, { attempt: 2 });
  check(
    "merge is additive: untouched keys survive (prevents premature overwrite)",
    s1.working_dir === "/root" && Array.isArray(s1.discovered_flags) && (s1.discovered_flags as string[])[0] === "flag{a}" && s1.attempt === 2,
  );
  check("merge does not mutate the input Σ", (s0 as any).attempt === 1);
  const s2 = mergeState(ctf, s1, { working_dir: null });
  check("null value deletes the key", !("working_dir" in s2));
}

// --- list merge strategies -------------------------------------------------
{
  const base = { discovered_flags: ["a"], tested_hypotheses: ["h1"], active_files: ["x"] };
  const un = mergeState(ctf, base, { discovered_flags: ["a", "b"] });
  check("list union dedups", JSON.stringify((un.discovered_flags as string[]).sort()) === JSON.stringify(["a", "b"]));
  const ap = mergeState(ctf, base, { tested_hypotheses: ["h2"] });
  check("list append concatenates", JSON.stringify(ap.tested_hypotheses) === JSON.stringify(["h1", "h2"]));
  const rp = mergeState(ctf, base, { active_files: ["y"] });
  check("list replace (default) overwrites", JSON.stringify(rp.active_files) === JSON.stringify(["y"]));
}

// --- deep map merge --------------------------------------------------------
{
  const base = { cmd_summary: { ls: "listed", cat: "read" } };
  const merged = mergeState(ctf, base, { cmd_summary: { grep: "searched" } });
  check(
    "map field deep-merges (sibling map keys preserved)",
    (merged.cmd_summary as any).ls === "listed" && (merged.cmd_summary as any).grep === "searched",
  );
}

// --- applyPatch rollback ---------------------------------------------------
{
  const s0 = { attempt: 1 };
  const bad = applyPatch(ctf, s0, { attempt: "not-a-number" as any });
  check("applyPatch rolls back on invalid type (Σ unchanged)", !bad.ok && bad.state === s0 && bad.errors.length > 0);
  const good = applyPatch(ctf, s0, { attempt: 2 });
  check("applyPatch applies a valid patch", good.ok && good.state.attempt === 2);
  const unk = applyPatch(ctf, s0, { nope: 1 });
  check("applyPatch rolls back on unknown key", !unk.ok && unk.state === s0);
}

// --- multi-agent deterministic conflict resolution (paper §7 #4 improvement) -
{
  // Two agents write the same scalar concurrently; last-writer-wins by ts.
  const r = mergeConcurrentPatches(ctf, [
    { agentId: "b", ts: 10, patch: { working_dir: "/from-b" } },
    { agentId: "a", ts: 20, patch: { working_dir: "/from-a" } },
  ]);
  check("concurrent scalar: last-writer-wins by ts", r.merged.working_dir === "/from-a");
  check("concurrent scalar: conflict recorded", r.conflicts.includes("working_dir"));

  // Tie on ts -> agentId lexical tiebreak (deterministic).
  const tie = mergeConcurrentPatches(ctf, [
    { agentId: "z", ts: 5, patch: { working_dir: "/z" } },
    { agentId: "a", ts: 5, patch: { working_dir: "/a" } },
  ]);
  check("concurrent scalar tie: agentId lexical tiebreak picks last (z)", tie.merged.working_dir === "/z");

  // union list field: both agents' additions survive regardless of order.
  const u = mergeConcurrentPatches(ctf, [
    { agentId: "a", ts: 1, patch: { discovered_flags: ["a"] } },
    { agentId: "b", ts: 2, patch: { discovered_flags: ["b"] } },
  ]);
  check("concurrent union list: both survive", JSON.stringify((u.merged.discovered_flags as string[]).sort()) === JSON.stringify(["a", "b"]));

  // non-contended keys are not conflicts.
  const nc = mergeConcurrentPatches(ctf, [
    { agentId: "a", ts: 1, patch: { attempt: 1 } },
    { agentId: "b", ts: 2, patch: { working_dir: "/x" } },
  ]);
  check("non-contended keys: no conflict", nc.conflicts.length === 0 && nc.merged.attempt === 1 && nc.merged.working_dir === "/x");

  // Determinism: same inputs in different array order -> identical merged output.
  const inA = mergeConcurrentPatches(ctf, [
    { agentId: "a", ts: 1, patch: { attempt: 1, working_dir: "/a" } },
    { agentId: "b", ts: 2, patch: { attempt: 2 } },
  ]);
  const inB = mergeConcurrentPatches(ctf, [
    { agentId: "b", ts: 2, patch: { attempt: 2 } },
    { agentId: "a", ts: 1, patch: { attempt: 1, working_dir: "/a" } },
  ]);
  check("concurrent merge is order-independent (deterministic)", JSON.stringify(inA.merged) === JSON.stringify(inB.merged));
}

// --- footprint + context ---------------------------------------------------
check("stateFootprintChars measures serialized size", stateFootprintChars({ a: 1 }) === JSON.stringify({ a: 1 }).length);
{
  const ctx = formatExecutionContext("do X", { a: 1 }, "obs Y");
  check("formatExecutionContext contains P, Σ, O and no reasoning", ctx.includes("do X") && ctx.includes('"a": 1') && ctx.includes("obs Y") && !ctx.includes("R_t"));
}

// --- store round-trip (loadStore/saveStore with explicit temp file) --------
{
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "skill-state-"));
  try {
    const f = path.join(tmp, "sub", "store.json");
    check("loadStore returns {} for missing file", Object.keys(loadStore(f)).length === 0);
    saveStore(f, { d: { schema: { domain: "d", fields: {} }, state: { k: 1 } } });
    const back = loadStore(f);
    check("saveStore+loadStore round-trips (creates dir)", (back.d?.state as any)?.k === 1);
    fs.writeFileSync(f, "{ this is : not json", "utf-8");
    check("loadStore tolerates a corrupt store (returns {})", Object.keys(loadStore(f)).length === 0);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

// --- tool impls (runDeclare/runUpdate/runGet) via a unique temp cwd --------
{
  const tmpCwd = fs.mkdtempSync(path.join(os.tmpdir(), "skill-state-cwd-"));
  const storeFile = storePathForCwd(tmpCwd);
  try {
    const decl = runDeclare(tmpCwd, "ctf", JSON.stringify(ctf.fields));
    check("runDeclare declares schema", textOf(decl).includes("declared schema for domain 'ctf'"));

    const good = runUpdate(tmpCwd, "ctf", JSON.stringify({ working_dir: "/tmp", discovered_flags: ["f1"] }));
    check("runUpdate applies valid patch", textOf(good).includes("applied ΔΣ") && textOf(good).includes("/tmp"));

    const badType = runUpdate(tmpCwd, "ctf", JSON.stringify({ working_dir: 5 }));
    check("runUpdate rolls back wrong type (§5.7 type coercion)", textOf(badType).includes("rolled back"));

    const badJson = runUpdate(tmpCwd, "ctf", "{ not valid json");
    check("runUpdate rolls back invalid JSON (§5.7 12% mode)", textOf(badJson).includes("rolled back") && textOf(badJson).includes("invalid JSON"));

    // The bad patches must not have corrupted persisted Σ.
    const got = runGet(tmpCwd, "ctf");
    check("runGet returns Σ intact after rollbacks", textOf(got).includes("/tmp") && textOf(got).includes("f1"));

    const unknownDomain = runGet(tmpCwd, "nope");
    check("runGet reports empty for unknown domain", textOf(unknownDomain).includes("no state yet"));
  } finally {
    fs.rmSync(tmpCwd, { recursive: true, force: true });
    try {
      fs.unlinkSync(storeFile);
    } catch {
      /* store file may not exist */
    }
  }
}

// --- prototype-pollution / forbidden keys (CWE-1321) --------------------------
{
  const anySchema = permissiveSchema("d");
  check("validatePatch rejects __proto__ key", !validatePatch(anySchema, { ["__proto__"]: { x: 1 } as any }).valid);
  check("validatePatch rejects constructor key", !validatePatch(anySchema, { constructor: 1 } as any).valid);
  check("validatePatch rejects prototype key", !validatePatch(anySchema, { prototype: 1 } as any).valid);
  const before = ({} as any).polluted;
  const r = applyPatch(anySchema, {}, JSON.parse('{"__proto__":{"polluted":true}}'));
  check("applyPatch rolls back a __proto__ patch", !r.ok);
  check("Object.prototype not polluted after __proto__ patch", ({} as any).polluted === before);
}

// --- NaN/Infinity rejected for number fields ---------------------------------
check("validatePatch rejects NaN for number field", !validatePatch(ctf, { attempt: NaN }).valid);
check("validatePatch rejects Infinity for number field", !validatePatch(ctf, { attempt: Infinity }).valid);
check("validatePatch accepts a finite number", validatePatch(ctf, { attempt: 7 }).valid);

// --- isPlainObject strictness: Date is not a mergeable map -------------------
{
  // A non-plain object (Date) must be REPLACED, not deep-merged to nothing (which
  // an over-broad isPlainObject would do, silently keeping the stale {a:1}).
  const withDate = mergeState(permissiveSchema("d"), { k: { a: 1 } }, { k: new Date(0) as any });
  const merged = withDate.k as any;
  check("mergeState replaces a non-plain object value (not deep-merged)", merged !== undefined && !(merged && merged.a === 1));
}

// --- orphan key can always be deleted (null before unknown-key check) --------
{
  const narrow: SkillStateSchema = { domain: "n", fields: { keep: { type: "string" } } };
  const withOrphan = { keep: "v", orphan: "old" };
  const del = applyPatch(narrow, withOrphan, { orphan: null });
  check("null deletion of an orphan (out-of-schema) key is allowed", del.ok && !("orphan" in del.state) && del.state.keep === "v");
}

// --- schema-declaration validation ------------------------------------------
check("validateSchemaFields accepts a valid schema", validateSchemaFields(ctf.fields).valid);
check("validateSchemaFields rejects an invalid type", !validateSchemaFields({ a: { type: "strnig" } }).valid);
check("validateSchemaFields rejects an invalid listMerge", !validateSchemaFields({ a: { type: "list", listMerge: "bogus" } }).valid);
check("validateSchemaFields rejects a non-object field", !validateSchemaFields({ a: 5 }).valid);

// --- permissive schema survives a persistence round-trip (self-destruct fix) --
{
  const tmpCwd = fs.mkdtempSync(path.join(os.tmpdir(), "skill-state-perm-"));
  const storeFile = storePathForCwd(tmpCwd);
  try {
    // Update an UNDECLARED domain (permissive fallback), then update again after a
    // full store round-trip. Previously the Proxy-based permissive schema
    // serialized to fields:{} and locked the domain out on reload.
    const u1 = runUpdate(tmpCwd, "undeclared", JSON.stringify({ a: 1 }));
    check("runUpdate on undeclared domain succeeds (permissive)", textOf(u1).includes("applied ΔΣ"));
    const reloaded = loadStore(storeFile);
    check("persisted permissive schema keeps its flag", reloaded.undeclared?.schema?.permissive === true);
    const u2 = runUpdate(tmpCwd, "undeclared", JSON.stringify({ b: 2 }));
    check("second update on undeclared domain still succeeds (no lockout)", textOf(u2).includes("applied ΔΣ") && textOf(u2).includes('"b": 2'));
  } finally {
    fs.rmSync(tmpCwd, { recursive: true, force: true });
    try { fs.unlinkSync(storeFile); } catch { /* may not exist */ }
  }
}

// --- runDeclare rejects a typo'd schema + forbidden domain ------------------
{
  const tmpCwd = fs.mkdtempSync(path.join(os.tmpdir(), "skill-state-decl-"));
  const storeFile = storePathForCwd(tmpCwd);
  try {
    const bad = runDeclare(tmpCwd, "d", JSON.stringify({ a: { type: "strnig" } }));
    check("runDeclare rejects a typo'd field type", textOf(bad).includes("rolled back"));
    const dom = runDeclare(tmpCwd, "__proto__", JSON.stringify({ a: { type: "string" } }));
    check("runDeclare rejects a forbidden domain", textOf(dom).includes("forbidden"));
    // Over-deep schema declaration must roll back (not crash JSON.stringify at save).
    let deepDesc: any = 1;
    for (let i = 0; i < 5000; i++) deepDesc = { n: deepDesc };
    const deepDecl = runDeclare(tmpCwd, "d2", JSON.stringify({ a: { type: "string", description: deepDesc } }));
    check("runDeclare rolls back an over-deep schema (no crash)", textOf(deepDecl).includes("rolled back"));
    // Width cap: an oversized (but shallow) argument is rejected before JSON.parse.
    const huge = JSON.stringify({ big: "x".repeat(300_000) });
    check("runDeclare rejects oversized 'fields' arg", textOf(runDeclare(tmpCwd, "d3", huge)).includes("rolled back"));
    check("runUpdate rejects oversized 'patch' arg", textOf(runUpdate(tmpCwd, "d", huge)).includes("rolled back"));
  } finally {
    fs.rmSync(tmpCwd, { recursive: true, force: true });
    try { fs.unlinkSync(storeFile); } catch { /* may not exist */ }
  }
}

// --- mergeConcurrentPatches: mid-sequence null delete (temporal fold) --------
{
  const r = mergeConcurrentPatches(ctf, [
    { agentId: "a", ts: 1, patch: { discovered_flags: ["old"] } },
    { agentId: "b", ts: 2, patch: { discovered_flags: null } },
    { agentId: "c", ts: 3, patch: { discovered_flags: ["new"] } },
  ]);
  check("concurrent union: mid-sequence null resets, later add rebuilds from empty", JSON.stringify(r.merged.discovered_flags) === JSON.stringify(["new"]));
  const r2 = mergeConcurrentPatches(ctf, [
    { agentId: "a", ts: 1, patch: { discovered_flags: ["x"] } },
    { agentId: "b", ts: 2, patch: { discovered_flags: null } },
  ]);
  check("concurrent union: trailing null yields a deletion", r2.merged.discovered_flags === null);

  // A type-invalid (non-array) concurrent write to a union/append list field must
  // NOT silently delete other agents' valid contributions: the raw invalid value
  // is surfaced so applyPatch/validatePatch rejects the whole patch (rollback).
  const bad = mergeConcurrentPatches(ctf, [
    { agentId: "a", ts: 1, patch: { discovered_flags: ["keep"] } },
    { agentId: "b", ts: 2, patch: { discovered_flags: "oops" as any } },
  ]);
  check("concurrent list: type-invalid write is surfaced raw (not coerced to null)", bad.merged.discovered_flags === "oops");
  const badApply = applyPatch(ctf, { discovered_flags: ["keep"] }, bad.merged);
  check("concurrent list: invalid write rolls back (valid contributions preserved)", !badApply.ok && JSON.stringify(badApply.state.discovered_flags) === JSON.stringify(["keep"]));

  // SANDWICHED type-invalid write (between two valid arrays) must also surface the
  // invalid value — not silently drop the earlier valid contribution and pass.
  const sw = mergeConcurrentPatches(ctf, [
    { agentId: "a", ts: 1, patch: { discovered_flags: ["f1"] } },
    { agentId: "b", ts: 2, patch: { discovered_flags: "bad" as any } },
    { agentId: "c", ts: 3, patch: { discovered_flags: ["f3"] } },
  ]);
  check("concurrent list: sandwiched invalid is surfaced (no silent loss)", sw.merged.discovered_flags === "bad");
  const swApply = applyPatch(ctf, { discovered_flags: ["f1"] }, sw.merged);
  check("concurrent list: sandwiched invalid rolls back (f1 preserved)", !swApply.ok && JSON.stringify(swApply.state.discovered_flags) === JSON.stringify(["f1"]));

  // Deep value via the concurrent path must not blow the stack in stableStringify/
  // combineLists — it is guarded to a clean rollback.
  let deepc: any = 1;
  for (let i = 0; i < 5000; i++) deepc = [deepc];
  const dc = mergeConcurrentPatches(ctf, [{ agentId: "a", ts: 1, patch: { discovered_flags: deepc } }]);
  check("concurrent: over-deep value guarded (no crash, surfaced for rejection)", dc.merged.discovered_flags === deepc);
  const dcApply = applyPatch(ctf, {}, dc.merged);
  check("concurrent: over-deep value rolls back via applyPatch", !dcApply.ok);
}

// --- nested forbidden key rejected at any depth ------------------------------
{
  const s = permissiveSchema("d");
  check("validatePatch rejects nested __proto__ key", !validatePatch(s, JSON.parse('{"m":{"level1":{"__proto__":{"evil":1}}}}')).valid);
  check("validatePatch rejects nested constructor key", !validatePatch(s, JSON.parse('{"m":{"constructor":1}}')).valid);
  check("validatePatch accepts a clean nested map", validatePatch(s, { m: { a: { b: 1 } } }).valid);
  const r = applyPatch(s, {}, JSON.parse('{"m":{"x":{"__proto__":{"evil":1}}}}'));
  check("applyPatch rolls back a nested-forbidden-key patch", !r.ok);
  // Symmetric: validateSchemaFields also rejects a forbidden key nested in a
  // field descriptor (e.g. a `description` value).
  check("validateSchemaFields rejects a nested forbidden key", !validateSchemaFields(JSON.parse('{"a":{"type":"string","description":{"__proto__":{"x":1}}}}')).valid);
}

// --- single-writer over-deep value is NOT reported as a multi-agent conflict --
{
  let deep: any = 1;
  for (let i = 0; i < 5000; i++) deep = [deep];
  const solo = mergeConcurrentPatches(ctf, [{ agentId: "a", ts: 1, patch: { discovered_flags: deep } }]);
  check("single-writer over-deep value is not a conflict", !solo.conflicts.includes("discovered_flags"));
  const multi = mergeConcurrentPatches(ctf, [
    { agentId: "a", ts: 1, patch: { discovered_flags: deep } },
    { agentId: "b", ts: 2, patch: { discovered_flags: ["x"] } },
  ]);
  check("multi-writer over-deep value IS a conflict", multi.conflicts.includes("discovered_flags"));
}

// --- domain length cap + malformed-entry read guard -------------------------
{
  const tmpCwd = fs.mkdtempSync(path.join(os.tmpdir(), "skill-state-domlen-"));
  const storeFile = storePathForCwd(tmpCwd);
  try {
    check("runDeclare rejects an over-long domain", textOf(runDeclare(tmpCwd, "d".repeat(300), '{"a":{"type":"string"}}')).includes("forbidden"));
    check("runGet rejects an over-long domain", textOf(runGet(tmpCwd, "d".repeat(300))).includes("forbidden"));
    // Malformed on-disk entry (missing `state`) must not crash the read path.
    saveStore(storeFile, { broken: { schema: { domain: "broken", fields: {} } } as any });
    const g = runGet(tmpCwd, "broken");
    check("runGet tolerates a malformed entry (no crash)", textOf(g).includes("broken") || textOf(g).includes("no state"));
  } finally {
    fs.rmSync(tmpCwd, { recursive: true, force: true });
    try { fs.unlinkSync(storeFile); } catch { /* may not exist */ }
  }
}

// --- forbidden-domain read guard (no crash on domain=__proto__) ------------
{
  const tmpCwd = fs.mkdtempSync(path.join(os.tmpdir(), "skill-state-dom-"));
  const storeFile = storePathForCwd(tmpCwd);
  try {
    const g = runGet(tmpCwd, "__proto__");
    check("runGet on forbidden domain returns 'forbidden' (no crash)", textOf(g).includes("forbidden"));
  } finally {
    fs.rmSync(tmpCwd, { recursive: true, force: true });
    try { fs.unlinkSync(storeFile); } catch { /* may not exist */ }
  }
}

// --- deep-nesting guard: over-deep patch rejected before recursion crashes ---
{
  let deep: any = 1;
  for (let i = 0; i < 5000; i++) deep = [deep];
  const v = validatePatch(permissiveSchema("d"), { k: deep });
  check("validatePatch rejects an over-deep value", !v.valid && v.errors.some((e) => e.includes("deeper")));
  const r = applyPatch(permissiveSchema("d"), {}, { k: deep });
  check("applyPatch rolls back an over-deep value without crashing", !r.ok);
  const shallow = validatePatch(permissiveSchema("d"), { k: [[[[[1]]]]] });
  check("validatePatch accepts a shallow nested value", shallow.valid);
}

// --- SharedExecutionState (multi-agent SKILL.state substrate, paper §7 #4) ---
{
  const schema = {
    domain: "mesh",
    fields: {
      status: { type: "string" as const },
      findings: { type: "list" as const, listMerge: "union" as const },
      attempt: { type: "number" as const },
    },
  };

  const s = new SharedExecutionState(schema, { status: "init" });
  const a = s.apply({ status: "drafting", findings: ["f1"] });
  check("SharedExecutionState.apply accepts a valid patch", a.ok && a.errors.length === 0);
  check("SharedExecutionState.get reflects the applied patch", s.get().status === "drafting");
  check(
    "SharedExecutionState.get returns a defensive copy",
    (() => {
      const g = s.get();
      (g as any).status = "mutated";
      return s.get().status === "drafting";
    })(),
  );

  const bad = s.apply({ attempt: "nan" as any });
  check("SharedExecutionState.apply rolls back invalid patch (Σ unchanged)", !bad.ok && s.get().attempt === undefined);

  const c = s.applyConcurrent([
    { agentId: "b", ts: 20, patch: { status: "verifying", findings: ["f2"] } },
    { agentId: "a", ts: 10, patch: { status: "remediating", findings: ["f3"] } },
  ]);
  check("SharedExecutionState.applyConcurrent: scalar last-writer-wins by ts", c.ok && s.get().status === "verifying");
  check(
    "SharedExecutionState.applyConcurrent: unions list fields across agents",
    JSON.stringify((s.get().findings as string[]).sort()) === JSON.stringify(["f1", "f2", "f3"]),
  );
  check("SharedExecutionState.applyConcurrent: reports the contended key", c.conflicts.includes("status"));

  const m1 = new SharedExecutionState(schema);
  const m2 = new SharedExecutionState(schema);
  const p = [
    { agentId: "x", ts: 1, patch: { status: "a", findings: ["p"] } },
    { agentId: "y", ts: 2, patch: { status: "b", findings: ["q"] } },
  ];
  m1.applyConcurrent(p);
  m2.applyConcurrent([p[1], p[0]]);
  check("SharedExecutionState convergence is order-independent", JSON.stringify(m1.get()) === JSON.stringify(m2.get()));
  check("SharedExecutionState.footprint is serialized size", s.footprint() === JSON.stringify(s.get()).length);

  // Defensive: an over-deep concurrent write degrades to a clean rollback, never
  // an uncaught exception in a peer's write path.
  let deepv: any = 1;
  for (let i = 0; i < 5000; i++) deepv = [deepv];
  const dres = s.applyConcurrent([{ agentId: "a", ts: 1, patch: { findings: deepv } }]);
  check("SharedExecutionState.applyConcurrent over-deep write rolls back (no crash)", dres.ok === false);
}

// --- formatStateDigest (default per-turn Σ auto-context) ---------------------
{
  check("formatStateDigest: empty entries -> empty string", formatStateDigest([]) === "");
  check("formatStateDigest: all-empty Σ -> empty string", formatStateDigest([{ domain: "d", sigma: {} }]) === "");
  const one = formatStateDigest([{ domain: "swarm-loop", sigma: { phase: "PLAN", attempts: 2 } }]);
  check("formatStateDigest: renders header + domain block", one.includes("current execution state") && one.includes("Σ [swarm-loop]") && one.includes('"phase"'));
  // Deterministic domain ordering (sorted by name) regardless of input order.
  const multi = formatStateDigest([
    { domain: "zeta", sigma: { k: 1 } },
    { domain: "alpha", sigma: { k: 2 } },
  ]);
  check("formatStateDigest: domains sorted deterministically", multi.indexOf("Σ [alpha]") < multi.indexOf("Σ [zeta]"));
  const multi2 = formatStateDigest([
    { domain: "alpha", sigma: { k: 2 } },
    { domain: "zeta", sigma: { k: 1 } },
  ]);
  check("formatStateDigest: order-independent output", multi === multi2);
  // Budget: whole blocks dropped (never split) with an omission note; stays bounded.
  const big: any = {};
  for (let i = 0; i < 40; i++) big[`field_${i}`] = "x".repeat(400);
  const bounded = formatStateDigest([
    { domain: "a", sigma: big },
    { domain: "b", sigma: big },
    { domain: "c", sigma: big },
  ], 2000);
  check("formatStateDigest: respects char budget", bounded.length <= 2000);
  check("formatStateDigest: notes omitted domains past budget", bounded.includes("omitted"));
  // Boundary: one block fits leaving little room, and a second is omitted — the
  // trailing note must NOT push the total past maxChars (note-reserve budgeting).
  const oneBlock: any = { f: "y".repeat(1500) };
  const boundary = formatStateDigest([
    { domain: "a", sigma: oneBlock },
    { domain: "b", sigma: oneBlock },
  ], 1900);
  check("formatStateDigest: omission note fits within budget at boundary", boundary.length <= 1900 && boundary.includes("omitted"));
  // Per-turn compute bound: with many tiny domains under a large budget, only up to
  // MAX_DIGEST_DOMAINS are serialized; the rest are omitted (not stringified).
  const many = [];
  for (let i = 0; i < MAX_DIGEST_DOMAINS + 10; i++) many.push({ domain: `d${String(i).padStart(3, "0")}`, sigma: { i } });
  const capped = formatStateDigest(many, 1_000_000);
  // Budget is huge (1M) and each Σ is tiny, so only the domain cap bounds output:
  // exactly MAX_DIGEST_DOMAINS blocks are serialized, the remaining 10 omitted.
  check("formatStateDigest: caps serialized domain count", (capped.match(/### Σ \[/g) || []).length === MAX_DIGEST_DOMAINS && capped.includes("omitted"));
  check("formatStateDigest: never emits a partial JSON block", (bounded.match(/```json/g) || []).length === (bounded.match(/```/g) || []).length / 2);
  check("formatStateDigest: default budget constant is small (re-injected each turn)", STATE_DIGEST_MAX_CHARS <= 16_384);
}

console.log(`\nskill-state: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
