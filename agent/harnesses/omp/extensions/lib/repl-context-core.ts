/**
 * RLM REPL Context Core Library
 *
 * Implements in-memory buffer storage, 100KB threshold interception,
 * LRU eviction with recent-buffer preservation, and safe slicing/filtering.
 */

import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
import { loadSolPiConfig, type SolPiConfig } from "./sol-pi-core";

/**
 * Decode the first `maxBytes` bytes of a UTF-8 buffer without splitting a
 * multibyte character. If `maxBytes` lands inside a character, the cut is moved
 * back to the preceding character boundary so the partial char is dropped rather
 * than decoded to a U+FFFD replacement char.
 */
export function sliceUtf8ToBytes(buf: Buffer, maxBytes: number): string {
  if (maxBytes >= buf.length) return buf.toString("utf-8");
  let cut = maxBytes;
  // UTF-8 continuation bytes are 0b10xxxxxx (0x80..0xBF). Back up while the byte
  // at the cut position is a continuation byte to land on a lead/ASCII byte.
  while (cut > 0 && (buf[cut] & 0xc0) === 0x80) cut--;
  return buf.subarray(0, cut).toString("utf-8");
}

export const REPL_THRESHOLD_BYTES = 100 * 1024; // 100KB = 102,400 bytes
export const MAX_MEMORY_BUDGET_BYTES = 50 * 1024 * 1024; // 50MB
export const MIN_PRESERVED_BUFFERS = 10;

/**
 * Relationship between sol-pi ObservationPack (observationPackConfig.minBytesThreshold,
 * default 10 KiB: archive + compact replay) and this store (REPL_THRESHOLD_BYTES, 100 KiB:
 * in-memory interception). Informational only; neither threshold is changed here.
 */
export interface ObservationPackThresholds {
  packMinBytes: number;
  replInterceptBytes: number;
  /** true when ObservationPack packs outputs earlier (at a smaller size) than REPL interception. */
  packsBeforeIntercept: boolean;
}

export function getObservationPackThresholds(
  config: Pick<SolPiConfig, "observationPackConfig"> = loadSolPiConfig()
): ObservationPackThresholds {
  const packMinBytes = config.observationPackConfig.minBytesThreshold;
  return {
    packMinBytes,
    replInterceptBytes: REPL_THRESHOLD_BYTES,
    packsBeforeIntercept: packMinBytes < REPL_THRESHOLD_BYTES,
  };
}

// --------------------------------------------------------------------------
// rlm_map_reduce: bounded chunk Map-Reduce via agent/scripts/rlm/rlm-bounded.py
// --------------------------------------------------------------------------
export const RLM_MAX_DEPTH = 1;
export const RLM_MAX_ITERATIONS = 12;
const RLM_MAX_CHUNK_BYTES = 64 * 1024 * 1024; // mirrors rlm-bounded.py MAX_CHUNK_BYTES
const RLM_MAX_QUERY_BYTES = 4096;
const RLM_MODEL_RE = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/;
// Any line separator Python's str.splitlines() honours (the script rejects those too).
const RLM_LINE_SEP_RE = new RegExp("[\\n\\r\\v\\f\\x1c-\\x1e\\x85\\u2028\\u2029]");
/** Only these env keys may be forwarded from the caller to the script. */
const RLM_ENV_PASSTHROUGH = ["RLM_BACKEND", "RLM_CHUNK_TIMEOUT"] as const;

export interface BoundedRlmOptions {
  mode?: string;
  query: string;
  contextFile: string;
  model?: string;
  /** Must be exactly 1 (omitted = 1). */
  maxDepth?: number;
  /** 1..12 (omitted = 12). Each map iteration is one chunk, so it is passed as --max-chunks. */
  maxIterations?: number;
  chunkBytes?: number;
  ledgerDir?: string;
  dryRun?: boolean;
  scriptPath?: string;
  env?: Partial<Record<(typeof RLM_ENV_PASSTHROUGH)[number], string>>;
}

export interface BoundedRlmResult {
  ok: boolean;
  result: Record<string, any>;
  stderr: string;
}

