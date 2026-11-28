/**
 * Hashline content-hash anchored editing core (zero external dependencies).
 *
 * Assigns deterministic 4-hex-char FNV-1a tags to each line (`N#XXXX|content`)
 * and a snapshot tag `[PATH#TAG]` on read, verifying anchors and seen-lines on
 * edit while preserving fallback compatibility with standard oldText/newText edits.
 */

import { createHash } from "node:crypto";
import * as path from "node:path";

export interface HashlineEditOp {
  anchor: string;
  end_anchor?: string;
  op?: "replace" | "insert_after" | "delete";
  content?: string;
}

export interface HashlineInput {
  path: string;
  file_tag?: string;
  edits?: HashlineEditOp[];
  oldText?: string;
  newText?: string;
  old_string?: string;
  new_string?: string;
}

export interface HashlineSessionState {
  seenLines: Map<string, Set<number>>;
  noopCounts: Map<string, number>;
  lastSuccessPayload: Map<string, { payloadKey: string; snapshot: string }>;
}

export function createHashlineState(): HashlineSessionState {
  return {
    seenLines: new Map(),
    noopCounts: new Map(),
    lastSuccessPayload: new Map(),
  };
}

/** Deterministic 16-bit FNV-1a hash formatted as 4 lowercase hex chars. */
export function lineHashTag(line: string): string {
  const normalized = line.replace(/\r$/, "");
  let h = 0x811c9dc5;
  for (let i = 0; i < normalized.length; i++) {
    h ^= normalized.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return ((h ^ (h >>> 16)) & 0xffff).toString(16).padStart(4, "0");
}

/** Deterministic 4-hex-char snapshot tag for the full file contents. */
export function computeFileSnapshotTag(content: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < content.length; i++) {
    h ^= content.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return ((h ^ (h >>> 16)) & 0xffff).toString(16).padStart(4, "0");
}

export function unwrapHashlinePath(rawPath: string): string {
  const t = rawPath.trim();
  if (t.length >= 2 && t[0] === "[" && t[t.length - 1] === "]") {
    const inner = t.slice(1, -1);
    const m = /#[0-9A-Fa-f]{4}$/.exec(inner);
    return m ? inner.slice(0, m.index) : inner;
  }
  return rawPath;
}

export function parseAnchor(anchor: string): { line: number; tag: string } {
  const m = /^\s*(\d+)#([0-9a-fA-F]{4})\s*$/.exec(anchor);
  if (!m) {
    throw new Error(`[E_INVALID_ANCHOR] Invalid hashline anchor "${anchor}". Expected "<line>#<4-hex>" (e.g. "12#a3f1").`);
  }
  const line = Number.parseInt(m[1], 10);
  if (line < 1) {
    throw new Error(`[E_INVALID_ANCHOR] Anchor line must be >= 1, got ${line}.`);
  }
  return { line, tag: m[2].toLowerCase() };
}

/** Normalize model dialect artifacts (CRLF, outer markdown code fences) in replacement content. */
export function normalizeEditDialect(raw: string): string {
  let text = raw.replace(/\r\n/g, "\n");
  const fenced = /^```[^\n]*\n([\s\S]*)\n```\s*$/.exec(text);
  if (fenced) {
    text = fenced[1];
  }
  return text;
}

export function annotateFileWithHashlines(
  filePath: string,
  content: string,
  state?: HashlineSessionState,
  offsetLine = 1,
): { text: string; snapshotTag: string; lineCount: number } {
  const resolved = path.resolve(unwrapHashlinePath(filePath));
  const snapshotTag = computeFileSnapshotTag(content);
  const lines = content.split("\n");
  if (state) {
    let seen = state.seenLines.get(resolved);
    if (!seen) {
      seen = new Set<number>();
      state.seenLines.set(resolved, seen);
    }
    for (let i = 0; i < lines.length; i++) {
      seen.add(offsetLine + i);
    }
  }
  const header = `[${filePath}#${snapshotTag}]`;
  const numbered = lines.map((line, i) => {
    const lineNum = offsetLine + i;
    return `${lineNum}#${lineHashTag(line)}|${line}`;
  });
  return {
    text: `${header}\n${numbered.join("\n")}`,
    snapshotTag,
    lineCount: lines.length,
  };
}

function buildCompactDiff(
  beforeLines: string[],
  afterLines: string[],
  filePath: string,
  newTag: string,
): string {
  let prefix = 0;
  while (prefix < beforeLines.length && prefix < afterLines.length && beforeLines[prefix] === afterLines[prefix]) {
    prefix++;
  }
  let suffix = 0;
  while (
    suffix < beforeLines.length - prefix &&
    suffix < afterLines.length - prefix &&
    beforeLines[beforeLines.length - 1 - suffix] === afterLines[afterLines.length - 1 - suffix]
  ) {
    suffix++;
  }
  const oldChangedEnd = beforeLines.length - suffix;
  const newChangedEnd = afterLines.length - suffix;
  const ctxStart = Math.max(0, prefix - 2);
  const ctxOldEnd = Math.min(beforeLines.length, oldChangedEnd + 2);
  const ctxNewEnd = Math.min(afterLines.length, newChangedEnd + 2);

  const out: string[] = [`[${filePath}#${newTag}] @@ -${ctxStart + 1},${ctxOldEnd - ctxStart} +${ctxStart + 1},${ctxNewEnd - ctxStart} @@`];
  for (let i = ctxStart; i < prefix; i++) {
    out.push(`  ${i + 1}#${lineHashTag(afterLines[i])}|${afterLines[i]}`);
  }
  for (let i = prefix; i < oldChangedEnd; i++) {
    out.push(`- ${i + 1}#${lineHashTag(beforeLines[i])}|${beforeLines[i]}`);
  }
  for (let i = prefix; i < newChangedEnd; i++) {
    out.push(`+ ${i + 1}#${lineHashTag(afterLines[i])}|${afterLines[i]}`);
  }
  for (let i = newChangedEnd; i < ctxNewEnd; i++) {
    out.push(`  ${i + 1}#${lineHashTag(afterLines[i])}|${afterLines[i]}`);
  }
  return out.join("\n");
}

export interface HashlineApplyResult {
  nextContent: string;
  changed: boolean;
  snapshotTag: string;
  diffPreview: string;
}

export function applyEditToContent(
  filePath: string,
  currentContent: string,
  input: HashlineInput,
  state: HashlineSessionState,
): HashlineApplyResult {
  const cleanPath = unwrapHashlinePath(filePath);
  const resolved = path.resolve(cleanPath);
  const currentTag = computeFileSnapshotTag(currentContent);
  const payloadKey = JSON.stringify({
    file_tag: input.file_tag,
    edits: input.edits,
    oldText: input.oldText ?? input.old_string,
    newText: input.newText ?? input.new_string,
  });

  const last = state.lastSuccessPayload.get(resolved);
  if (last && last.payloadKey === payloadKey && last.snapshot === currentTag) {
    throw new Error(`[E_DUPLICATE_EDIT] Identical edit payload already succeeded on unchanged ${cleanPath}.`);
  }

  if (input.file_tag && input.file_tag.toLowerCase() !== currentTag) {
    throw new Error(
      `[E_STALE_SNAPSHOT] Snapshot tag mismatch for ${cleanPath}: expected #${input.file_tag}, actual #${currentTag}. Re-read the file first.`,
    );
  }

  const lines = currentContent.split("\n");
  let nextLines: string[];
  const rebasedNotes: string[] = [];

  if (Array.isArray(input.edits) && input.edits.length > 0) {
    const seen = state.seenLines.get(resolved);
    const resolvedOps = input.edits.map((op) => {
      const start = parseAnchor(op.anchor);
      const end = op.end_anchor ? parseAnchor(op.end_anchor) : start;
      if (end.line < start.line) {
        throw new Error(`[E_INVALID_RANGE] end_anchor line ${end.line} < anchor line ${start.line}.`);
      }
      let effectiveStart = start.line;
      let effectiveEnd = end.line;
      const inBounds = effectiveStart <= lines.length && effectiveEnd <= lines.length;
      const startTagNow = inBounds ? lineHashTag(lines[effectiveStart - 1]) : "";
      if (!inBounds || startTagNow !== start.tag) {
        if (!op.end_anchor) {
          const rebased = findUniqueRebasedLine(lines, start.line, start.tag);
          if (rebased !== null) {
            rebasedNotes.push(`[rebased L${start.line}->L${rebased}]`);
            effectiveStart = rebased;
            effectiveEnd = rebased;
          } else {
            throw new Error(
              `[E_HASH_MISMATCH] Line ${start.line} tag mismatch in ${cleanPath}: expected #${start.tag}, actual #${startTagNow || "EOF"}. Re-read before editing.`,
            );
          }
        } else if (!inBounds) {
          throw new Error(`[E_LINE_OUT_OF_RANGE] Anchor line out of range (1..${lines.length}).`);
        } else {
          throw new Error(
            `[E_HASH_MISMATCH] Line ${start.line} tag mismatch in ${cleanPath}: expected #${start.tag}, actual #${startTagNow}. Re-read before editing.`,
          );
        }
      }
      if (seen) {
        if (rebasedNotes.length === 0) {
          for (let ln = effectiveStart; ln <= effectiveEnd; ln++) {
            if (!seen.has(ln)) {
              throw new Error(`[E_UNSEEN_LINE] Line ${ln} in ${cleanPath} was not read in this session. Read it before editing.`);
            }
          }
        } else if (!seen.has(effectiveStart) && !seen.has(start.line)) {
          throw new Error(`[E_UNSEEN_LINE] Line ${start.line} in ${cleanPath} was not read in this session. Read it before editing.`);
        }
      }
      if (op.end_anchor) {
        const actualEndTag = lineHashTag(lines[effectiveEnd - 1]);
        if (actualEndTag !== end.tag) {
          throw new Error(
            `[E_HASH_MISMATCH] End line ${effectiveEnd} tag mismatch in ${cleanPath}: expected #${end.tag}, actual #${actualEndTag}. Re-read before editing.`,
          );
        }
      }
      return {
        startLine: effectiveStart,
        endLine: effectiveEnd,
        op: op.op ?? "replace",
        content: op.content !== undefined ? normalizeEditDialect(op.content) : "",
      };
    });

    // Sort bottom-up so earlier indices stay valid and reject overlapping ranges.
    resolvedOps.sort((a, b) => b.startLine - a.startLine);
    for (let i = 1; i < resolvedOps.length; i++) {
      if (resolvedOps[i].endLine >= resolvedOps[i - 1].startLine) {
        throw new Error(`[E_OVERLAPPING_EDITS] Edits overlap around line ${resolvedOps[i - 1].startLine}.`);
      }
    }

    nextLines = [...lines];
    for (const op of resolvedOps) {
      const replacementLines = op.op === "delete" ? [] : op.content === "" ? [] : op.content.split("\n");
      if (op.op === "insert_after") {
        nextLines.splice(op.endLine, 0, ...replacementLines);
      } else {
        nextLines.splice(op.startLine - 1, op.endLine - op.startLine + 1, ...replacementLines);
      }
    }
  } else {
    const oldStr = input.oldText ?? input.old_string;
    const newStr = input.newText ?? input.new_string;
    if (typeof oldStr !== "string" || typeof newStr !== "string") {
      throw new Error("edit requires either `edits` (hashline operations) or `oldText` + `newText`.");
    }
    const normOld = normalizeEditDialect(oldStr);
    const normNew = normalizeEditDialect(newStr);
    const normCur = currentContent.replace(/\r\n/g, "\n");
    const firstIdx = normCur.indexOf(normOld);
    if (firstIdx === -1) {
      throw new Error(`Could not find exact oldText in ${cleanPath}.`);
    }
    if (normOld.length > 0 && normCur.indexOf(normOld, firstIdx + 1) !== -1) {
      throw new Error(`oldText matched multiple locations in ${cleanPath}; use hashline anchors or include more context.`);
    }
    const replaced = normCur.slice(0, firstIdx) + normNew + normCur.slice(firstIdx + normOld.length);
    nextLines = replaced.split("\n");
  }

  const nextContent = nextLines.join("\n");
  const changed = nextContent !== currentContent;

  if (!changed) {
    const noopKey = `${resolved}:${payloadKey}`;
    const count = (state.noopCounts.get(noopKey) ?? 0) + 1;
    state.noopCounts.set(noopKey, count);
    if (count >= 3) {
      throw new Error(`[E_NOOP_LOOP] Aborted after ${count} identical no-op edits on ${cleanPath}.`);
    }
    return {
      nextContent,
      changed: false,
      snapshotTag: currentTag,
      diffPreview: `[${cleanPath}#${currentTag}] No changes (noop ${count}/3).`,
    };
  }

  state.noopCounts.clear();
  const nextTag = computeFileSnapshotTag(nextContent);
  state.lastSuccessPayload.set(resolved, { payloadKey, snapshot: nextTag });

  // Mark newly produced line range as seen so follow-up edits on the same hunk work directly.
  let seen = state.seenLines.get(resolved);
  if (!seen) {
    seen = new Set<number>();
    state.seenLines.set(resolved, seen);
  }
  for (let i = 1; i <= nextLines.length; i++) {
    seen.add(i);
  }

  const basePreview = buildCompactDiff(lines, nextLines, cleanPath, nextTag);
  return {
    nextContent,
    changed: true,
    snapshotTag: nextTag,
    diffPreview: rebasedNotes.length > 0 ? `${rebasedNotes.join(" ")} ${basePreview}` : basePreview,
  };
}

/**
 * Find a unique matching line within `+/- window` lines when a line number
 * drifted after another edit. Fails closed (returns null) if 0 or >=2 matches exist.
 */
export function findUniqueRebasedLine(
  lines: string[],
  expectedLine: number,
  expectedTag: string,
  window = 15,
): number | null {
  const tag = expectedTag.toLowerCase();
  const minLine = Math.max(1, expectedLine - window);
  const maxLine = Math.min(lines.length, expectedLine + window);
  const matches: number[] = [];
  for (let ln = minLine; ln <= maxLine; ln++) {
    if (lineHashTag(lines[ln - 1]) === tag) {
      matches.push(ln);
      if (matches.length > 1) return null;
    }
  }
  return matches.length === 1 ? matches[0] : null;
}

export interface CasUndoEntry {
  digest: string;
  absPath: string;
  content: string;
  ts: number;
}

/** Bounded Content-Addressed Snapshot store for 0-token edit rollbacks. */
export class CasUndoStore {
  private entries: CasUndoEntry[] = [];
  private blobs = new Map<string, string>();

  constructor(readonly maxEntries = 32) {}

  push(absPath: string, content: string): string {
    const resolved = path.resolve(absPath);
    const digest = createHash("sha256").update(content, "utf-8").digest("hex").slice(0, 16);
    if (!this.blobs.has(digest)) {
      this.blobs.set(digest, content);
    }
    this.entries.push({ digest, absPath: resolved, content, ts: Date.now() });
    while (this.entries.length > this.maxEntries) {
      const dropped = this.entries.shift();
      if (dropped && !this.entries.some((e) => e.digest === dropped.digest)) {
        this.blobs.delete(dropped.digest);
      }
    }
    return digest;
  }

  pop(absPath?: string): CasUndoEntry | null {
    if (this.entries.length === 0) return null;
    let idx = this.entries.length - 1;
    if (absPath) {
      const resolved = path.resolve(absPath);
      idx = -1;
      for (let i = this.entries.length - 1; i >= 0; i--) {
        if (this.entries[i].absPath === resolved) {
          idx = i;
          break;
        }
      }
      if (idx === -1) return null;
    }
    const [entry] = this.entries.splice(idx, 1);
    const body = this.blobs.get(entry.digest) ?? entry.content;
    if (!this.entries.some((e) => e.digest === entry.digest)) {
      this.blobs.delete(entry.digest);
    }
    return { ...entry, content: body };
  }

  list(): Array<{ digest: string; absPath: string; ts: number }> {
    return this.entries.map(({ digest, absPath: p, ts }) => ({ digest, absPath: p, ts }));
  }
}
