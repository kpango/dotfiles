/**
 * Unit Tests for Idempotent Session Journal Core
 *
 * Tests deterministic SHA-256 key computation (canonical JSON key order invariance),
 * atomic JSONL journal appending, replay bypass for COMPLETED calls, and re-execution
 * on FAILED/PENDING calls.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  computeIdempotencyKey,
  canonicalizeJson,
  computeParamsHash,
  SessionJournal,
} from "./session-journal-core";

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

function eq<T>(name: string, actual: T, expected: T, msg?: string) {
  const ok = actual === expected;
  check(name, ok, msg || `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

// 1. Canonical JSON sorting: key order invariance
const objA = { b: 2, a: 1, c: { y: "test", x: 10 } };
const objB = { a: 1, c: { x: 10, y: "test" }, b: 2 };
eq(
  "canonicalizeJson sorts keys at root and nested levels",
  canonicalizeJson(objA),
  canonicalizeJson(objB)
);

// 2. Deterministic SHA-256 idempotency key: key order invariance
const key1 = computeIdempotencyKey("bash", { cmd: "git status", timeout: 1000 }, "/home/repo");
const key2 = computeIdempotencyKey("bash", { timeout: 1000, cmd: "git status" }, "/home/repo");
eq("computeIdempotencyKey is invariant to object key order", key1, key2);

// 3. Sensitivity to toolName, params, and cwd
const keyDiffTool = computeIdempotencyKey("read_file", { timeout: 1000, cmd: "git status" }, "/home/repo");
check("Different tool yields different key", key1 !== keyDiffTool);

const keyDiffParams = computeIdempotencyKey("bash", { cmd: "git diff" }, "/home/repo");
check("Different params yield different key", key1 !== keyDiffParams);

const keyDiffCwd = computeIdempotencyKey("bash", { cmd: "git status", timeout: 1000 }, "/other/repo");
check("Different cwd yields different key", key1 !== keyDiffCwd);

// 4. Circular reference handling in canonicalizeJson
const circularObj: any = { name: "loop" };
circularObj.self = circularObj;
let circularJson = "";
try {
  circularJson = canonicalizeJson(circularObj);
  check("Circular references handled safely without throwing", circularJson.includes("[Circular]"));
} catch (err: any) {
  check("Circular references handled safely without throwing", false, err.message);
}

// 5. Journal lifecycle with temporary file
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-journal-test-"));
const testJournalPath = path.join(tempDir, "test-session.jsonl");

try {
  const journal = new SessionJournal(testJournalPath);

  // Initial state is empty
  const initialHistory = journal.getHistory();
  eq("New journal has 0 entries", initialHistory.length, 0);
  const initialStatus = journal.getStatus();
  eq("New journal totalEntries is 0", initialStatus.totalEntries, 0);

  // Record tool start (PENDING)
  const toolCall1 = {
    toolName: "bash",
    params: { command: "make test" },
    cwd: "/workspace",
    sessionId: "sess-1",
  };
  const startEntry = journal.recordStart(toolCall1);
  const call1Key = startEntry.idempotencyKey;

  check("recordStart returns PENDING entry", startEntry.status === "PENDING");
  check("idempotencyKey is populated", Boolean(call1Key) && call1Key.length === 64);

  // Replay check during PENDING: must NOT replay (replayed = false)
  const pendingReplay = journal.checkReplay(call1Key);
  check("PENDING tool execution does not trigger replay", pendingReplay.replayed === false);

  // Record tool completion (COMPLETED)
  const executionOutput = { stdout: "10 tests passed", exitCode: 0 };
  journal.recordCompletion(call1Key, executionOutput, 0);

  // Replay check after COMPLETED: MUST replay (replayed = true)
  const completedReplay = journal.checkReplay(call1Key);
  check("COMPLETED tool execution triggers replay bypass", completedReplay.replayed === true);
  eq("Replayed result matches cached execution output", completedReplay.result?.stdout, "10 tests passed");

  // Record a failed tool execution
  const failedCall = {
    toolName: "edit",
    params: { file: "missing.go" },
    cwd: "/workspace",
    sessionId: "sess-1",
  };
  const failStart = journal.recordStart(failedCall);
  const failKey = failStart.idempotencyKey;
  journal.recordFailure(failKey, "File not found: missing.go", 1);

  // Replay check after FAILED: must NOT replay (replayed = false, allowing re-execution)
  const failedReplay = journal.checkReplay(failKey);
  check("FAILED tool execution does not trigger replay bypass", failedReplay.replayed === false);

  // Status checks
  const status = journal.getStatus();
  eq("Status reports totalEntries = 4 (2 starts + 1 complete + 1 fail)", status.totalEntries, 4);
  eq("Status reports completed = 1", status.completed, 1);
  eq("Status reports failed = 1", status.failed, 1);
  eq("Status reports uniqueKeys = 2", status.uniqueKeys, 2);

  // Test clear()
  journal.clear();
  eq("After clear, totalEntries is 0", journal.getStatus().totalEntries, 0);
  eq("After clear, checkReplay returns false", journal.checkReplay(call1Key).replayed, false);
} finally {
  // Clean up temporary directory
  try {
    fs.rmSync(tempDir, { recursive: true, force: true });
  } catch {
    // Ignore cleanup errors
  }
}

console.log(`\nsession-journal.test: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