type SpawnFn = (cmd: string, args: string[], opts: Record<string, any>) => SpawnSyncReturns<string>;

function defaultRlmScriptPath(): string {
  // lib/ -> extensions/ -> omp/ -> harnesses/ -> agent/
  return path.resolve(import.meta.dir, "../../../../scripts/rlm/rlm-bounded.py");
}

function rlmInt(name: string, v: unknown, min: number, max: number, dflt: number): number {
  if (v === undefined) return dflt;
  if (typeof v !== "number" || !Number.isInteger(v) || v < min || v > max) {
    throw new Error(`rlm_map_reduce: ${name} must be an integer in ${min}..${max}, got ${String(v)}`);
  }
  return v;
}

function rlmAbsPath(name: string, v: unknown): string {
  if (typeof v !== "string" || v.length === 0 || v.includes("\0") || !path.isAbsolute(v)) {
    throw new Error(`rlm_map_reduce: ${name} must be an absolute path without NUL`);
  }
  return v;
}

/** Fail-closed: any invalid input or non-zero script exit throws. Never uses a shell. */
export function runBoundedRlmChunkQuery(
  opts: BoundedRlmOptions,
  spawn: SpawnFn = spawnSync as unknown as SpawnFn
): BoundedRlmResult {
  if (opts.mode !== undefined && opts.mode !== "rlm_map_reduce") {
    throw new Error(`rlm_map_reduce: unsupported mode '${String(opts.mode)}'`);
  }
  const maxDepth = rlmInt("maxDepth", opts.maxDepth, 1, RLM_MAX_DEPTH, RLM_MAX_DEPTH);
  const maxIterations = rlmInt("maxIterations", opts.maxIterations, 1, RLM_MAX_ITERATIONS, RLM_MAX_ITERATIONS);
  const chunkBytes = rlmInt("chunkBytes", opts.chunkBytes, 1, RLM_MAX_CHUNK_BYTES, 65536);

  const q = opts.query;
  if (typeof q !== "string" || q.length === 0 || q.includes("\0") || RLM_LINE_SEP_RE.test(q)) {
    throw new Error("rlm_map_reduce: query must be a non-empty single-line string without NUL");
  }
  if (Buffer.byteLength(q, "utf-8") > RLM_MAX_QUERY_BYTES) {
    throw new Error(`rlm_map_reduce: query exceeds ${RLM_MAX_QUERY_BYTES} bytes`);
  }
  const model = opts.model;
  if (model !== undefined && (typeof model !== "string" || !RLM_MODEL_RE.test(model))) {
    throw new Error("rlm_map_reduce: model has invalid characters");
  }
  const contextFile = rlmAbsPath("contextFile", opts.contextFile);
  let st: fs.Stats;
  try {
    st = fs.lstatSync(contextFile);
  } catch (e: any) {
    throw new Error(`rlm_map_reduce: cannot stat contextFile: ${e.message}`);
  }
  if (!st.isFile()) throw new Error("rlm_map_reduce: contextFile must be a regular file (no symlink/dir/device)");
  const ledgerDir = opts.ledgerDir === undefined ? undefined : rlmAbsPath("ledgerDir", opts.ledgerDir);
  const script = opts.scriptPath === undefined ? defaultRlmScriptPath() : rlmAbsPath("scriptPath", opts.scriptPath);
  if (!fs.existsSync(script)) throw new Error(`rlm_map_reduce: script not found: ${script}`);

  // `--opt=value` form: a value starting with "-" can never be parsed as a separate option.
  const args = [
    "-I",
    "-B",
    script,
    `--query=${q}`,
    `--context-file=${contextFile}`,
    `--max-depth=${maxDepth}`,
    `--max-chunks=${maxIterations}`,
    `--chunk-bytes=${chunkBytes}`,
    "--json",
  ];
  if (model !== undefined) args.push(`--model=${model}`);
  if (ledgerDir !== undefined) args.push(`--ledger-dir=${ledgerDir}`);
  if (opts.dryRun) args.push("--dry-run");

  const env: Record<string, string> = { PATH: process.env.PATH ?? "/usr/bin:/bin", LANG: "C.UTF-8" };
  for (const k of RLM_ENV_PASSTHROUGH) {
    const v = opts.env?.[k] ?? process.env[k];
    if (v !== undefined) env[k] = v;
  }
  const r = spawn("python3", args, {
    shell: false,
    encoding: "utf-8",
    env,
    timeout: 300_000,
    maxBuffer: 1024 * 1024,
  });
  if (r.error) throw new Error(`rlm_map_reduce: failed to run script: ${r.error.message}`);
  if (r.status !== 0) {
    throw new Error(`rlm_map_reduce: script exited ${r.status}: ${(r.stderr || "").trim()}`);
  }
  let result: Record<string, any>;
  try {
    result = JSON.parse(r.stdout || "");
  } catch {
    throw new Error("rlm_map_reduce: script output is not valid JSON");
  }
  return { ok: true, result, stderr: r.stderr || "" };
}

