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
} from "./repl-context-core";

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
// Summary
// --------------------------------------------------------------------------
console.log(`\nrepl-context-core: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
