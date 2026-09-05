/**
 * Unit Tests for GrokBot Persistent Daemon Session Core
 *
 * Verifies ID generation uniqueness, state persistence and reconciliation,
 * PID liveness detection, process spawning, termination state transitions,
 * active daemon scanning, log tailing, Blackboard IPC event emission,
 * and error resilience.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  DaemonSessionRecord,
  SpawnDaemonOptions,
  generateDaemonId,
  getDefaultDaemonDir,
  ensureDirectory,
  checkDaemonLiveness,
  syncDaemonStateByPid,
  spawnDaemonProcess,
  terminateDaemonProcess,
  listActiveDaemons,
  readDaemonLog,
  getDaemonDetails,
  emitMeshProgress,
} from "./daemon-session-core";

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

// ----------------------------------------------------------------------------
// 1. generateDaemonId Tests
// ----------------------------------------------------------------------------
const id1 = generateDaemonId();
check("generateDaemonId returns non-empty string", Boolean(id1) && typeof id1 === "string");
check("generateDaemonId starts with daemon- prefix", id1.startsWith("daemon-"));

const ids = new Set<string>();
for (let i = 0; i < 100; i++) {
  ids.add(generateDaemonId());
}
eq("generateDaemonId generates 100 unique IDs across fast iterations", ids.size, 100);

// ----------------------------------------------------------------------------
// 2. Directory and Liveness Tests
// ----------------------------------------------------------------------------
const defaultDir = getDefaultDaemonDir();
check("getDefaultDaemonDir ends in sessions/daemon", defaultDir.endsWith(path.join("sessions", "daemon")));

check("checkDaemonLiveness returns true for current process (process.pid)", checkDaemonLiveness(process.pid));
check("checkDaemonLiveness returns false for non-existent PID (99999999)", checkDaemonLiveness(99999999) === false);
check("checkDaemonLiveness returns false for PID 0", checkDaemonLiveness(0) === false);
check("checkDaemonLiveness returns false for negative PID", checkDaemonLiveness(-42) === false);
check("checkDaemonLiveness returns false for NaN", checkDaemonLiveness(NaN) === false);

// ----------------------------------------------------------------------------
// 3. Isolated Lifecycle Tests in Temporary Directory
// ----------------------------------------------------------------------------
const testTempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-daemon-test-"));

try {
  ensureDirectory(testTempDir);
  check("ensureDirectory succeeds on existing/new directory", fs.existsSync(testTempDir));

  // Test 3.1: spawnDaemonProcess with mock spawnFn
  let unrefCalled = false;
  const mockSpawnFn = (cmd: string, args: string[], opts: any) => {
    fs.writeFileSync(opts.logPath, "Mock daemon started\nRunning task iteration 1\n", "utf-8");
    return {
      pid: process.pid,
      unref: () => {
        unrefCalled = true;
      },
    };
  };

  const spawnOptions: SpawnDaemonOptions = {
    objective: "Run autonomous audit loop",
    cwd: "/workspace/project",
    model: "gemini-3.8-flash",
    daemonDir: testTempDir,
    spawnFn: mockSpawnFn,
  };

  const record = spawnDaemonProcess(spawnOptions);

  eq("spawnDaemonProcess returns record with objective", record.objective, "Run autonomous audit loop");
  eq("spawnDaemonProcess returns record with cwd", record.cwd, "/workspace/project");
  eq("spawnDaemonProcess returns record with model", record.model, "gemini-3.8-flash");
  eq("spawnDaemonProcess status is RUNNING", record.status, "RUNNING");
  eq("spawnDaemonProcess pid is process.pid", record.pid, process.pid);
  check("spawnDaemonProcess calls child.unref()", unrefCalled);

  check("State file exists on disk", fs.existsSync(record.statePath));
  check("Log file exists on disk", fs.existsSync(record.logPath));

  const loadedState = JSON.parse(fs.readFileSync(record.statePath, "utf-8")) as DaemonSessionRecord;
  eq("Persisted state daemonId matches returned record", loadedState.daemonId, record.daemonId);
  eq("Persisted state status matches returned record", loadedState.status, "RUNNING");

  // Test 3.2: readDaemonLog
  const initialLog = readDaemonLog(record.logPath, 10);
  check("readDaemonLog reads content from log file", initialLog.includes("Mock daemon started"));

  const missingLog = readDaemonLog(path.join(testTempDir, "non-existent.log"));
  check("readDaemonLog handles non-existent log gracefully", missingLog.includes("does not exist"));

  // Test 3.3: getDaemonDetails
  const details = getDaemonDetails(record.daemonId, testTempDir);
  check("getDaemonDetails returns non-null record for valid daemonId", details.record !== null);
  eq("getDaemonDetails returns matching record ID", details.record?.daemonId, record.daemonId);
  check("getDaemonDetails includes logTail", details.logTail.includes("Mock daemon started"));

  const missingDetails = getDaemonDetails("daemon-non-existent", testTempDir);
  check("getDaemonDetails returns null record for non-existent daemonId", missingDetails.record === null);

  // Test 3.4: syncDaemonStateByPid
  const mockDeadPid = 888888;
  const deadRecord: DaemonSessionRecord = {
    daemonId: "daemon-mock-dead",
    pid: mockDeadPid,
    objective: "Dead background task",
    cwd: "/workspace",
    status: "RUNNING",
    startedAt: Date.now() - 10000,
    logPath: path.join(testTempDir, "daemon-mock-dead.log"),
    statePath: path.join(testTempDir, "daemon-mock-dead.json"),
  };
  fs.writeFileSync(deadRecord.statePath, JSON.stringify(deadRecord, null, 2), "utf-8");

  syncDaemonStateByPid(mockDeadPid, "STOPPED", testTempDir);
  const reloadedDead = JSON.parse(fs.readFileSync(deadRecord.statePath, "utf-8")) as DaemonSessionRecord;
  eq("syncDaemonStateByPid updates status to STOPPED", reloadedDead.status, "STOPPED");
  check("syncDaemonStateByPid sets completedAt", Boolean(reloadedDead.completedAt));

  // Test 3.5: terminateDaemonProcess
  const termResult = terminateDaemonProcess(mockDeadPid, "SIGTERM", testTempDir);
  check("terminateDaemonProcess succeeds for mock PID", termResult === true);
  check("terminateDaemonProcess returns false for invalid PID 0", terminateDaemonProcess(0) === false);

  // Test 3.6: listActiveDaemons
  // Add a completed record and an active dead record that needs reconciliation
  const reconcilePid = 999999;
  const unverifiedDeadRecord: DaemonSessionRecord = {
    daemonId: "daemon-needs-reconcile",
    pid: reconcilePid,
    objective: "Unreconciled task",
    cwd: "/workspace",
    status: "RUNNING",
    startedAt: Date.now() - 5000,
    logPath: path.join(testTempDir, "daemon-needs-reconcile.log"),
    statePath: path.join(testTempDir, "daemon-needs-reconcile.json"),
  };
  fs.writeFileSync(unverifiedDeadRecord.statePath, JSON.stringify(unverifiedDeadRecord, null, 2), "utf-8");

  // Inject a malformed file to test resilience
  fs.writeFileSync(path.join(testTempDir, "corrupt.json"), "{ not-valid-json ]", "utf-8");

  const listedDaemons = listActiveDaemons(testTempDir);
  check("listActiveDaemons returns an array", Array.isArray(listedDaemons));
  check("listActiveDaemons ignores corrupted JSON without crashing", listedDaemons.length >= 3);

  const reconciled = listedDaemons.find((d) => d.daemonId === "daemon-needs-reconcile");
  check("listActiveDaemons finds dead RUNNING session", Boolean(reconciled));
  eq("listActiveDaemons reconciles dead RUNNING session to COMPLETED", reconciled?.status, "COMPLETED");

  // Test 3.7: emitMeshProgress
  emitMeshProgress(record, "verification", { result: "PASS", tests: 42 });
  const blackboardPath = path.join(os.homedir(), ".pi", "agent", "blackboard", "blackboard.jsonl");
  check("emitMeshProgress appends to blackboard.jsonl", fs.existsSync(blackboardPath));

  if (fs.existsSync(blackboardPath)) {
    const bbContent = fs.readFileSync(blackboardPath, "utf-8");
    check("Blackboard contains daemon record ID", bbContent.includes(record.daemonId));
    check("Blackboard contains verification topic", bbContent.includes("verification"));
  }

  // Test 3.8: Non-existent directory handling in listActiveDaemons
  const emptyList = listActiveDaemons(path.join(testTempDir, "does-not-exist"));
  eq("listActiveDaemons returns [] for missing directory", emptyList.length, 0);

} finally {
  try {
    fs.rmSync(testTempDir, { recursive: true, force: true });
  } catch {
    // Ignore cleanup error
  }
}

console.log(`\ndaemon-session.test: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
