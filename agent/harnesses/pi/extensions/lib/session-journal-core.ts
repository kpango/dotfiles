/**
 * Idempotent Tool Journal Core for Pi Coding Agent
 *
 * Provides DeepSeekHarness-style idempotent tool journals, deterministic SHA-256
 * key computation with canonical JSON serialization, and replay checking to
 * prevent unintended duplicate executions and side-effects.
 */

import { createHash } from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";

export type JournalEntryStatus = "PENDING" | "COMPLETED" | "FAILED";

export interface ToolJournalEntry {
  idempotencyKey: string;
  sessionId: string;
  toolName: string;
  canonicalParamsHash: string;
  params: any;
  cwd: string;
  status: JournalEntryStatus;
  startedAt: number;
  completedAt?: number;
  exitCode?: number;
  result?: any;
  error?: string;
}

export interface ReplayCheckResult {
  replayed: boolean;
  result?: any;
  entry?: ToolJournalEntry;
}

/**
 * Recursively canonicalize any JavaScript value into a deterministic JSON string.
 * Keys in objects are sorted alphabetically at all nesting depths.
 * Circular references are safely replaced with `"[Circular]"`.
 */
export function canonicalizeJson(obj: unknown, seen = new WeakSet()): string {
  if (obj === null || obj === undefined) {
    return JSON.stringify(null);
  }

  const type = typeof obj;
  if (type === "number" || type === "boolean" || type === "string") {
    return JSON.stringify(obj);
  }

  if (type !== "object") {
    return JSON.stringify(String(obj));
  }

  if (seen.has(obj as object)) {
    return '"[Circular]"';
  }
  seen.add(obj as object);

  if (Array.isArray(obj)) {
    const items = obj.map((item) => canonicalizeJson(item, seen));
    return `[${items.join(",")}]`;
  }

  const keys = Object.keys(obj as Record<string, unknown>).sort();
  const pairs = keys.map((key) => {
    const val = (obj as Record<string, unknown>)[key];
    return `${JSON.stringify(key)}:${canonicalizeJson(val, seen)}`;
  });

  return `{${pairs.join(",")}}`;
}

/**
 * Compute a deterministic SHA-256 idempotency key for a tool execution.
 * Key order in `params` is canonically sorted so semantic duplicates always match.
 */
export function computeIdempotencyKey(toolName: string, params: unknown, cwd: string): string {
  const canonicalParams = canonicalizeJson(params);
  const normalizedCwd = cwd ? path.normalize(cwd) : "";
  const payload = `${toolName}:${canonicalParams}:${normalizedCwd}`;
  return createHash("sha256").update(payload, "utf8").digest("hex");
}

/**
 * Compute SHA-256 hash of canonical params alone.
 */
export function computeParamsHash(params: unknown): string {
  return createHash("sha256").update(canonicalizeJson(params), "utf8").digest("hex");
}

/**
 * Append-only JSONL Tool Journal with replay prevention and atomic append.
 */
export class SessionJournal {
  private readonly journalFilePath: string;
  private readonly lockFilePath: string;

  constructor(journalFilePath: string) {
    this.journalFilePath = path.resolve(journalFilePath);
    this.lockFilePath = `${this.journalFilePath}.lock`;
    this.ensureDirectoryExists();
  }

  private ensureDirectoryExists(): void {
    const dir = path.dirname(this.journalFilePath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  }

  /**
   * Acquire a cooperative file lock for atomic journal operations.
   */
  private acquireLock(maxWaitMs = 1500, pollIntervalMs = 25): boolean {
    const start = Date.now();
    while (Date.now() - start < maxWaitMs) {
      try {
        const fd = fs.openSync(this.lockFilePath, "wx");
        fs.closeSync(fd);
        return true;
      } catch (err: any) {
        if (err.code === "EEXIST") {
          // Check for stale lock (older than 5 seconds)
          try {
            const stat = fs.statSync(this.lockFilePath);
            if (Date.now() - stat.mtimeMs > 5000) {
              fs.unlinkSync(this.lockFilePath);
              continue;
            }
          } catch {
            // Lock was removed concurrently
            continue;
          }
          Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, pollIntervalMs);
        } else {
          return false;
        }
      }
    }
    return false;
  }

  /**
   * Release the file lock.
   */
  private releaseLock(): void {
    try {
      if (fs.existsSync(this.lockFilePath)) {
        fs.unlinkSync(this.lockFilePath);
      }
    } catch {
      // Ignore errors releasing lock
    }
  }

  /**
   * Append an entry to the JSONL file with locking.
   */
  private appendEntry(entry: ToolJournalEntry): void {
    this.ensureDirectoryExists();
    const line = JSON.stringify(entry) + "\n";
    const locked = this.acquireLock();
    try {
      fs.appendFileSync(this.journalFilePath, line, { encoding: "utf8" });
    } finally {
      if (locked) {
        this.releaseLock();
      }
    }
  }

