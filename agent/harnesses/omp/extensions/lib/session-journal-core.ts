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
import { boundJsonPayload } from "./bounded-payload";

export type JournalEntryStatus = "PENDING" | "COMPLETED" | "FAILED";

/**
 * 1 エントリに保存する結果の上限。大きな bash 出力をそのまま書くと
 * journal が 1 セッションで数百 MB に膨れ、初回の索引構築が秒単位になる。
 */
export const MAX_JOURNAL_RESULT_BYTES = 16 * 1024;
/** 上限を超えた結果は先頭だけ残し、replay 対象から外す。 */
export const RESULT_PREVIEW_CHARS = 2048;
/**
 * journal ファイルの上限。超えたら 1 世代だけ退避 (`<file>.1`) して作り直す。
 * 追記専用のままではファイルサイズが単調増加し、1 セッション 200MB 規模に達する。
 */
export const MAX_JOURNAL_FILE_BYTES = 64 * 1024 * 1024;

export interface SessionJournalOptions {
  maxFileBytes?: number;
  maxResultBytes?: number;
}

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
  /** true のとき result は preview のみ。replay には使わない。 */
  resultTruncated?: boolean;
  error?: string;
}

export interface ReplayCheckResult {
  replayed: boolean;
  result?: any;
  entry?: ToolJournalEntry;
}