export interface ReplBufferEntry {
  id: string; // e.g. "repl_buf_7f8a9b1c2d3e"
  handle: string; // e.g. "#repl_buf_7f8a9b1c2d3e"
  hash: string; // e.g. "7f8a9b1c2d3e"
  sourceTool: string;
  byteLength: number;
  lineCount: number;
  preview: string;
  createdAt: number;
  lastAccessedAt: number;
  content: string;
}

export interface ReplSliceQuery {
  bufferId: string;
  startLine?: number;
  endLine?: number;
  maxBytes?: number;
}

export interface ReplFilterQuery {
  bufferId: string;
  pattern: string;
  isRegex?: boolean;
  contextLines?: number;
  maxMatches?: number;
}

export interface ReplQueryResult {
  bufferId: string;
  matchedLines: number;
  totalLines: number;
  content: string;
  truncated: boolean;
  error?: string;
}

export interface ReplBufferSummary {
  bufferId: string;
  handle: string;
  sourceTool: string;
  byteLength: number;
  lineCount: number;
  preview: string;
  createdAt: number;
  lastAccessedAt: number;
}

export class ReplContextStore {
  private buffers: Map<string, ReplBufferEntry> = new Map();
  private totalBytes = 0;
  private maxMemoryBytes: number;
  private minPreservedBuffers: number;

  constructor(
    maxMemoryBytes: number = MAX_MEMORY_BUDGET_BYTES,
    minPreservedBuffers: number = MIN_PRESERVED_BUFFERS
  ) {
    this.maxMemoryBytes = maxMemoryBytes;
    this.minPreservedBuffers = minPreservedBuffers;
  }

  public normalizeBufferId(id: string): string {
    const trimmed = (id || "").trim();
    return trimmed.startsWith("#") ? trimmed.slice(1) : trimmed;
  }

  public store(
    content: string,
    sourceTool = "unknown"
  ): {
    intercepted: boolean;
    bufferId?: string;
    handle?: string;
    summary?: string;
    entry?: ReplBufferEntry;
  } {
    const byteLength = Buffer.byteLength(content, "utf-8");
    if (byteLength <= REPL_THRESHOLD_BYTES) {
      return { intercepted: false };
    }

    const hash = crypto.createHash("sha256").update(content).digest("hex").slice(0, 12);
    const id = `repl_buf_${hash}`;
    const handle = `#${id}`;

    // Remove any prior version of this buffer BEFORE eviction so the budget
    // check is accurate. Previously evictIfNeeded ran while totalBytes still
    // included this buffer's old size, double-counting it and needlessly
    // over-evicting OTHER buffers when a buffer is updated in place.
    if (this.buffers.has(id)) {
      const prior = this.buffers.get(id)!;
      this.totalBytes -= prior.byteLength;
      this.buffers.delete(id);
    }

    // Evict if necessary before adding
    this.evictIfNeeded(byteLength);

    const lines = content.split(/\r?\n/);
    const lineCount = lines.length;
    const preview = lines.slice(0, 5).join("\n");
    const now = Date.now();

    const entry: ReplBufferEntry = {
      id,
      handle,
      hash,
      sourceTool,
      byteLength,
      lineCount,
      preview,
      createdAt: now,
      lastAccessedAt: now,
      content,
    };

    this.buffers.set(id, entry);
    this.totalBytes += byteLength;

    const summary = [
      `[RLM Context Intercepted: Output (${byteLength.toLocaleString()} bytes, ${lineCount} lines) from '${sourceTool}' exceeded 100KB threshold.]`,
      `Stored in memory buffer handle: ${handle}`,
      `Preview (first 5 lines):`,
      preview,
      `---`,
      `To query this output without blowing token context, use tool 'repl_filter':`,
      `  - Slicing: { bufferId: "${id}", queryType: "slice", startLine: 1, endLine: 50 }`,
      `  - Searching: { bufferId: "${id}", queryType: "filter", pattern: "ERROR|FAIL", isRegex: true }`,
      `  - Head/Tail: { bufferId: "${id}", queryType: "head"|"tail" }`,
    ].join("\n");

    return {
      intercepted: true,
      bufferId: id,
      handle,
      summary,
      entry,
    };
  }