  /**
   * Read all valid entries from the JSONL journal.
   */
  public getHistory(): ToolJournalEntry[] {
    if (!fs.existsSync(this.journalFilePath)) {
      return [];
    }

    try {
      const content = fs.readFileSync(this.journalFilePath, "utf8");
      const lines = content.split("\n");
      const entries: ToolJournalEntry[] = [];

      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) continue;
        try {
          const parsed = JSON.parse(trimmed) as ToolJournalEntry;
          if (parsed && parsed.idempotencyKey) {
            entries.push(parsed);
          }
        } catch {
          // Skip corrupted lines gracefully
        }
      }

      return entries;
    } catch {
      return [];
    }
  }

  /**
   * Lookup the most recent entry for a given idempotency key.
   */
  public lookup(idempotencyKey: string): ToolJournalEntry | null {
    const history = this.getHistory();
    // Search in reverse for latest status of key
    for (let i = history.length - 1; i >= 0; i--) {
      if (history[i].idempotencyKey === idempotencyKey) {
        return history[i];
      }
    }
    return null;
  }

  /**
   * Check if a tool execution can be replayed from cache.
   * If prior execution succeeded (COMPLETED), returns cached result.
   * If prior execution failed or is pending, returns replayed = false.
   */
  public checkReplay(idempotencyKey: string): ReplayCheckResult {
    const entry = this.lookup(idempotencyKey);
    if (!entry) {
      return { replayed: false };
    }

    if (entry.status === "COMPLETED") {
      return {
        replayed: true,
        result: entry.result,
        entry,
      };
    }

    return { replayed: false, entry };
  }

  /**
   * Record the start of a tool execution (status: PENDING).
   */
  public recordStart(
    entry: Omit<ToolJournalEntry, "status" | "startedAt"> | {
      toolName: string;
      params: any;
      cwd: string;
      sessionId?: string;
      idempotencyKey?: string;
    }
  ): ToolJournalEntry {
    const idempotencyKey =
      entry.idempotencyKey || computeIdempotencyKey(entry.toolName, entry.params, entry.cwd);
    const canonicalParamsHash =
      (entry as any).canonicalParamsHash || computeParamsHash(entry.params);
    const sessionId = entry.sessionId || "default-session";

    const fullEntry: ToolJournalEntry = {
      idempotencyKey,
      sessionId,
      toolName: entry.toolName,
      canonicalParamsHash,
      params: entry.params,
      cwd: entry.cwd,
      status: "PENDING",
      startedAt: Date.now(),
    };

    this.appendEntry(fullEntry);
    return fullEntry;
  }

  /**
   * Record completion of a tool execution (status: COMPLETED).
   */
  public recordCompletion(idempotencyKey: string, result: any, exitCode = 0): void {
    const prior = this.lookup(idempotencyKey);
    const fullEntry: ToolJournalEntry = {
      idempotencyKey,
      sessionId: prior?.sessionId || "default-session",
      toolName: prior?.toolName || "unknown",
      canonicalParamsHash: prior?.canonicalParamsHash || "",
      params: prior?.params ?? null,
      cwd: prior?.cwd || "",
      status: "COMPLETED",
      startedAt: prior?.startedAt || Date.now(),
      completedAt: Date.now(),
      exitCode,
      result,
    };

    this.appendEntry(fullEntry);
  }

  /**
   * Record failure of a tool execution (status: FAILED).
   */
  public recordFailure(idempotencyKey: string, error: string, exitCode = 1): void {
    const prior = this.lookup(idempotencyKey);
    const fullEntry: ToolJournalEntry = {
      idempotencyKey,
      sessionId: prior?.sessionId || "default-session",
      toolName: prior?.toolName || "unknown",
      canonicalParamsHash: prior?.canonicalParamsHash || "",
      params: prior?.params ?? null,
      cwd: prior?.cwd || "",
      status: "FAILED",
      startedAt: prior?.startedAt || Date.now(),
      completedAt: Date.now(),
      exitCode,
      error,
    };

    this.appendEntry(fullEntry);
  }

  /**
   * Get summary statistics of the journal.
   */
  public getStatus(): {
    totalEntries: number;
    pending: number;
    completed: number;
    failed: number;
    uniqueKeys: number;
  } {
    const history = this.getHistory();
    const keyMap = new Map<string, JournalEntryStatus>();

    for (const entry of history) {
      keyMap.set(entry.idempotencyKey, entry.status);
    }

    let pending = 0;
    let completed = 0;
    let failed = 0;

    for (const status of keyMap.values()) {
      if (status === "PENDING") pending++;
      else if (status === "COMPLETED") completed++;
      else if (status === "FAILED") failed++;
    }

    return {
      totalEntries: history.length,
      pending,
      completed,
      failed,
      uniqueKeys: keyMap.size,
    };
  }

  /**
   * Clear the journal file.
   */
  public clear(): void {
    const locked = this.acquireLock();
    try {
      if (fs.existsSync(this.journalFilePath)) {
        fs.writeFileSync(this.journalFilePath, "", { encoding: "utf8" });
      }
    } finally {
      if (locked) {
        this.releaseLock();
      }
    }
  }

  public getFilePath(): string {
    return this.journalFilePath;
  }
}
