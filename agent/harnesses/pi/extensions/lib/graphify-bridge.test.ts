import { findGraphFile, queryGraph, explainConcept } from "../graphify-bridge";
import * as path from "node:path";
import * as fs from "node:fs";
import * as os from "node:os";

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

const root = path.resolve(__dirname, "../../../../..");

// 1. Locate graph.json
const graphPath = findGraphFile(root);
check("findGraphFile finds repository graph", graphPath !== null, `Got: ${graphPath}`);

// 2. Query graph
const qResult = queryGraph("agent", root);
check("queryGraph returns summary or nodes", qResult.summary.length > 0);

// 3. Explain concept
const eResult = explainConcept("Makefile", root);
check("explainConcept executes", typeof eResult.found === "boolean");

// L1 regression: a query/concept containing shell metacharacters must be treated
// as literal data (spawnSync argv), never executed. Run queryGraph/explainConcept
// with a command-substitution payload and assert no side-effect marker is created
// and no exception escapes.
{
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "graphify-inj-"));
  const marker = path.join(tmp, "pwned");
  fs.writeFileSync(path.join(tmp, "graph.json"), JSON.stringify({ nodes: [], edges: [] }));
  const payloads = [
    `x$(touch ${marker})`,
    "y`touch " + marker + "`",
    `z; touch ${marker}`,
  ];
  let threw = false;
  for (const p of payloads) {
    try { queryGraph(p, tmp); explainConcept(p, tmp); } catch { threw = true; }
  }
  check("L1: shell-metacharacter query does not execute commands", !fs.existsSync(marker));
  check("L1: shell-metacharacter query does not throw", !threw);
  try { fs.rmSync(tmp, { recursive: true, force: true }); } catch {}
}

console.log(`\ngraphify-bridge: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
