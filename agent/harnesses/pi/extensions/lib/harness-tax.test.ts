/**
 * Regression guard for Harness Tax prevention (pi-agent-improvement.pdf #1, #3, #4).
 *
 * Ensures custom extension tools stay minimal in the direct schema budget while
 * specialized tools declare `exposure: "deferred"` for tool_search / codemode.
 */

import * as fs from "node:fs";
import * as path from "node:path";

let pass = 0;
let fail = 0;

function check(name: string, ok: boolean, detail?: string) {
  if (ok) {
    pass++;
  } else {
    fail++;
    console.error(`FAIL: ${name}${detail ? ` (${detail})` : ""}`);
  }
}

const extDir = path.resolve(import.meta.dir, "..");
const files = fs
  .readdirSync(extDir)
  .filter((f) => f.endsWith(".ts"))
  .sort();

const tools: Array<{ name: string; exposure: string; file: string }> = [];
const regBlockRe = /pi\.registerTool\(\s*\{([\s\S]*?)\bparameters\s*:/g;

for (const file of files) {
  const src = fs.readFileSync(path.join(extDir, file), "utf-8");
  let match: RegExpExecArray | null;
  regBlockRe.lastIndex = 0;
  while ((match = regBlockRe.exec(src)) !== null) {
    const body = match[1];
    const nameMatch = /\bname\s*:\s*["']([^"']+)["']/.exec(body);
    if (!nameMatch) continue;
    const expMatch = /\bexposure\s*:\s*["']([^"']+)["']/.exec(body);
    tools.push({
      name: nameMatch[1],
      exposure: expMatch ? expMatch[1] : "direct",
      file,
    });
  }
}

const directTools = tools.filter((t) => t.exposure === "direct" || t.exposure === "model-only");
const deferredTools = tools.filter((t) => t.exposure === "deferred");

check("discovered >= 30 registered extension tools", tools.length >= 30, `count=${tools.length}`);
check(
  "direct custom tools <= 5 (Harness Tax budget)",
  directTools.length <= 5,
  `direct=${directTools.map((t) => t.name).join(",")}`,
);

for (const coreName of ["edit", "obs_recall", "update_plan", "subagent"]) {
  const entry = tools.find((t) => t.name === coreName);
  check(`core tool '${coreName}' remains direct`, Boolean(entry && entry.exposure === "direct"), entry?.exposure);
}

for (const specName of [
  "lsp",
  "debug",
  "ast_grep_search",
  "claude_code",
  "hermes_query",
  "antigravity_cli",
  "mesh_publish",
  "web_search",
  "run_adversarial_review",
]) {
  const entry = tools.find((t) => t.name === specName);
  check(
    `specialized tool '${specName}' has exposure: deferred`,
    Boolean(entry && entry.exposure === "deferred"),
    entry?.exposure,
  );
}

check("at least 30 tools deferred", deferredTools.length >= 30, `deferred=${deferredTools.length}`);

console.log(`\nharness-tax: ${pass} passed, ${fail} failed (direct=${directTools.length}, deferred=${deferredTools.length})`);
if (fail > 0) process.exit(1);