  public get(bufferId: string): ReplBufferEntry | undefined {
    const id = this.normalizeBufferId(bufferId);
    const entry = this.buffers.get(id);
    if (entry) {
      entry.lastAccessedAt = Date.now();
    }
    return entry;
  }

  public slice(query: ReplSliceQuery): ReplQueryResult {
    const id = this.normalizeBufferId(query.bufferId);
    const entry = this.get(id);

    if (!entry) {
      return {
        bufferId: query.bufferId,
        matchedLines: 0,
        totalLines: 0,
        content: "",
        truncated: false,
        error: `Buffer '${query.bufferId}' not found or expired`,
      };
    }

    const lines = entry.content.split(/\r?\n/);
    const totalLines = lines.length;

    const startLine = query.startLine !== undefined ? query.startLine : 1;
    if (startLine > totalLines) {
      return {
        bufferId: entry.id,
        matchedLines: 0,
        totalLines,
        content: "",
        truncated: false,
        error: `Requested line range out of bounds (1..${totalLines})`,
      };
    }

    const safeStart = Math.max(1, startLine);
    const safeEnd =
      query.endLine !== undefined ? Math.min(query.endLine, totalLines) : totalLines;

    if (safeStart > safeEnd) {
      return {
        bufferId: entry.id,
        matchedLines: 0,
        totalLines,
        content: "",
        truncated: false,
        error: `Start line (${safeStart}) cannot be greater than end line (${safeEnd})`,
      };
    }

    const selectedLines = lines.slice(safeStart - 1, safeEnd);
    let formatted = selectedLines
      .map((line, idx) => `L${safeStart + idx}: ${line}`)
      .join("\n");

    let truncated = false;
    if (query.maxBytes !== undefined && query.maxBytes > 0) {
      const buf = Buffer.from(formatted, "utf-8");
      if (buf.length > query.maxBytes) {
        formatted = sliceUtf8ToBytes(buf, query.maxBytes) + "\n...[TRUNCATED]";
        truncated = true;
      }
    }

    return {
      bufferId: entry.id,
      matchedLines: selectedLines.length,
      totalLines,
      content: formatted,
      truncated,
    };
  }

