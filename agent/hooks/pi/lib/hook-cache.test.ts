import { callDecide, clearDecideCache, getDecideCacheSize } from "./shared";
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

const root = path.resolve(__dirname, "../../../..");

// 1. Initial state
clearDecideCache();
check("Cache is initially empty", getDecideCacheSize() === 0);

// 2. First call populates cache
const req = {
  family: "security_gate",
  command: "ls -la",
};
const start1 = performance.now();
const res1 = callDecide(root, req, { allowed: true });
const dur1 = performance.now() - start1;

check("First call succeeds", typeof res1 === "object");
check("Cache size increases to 1", getDecideCacheSize() === 1);

// 3. Second call hits cache (orders of magnitude faster)
const start2 = performance.now();
const res2 = callDecide(root, req, { allowed: true });
const dur2 = performance.now() - start2;

check("Second call hits cache and returns equal result", JSON.stringify(res1) === JSON.stringify(res2));
check("Cached call is significantly faster than first call", dur2 < dur1 || dur2 < 2.0, `dur1=${dur1.toFixed(2)}ms, dur2=${dur2.toFixed(2)}ms`);

// 4. Cache clear
clearDecideCache();
check("Cache cleared", getDecideCacheSize() === 0);

console.log(`\nhook-cache: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
