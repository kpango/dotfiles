import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { buildArgs, resolveScriptPath, runSandbox } from "../sandbox-run";

let pass = 0;
let fail = 0;
function eq<T>(name: string, actual: T, expected: T) {
  if (JSON.stringify(actual) === JSON.stringify(expected)) {
    console.log(`ok: ${name}`);
    pass++;
  } else {
    console.error(`FAIL: ${name}\n  actual:   ${JSON.stringify(actual)}\n  expected: ${JSON.stringify(expected)}`);
    fail++;
  }
}

eq("argv built with separator", buildArgs({ command: ["echo", "--x"] }), { args: ["--backend", "auto", "--", "echo", "--x"] });
eq("allowHosts forwarded", buildArgs({ command: ["x"], backend: "gondolin", allowHosts: ["example.com"] }), {
  args: ["--backend", "gondolin", "--allow-host", "example.com", "--", "x"],
});
eq("empty command rejected", "error" in buildArgs({ command: [] }), true);
eq("non-string argv rejected", "error" in buildArgs({ command: ["a", 1 as any] }), true);
eq("NUL rejected", "error" in buildArgs({ command: ["a\0b"] }), true);
eq("unknown backend rejected", "error" in buildArgs({ command: ["a"], backend: "docker" }), true);
eq("flag-looking host rejected", "error" in buildArgs({ command: ["a"], allowHosts: ["--secret"] }), true);
eq("host with shell chars rejected", "error" in buildArgs({ command: ["a"], allowHosts: ["a.com;id"] }), true);

const real = resolveScriptPath({});
eq("default script path resolves to the repo gondolin-run.mjs", fs.existsSync(real) && real.endsWith("agent/scripts/sandbox/gondolin-run.mjs"), true);

// End to end through the real gondolin-run.mjs, with pa-sandbox replaced by a stub (no host isolation needed here).
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "sandbox-run-test-"));
try {
  const stub = path.join(tmp, "pa-sandbox");
  fs.writeFileSync(stub, '#!/usr/bin/env bash\nshift\nprintf "stub-ran:%s\\n" "$*"\n', { mode: 0o755 });
  const nomod = path.join(tmp, "no-such-gondolin-module.mjs");
  const env = { ...process.env, GONDOLIN_RUN_PA_SANDBOX: stub, GONDOLIN_RUN_MODULE: nomod };
  const r = runSandbox({ command: ["echo", "hi"], backend: "pa-sandbox" }, tmp, env);
  eq("runs through the pa-sandbox stub", r.ok && r.text.includes("stub-ran:echo hi"), true);
  const r2 = runSandbox({ command: ["echo"], backend: "pa-sandbox", allowHosts: ["example.com"] }, tmp, env);
  eq("allowHosts with pa-sandbox is a hard failure, not ignored", r2.ok, false);
  const r3 = runSandbox({ command: ["echo"] }, tmp, { ...env, GONDOLIN_RUN_SCRIPT: path.join(tmp, "missing.mjs") });
  eq("missing script reported", r3.ok === false && r3.text.includes("does not exist"), true);
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}

console.log(`\nsandbox-run: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
