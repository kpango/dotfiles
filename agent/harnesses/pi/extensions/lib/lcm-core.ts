/**
 * Lossless Context Management (LCM) + Subtask Stack Machine Core
 *
 * Implements deterministic hierarchical context compaction and subtask boundary
 * collapsing based on:
 * - LCM (`arXiv:2605.04050`): immutable append-only transcript store (`0700`/`0600`)
 *   with `lcm-<hex>` pointers and 3-level escalating convergence guarantees.
 * - Subtask Stack Machine (`arXiv:2611.12122`): tracks nested subtask frames;
 *   only completed frames are collapsed on pop, keeping active prefix cache intact.
 */

import { createHash } from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

export interface LcmRecord {
  id: string;
  ts: string;
  label: string;
  bytes: number;
  content: string;
}

export interface LcmSearchHit {
  id: string;
  ts: string;
  label: string;
  bytes: number;
  snippet: string;
}

export function utf8SafeTruncate(input: string, maxBytes: number): string {
  if (maxBytes <= 0 || !input) return "";
  const buf = Buffer.from(input, "utf-8");
  if (buf.length <= maxBytes) return input;
  let end = maxBytes;
  // Back off from any UTF-8 continuation byte (10xxxxxx = 0x80..0xbf) so we cut on a codepoint boundary.
  while (end > 0 && (buf[end] & 0xc0) === 0x80) {
    end--;
  }
  return buf.subarray(0, end).toString("utf-8");
}

export class ImmutableLcmStore {
  readonly storeDir: string;
  readonly storeFile: string;
  private seenIds = new Set<string>();

  constructor(sessionId = "default", rootDir: string = path.join(os.homedir(), ".pi", "agent", "lcm")) {
    const safeSession = sessionId.replace(/[^A-Za-z0-9._-]+/g, "_") || "default";
    this.storeDir = path.join(rootDir, safeSession);
    this.storeFile = path.join(this.storeDir, "store.jsonl");
  }

  private ensureStore(): void {
    fs.mkdirSync(this.storeDir, { recursive: true, mode: 0o700 });
    fs.chmodSync(this.storeDir, 0o700);
  }

  append(label: string, content: string): LcmRecord {
    this.ensureStore();
    const cleanLabel = String(label || "record").slice(0, 120);
    const body = String(content ?? "");
    const digest = createHash("sha256").update(`${cleanLabel}\n${body}`).digest("hex").slice(0, 10);
    const id = `lcm-${digest}`;
    const record: LcmRecord = {
      id,
      ts: new Date().toISOString(),
      label: cleanLabel,
      bytes: Buffer.byteLength(body, "utf-8"),
      content: body,
    };

    if (!this.seenIds.has(id)) {
      this.seenIds.add(id);
      const line = JSON.stringify(record) + "\n";
      fs.appendFileSync(this.storeFile, line, { encoding: "utf-8", mode: 0o600 });
      fs.chmodSync(this.storeFile, 0o600);
    }
    return record;
  }

  readAll(): LcmRecord[] {
    if (!fs.existsSync(this.storeFile)) return [];
    const lines = fs.readFileSync(this.storeFile, "utf-8").split("\n");
    const out: LcmRecord[] = [];
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const parsed = JSON.parse(line) as LcmRecord;
        if (parsed && typeof parsed.id === "string") {
          out.push(parsed);
          this.seenIds.add(parsed.id);
        }
      } catch {
        // Ignore corrupted partial trailing lines cleanly.
      }
    }
    return out;
  }

  getById(id: string): LcmRecord | null {
    const target = id.trim();
    if (!target) return null;
    for (const rec of this.readAll()) {
      if (rec.id === target) return rec;
    }
    return null;
  }

  search(query: string, limit = 10): LcmSearchHit[] {
    const needle = query.trim().toLowerCase();
    if (!needle) return [];
    const hits: LcmSearchHit[] = [];
    for (const rec of this.readAll()) {
      const hay = `${rec.label}\n${rec.content}`;
      const idx = hay.toLowerCase().indexOf(needle);
      if (idx === -1) continue;
      const start = Math.max(0, idx - 60);
      const snippet = hay.slice(start, start + 220).replace(/\s+/g, " ").trim();
      hits.push({
        id: rec.id,
        ts: rec.ts,
        label: rec.label,
        bytes: rec.bytes,
        snippet,
      });
      if (hits.length >= Math.max(1, limit)) break;
    }
    return hits;
  }
}

