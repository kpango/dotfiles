/**
 * Self-hosted LSP Client Core (JSON-RPC 2.0 over stdio, zero external deps).
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const MODULE_DIR =
  typeof import.meta.dir === "string"
    ? import.meta.dir
    : typeof __dirname === "string"
      ? __dirname
      : path.dirname(fileURLToPath(import.meta.url));

export interface LspServerConfig {
  command: string;
  fallbackCommand?: string;
  args?: string[];
  fileTypes: string[];
  rootMarkers?: string[];
  settings?: Record<string, unknown>;
  capabilities?: Record<string, unknown>;
}

export interface LspConfig {
  idleTimeoutMs?: number;
  servers: Record<string, LspServerConfig>;
}

export interface LspDiagnostic {
  range: { start: { line: number; character: number }; end: { line: number; character: number } };
  severity?: number;
  message: string;
  source?: string;
  code?: string | number;
}

export interface LspTextEdit {
  range: { start: { line: number; character: number }; end: { line: number; character: number } };
  newText: string;
}

export function loadLspConfig(candidatePaths?: string[]): LspConfig {
  const paths = candidatePaths ?? [
    path.join(os.homedir(), ".pi", "agent", "lsp.json"),
    path.resolve(MODULE_DIR, "..", "..", "lsp.json"),
  ];
  for (const p of paths) {
    try {
      if (fs.existsSync(p)) {
        const parsed = JSON.parse(fs.readFileSync(p, "utf-8")) as LspConfig;
        if (parsed && typeof parsed === "object" && parsed.servers) {
          return parsed;
        }
      }
    } catch {
      // Fall through to next candidate.
    }
  }
  return { idleTimeoutMs: 300_000, servers: {} };
}

export function resolveServerCommandOverride(
  serverName: string,
  env: NodeJS.ProcessEnv = process.env,
): { command: string; args: string[] } | null {
  const envKey = `PI_${serverName.toUpperCase().replace(/[^A-Z0-9]+/g, "_")}_LSP_COMMAND`;
  const raw = env[envKey];
  if (!raw || !raw.trim()) return null;
  const parts = raw.trim().split(/\s+/);
  return { command: parts[0], args: parts.slice(1) };
}

export function matchLspServerForFile(
  config: LspConfig,
  filePath: string,
  cwd: string,
): { serverName: string; server: LspServerConfig; rootDir: string } | null {
  const base = path.basename(filePath);
  const ext = path.extname(filePath).toLowerCase();

  for (const [serverName, server] of Object.entries(config.servers || {})) {
    const matches = server.fileTypes.some((ft) => ft === base || ft.toLowerCase() === ext);
    if (!matches) continue;

    let rootDir = path.resolve(cwd);
    const markers = server.rootMarkers ?? [];
    if (markers.length > 0) {
      let cur = path.dirname(path.resolve(cwd, filePath));
      while (true) {
        if (markers.some((m) => fs.existsSync(path.join(cur, m)))) {
          rootDir = cur;
          break;
        }
        const parent = path.dirname(cur);
        if (parent === cur) break;
        cur = parent;
      }
    }
    return { serverName, server, rootDir };
  }
  return null;
}

export function encodeLspMessage(payload: unknown): Buffer {
  const body = Buffer.from(JSON.stringify(payload), "utf-8");
  const header = Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, "ascii");
  return Buffer.concat([header, body]);
}

export class LspMessageParser {
  private buf: Buffer = Buffer.alloc(0);

  push(chunk: Buffer): unknown[] {
    this.buf = Buffer.concat([this.buf, chunk]);
    const messages: unknown[] = [];

    while (true) {
      const headerEnd = this.buf.indexOf("\r\n\r\n");
      if (headerEnd === -1) break;
      const header = this.buf.subarray(0, headerEnd).toString("ascii");
      const m = /Content-Length:\s*(\d+)/i.exec(header);
      if (!m) {
        this.buf = this.buf.subarray(headerEnd + 4);
        continue;
      }
      const len = Number.parseInt(m[1], 10);
      const bodyStart = headerEnd + 4;
      if (this.buf.length < bodyStart + len) break;

      const jsonBytes = this.buf.subarray(bodyStart, bodyStart + len).toString("utf-8");
      this.buf = this.buf.subarray(bodyStart + len);
      try {
        messages.push(JSON.parse(jsonBytes));
      } catch {
        // Ignore malformed JSON-RPC frame.
      }
    }

    return messages;
  }
}

export function positionToOffset(content: string, line: number, character: number): number {
  const lines = content.split("\n");
  const targetLine = Math.max(0, Math.min(line, lines.length - 1));
  let offset = 0;
  for (let i = 0; i < targetLine; i++) {
    offset += lines[i].length + 1;
  }
  const lineStr = lines[targetLine] ?? "";
  return offset + Math.max(0, Math.min(character, lineStr.length));
}

export function applyNonOverlappingTextEdits(content: string, edits: LspTextEdit[]): string {
  if (edits.length === 0) return content;
  const spans = edits.map((e) => ({
    start: positionToOffset(content, e.range.start.line, e.range.start.character),
    end: positionToOffset(content, e.range.end.line, e.range.end.character),
    newText: e.newText,
  }));
  spans.sort((a, b) => a.start - b.start || a.end - b.end);
  for (let i = 1; i < spans.length; i++) {
    if (spans[i].start < spans[i - 1].end) {
      throw new Error("Refusing to apply overlapping LSP TextEdits.");
    }
  }
  let out = content;
  for (let i = spans.length - 1; i >= 0; i--) {
    out = out.slice(0, spans[i].start) + spans[i].newText + out.slice(spans[i].end);
  }
  return out;
}

export function formatDiagnosticsReport(
  filePath: string,
  diagnostics: LspDiagnostic[],
  errorsOnly = false,
): string {
  const filtered = errorsOnly ? diagnostics.filter((d) => (d.severity ?? 1) === 1) : diagnostics;
  if (filtered.length === 0) return "";
  const label = (sev?: number) => (sev === 1 ? "ERROR" : sev === 2 ? "WARN" : sev === 3 ? "INFO" : "HINT");
  return filtered
    .map((d) => {
      const ln = d.range.start.line + 1;
      const col = d.range.start.character + 1;
      const src = d.source ? `[${d.source}] ` : "";
      return `${filePath}:${ln}:${col}: ${label(d.severity)} ${src}${d.message}`;
    })
    .join("\n");
}

export interface DeltaDiagnosticsResult {
  added: LspDiagnostic[];
  persistedCount: number;
  resolvedCount: number;
}

export function diagnosticFingerprint(d: LspDiagnostic): string {
  const line = d.range?.start?.line ?? -1;
  const ch = d.range?.start?.character ?? -1;
  return `${d.severity ?? 1}:${line}:${ch}:${d.source ?? ""}:${d.code ?? ""}:${d.message}`;
}

export function computeDeltaDiagnostics(
  prev: LspDiagnostic[],
  next: LspDiagnostic[],
  errorsOnly = true,
): DeltaDiagnosticsResult {
  const filterFn = (list: LspDiagnostic[]) =>
    errorsOnly ? list.filter((d) => (d.severity ?? 1) === 1) : list;
  const prevFiltered = filterFn(prev);
  const nextFiltered = filterFn(next);

  const prevSet = new Set(prevFiltered.map(diagnosticFingerprint));
  const nextSet = new Set(nextFiltered.map(diagnosticFingerprint));

  const added = nextFiltered.filter((d) => !prevSet.has(diagnosticFingerprint(d)));
  let persistedCount = 0;
  for (const d of nextFiltered) {
    if (prevSet.has(diagnosticFingerprint(d))) persistedCount++;
  }
  let resolvedCount = 0;
  for (const d of prevFiltered) {
    if (!nextSet.has(diagnosticFingerprint(d))) resolvedCount++;
  }
  return { added, persistedCount, resolvedCount };
}

export function formatDeltaDiagnosticsReport(
  filePath: string,
  delta: DeltaDiagnosticsResult,
  errorsOnly = true,
): string {
  if (delta.added.length === 0) {
    return delta.resolvedCount > 0
      ? `[LSP delta] ${filePath}: resolved ${delta.resolvedCount} diagnostic(s); ${delta.persistedCount} pre-existing.`
      : "";
  }
  const body = formatDiagnosticsReport(filePath, delta.added, errorsOnly);
  const tail =
    delta.persistedCount > 0 ? `\n(+ ${delta.persistedCount} pre-existing unchanged diagnostic(s) suppressed)` : "";
  return `${body}${tail}`;
}

export function formatHonestyNotice(
  serverName: string,
  reason: "cold" | "timeout" | "unavailable",
  detail?: string,
): string {
  const suffix = detail ? `: ${detail}` : "";
  return `[LSP diagnostics: unconfirmed (${serverName}: ${reason}${suffix})]`;
}

export function isGitCommitOrPushCommand(cmd: string): boolean {
  const s = cmd.trim();
  if (!s) return false;
  return /(?:^|\s|&&|\|\||;)git\s+(?:commit|push)\b/.test(s);
}

export function guessLanguageId(filePath: string): string {
  const ext = path.extname(filePath).toLowerCase();
  const map: Record<string, string> = {
    ".go": "go",
    ".rs": "rust",
    ".ts": "typescript",
    ".tsx": "typescriptreact",
    ".js": "javascript",
    ".jsx": "javascriptreact",
    ".py": "python",
    ".c": "c",
    ".cc": "cpp",
    ".cpp": "cpp",
    ".h": "c",
    ".hpp": "cpp",
    ".sh": "shellscript",
    ".bash": "shellscript",
    ".zsh": "shellscript",
    ".nix": "nix",
  };
  return map[ext] ?? "plaintext";
}
