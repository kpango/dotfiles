import { canonicalizeJson, MAX_CANONICALIZE_DEPTH } from "./canonical-json";

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

// --- primitives / null / undefined -----------------------------------------
check("null -> null", canonicalizeJson(null) === "null");
check("undefined -> null", canonicalizeJson(undefined) === "null");
check("number", canonicalizeJson(5) === "5");
check("boolean", canonicalizeJson(true) === "true");
check("string quoted", canonicalizeJson("x") === '"x"');
check("non-JSON primitive stringified", canonicalizeJson(BigInt(7)) === '"7"');

// --- deterministic key ordering at all depths ------------------------------
check(
  "keys sorted at all depths",
  canonicalizeJson({ b: 1, a: { d: 2, c: 3 } }) === '{"a":{"c":3,"d":2},"b":1}',
);
check("array order preserved", canonicalizeJson([3, 1, 2]) === "[3,1,2]");
check("empty object/array", canonicalizeJson({}) === "{}" && canonicalizeJson([]) === "[]");

// --- semantic-equality: distinct-but-equal vs order differ -----------------
check(
  "key order independent",
  canonicalizeJson({ x: 1, y: 2 }) === canonicalizeJson({ y: 2, x: 1 }),
);

// --- DAG-shared (non-circular) reference must NOT be flagged circular -------
const shared = { k: 1 };
const dag = { a: shared, b: shared };
check(
  "shared non-circular ref serializes like structural equal",
  canonicalizeJson(dag) === canonicalizeJson({ a: { k: 1 }, b: { k: 1 } }),
);
check("shared ref not flagged [Circular]", !canonicalizeJson(dag).includes("[Circular]"));

// --- true cycle is contained -----------------------------------------------
const cyc: any = { a: 1 };
cyc.self = cyc;
check("true cycle -> [Circular] sentinel (no crash)", canonicalizeJson(cyc).includes("[Circular]"));

// --- depth cap: pathological nesting is bounded, not a stack overflow -------
let deep: any = 1;
for (let i = 0; i < 5000; i++) deep = { n: deep };
let deepOut = "";
let threw = false;
try {
  deepOut = canonicalizeJson(deep);
} catch {
  threw = true;
}
check("over-deep value does not throw", !threw);
check("over-deep value hits [MaxDepth] sentinel", deepOut.includes("[MaxDepth]"));
check("depth cap constant is exported", MAX_CANONICALIZE_DEPTH === 256);

// --- equivalence with the former skill-state stableStringify form ----------
// (JSON-safe, acyclic, shallow value: sorted-key stable serialization.)
function legacyStable(v: any): string {
  if (v === null || typeof v !== "object") return JSON.stringify(v) ?? "null";
  if (Array.isArray(v)) return "[" + v.map(legacyStable).join(",") + "]";
  const keys = Object.keys(v).sort();
  return "{" + keys.map((k) => JSON.stringify(k) + ":" + legacyStable(v[k])).join(",") + "}";
}
for (const v of [
  null,
  1,
  "s",
  true,
  [1, 2, 3],
  { b: 1, a: 2 },
  { list: ["x", "y"], nested: { z: 9, a: 0 } },
  [],
  {},
]) {
  check(
    `equivalence with legacy stableStringify: ${JSON.stringify(v)}`,
    canonicalizeJson(v) === legacyStable(v),
  );
}

console.log(`\ncanonical-json: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