const STRUCTURAL_LINE_RE =
  /^\s*(?:#{1,6}\s|[-*]\s|@@\s|\+\s|-\s)|(?:FAIL|PASS|ERROR|WARN|BLOCKED|DECIDED|[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:\d+)/i;

export function escalateCompact(
  text: string,
  targetBytes: number,
  pointerId?: string,
): { level: 1 | 2 | 3; text: string } {
  const budget = Math.max(64, Math.floor(targetBytes));
  const raw = String(text ?? "");
  if (Buffer.byteLength(raw, "utf-8") <= budget) {
    return { level: 1, text: raw };
  }

  const lines = raw.split("\n");
  const structural = lines.filter((l) => STRUCTURAL_LINE_RE.test(l));
  const suffix = pointerId ? `\n[lcm: archived verbatim at ${pointerId}]` : "\n[lcm: truncated]";
  const suffixBytes = Buffer.byteLength(suffix, "utf-8");

  if (structural.length > 0 && budget > suffixBytes) {
    const structuralText = structural.join("\n");
    if (Buffer.byteLength(structuralText, "utf-8") + suffixBytes <= budget) {
      return { level: 2, text: structuralText + suffix };
    }
  }

  const headBudget = Math.max(0, budget - suffixBytes);
  const head = utf8SafeTruncate(raw, headBudget).trimEnd();
  return { level: 3, text: head + suffix };
}

export interface SubtaskFrame {
  id: string;
  name: string;
  startIndex: number;
  pushedAt: string;
}

export interface CollapsedSpan {
  frameId: string;
  name: string;
  startIndex: number;
  endIndex: number;
  pointerId: string;
  collapsedText: string;
}

export class SubtaskStackMachine {
  private frames: SubtaskFrame[] = [];
  private collapsedSpans: CollapsedSpan[] = [];
  private seq = 0;

  constructor(private readonly store: ImmutableLcmStore) {}

  reset(): void {
    this.frames = [];
    this.collapsedSpans = [];
    this.seq = 0;
  }

  push(name: string, startIndex: number): SubtaskFrame {
    const frame: SubtaskFrame = {
      id: `frame-${++this.seq}`,
      name: String(name || `subtask-${this.seq}`).trim(),
      startIndex: Math.max(0, Math.floor(startIndex)),
      pushedAt: new Date().toISOString(),
    };
    this.frames.push(frame);
    return frame;
  }

  pop(endIndex: number, summary: string, rawTranscript?: string, maxSummaryBytes = 2048): CollapsedSpan | null {
    const frame = this.frames.pop();
    if (!frame) return null;

    const cleanEnd = Math.max(frame.startIndex, Math.floor(endIndex));
    const archive = this.store.append(`subtask:${frame.name}`, rawTranscript || summary);
    const compacted = escalateCompact(summary, maxSummaryBytes, archive.id);
    const collapsedText = `[Subtask Popped: ${frame.name} | lcm=${archive.id} (${archive.bytes}B archived)]\n${compacted.text}`;
    const span: CollapsedSpan = {
      frameId: frame.id,
      name: frame.name,
      startIndex: frame.startIndex,
      endIndex: cleanEnd,
      pointerId: archive.id,
      collapsedText,
    };

    // Replace any inner child spans subsumed by this outer frame so ranges stay disjoint.
    this.collapsedSpans = this.collapsedSpans.filter(
      (s) => s.endIndex <= span.startIndex || s.startIndex >= span.endIndex,
    );
    this.collapsedSpans.push(span);
    return span;
  }

  getActiveFrames(): SubtaskFrame[] {
    return [...this.frames];
  }

  getCollapsedSpans(): CollapsedSpan[] {
    return [...this.collapsedSpans];
  }

  applyCollapsedSpans<TMessage>(
    messages: TMessage[],
    makeSummaryMessage: (span: CollapsedSpan) => TMessage,
  ): TMessage[] {
    if (this.collapsedSpans.length === 0 || messages.length === 0) return messages;
    const sorted = [...this.collapsedSpans].sort((a, b) => a.startIndex - b.startIndex);
    const out: TMessage[] = [];
    let cursor = 0;

    for (const span of sorted) {
      if (span.startIndex >= messages.length || span.endIndex <= span.startIndex) continue;
      const start = Math.max(cursor, span.startIndex);
      const end = Math.min(messages.length, span.endIndex);
      if (end <= start) continue;

      while (cursor < start) {
        out.push(messages[cursor++]);
      }
      out.push(makeSummaryMessage(span));
      cursor = end;
    }

    while (cursor < messages.length) {
      out.push(messages[cursor++]);
    }
    return out;
  }
}
