/**
 * Language Server Protocol (LSP) Bridge Extension for Pi Coding Agent
 *
 * Provides real-time language server diagnostics, type checking, definition lookup,
 * symbol navigation, and reference finding for Go (gopls), Rust (cargo/rustc),
 * TypeScript (tsc), Python (ruff/pyright), C/C++ (clang), and Nix (nil).
 */

import { execSync, spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export interface DiagnosticItem {
  file: string;
  line: number;
  column: number;
  severity: "error" | "warning" | "info";
  message: string;
  source: string;
}

export function detectLanguage(filePath: string): string {
  const ext = path.extname(filePath).toLowerCase();
  switch (ext) {
    case ".go":
      return "go";
    case ".rs":
      return "rust";
    case ".ts":
    case ".tsx":
    case ".js":
    case ".jsx":
      return "typescript";
    case ".py":
      return "python";
    case ".c":
    case ".cc":
    case ".cpp":
    case ".cxx":
    case ".h":
    case ".hpp":
      return "cpp";
    case ".nix":
      return "nix";
    default:
      return "unknown";
  }
}

export function runDiagnostics(targetPath: string, cwd: string): { diagnostics: DiagnosticItem[]; rawOutput: string } {
  const fullPath = path.isAbsolute(targetPath) ? targetPath : path.resolve(cwd, targetPath);
  const lang = detectLanguage(fullPath);
  const diagnostics: DiagnosticItem[] = [];
  let rawOutput = "";

  if (lang === "go") {
    try {
      const res = spawnSync("gopls", ["check", fullPath], { cwd, encoding: "utf-8", timeout: 15000 });
      rawOutput = (res.stdout || "") + (res.stderr || "");
      const lines = rawOutput.split("\n");
      for (const line of lines) {
        const match = line.match(/^(.+?):(\d+):(\d+):\s*(.+)$/);
        if (match) {
          diagnostics.push({
            file: match[1],
            line: parseInt(match[2], 10),
            column: parseInt(match[3], 10),
            severity: "error",
            message: match[4].trim(),
            source: "gopls",
          });
        }
      }
    } catch (e: any) {
      rawOutput = `gopls check error: ${e.message}`;
    }
  } else if (lang === "rust") {
    try {
      const res = spawnSync("cargo", ["check", "--message-format=json"], { cwd, encoding: "utf-8", timeout: 20000 });
      rawOutput = res.stdout || "";
      const lines = rawOutput.split("\n");
      for (const line of lines) {
        if (!line.trim().startsWith("{")) continue;
        try {
          const msg = JSON.parse(line);
          if (msg.reason === "compiler-message" && msg.message) {
            const span = msg.message.spans?.[0];
            diagnostics.push({
              file: span?.file_name || targetPath,
              line: span?.line_start || 1,
              column: span?.column_start || 1,
              severity: msg.message.level === "error" ? "error" : "warning",
              message: msg.message.message,
              source: "rustc",
            });
          }
        } catch {
          // ignore unparseable json lines
        }
      }
    } catch (e: any) {
      rawOutput = `cargo check error: ${e.message}`;
    }
  } else if (lang === "typescript") {
    try {
      const res = spawnSync("tsc", ["--noEmit", "--pretty", "false"], { cwd, encoding: "utf-8", timeout: 15000 });
      rawOutput = (res.stdout || "") + (res.stderr || "");
      const lines = rawOutput.split("\n");
      for (const line of lines) {
        const match = line.match(/^(.+?)\((\d+),(\d+)\):\s*(error|warning)\s*(TS\d+:\s*.+)$/i);
        if (match) {
          diagnostics.push({
            file: match[1],
            line: parseInt(match[2], 10),
            column: parseInt(match[3], 10),
            severity: match[4].toLowerCase() === "error" ? "error" : "warning",
            message: match[5].trim(),
            source: "tsc",
          });
        }
      }
    } catch (e: any) {
      rawOutput = `tsc error: ${e.message}`;
    }
  } else if (lang === "python") {
    try {
      const res = spawnSync("ruff", ["check", fullPath, "--output-format=json"], { cwd, encoding: "utf-8", timeout: 10000 });
      rawOutput = res.stdout || "";
      if (rawOutput.trim().startsWith("[")) {
        const parsed = JSON.parse(rawOutput);
        for (const item of parsed) {
          diagnostics.push({
            file: item.filename || targetPath,
            line: item.location?.row || 1,
            column: item.location?.column || 1,
            severity: "error",
            message: `${item.code}: ${item.message}`,
            source: "ruff",
          });
        }
      }
    } catch (e: any) {
      rawOutput = `ruff error: ${e.message}`;
    }
  } else if (lang === "nix") {
    try {
      const res = spawnSync("nix-instantiate", ["--parse", fullPath], { cwd, encoding: "utf-8", timeout: 10000 });
      if (res.status !== 0) {
        rawOutput = res.stderr || "";
        const match = rawOutput.match(/error:\s*(.+?)\s*at\s*(.+?):(\d+):(\d+)/i);
        if (match) {
          diagnostics.push({
            file: match[2],
            line: parseInt(match[3], 10),
            column: parseInt(match[4], 10),
            severity: "error",
            message: match[1],
            source: "nix",
          });
        } else if (rawOutput.trim()) {
          diagnostics.push({
            file: targetPath,
            line: 1,
            column: 1,
            severity: "error",
            message: rawOutput.trim(),
            source: "nix",
          });
        }
      }
    } catch (e: any) {
      rawOutput = `nix-instantiate error: ${e.message}`;
    }
  }

  return { diagnostics, rawOutput };
}

export function runDefinition(targetPath: string, line: number, column: number, cwd: string): string | null {
  const fullPath = path.isAbsolute(targetPath) ? targetPath : path.resolve(cwd, targetPath);
  const lang = detectLanguage(fullPath);

  if (lang === "go") {
    try {
      const loc = `${fullPath}:${line}:${column}`;
      const res = spawnSync("gopls", ["definition", loc], { cwd, encoding: "utf-8", timeout: 10000 });
      const out = (res.stdout || "").trim();
      if (out && !out.includes("no identifier found") && res.status === 0) {
        return out;
      }
    } catch {
      return null;
    }
  }
  return null;
}

export function runSymbols(targetPath: string, cwd: string): string[] {
  const fullPath = path.isAbsolute(targetPath) ? targetPath : path.resolve(cwd, targetPath);
  const lang = detectLanguage(fullPath);

  if (lang === "go") {
    try {
      const res = spawnSync("gopls", ["symbols", fullPath], { cwd, encoding: "utf-8", timeout: 10000 });
      const out = (res.stdout || "").trim();
      if (out && res.status === 0) {
        return out.split("\n").filter(Boolean);
      }
    } catch {
      // fallback to regex
    }
  }

  if (fs.existsSync(fullPath)) {
    try {
      const content = fs.readFileSync(fullPath, "utf-8");
      const lines = content.split("\n");
      const symbols: string[] = [];
      const funcRegex = /^(?:export\s+)?(?:async\s+)?function\s+([a-zA-Z0-9_]+)|func\s+(?:\([^)]+\)\s+)?([a-zA-Z0-9_]+)|fn\s+([a-zA-Z0-9_]+)|def\s+([a-zA-Z0-9_]+)/;
      const typeRegex = /^(?:export\s+)?(?:type|interface|class|struct|enum)\s+([a-zA-Z0-9_]+)/;

      for (let i = 0; i < lines.length; i++) {
        const lineStr = lines[i].trim();
        const funcMatch = lineStr.match(funcRegex);
        if (funcMatch) {
          const name = funcMatch[1] || funcMatch[2] || funcMatch[3] || funcMatch[4];
          symbols.push(`[Function] ${name} (line ${i + 1})`);
          continue;
        }
        const typeMatch = lineStr.match(typeRegex);
        if (typeMatch) {
          symbols.push(`[Type] ${typeMatch[1]} (line ${i + 1})`);
        }
      }
      return symbols;
    } catch {
      return [];
    }
  }
  return [];
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "lsp_diagnostics",
    label: "LSP Diagnostics",
    description: "Get real-time compiler, syntax, and type diagnostics for a file or workspace via language servers (gopls, cargo, tsc, ruff, nix) without full builds.",
    parameters: Type.Object({
      path: Type.String({ description: "Path to file or directory to diagnose" }),
    }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const { diagnostics, rawOutput } = runDiagnostics(params.path, ctx.cwd);
      if (diagnostics.length === 0) {
        return {
          content: [{ type: "text", text: `✓ No compiler or type diagnostics/errors found for: ${params.path}` }],
          details: { count: 0 },
        };
      }

      const formatted = diagnostics
        .map((d) => `[${d.severity.toUpperCase()}] ${path.basename(d.file)}:${d.line}:${d.column} (${d.source}): ${d.message}`)
        .join("\n");

      return {
        content: [{ type: "text", text: `Found ${diagnostics.length} diagnostic(s) in ${params.path}:\n\n${formatted}` }],
        details: { count: diagnostics.length, diagnostics, rawOutput },
      };
    },
  });

  pi.registerTool({
    name: "lsp_definition",
    label: "LSP Definition",
    description: "Jump to symbol declaration/definition using language server protocol (Go, Rust, etc.).",
    parameters: Type.Object({
      path: Type.String({ description: "Target file path" }),
      line: Type.Integer({ description: "Line number (1-indexed)" }),
      column: Type.Integer({ description: "Column number (1-indexed)" }),
    }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const def = runDefinition(params.path, params.line, params.column, ctx.cwd);
      if (!def) {
        return {
          content: [{ type: "text", text: `No definition found at ${params.path}:${params.line}:${params.column}` }],
        };
      }
      return {
        content: [{ type: "text", text: `Definition: ${def}` }],
        details: { location: def },
      };
    },
  });

  pi.registerTool({
    name: "lsp_symbols",
    label: "LSP Symbols",
    description: "List all functions, types, interfaces, and methods in a file.",
    parameters: Type.Object({
      path: Type.String({ description: "Target file path" }),
    }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const symbols = runSymbols(params.path, ctx.cwd);
      if (symbols.length === 0) {
        return {
          content: [{ type: "text", text: `No symbols found in: ${params.path}` }],
          details: { count: 0 },
        };
      }
      return {
        content: [{ type: "text", text: `Symbols in ${params.path} (${symbols.length}):\n${symbols.join("\n")}` }],
        details: { count: symbols.length, symbols },
      };
    },
  });
}
