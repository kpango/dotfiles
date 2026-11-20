/**
 * Tests for RLM REPL Context Core Library
 *
 * Verifies 100KB threshold interception, handle generation,
 * line slicing, regex filtering, LRU eviction, and boundary conditions.
 */

import {
  ReplContextStore,
  REPL_THRESHOLD_BYTES,
  MAX_MEMORY_BUDGET_BYTES,
  MIN_PRESERVED_BUFFERS,
  sliceUtf8ToBytes,
  getObservationPackThresholds,
  runBoundedRlmChunkQuery,
  RLM_MAX_DEPTH,
  RLM_MAX_ITERATIONS,
} from "./repl-context-core";
import { DEFAULT_CONFIG } from "./sol-pi-core";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { createHash } from "node:crypto";

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

console.log("=== Running REPL Context Core Tests ===\n");

// --------------------------------------------------------------------------
// Test 1: 100KB Threshold Detection
// --------------------------------------------------------------------------
const store = new ReplContextStore();

const smallContent = "This is a small output below 100KB.\nLine 2\nLine 3\n";
const smallResult = store.store(smallContent, "bash");
check("Content <= 100KB is not intercepted", !smallResult.intercepted);

// Exactly 100 * 1024 bytes (102,400 bytes) should NOT be intercepted (threshold is strictly > 100KB)
const exact100K = "a".repeat(100 * 1024);
const exactResult = store.store(exact100K, "cat");
check("Content exactly 100KB (102,400 bytes) is not intercepted", !exactResult.intercepted);

// 100KB + 1 byte should be intercepted
const over100K = "a".repeat(100 * 1024 + 1);
const overResult = store.store(over100K, "find");
check("Content > 100KB is intercepted", overResult.intercepted === true);
check("Intercepted buffer returns handle starting with #repl_buf_", Boolean(overResult.handle?.startsWith("#repl_buf_")));
check("Intercepted buffer returns valid bufferId", Boolean(overResult.bufferId?.startsWith("repl_buf_")));
check("Summary includes handle and preview", Boolean(overResult.summary?.includes(overResult.handle!)));

// --------------------------------------------------------------------------
// Test 2: Multi-line Content Storage & Preview
// --------------------------------------------------------------------------
const lines1000: string[] = [];
for (let i = 1; i <= 1000; i++) {
  lines1000.push(`Line ${i}: log entry with payload data ${"x".repeat(120)}`);
}
const massiveLog = lines1000.join("\n");
const massiveResult = store.store(massiveLog, "test_runner");

check("Massive 1000-line log is intercepted", massiveResult.intercepted === true);
const bufId = massiveResult.bufferId!;
const entry = store.get(bufId);
check("Buffer entry exists in store", Boolean(entry));
check("Buffer entry line count is 1000", entry?.lineCount === 1000);
check("Preview has 5 lines", entry?.preview.split("\n").length === 5);

// --------------------------------------------------------------------------
// Test 3: Slicing (1-Indexed Line Ranges & Bounds)
// --------------------------------------------------------------------------
// Normal slice: lines 10 to 15
const slice1 = store.slice({ bufferId: bufId, startLine: 10, endLine: 15 });
check("Slice returns matchedLines = 6", slice1.matchedLines === 6);
check("Slice content starts with L10", slice1.content.includes("L10: Line 10:"));
check("Slice content includes L15", slice1.content.includes("L15: Line 15:"));
check("Slice totalLines equals 1000", slice1.totalLines === 1000);

// Default startLine (1) and endLine
const sliceHead = store.slice({ bufferId: bufId, startLine: 1, endLine: 5 });
check("Slice head lines 1-5 has 5 lines", sliceHead.matchedLines === 5);
check("Slice head starts with L1", sliceHead.content.startsWith("L1:"));

// Boundary Check: startLine > totalLines
const sliceOob = store.slice({ bufferId: bufId, startLine: 2000 });
check("Slice with startLine > totalLines returns error", Boolean(sliceOob.error));
check("Out-of-bounds error message mentions (1..1000)", sliceOob.error?.includes("1..1000") === true);
check("Out-of-bounds returns empty content", sliceOob.content === "");

// Boundary Check: startLine > endLine
const sliceInverted = store.slice({ bufferId: bufId, startLine: 50, endLine: 20 });
check("Slice with startLine > endLine returns error", Boolean(sliceInverted.error));

// Non-existent buffer
const sliceMissing = store.slice({ bufferId: "repl_buf_nonexistent" });
check("Slice on missing buffer returns error", Boolean(sliceMissing.error));