// Canonical JSON serialization is consolidated in ./canonical-json (shared with
// skill-state-core's stable value comparison). Imported for local use here and
// re-exported so existing importers of session-journal-core keep working.
import { canonicalizeJson, MAX_CANONICALIZE_DEPTH } from "./canonical-json";
export { canonicalizeJson, MAX_CANONICALIZE_DEPTH };

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
  private readonly maxFileBytes: number;
  private readonly maxResultBytes: number;
  // 増分インデックス: lookup のたびに JSONL 全体を読み直さないためのキャッシュ。
  private entries: ToolJournalEntry[] = [];
  private latestByKey = new Map<string, ToolJournalEntry>();
  private loadedBytes = 0;
  private loadedMtimeMs = -1;

  constructor(journalFilePath: string, options: SessionJournalOptions = {}) {
    this.journalFilePath = path.resolve(journalFilePath);
    this.lockFilePath = `${this.journalFilePath}.lock`;
    this.maxFileBytes = options.maxFileBytes ?? MAX_JOURNAL_FILE_BYTES;
    this.maxResultBytes = options.maxResultBytes ?? MAX_JOURNAL_RESULT_BYTES;
    this.ensureDirectoryExists();
  }

  /**
   * 結果が上限を超える場合は preview に置き換える。
   * 切り詰めた結果は replay すると内容が欠けるため、`resultTruncated` を立てて
   * `checkReplay` 側で replay 対象から外す。
   */
  private capResult(result: any): { result: any; truncated: boolean } {
    const bounded = boundJsonPayload(result, {
      maxBytes: this.maxResultBytes,
      previewChars: RESULT_PREVIEW_CHARS,
    });
    return { result: bounded.value, truncated: bounded.truncated };
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
   * ファイルが上限を超えていれば 1 世代だけ退避して作り直す。
   * 既存の `.1` は上書きする(世代は常に 1 つ)。
   */
  private rotateIfOversized(): void {
    let size: number;
    try {
      size = fs.statSync(this.journalFilePath).size;
    } catch {
      return;
    }
    if (size <= this.maxFileBytes) return;
    try {
      const archived = `${this.journalFilePath}.1`;
      fs.rmSync(archived, { force: true });
      fs.renameSync(this.journalFilePath, archived);
      this.resetIndex();
    } catch {
      // 退避に失敗しても追記は続行する(次回の append で再試行)
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
      this.rotateIfOversized();
      fs.appendFileSync(this.journalFilePath, line, { encoding: "utf8" });
    } finally {
      if (locked) {
        this.releaseLock();
      }
    }
    this.syncFromDisk();
  }

  /**
   * 追記された分だけを読み、メモリ上の索引を更新する。
   * 呼び出しごとに全履歴を JSON.parse し直すと、大きな result を含む journal で
   * ツール呼び出しのたびに秒単位のブロックが発生する(実測: 1 セッションで ~100s)。
   */
  private syncFromDisk(): void {
    let stat: fs.Stats;
    try {
      stat = fs.statSync(this.journalFilePath);
    } catch {
      this.resetIndex();
      return;
    }

    if (stat.size === this.loadedBytes) {
      // 同一サイズのまま書き換えられた場合(mtime だけ変化)は索引を作り直す
      if (stat.mtimeMs !== this.loadedMtimeMs) this.reloadFromDisk();
      return;
    }
    if (stat.size < this.loadedBytes) {
      // 切り詰め・ローテーション
      this.reloadFromDisk();
      return;
    }

    // 追記分のみ読む
    const length = stat.size - this.loadedBytes;
    const buf = Buffer.allocUnsafe(length);
    const fd = fs.openSync(this.journalFilePath, "r");
    try {
      fs.readSync(fd, buf, 0, length, this.loadedBytes);
    } finally {
      fs.closeSync(fd);
    }

    const text = buf.toString("utf8");
    const lastNewline = text.lastIndexOf("\n");
    // 書き込み途中の行は次回の sync に回す(バイト位置を進めない)
    if (lastNewline === -1) return;
    const complete = text.slice(0, lastNewline + 1);

    if (!this.ingest(complete)) {
      // 追記位置が既存内容と噛み合わない = 外部で書き換えられた。作り直す。
      this.reloadFromDisk();
      return;
    }

    this.loadedBytes += Buffer.byteLength(complete, "utf8");
    this.loadedMtimeMs = stat.mtimeMs;
  }

  /** JSONL 断片を取り込む。完全な行だけを対象にし、解析できない行があれば false。 */
  private ingest(text: string): boolean {
    let ok = true;
    for (const line of text.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      try {
        const parsed = JSON.parse(trimmed) as ToolJournalEntry;
        if (parsed && parsed.idempotencyKey) {
          this.entries.push(parsed);
          this.latestByKey.set(parsed.idempotencyKey, parsed);
        }
      } catch {
        // 破損行はスキップする(全文再読込では許容、追記差分では書き換え検出に使う)
        ok = false;
      }
    }
    return ok;
  }

  private resetIndex(): void {
    this.entries = [];
    this.latestByKey.clear();
    this.loadedBytes = 0;
    this.loadedMtimeMs = -1;
  }

  /** 索引を作り直す(切り詰め・外部書き換え時のフォールバック)。 */
  private reloadFromDisk(): void {
    this.resetIndex();
    let buf: Buffer;
    try {
      buf = fs.readFileSync(this.journalFilePath);
    } catch {
      return;
    }
    this.ingest(buf.toString("utf8"));
    this.loadedBytes = buf.byteLength;
    try {
      this.loadedMtimeMs = fs.statSync(this.journalFilePath).mtimeMs;
    } catch {
      this.loadedMtimeMs = -1;
    }
  }

  /**
   * Read all valid entries from the JSONL journal.
   */
  public getHistory(): ToolJournalEntry[] {
    this.syncFromDisk();
    return [...this.entries];
  }

  /**
   * Lookup the most recent entry for a given idempotency key.
   */
  public lookup(idempotencyKey: string): ToolJournalEntry | null {
    this.syncFromDisk();
    return this.latestByKey.get(idempotencyKey) ?? null;
  }

  /**
   * Check if a tool execution can be replayed from cache.
   * If prior execution succeeded (COMPLETED), returns cached result.
   * If prior execution failed or is pending, returns replayed = false.
   *
   * `maxAgeMs` bounds replay to recent completions. Read-only tools whose
   * results depend on mutable filesystem state should pass a short TTL so a
   * repeated read after an edit does not silently replay a stale snapshot.
   */
  public checkReplay(idempotencyKey: string, maxAgeMs?: number): ReplayCheckResult {
    const entry = this.lookup(idempotencyKey);
    if (!entry) {
      return { replayed: false };
    }

    if (entry.status === "COMPLETED") {
      if (entry.resultTruncated) {
        // 保存時に上限で切り詰めた結果は内容が欠けているため replay しない
        return { replayed: false, entry };
      }
      if (typeof maxAgeMs === "number" && maxAgeMs > 0) {
        // Unknown freshness (missing/invalid completedAt) is treated as
        // stale for read-only tools so a corrupted journal entry cannot
        // silently replay old content.
        if (
          typeof entry.completedAt !== "number" ||
          Date.now() - entry.completedAt > maxAgeMs
        ) {
          return { replayed: false, entry };
        }
      }
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
    const capped = this.capResult(result);
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
      result: capped.result,
      ...(capped.truncated ? { resultTruncated: true } : {}),
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
      this.entries = [];
      this.latestByKey.clear();
      this.loadedBytes = 0;
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

/**
 * ジャーナルディレクトリの合計サイズ上限。セッションをまたいで古いファイルが
 * 溜まり続ける(実測 2 日で 765MB / 74 ファイル)ため、mtime の古い順に削除する。
 */
export const JOURNAL_DIR_MAX_BYTES = 256 * 1024 * 1024;

export interface PruneJournalDirOptions {
  maxBytes?: number;
  /** これより新しいファイルは削除しない(並行セッション保護)。既定 1h。 */
  minAgeMs?: number;
  /** 削除しないファイル名(現在のセッションの journal)。 */
  keep?: string[];
  /** テスト用: 削除せず対象だけ返す。 */
  dryRun?: boolean;
}

/**
 * journal ディレクトリを `maxBytes` 以下に縮小する。journal は replay 用キャッシュで
 * 正本ではないため、終了済みセッションのファイル削除は安全。壊れた/無関係な
 * エントリには触れない(名前が `.jsonl` / `.jsonl.N` の通常ファイルのみ)。
 */
export function pruneJournalDir(
  dir: string,
  options: PruneJournalDirOptions = {},
): { removed: string[]; freedBytes: number } {
  const maxBytes = options.maxBytes ?? JOURNAL_DIR_MAX_BYTES;
  const minAgeMs = options.minAgeMs ?? 60 * 60 * 1000;
  const cutoff = Date.now() - minAgeMs;
  const keep = new Set(options.keep ?? []);
  let names: string[];
  try {
    names = fs.readdirSync(dir);
  } catch {
    return { removed: [], freedBytes: 0 };
  }
  const files: { name: string; size: number; mtimeMs: number }[] = [];
  let total = 0;
  for (const name of names) {
    if (!/\.jsonl(\.\d+)?$/.test(name)) continue;
    try {
      const stat = fs.statSync(path.join(dir, name));
      if (!stat.isFile()) continue;
      total += stat.size;
      // keep 対象と直近に更新されたファイルは合計には数えるが、削除候補から外す。
      if (!keep.has(name) && stat.mtimeMs < cutoff) {
        files.push({ name, size: stat.size, mtimeMs: stat.mtimeMs });
      }
    } catch {
      // 消えた/読めないファイルは対象外
    }
  }
  if (total <= maxBytes) return { removed: [], freedBytes: 0 };
  files.sort((a, b) => a.mtimeMs - b.mtimeMs);
  const removed: string[] = [];
  let freedBytes = 0;
  for (const file of files) {
    if (total - freedBytes <= maxBytes) break;
    if (!options.dryRun) {
      try {
        fs.rmSync(path.join(dir, file.name), { force: true });
      } catch {
        continue;
      }
    }
    removed.push(file.name);
    freedBytes += file.size;
  }
  return { removed, freedBytes };
}
