import { findGraphFile, queryGraph, explainConcept } from "../graphify-bridge";
import * as path from "node:path";

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

console.log(`\ngraphify-bridge: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
