/**
 * Self-hosted DAP (Debug Adapter Protocol) Client Core (zero external deps).
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

export interface DapAdapterConfig {
  command: string;
  connectMode?: "stdio" | "socket";
  transport?: "stdio" | "socket";
  args?: string[];
  fileTypes: string[];
  rootMarkers?: string[];
  launchDefaults?: Record<string, unknown>;
}

export interface DapConfig {
  adapters: Record<string, DapAdapterConfig>;
}

export interface DapStackFrame {
  id: number;
  name: string;
  line: number;
  column: number;
  source?: { name?: string; path?: string };
}

export interface DapVariable {
  name: string;
  value: string;
  type?: string;
  variablesReference: number;
}

export function loadDapConfig(candidatePaths?: string[]): DapConfig {
  const paths = candidatePaths ?? [
    path.join(os.homedir(), ".pi", "agent", "dap.json"),
    path.resolve(MODULE_DIR, "..", "..", "dap.json"),
  ];
  for (const p of paths) {
    try {
      if (fs.existsSync(p)) {
        const parsed = JSON.parse(fs.readFileSync(p, "utf-8")) as DapConfig;
        if (parsed && typeof parsed === "object" && parsed.adapters) {
          return parsed;
        }
      }
    } catch {
      // Fall through to next candidate.
    }
  }
  return { adapters: {} };
}

export function matchDapAdapter(
  config: DapConfig,
  hintOrFile?: string,
  adapterName?: string,
  cwd: string = process.cwd(),
): { adapterName: string; adapter: DapAdapterConfig; rootDir: string } | null {
  const entries = Object.entries(config.adapters || {});
  if (adapterName && config.adapters?.[adapterName]) {
    const adapter = config.adapters[adapterName];
    return {
      adapterName,
      adapter,
      rootDir: resolveRootDir(hintOrFile, adapter.rootMarkers ?? [], cwd),
    };
  }
  if (!hintOrFile) return null;
  const base = path.basename(hintOrFile);
  const ext = path.extname(hintOrFile).toLowerCase();
  for (const [name, adapter] of entries) {
    if (adapter.fileTypes.some((ft) => ft === base || ft.toLowerCase() === ext)) {
      return {
        adapterName: name,
        adapter,
        rootDir: resolveRootDir(hintOrFile, adapter.rootMarkers ?? [], cwd),
      };
    }
  }
  return null;
}

function resolveRootDir(hintOrFile: string | undefined, markers: string[], cwd: string): string {
  const absCwd = path.resolve(cwd);
  if (!hintOrFile || markers.length === 0) return absCwd;
  const start = fs.existsSync(hintOrFile) && fs.statSync(hintOrFile).isDirectory()
    ? path.resolve(absCwd, hintOrFile)
    : path.dirname(path.resolve(absCwd, hintOrFile));
  let cur = start;
  while (true) {
    if (markers.some((m) => fs.existsSync(path.join(cur, m)))) {
      return cur;
    }
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  return absCwd;
}

export function encodeDapMessage(payload: unknown): Buffer {
  const body = Buffer.from(JSON.stringify(payload), "utf-8");
  const header = Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, "ascii");
  return Buffer.concat([header, body]);
}

export class DapMessageParser {
  private buf = Buffer.alloc(0);

  push(chunk: Buffer): Array<Record<string, unknown>> {
    this.buf = Buffer.concat([this.buf, chunk]);
    const messages: Array<Record<string, unknown>> = [];

    while (true) {
      const sepIdx = this.buf.indexOf("\r\n\r\n");
      if (sepIdx === -1) break;
      const headerStr = this.buf.slice(0, sepIdx).toString("ascii");
      const match = /Content-Length:\s*(\d+)/i.exec(headerStr);
      if (!match) {
        this.buf = this.buf.slice(sepIdx + 4);
        continue;
      }
      const len = Number.parseInt(match[1], 10);
      const bodyStart = sepIdx + 4;
      if (this.buf.length < bodyStart + len) break;

      const body = this.buf.slice(bodyStart, bodyStart + len).toString("utf-8");
      this.buf = this.buf.slice(bodyStart + len);
      try {
        messages.push(JSON.parse(body) as Record<string, unknown>);
      } catch {
        // Skip malformed DAP payload.
      }
    }

    return messages;
  }
}

export function parseDlvListenEndpoint(output: string): { host: string; port: number } | null {
  const match = /listening at:\s*([^\s:]+):(\d+)/i.exec(output);
  if (!match) return null;
  const port = Number.parseInt(match[2], 10);
  if (!Number.isFinite(port) || port <= 0) return null;
  return { host: match[1], port };
}

export function formatStackFrames(frames: DapStackFrame[]): string {
  if (frames.length === 0) return "(no stack frames)";
  return frames
    .map((f) => {
      const loc = f.source?.path ?? f.source?.name ?? "<unknown>";
      return `#${f.id} ${f.name} at ${loc}:${f.line}:${f.column}`;
    })
    .join("\n");
}

export function formatVariables(vars: DapVariable[]): string {
  if (vars.length === 0) return "(no variables)";
  return vars
    .map((v) => {
      const typePart = v.type ? `: ${v.type}` : "";
      const refPart = v.variablesReference > 0 ? ` [ref=${v.variablesReference}]` : "";
      return `${v.name}${typePart} = ${v.value}${refPart}`;
    })
    .join("\n");
}
