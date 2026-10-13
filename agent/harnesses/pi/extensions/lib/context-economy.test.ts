import { estimateSessionCost, cacheHitRatePercent, type SessionTokenStats } from "../context-economy";

let pass = 0;
let fail = 0;
function check(desc: string, ok: boolean, detail?: string) {
  if (ok) {
    console.log(`ok: ${desc}`);
    pass++;
  } else {
    console.log(`FAIL: ${desc}${detail ? ` (${detail})` : ""}`);
    fail++;
  }
}

const base: SessionTokenStats = {
  inputTokens: 0,
  outputTokens: 0,
  cacheReadTokens: 0,
  cacheWriteTokens: 0,
  turnCount: 0,
};

// Per-class rates: in $3/M, out $15/M, cacheRead $0.30/M, cacheWrite $3.75/M.
check(
  "input tokens billed at $3/M",
  Math.abs(estimateSessionCost({ ...base, inputTokens: 1_000_000 }) - 3.0) < 1e-9
);
check(
  "output tokens billed at $15/M",
  Math.abs(estimateSessionCost({ ...base, outputTokens: 1_000_000 }) - 15.0) < 1e-9
);
check(
  "cache-read tokens billed at $0.30/M",
  Math.abs(estimateSessionCost({ ...base, cacheReadTokens: 1_000_000 }) - 0.3) < 1e-9
);
// L3 regression: cache-write tokens MUST be billed (previously omitted -> $0).
check(
  "cache-write tokens billed at $3.75/M (regression: was omitted)",
  Math.abs(estimateSessionCost({ ...base, cacheWriteTokens: 1_000_000 }) - 3.75) < 1e-9
);
check(
  "cache-write cost is non-zero for a cache-heavy session",
  estimateSessionCost({ ...base, cacheWriteTokens: 500_000 }) > 0
);
// Combined session sums all four classes.
check(
  "combined cost sums all token classes",
  Math.abs(
    estimateSessionCost({
      inputTokens: 1_000_000,
      outputTokens: 1_000_000,
      cacheReadTokens: 1_000_000,
      cacheWriteTokens: 1_000_000,
      turnCount: 3,
    }) - (3.0 + 15.0 + 0.3 + 3.75)
  ) < 1e-9
);

// L2: cache hit rate divides reads by ALL prompt-side input (incl. cache writes)
check(
  "cacheHitRatePercent includes cache writes in the denominator",
  Math.abs(cacheHitRatePercent({ ...base, inputTokens: 100, cacheReadTokens: 900, cacheWriteTokens: 1000 }) - 45.0) < 1e-9,
  `got ${cacheHitRatePercent({ ...base, inputTokens: 100, cacheReadTokens: 900, cacheWriteTokens: 1000 })}`
);
check(
  "cacheHitRatePercent is 0 with no input",
  cacheHitRatePercent({ ...base }) === 0
);
check(
  "cacheHitRatePercent is 100 when all input is cache reads",
  Math.abs(cacheHitRatePercent({ ...base, cacheReadTokens: 500 }) - 100.0) < 1e-9
);

console.log(`\ncontext-economy.test: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
