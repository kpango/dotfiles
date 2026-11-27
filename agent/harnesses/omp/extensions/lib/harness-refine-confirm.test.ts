// harness_refine models-update apply / sync must not run without an explicit user confirmation (they rewrite Tier B files from
// external data). The extension is loaded with a fake pi and driven through its registered tool.
//
// SAFETY: this test only exercises the CANCELLED paths. A confirmed models-update runs update-model-catalog.py for real
// (network fetch + rewriting agent/models/catalog.json and the model-routing.json files), so no case here may answer
// `true`, and the read-only actions (dry-run / check) are not driven either. A first version of this test did, and rewrote
// the real Tier B files.
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import harness from "../continual-harness";

let pass = 0;
let fail = 0;
function check(name: string, ok: boolean, msg?: string) {
  if (ok) {
    console.log(`ok: ${name}`);
    pass++;
  } else {
    console.error(`FAIL: ${name}: ${msg || ""}`);
    fail++;
  }
}

const registered: { tool?: any } = {};
const pi: any = new Proxy({}, { get: (_t, k) => (k === "registerTool" ? (t: any) => (registered.tool = t) : () => undefined) });
harness(pi);
const tool = registered.tool;
check("harness_refine tool is registered", !!tool && typeof tool.execute === "function");

const cwd = fs.mkdtempSync(path.join(os.tmpdir(), "refine-confirm-"));
const text = (r: any): string => String(r?.content?.[0]?.text ?? "");
const run = (args: Record<string, unknown>, ctx: any) => tool.execute("id", args, undefined, undefined, ctx);
const cancelled = (t: string) => /cancelled: user confirmation is required/.test(t);

for (const args of [
  { mode: "models-update", apply: true },
  { mode: "models-update", catalogAction: "apply" },
  { mode: "models-update", catalogAction: "sync" },
]) {
  const label = JSON.stringify(args);
  check(`${label}: no UI -> cancelled`, cancelled(text(await run(args, { cwd }))));
  check(`${label}: no ui.confirm function -> cancelled`, cancelled(text(await run(args, { cwd, ui: {} }))));
  for (const [what, answer] of [["false", false], ['"yes" (truthy, not === true)', "yes"], ["undefined", undefined], ["1 (truthy, not === true)", 1], ["null", null]] as [string, unknown][]) {
    let asked = 0;
    const ctx = { cwd, ui: { confirm: async () => { asked++; return answer; } } };
    check(`${label}: user answer ${what} -> cancelled, and the dialog was shown`, cancelled(text(await run(args, ctx))) && asked === 1);
  }
}

// The models-update branch is wrapped in try/catch, so a dialog that throws ends as "update failed", never as an apply.
let threwText = "";
try {
  threwText = text(await run({ mode: "models-update", apply: true }, { cwd, ui: { confirm: async () => { throw new Error("dialog failed"); } } }));
} catch (e) {
  threwText = `THROWN: ${(e as Error).message}`;
}
check("a confirm dialog that throws ends as a failure (never falls through to apply)", /Model catalog update failed: dialog failed/.test(threwText), threwText);

fs.rmSync(cwd, { recursive: true, force: true });
console.log(`\nharness-refine-confirm: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
