/**
 * GrokBot-Style Persistent Daemon Session Core for Pi Coding Agent
 *
 * Provides headless detached daemon execution surviving TTY disconnects,
 * process liveness checking, atomic state persistence, graceful termination,
 * and P2P Blackboard/Mesh event publication.
 */

import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

export interface DaemonSessionRecord {
  daemonId: string;
  pid: number;
  objective: string;
  cwd: string;
  model?: string;
  status: "STARTING" | "RUNNING" | "COMPLETED" | "FAILED" | "STOPPED";
  startedAt: number;
  completedAt?: number;
  exitCode?: number;
  logPath: string;
  statePath: string;
}

export interface SpawnDaemonOptions {
  objective: string;
  cwd: string;
  model?: string;
  daemonDir?: string;
  detached?: boolean;
  spawnFn?: (
    command: string,
    args: string[],
    options: any
  ) => { pid?: number; unref?: () => void };
  command?: string;
  args?: string[];
}

/**
 * Return default directory for daemon state and log files:
 * ~/.pi/agent/sessions/daemon
 */
export function getDefaultDaemonDir(): string {
  return path.join(os.homedir(), ".pi", "agent", "sessions", "daemon");
}

/**
 * Recursively ensure a directory exists.
 */
export function ensureDirectory(dir: string): void {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

/**
 * Generate a unique daemon ID prefixed with "daemon-".
 */
export function generateDaemonId(): string {
  const ts = Date.now();
  const rand = randomBytes(4).toString("hex");
  return `daemon-${ts}-${rand}`;
}

/**
 * Safely check if a process is alive using process.kill(pid, 0).
 * Handles ESRCH (process not found) vs active / EPERM (process exists).
 */
export function checkDaemonLiveness(pid: number): boolean {
  if (!pid || typeof pid !== "number" || isNaN(pid) || pid <= 0) {
    return false;
  }
  try {
    process.kill(pid, 0);
    return true;
  } catch (err: any) {
    if (err.code === "ESRCH") {
      return false;
    }
    if (err.code === "EPERM") {
      return true;
    }
    return false;
  }
}

/**
 * Update the state file of a daemon matching PID to a new status.
 */
export function syncDaemonStateByPid(
  pid: number,
  status: "STOPPED" | "COMPLETED" | "FAILED",
  daemonDir?: string
): void {
  const dir = daemonDir || getDefaultDaemonDir();
  if (!fs.existsSync(dir)) return;

  try {
    const files = fs.readdirSync(dir);
    for (const file of files) {
      if (!file.endsWith(".json")) continue;
      const filePath = path.join(dir, file);
      try {
        const content = fs.readFileSync(filePath, "utf-8");
        const record = JSON.parse(content) as DaemonSessionRecord;
        if (
          record &&
          record.pid === pid &&
          (record.status === "RUNNING" || record.status === "STARTING")
        ) {
          record.status = status;
          record.completedAt = Date.now();
          fs.writeFileSync(filePath, JSON.stringify(record, null, 2), "utf-8");
        }
      } catch {
        // Skip malformed records
      }
    }
  } catch {
    // Ignore directory read errors
  }
}

/**
 * Spawn a persistent detached background daemon process.
 * Writes initial state to statePath and redirects stdout/stderr to logPath.
 */
export function spawnDaemonProcess(
  options: SpawnDaemonOptions
): DaemonSessionRecord {
  const daemonDir = options.daemonDir || getDefaultDaemonDir();
  ensureDirectory(daemonDir);

  const daemonId = generateDaemonId();
  const logPath = path.join(daemonDir, `${daemonId}.log`);
  const statePath = path.join(daemonDir, `${daemonId}.json`);

  const cmd = options.command || "pi";
  const cmdArgs = options.args || [
    "--prompt",
    options.objective,
    ...(options.model ? ["--model", options.model] : []),
  ];

  let pid = 0;
  let childInstance: any = null;

  if (options.spawnFn) {
    // Injectable spawnFn for deterministic testing
    childInstance = options.spawnFn(cmd, cmdArgs, {
      cwd: options.cwd,
      detached: options.detached ?? true,
      logPath,
      statePath,
    });
    pid = childInstance?.pid ?? process.pid;
    if (childInstance?.unref) {
      childInstance.unref();
    }
  } else {
    // Real background process spawn
    const logFd = fs.openSync(logPath, "a");
    try {
      childInstance = spawn(cmd, cmdArgs, {
        cwd: options.cwd,
        detached: options.detached !== false,
        stdio: ["ignore", logFd, logFd],
        env: {
          ...process.env,
          PI_DAEMON_ID: daemonId,
          PI_DAEMON_LOG: logPath,
        },
      });
      pid = childInstance.pid ?? 0;
      if (options.detached !== false && childInstance?.unref) {
        childInstance.unref();
      }
    } finally {
      try {
        fs.closeSync(logFd);
      } catch {
        // Ignore file close error
      }
    }
  }

  const record: DaemonSessionRecord = {
    daemonId,
    pid,
    objective: options.objective,
    cwd: options.cwd,
    model: options.model,
    status: "RUNNING",
    startedAt: Date.now(),
    logPath,
    statePath,
  };

  fs.writeFileSync(statePath, JSON.stringify(record, null, 2), "utf-8");

  // Emit initial mesh event
  emitMeshProgress(record, "daemon", { event: "DAEMON_SPAWNED" });

  return record;
}

/**
 * Terminate a background daemon process by PID and update its state record.
 */
export function terminateDaemonProcess(
  pid: number,
  signal: NodeJS.Signals = "SIGTERM",
  daemonDir?: string
): boolean {
  if (!pid || typeof pid !== "number" || isNaN(pid) || pid <= 0) {
    return false;
  }

  const isAlive = checkDaemonLiveness(pid);
  if (!isAlive) {
    syncDaemonStateByPid(pid, "STOPPED", daemonDir);
    return true;
  }

  try {
    process.kill(pid, signal);
  } catch (err: any) {
    if (err.code === "ESRCH") {
      syncDaemonStateByPid(pid, "STOPPED", daemonDir);
      return true;
    }
    return false;
  }

  syncDaemonStateByPid(pid, "STOPPED", daemonDir);
  return true;
}

/**
 * List all daemon records in daemonDir.
 * Checks liveness of RUNNING/STARTING processes and updates state if exited.
 */
export function listActiveDaemons(daemonDir?: string): DaemonSessionRecord[] {
  const dir = daemonDir || getDefaultDaemonDir();
  if (!fs.existsSync(dir)) {
    return [];
  }

  const records: DaemonSessionRecord[] = [];
  try {
    const files = fs.readdirSync(dir);
    for (const file of files) {
      if (!file.endsWith(".json")) continue;
      const filePath = path.join(dir, file);
      try {
        const content = fs.readFileSync(filePath, "utf-8");
        const record = JSON.parse(content) as DaemonSessionRecord;
        if (!record || !record.daemonId) continue;

        if (record.status === "RUNNING" || record.status === "STARTING") {
          const alive = checkDaemonLiveness(record.pid);
          if (!alive) {
            record.status =
              record.exitCode === 0
                ? "COMPLETED"
                : record.exitCode !== undefined
                ? "FAILED"
                : "COMPLETED";
            record.completedAt = record.completedAt || Date.now();
            try {
              fs.writeFileSync(filePath, JSON.stringify(record, null, 2), "utf-8");
            } catch {
              // Ignore write error
            }
          }
        }
        records.push(record);
      } catch {
        // Skip malformed records
      }
    }
  } catch {
    return [];
  }

  records.sort((a, b) => b.startedAt - a.startedAt);
  return records;
}

/**
 * Read the last N lines of a daemon log file.
 */
export function readDaemonLog(logPath: string, maxLines = 50): string {
  if (!fs.existsSync(logPath)) {
    return "(Log file does not exist yet)";
  }
  try {
    const content = fs.readFileSync(logPath, "utf-8");
    const lines = content.split("\n");
    if (lines.length <= maxLines) {
      return content;
    }
    return lines.slice(-maxLines).join("\n");
  } catch (err: any) {
    return `Error reading log file: ${err.message}`;
  }
}

/**
 * Get detailed status of a specific daemon by ID.
 */
export function getDaemonDetails(
  daemonId: string,
  daemonDir?: string
): { record: DaemonSessionRecord | null; logTail: string } {
  const dir = daemonDir || getDefaultDaemonDir();
  const statePath = path.join(dir, `${daemonId}.json`);

  if (!fs.existsSync(statePath)) {
    return { record: null, logTail: `Daemon session not found: ${daemonId}` };
  }

  try {
    const content = fs.readFileSync(statePath, "utf-8");
    const record = JSON.parse(content) as DaemonSessionRecord;

    if (record.status === "RUNNING" || record.status === "STARTING") {
      const alive = checkDaemonLiveness(record.pid);
      if (!alive) {
        record.status = "COMPLETED";
        record.completedAt = record.completedAt || Date.now();
        try {
          fs.writeFileSync(statePath, JSON.stringify(record, null, 2), "utf-8");
        } catch {
          // Ignore write error
        }
      }
    }

    const logTail = readDaemonLog(record.logPath, 30);
    return { record, logTail };
  } catch (err: any) {
    return { record: null, logTail: `Error reading daemon state: ${err.message}` };
  }
}

/**
 * Emit a progress event from the daemon onto the Blackboard / P2P Mesh.
 * Writes JSONL to blackboard stream and fails open gracefully.
 */
export function emitMeshProgress(
  daemonRecord: DaemonSessionRecord,
  topic: string,
  payload: any
): void {
  try {
    const event = {
      id: `mesh-${Date.now()}-${randomBytes(3).toString("hex")}`,
      timestamp: Date.now(),
      topic,
      sender: {
        id: daemonRecord.daemonId,
        role: "daemon",
        pid: daemonRecord.pid,
      },
      correlationId: daemonRecord.daemonId,
      payload: {
        daemonId: daemonRecord.daemonId,
        objective: daemonRecord.objective,
        status: daemonRecord.status,
        logPath: daemonRecord.logPath,
        ...(typeof payload === "object" && payload !== null
          ? payload
          : { data: payload }),
      },
    };

    const line = JSON.stringify(event) + "\n";

    // Primary blackboard path
    const blackboardDir = path.join(os.homedir(), ".pi", "agent", "blackboard");
    ensureDirectory(blackboardDir);
    const blackboardPath = path.join(blackboardDir, "blackboard.jsonl");

    fs.appendFileSync(blackboardPath, line, "utf-8");

    // Optional relay stream path
    const relayDir = path.join(os.homedir(), ".pi", "agent", "relay", "blackboard");
    if (fs.existsSync(relayDir)) {
      const streamPath = path.join(relayDir, `${daemonRecord.daemonId}.jsonl`);
      fs.appendFileSync(streamPath, line, "utf-8");
    }
  } catch {
    // Fail open gracefully
  }
}