// --------------------------------------------------------------------------
// Test 4: Pattern Filtering (Regex & Plain Text)
// --------------------------------------------------------------------------
// Filter plain text
const filterPlain = store.filter({ bufferId: bufId, pattern: "Line 42:" });
check("Filter plain text finds Line 42", filterPlain.matchedLines === 1);
check("Filter result includes line number L42", filterPlain.content.includes("L42: Line 42:"));

// Filter regex
const filterRegex = store.filter({
  bufferId: bufId,
  pattern: "Line 10[0-2]:",
  isRegex: true,
});
check("Filter regex matches 3 lines (100, 101, 102)", filterRegex.matchedLines === 3);
check("Regex content includes L100, L101, L102", filterRegex.content.includes("L100:") && filterRegex.content.includes("L102:"));

// Filter with invalid regex (safe execution)
const filterInvalidRegex = store.filter({
  bufferId: bufId,
  pattern: "[unclosed-regex-bracket",
  isRegex: true,
});
check("Invalid regex returns safe error without crashing", Boolean(filterInvalidRegex.error));

// Filter with context lines
const filterCtx = store.filter({
  bufferId: bufId,
  pattern: "Line 50:",
  contextLines: 2,
});
// Line 50 with 2 lines before (48, 49) and 2 lines after (51, 52) = 5 lines total
check("Filter with contextLines=2 returns 5 lines", filterCtx.content.split("\n").length === 5);
check("Context includes L48 and L52", filterCtx.content.includes("L48:") && filterCtx.content.includes("L52:"));

// --------------------------------------------------------------------------
// Test 5: Head, Tail, and Summarize
// --------------------------------------------------------------------------
const headRes = store.head(bufId, 3);
check("Head returns 3 lines", headRes.matchedLines === 3);
check("Head starts at L1", headRes.content.startsWith("L1:"));

const tailRes = store.tail(bufId, 4);
check("Tail returns 4 lines", tailRes.matchedLines === 4);
check("Tail ends at L1000", tailRes.content.includes("L1000:"));

const summary = store.summarize(bufId);
check("Summarize returns valid summary object", summary !== null && summary.lineCount === 1000);
check("Summarize contains handle", summary?.handle === massiveResult.handle);

// --------------------------------------------------------------------------
// Test 6: Memory Budget & LRU Eviction Preserving Most Recent 10 Buffers
// --------------------------------------------------------------------------
// Create a store with a smaller budget to test LRU eviction deterministically:
// e.g. budget = 1.5MB, each item ~110KB
const smallBudgetStore = new ReplContextStore(1500 * 1024, 10);

const storedIds: string[] = [];
for (let i = 0; i < 15; i++) {
  const content = `Buffer ${i}: ` + "x".repeat(110 * 1024);
  const res = smallBudgetStore.store(content, `tool_${i}`);
  if (res.bufferId) {
    storedIds.push(res.bufferId);
  }
}

// Total buffers in store should not exceed budget, and must preserve at least 10 recent
check("Stored 15 buffers into small store", storedIds.length === 15);
check(
  "Store retains at least 10 buffers (minimum preservation invariant)",
  smallBudgetStore.getBufferCount() >= 10
);
// The most recent 10 buffers should still be present
const recent10 = storedIds.slice(5);
let allRecentRetained = true;
for (const id of recent10) {
  if (!smallBudgetStore.get(id)) {
    allRecentRetained = false;
    break;
  }
}
check("The 10 most recent buffers were preserved during eviction", allRecentRetained);

// --------------------------------------------------------------------------
// Test 7: Clear and Delete
// --------------------------------------------------------------------------
const toDelete = storedIds[storedIds.length - 1];
const deleted = smallBudgetStore.delete(toDelete);
check("Delete buffer returns true", deleted);
check("Deleted buffer cannot be retrieved", smallBudgetStore.get(toDelete) === undefined);

smallBudgetStore.clear();
check("Clear empties the store", smallBudgetStore.getBufferCount() === 0);
check("Clear resets totalBytes to 0", smallBudgetStore.getTotalBytes() === 0);

// --------------------------------------------------------------------------
// L2 regression: an in-place buffer UPDATE must not over-evict, and totalBytes
// must stay consistent (the prior size is removed BEFORE the eviction check).
// --------------------------------------------------------------------------
{
  const s = new ReplContextStore(REPL_THRESHOLD_BYTES * 5, 2);
  const big = (n: number) => "A".repeat(REPL_THRESHOLD_BYTES + 10) + n;
  for (let i = 0; i < 4; i++) s.store(big(i), `src${i}`);
  const beforeCount = s.getBufferCount();
  s.store(big(0), "src0-updated"); // in-place update of an existing buffer
  check("L2: in-place update does not over-evict other buffers", s.getBufferCount() === beforeCount);
  check("L2: totalBytes stays consistent after in-place update", s.getTotalBytes() > 0);
}