  public filter(query: ReplFilterQuery): ReplQueryResult {
    const id = this.normalizeBufferId(query.bufferId);
    const entry = this.get(id);

    if (!entry) {
      return {
        bufferId: query.bufferId,
        matchedLines: 0,
        totalLines: 0,
        content: "",
        truncated: false,
        error: `Buffer '${query.bufferId}' not found or expired`,
      };
    }

    const lines = entry.content.split(/\r?\n/);
    const totalLines = lines.length;
    const contextLines = Math.max(0, query.contextLines || 0);
    const maxMatches = query.maxMatches || 200;

    let matcher: (line: string) => boolean;

    if (query.isRegex) {
      try {
        const re = new RegExp(query.pattern);
        matcher = (line: string) => re.test(line);
      } catch (err: any) {
        return {
          bufferId: entry.id,
          matchedLines: 0,
          totalLines,
          content: "",
          truncated: false,
          error: `Invalid regular expression pattern: ${err.message}`,
        };
      }
    } else {
      const lower = query.pattern.toLowerCase();
      matcher = (line: string) => line.toLowerCase().includes(lower);
    }

    const matchedIndices = new Set<number>();
    let rawMatchCount = 0;

    for (let i = 0; i < lines.length; i++) {
      if (matcher(lines[i])) {
        rawMatchCount++;
        const from = Math.max(0, i - contextLines);
        const to = Math.min(lines.length - 1, i + contextLines);
        for (let c = from; c <= to; c++) {
          matchedIndices.add(c);
        }
        if (rawMatchCount >= maxMatches) {
          break;
        }
      }
    }

    const sortedIndices = Array.from(matchedIndices).sort((a, b) => a - b);
    const formatted = sortedIndices
      .map((idx) => `L${idx + 1}: ${lines[idx]}`)
      .join("\n");

    return {
      bufferId: entry.id,
      matchedLines: rawMatchCount,
      totalLines,
      content: formatted,
      truncated: rawMatchCount >= maxMatches,
    };
  }

  public head(bufferId: string, n = 10): ReplQueryResult {
    return this.slice({ bufferId, startLine: 1, endLine: n });
  }

  public tail(bufferId: string, n = 10): ReplQueryResult {
    const id = this.normalizeBufferId(bufferId);
    const entry = this.get(id);
    if (!entry) {
      return {
        bufferId,
        matchedLines: 0,
        totalLines: 0,
        content: "",
        truncated: false,
        error: `Buffer '${bufferId}' not found or expired`,
      };
    }
    const start = Math.max(1, entry.lineCount - n + 1);
    return this.slice({ bufferId: id, startLine: start, endLine: entry.lineCount });
  }

  public summarize(bufferId: string): ReplBufferSummary | null {
    const id = this.normalizeBufferId(bufferId);
    const entry = this.get(id);
    if (!entry) return null;

    return {
      bufferId: entry.id,
      handle: entry.handle,
      sourceTool: entry.sourceTool,
      byteLength: entry.byteLength,
      lineCount: entry.lineCount,
      preview: entry.preview,
      createdAt: entry.createdAt,
      lastAccessedAt: entry.lastAccessedAt,
    };
  }

  public list(): ReplBufferSummary[] {
    return Array.from(this.buffers.values()).map((e) => ({
      bufferId: e.id,
      handle: e.handle,
      sourceTool: e.sourceTool,
      byteLength: e.byteLength,
      lineCount: e.lineCount,
      preview: e.preview,
      createdAt: e.createdAt,
      lastAccessedAt: e.lastAccessedAt,
    }));
  }

  public clear(): void {
    this.buffers.clear();
    this.totalBytes = 0;
  }

  public delete(bufferId: string): boolean {
    const id = this.normalizeBufferId(bufferId);
    const entry = this.buffers.get(id);
    if (entry) {
      this.totalBytes -= entry.byteLength;
      return this.buffers.delete(id);
    }
    return false;
  }

  public getTotalBytes(): number {
    return this.totalBytes;
  }

  public getBufferCount(): number {
    return this.buffers.size;
  }

  private evictIfNeeded(neededBytes: number): void {
    if (this.totalBytes + neededBytes <= this.maxMemoryBytes) {
      return;
    }

    // Sort entries by lastAccessedAt ascending (oldest first)
    const sorted = Array.from(this.buffers.values()).sort(
      (a, b) => a.lastAccessedAt - b.lastAccessedAt
    );

    // Never evict down below minPreservedBuffers
    while (
      this.totalBytes + neededBytes > this.maxMemoryBytes &&
      this.buffers.size > this.minPreservedBuffers
    ) {
      // Find candidate outside the newest minPreservedBuffers
      const evictableCount = this.buffers.size - this.minPreservedBuffers;
      if (evictableCount <= 0) break;

      const oldest = sorted.shift();
      if (!oldest) break;

      this.buffers.delete(oldest.id);
      this.totalBytes -= oldest.byteLength;
    }
  }
}

// Global default singleton store for extension lifecycle
export const globalReplStore = new ReplContextStore();
