/**
 * RLM REPL Context Core Library
 *
 * Implements in-memory buffer storage, 100KB threshold interception,
 * LRU eviction with recent-buffer preservation, and safe slicing/filtering.
 */

import * as crypto from "node:crypto";

export const REPL_THRESHOLD_BYTES = 100 * 1024; // 100KB = 102,400 bytes
export const MAX_MEMORY_BUDGET_BYTES = 50 * 1024 * 1024; // 50MB
export const MIN_PRESERVED_BUFFERS = 10;

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

    // Evict if necessary before adding
    this.evictIfNeeded(byteLength);

    const lines = content.split(/\r?\n/);
    const lineCount = lines.length;
    const preview = lines.slice(0, 5).join("\n");
    const now = Date.now();

    // If updating existing buffer, subtract prior size
    if (this.buffers.has(id)) {
      const prior = this.buffers.get(id)!;
      this.totalBytes -= prior.byteLength;
    }

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
        formatted = buf.subarray(0, query.maxBytes).toString("utf-8") + "\n...[TRUNCATED]";
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