// --------------------------------------------------------------------------
// WA1: sol-pi observationPack threshold linkage
// --------------------------------------------------------------------------
{
  const t = getObservationPackThresholds(DEFAULT_CONFIG);
  check("WA1: pack threshold comes from sol-pi config (10240)", t.packMinBytes === 10240);
  check("WA1: repl intercept threshold stays 100KiB", t.replInterceptBytes === REPL_THRESHOLD_BYTES && REPL_THRESHOLD_BYTES === 102400);
  check("WA1: pack fires before repl intercept (10KiB < 100KiB)", t.packsBeforeIntercept === true);
  const custom = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  custom.observationPackConfig.minBytesThreshold = 200000;
  const t2 = getObservationPackThresholds(custom);
  check("WA1: custom pack threshold above repl threshold is reported", t2.packMinBytes === 200000 && t2.packsBeforeIntercept === false);
}

// --------------------------------------------------------------------------
// WA4: rlm_map_reduce -> runBoundedRlmChunkQuery
// --------------------------------------------------------------------------
{
  const work = fs.mkdtempSync(path.join(os.tmpdir(), "rlmtest-"));
  fs.chmodSync(work, 0o700);
  const ctxFile = path.join(work, "ctx.log");
  fs.writeFileSync(ctxFile, "alpha line\nERROR boom\nbeta line\nerror again\n");
  const ledger = path.join(work, "ledger");
  const base = { query: "error", contextFile: ctxFile, ledgerDir: ledger };
  const throws = (o: any): boolean => {
    try {
      runBoundedRlmChunkQuery(o);
      return false;
    } catch {
      return true;
    }
  };
  // Validation must reject BEFORE the script is spawned (TS guard, not just the script's own checks).
  const rejects = (o: any): boolean => {
    let spawned = 0;
    const spy = () => {
      spawned++;
      return { status: 0, stdout: "{}", stderr: "" } as any;
    };
    try {
      runBoundedRlmChunkQuery(o, spy as any);
      return false;
    } catch {
      return spawned === 0;
    }
  };

  check("RLM: constants are depth 1 / iterations 12", RLM_MAX_DEPTH === 1 && RLM_MAX_ITERATIONS === 12);

  // happy path (dry-run needs no backend)
  const ok = runBoundedRlmChunkQuery({ ...base, dryRun: true });
  check("RLM: dry-run succeeds with depth 1", ok.ok === true && ok.result?.depth === 1 && ok.result?.dry_run === true);
  check("RLM: ledger written", fs.existsSync(path.join(ledger, "rlm-trace.jsonl")));

  // depth boundary
  const d1 = runBoundedRlmChunkQuery({ ...base, dryRun: true, maxDepth: 1 });
  check("RLM: maxDepth=1 accepted", d1.ok === true);
  check("RLM: maxDepth=2 rejected (fail-closed)", rejects({ ...base, dryRun: true, maxDepth: 2 }));
  check("RLM: maxDepth=0 rejected", rejects({ ...base, dryRun: true, maxDepth: 0 }));
  check("RLM: maxDepth=1.5 rejected", rejects({ ...base, dryRun: true, maxDepth: 1.5 }));
  check("RLM: maxDepth='1' (string) rejected", rejects({ ...base, dryRun: true, maxDepth: "1" }));

  // iteration boundary
  const i12 = runBoundedRlmChunkQuery({ ...base, dryRun: true, maxIterations: 12 });
  check("RLM: maxIterations=12 accepted", i12.ok === true);
  check("RLM: maxIterations=13 rejected (fail-closed)", rejects({ ...base, dryRun: true, maxIterations: 13 }));
  check("RLM: maxIterations=0 rejected", rejects({ ...base, dryRun: true, maxIterations: 0 }));
  check("RLM: maxIterations=NaN rejected", rejects({ ...base, dryRun: true, maxIterations: NaN }));
  check("RLM: maxIterations=Infinity rejected", rejects({ ...base, dryRun: true, maxIterations: Infinity }));

  // input validation
  check("RLM: empty query rejected", rejects({ ...base, query: "" }));
  check("RLM: multi-line query rejected", rejects({ ...base, query: "a\nb" }));
  check("RLM: NUL in query rejected", rejects({ ...base, query: "a\0b" }));
  check("RLM: relative contextFile rejected", rejects({ ...base, contextFile: "ctx.log" }));
  check("RLM: contextFile with NUL rejected", rejects({ ...base, contextFile: ctxFile + "\0x" }));
  check("RLM: missing contextFile rejected", rejects({ ...base, contextFile: path.join(work, "nope") }));
  check("RLM: directory contextFile rejected", rejects({ ...base, contextFile: work }));
  const link = path.join(work, "link.log");
  fs.symlinkSync(ctxFile, link);
  check("RLM: symlink contextFile rejected", rejects({ ...base, contextFile: link }));
  check("RLM: model starting with '-' rejected", rejects({ ...base, model: "--evil" }));
  check("RLM: model with shell metachar rejected", rejects({ ...base, model: "m;ls" }));
  check("RLM: relative ledgerDir rejected", rejects({ ...base, ledgerDir: "ledger" }));
  check("RLM: chunkBytes=0 rejected", rejects({ ...base, chunkBytes: 0 }));
  check("RLM: chunkBytes too large rejected", rejects({ ...base, chunkBytes: 64 * 1024 * 1024 + 1 }));
  check("RLM: unknown mode rejected", rejects({ ...base, mode: "rlm_recursive" }));
  check("RLM: nonexistent script rejected", rejects({ ...base, scriptPath: path.join(work, "no.py") }));

  // argv, no shell
  {
    let seen: any;
    const fake = (cmd: string, args: string[], opts: any) => {
      seen = { cmd, args, opts };
      return { status: 0, stdout: JSON.stringify({ depth: 1 }) + "\n", stderr: "", error: undefined } as any;
    };
    const evil = "$(touch PWNED); `id` * | -x";
    runBoundedRlmChunkQuery({ ...base, query: evil, dryRun: true }, fake as any);
    check("RLM: spawn uses argv array without shell", Array.isArray(seen.args) && !seen.opts.shell);
    check("RLM: python isolated flags -I -B first", seen.args[0] === "-I" && seen.args[1] === "-B");
    check("RLM: query passed as single literal --query=<value> arg", seen.args.includes("--query=" + evil));
    check("RLM: --max-depth=1 passed", seen.args.includes("--max-depth=1"));
    check("RLM: --json passed", seen.args.includes("--json"));
    process.env.ANTHROPIC_API_KEY_T2PROBE = "secret";
    runBoundedRlmChunkQuery({ ...base, dryRun: true }, fake as any);
    check("RLM: env is allowlisted (no secrets leak)", !("ANTHROPIC_API_KEY_T2PROBE" in seen.opts.env));
    delete process.env.ANTHROPIC_API_KEY_T2PROBE;
  }
  // exit status of the script is honoured even when stdout looks valid
  {
    const bad = () => ({ status: 3, stdout: JSON.stringify({ depth: 1 }), stderr: "boom" }) as any;
    let threw = false;
    try {
      runBoundedRlmChunkQuery({ ...base, dryRun: true }, bad as any);
    } catch {
      threw = true;
    }
    check("RLM: non-zero script exit is an error even with valid JSON stdout", threw);
  }
  // real run: the shell metacharacters must stay literal (ledger hash == sha256 of literal query)
  {
    const evil = "$(touch " + path.join(work, "PWNED") + "); `id` *";
    const r = runBoundedRlmChunkQuery({ ...base, query: evil, dryRun: true });
    const expect = createHash("sha256").update(evil).digest("hex");
    check("RLM: real run keeps query literal (sha256 matches)", r.ok === true && r.result?.query_sha256 === expect);
    check("RLM: no shell expansion side effect", !fs.existsSync(path.join(work, "PWNED")));
  }
  // non-zero exit from the script -> error (fail-closed), e.g. non-dry-run without backend
  check("RLM: script failure (no backend) surfaces as error", throws({ ...base, env: { RLM_BACKEND: "" } }));
  // stub backend produces a real map-reduce result
  {
    const r = runBoundedRlmChunkQuery({ ...base, env: { RLM_BACKEND: "stub" } });
    check("RLM: stub backend map-reduce counts hits", r.ok === true && r.result?.total_hits === 2);
  }
  fs.rmSync(work, { recursive: true, force: true });
}

// --------------------------------------------------------------------------
// Summary
// --------------------------------------------------------------------------
// L1 regression: byte truncation never splits a multibyte UTF-8 character.
{
  const buf = Buffer.from("L1: " + "あ".repeat(20), "utf-8"); // each あ = 3 bytes
  const cut9 = sliceUtf8ToBytes(buf, 9);
  check("L1: UTF-8 byte truncation drops partial char (no U+FFFD)", !cut9.includes("�") && cut9 === "L1: あ");
  check("L1: UTF-8 truncation at an exact boundary keeps the whole char", sliceUtf8ToBytes(buf, 10) === "L1: ああ");
  check("L1: ASCII truncation is exact", sliceUtf8ToBytes(Buffer.from("hello"), 3) === "hel");
  check("L1: maxBytes >= length returns whole string", sliceUtf8ToBytes(Buffer.from("hi"), 100) === "hi");
}

console.log(`\nrepl-context-core: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
