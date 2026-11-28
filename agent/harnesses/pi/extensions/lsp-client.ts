/**
 * Self-hosted LSP Client Extension for Pi 1.7.0
 *
 * - Reads `~/.pi/agent/lsp.json` (fallback `agent/harnesses/pi/lsp.json`).
 * - Registers `lsp` tool (diagnostics, definition, type_definition, implementation,
 *   references, hover, symbols, workspace_symbols, rename, code_actions, format,
 *   status, reload).
 * - Automatically attaches ERROR diagnostics after `edit`/`write` unless
 *   `PI_LSP_DIAGNOSTICS_ON_EDIT=0`.
 */

import { spawn, spawnSync, type ChildProcessWithoutNullStreams } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Container, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import {
  LspMessageParser,
  applyNonOverlappingTextEdits,
  computeDeltaDiagnostics,
  encodeLspMessage,
  formatDiagnosticsReport,
  formatDeltaDiagnosticsReport,
  formatHonestyNotice,
  guessLanguageId,
  isGitCommitOrPushCommand,
  loadLspConfig,
  matchLspServerForFile,
  resolveServerCommandOverride,
  type LspConfig,
  type LspDiagnostic,
  type LspServerConfig,
  type LspTextEdit,
} from "./lib/lsp-core";

export * from "./lib/lsp-core";

interface ActiveLspClient {
  key: string;
  serverName: string;
  rootDir: string;
  proc: ChildProcessWithoutNullStreams;
  nextId: number;
  pending: Map<number, { resolve: (v: any) => void; reject: (e: Error) => void }>;
  diagnostics: Map<string, LspDiagnostic[]>;
  openedVersions: Map<string, number>;
  stderrLines: string[];
  lastUsed: number;
  supportsPullDiag: boolean;
}

function commandExists(cmd: string): boolean {
  const res = spawnSync("which", [cmd], { stdio: "ignore" });
  return res.status === 0;
}

export default function (pi: ExtensionAPI) {
  let config: LspConfig = loadLspConfig();
  const clients = new Map<string, ActiveLspClient>();
  const lastDiagnosticsByFile = new Map<string, LspDiagnostic[]>();
  const unresolvedErrorsByFile = new Map<string, number>();

  const shutdownAll = () => {
    for (const c of clients.values()) {
      try {
        c.proc.kill("SIGTERM");
      } catch {
        // Ignore cleanup errors.
      }
    }
    clients.clear();
    lastDiagnosticsByFile.clear();
    unresolvedErrorsByFile.clear();
  };

  pi.on("session_start", async () => {
    lastDiagnosticsByFile.clear();
    unresolvedErrorsByFile.clear();
  });

  pi.on("session_shutdown", async () => {
    shutdownAll();
  });

  async function sendRequest(client: ActiveLspClient, method: string, params: unknown, timeoutMs = 15_000): Promise<any> {
    client.lastUsed = Date.now();
    const id = client.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        client.pending.delete(id);
        reject(new Error(`LSP ${method} timed out after ${timeoutMs}ms (stderr: ${client.stderrLines.slice(-3).join(" | ")})`));
      }, timeoutMs);
      client.pending.set(id, {
        resolve: (v) => {
          clearTimeout(timer);
          resolve(v);
        },
        reject: (e) => {
          clearTimeout(timer);
          reject(e);
        },
      });
      client.proc.stdin.write(encodeLspMessage({ jsonrpc: "2.0", id, method, params }));
    });
  }

  function sendNotification(client: ActiveLspClient, method: string, params: unknown): void {
    client.lastUsed = Date.now();
    client.proc.stdin.write(encodeLspMessage({ jsonrpc: "2.0", method, params }));
  }

  async function ensureClient(serverName: string, server: LspServerConfig, rootDir: string): Promise<ActiveLspClient> {
    const key = `${serverName}::${rootDir}`;
    const existing = clients.get(key);
    if (existing && !existing.proc.killed && existing.proc.exitCode === null) {
      existing.lastUsed = Date.now();
      return existing;
    }

    const override = resolveServerCommandOverride(serverName);
    let command = override?.command ?? server.command;
    let args = override?.args ?? server.args ?? [];
    if (!override && !commandExists(command) && server.fallbackCommand && commandExists(server.fallbackCommand)) {
      command = server.fallbackCommand;
      args = [];
    }
    if (!commandExists(command)) {
      throw new Error(`LSP server binary not found: ${command}`);
    }

    const proc = spawn(command, args, { cwd: rootDir, stdio: ["pipe", "pipe", "pipe"] });
    const client: ActiveLspClient = {
      key,
      serverName,
      rootDir,
      proc,
      nextId: 1,
      pending: new Map(),
      diagnostics: new Map(),
      openedVersions: new Map(),
      stderrLines: [],
      lastUsed: Date.now(),
      supportsPullDiag: false,
    };
    const parser = new LspMessageParser();

    proc.stdout.on("data", (chunk: Buffer) => {
      for (const msg of parser.push(chunk) as Array<{ id?: number; method?: string; params?: any; result?: any; error?: any }>) {
        if (typeof msg.id === "number" && (msg.result !== undefined || msg.error !== undefined)) {
          const p = client.pending.get(msg.id);
          if (p) {
            client.pending.delete(msg.id);
            if (msg.error) p.reject(new Error(msg.error.message || JSON.stringify(msg.error)));
            else p.resolve(msg.result);
          }
        } else if (msg.method === "textDocument/publishDiagnostics" && msg.params?.uri) {
          client.diagnostics.set(msg.params.uri, Array.isArray(msg.params.diagnostics) ? msg.params.diagnostics : []);
        }
      }
    });

    proc.stderr.on("data", (chunk: Buffer) => {
      const lines = chunk.toString("utf-8").split("\n").filter(Boolean);
      client.stderrLines.push(...lines);
      if (client.stderrLines.length > 30) client.stderrLines.splice(0, client.stderrLines.length - 30);
    });

    proc.on("exit", () => {
      for (const p of client.pending.values()) {
        p.reject(new Error(`LSP server ${serverName} exited`));
      }
      client.pending.clear();
      clients.delete(key);
    });

    clients.set(key, client);

    const initResult = await sendRequest(client, "initialize", {
      processId: process.pid,
      rootUri: pathToFileURL(rootDir).href,
      capabilities: {
        textDocument: {
          publishDiagnostics: { relatedInformation: true },
          diagnostic: { dynamicRegistration: false },
          hover: { contentFormat: ["markdown", "plaintext"] },
        },
        ...(server.capabilities ?? {}),
      },
      initializationOptions: server.settings ?? {},
    });
    client.supportsPullDiag = Boolean(initResult?.capabilities?.diagnosticProvider);
    sendNotification(client, "initialized", {});
    return client;
  }

  async function syncDocument(client: ActiveLspClient, absPath: string): Promise<string> {
    const uri = pathToFileURL(absPath).href;
    const text = fs.readFileSync(absPath, "utf-8");
    const prevVer = client.openedVersions.get(uri);
    if (prevVer === undefined) {
      client.openedVersions.set(uri, 1);
      sendNotification(client, "textDocument/didOpen", {
        textDocument: { uri, languageId: guessLanguageId(absPath), version: 1, text },
      });
    } else {
      const nextVer = prevVer + 1;
      client.openedVersions.set(uri, nextVer);
      sendNotification(client, "textDocument/didChange", {
        textDocument: { uri, version: nextVer },
        contentChanges: [{ text }],
      });
    }
    return uri;
  }

  async function fetchDiagnostics(client: ActiveLspClient, absPath: string, uri: string): Promise<LspDiagnostic[]> {
    if (client.supportsPullDiag) {
      try {
        const res = await sendRequest(client, "textDocument/diagnostic", { textDocument: { uri } }, 8000);
        if (Array.isArray(res?.items)) return res.items as LspDiagnostic[];
      } catch {
        // Fallback to push diagnostics.
      }
    }
    await new Promise((r) => setTimeout(r, 250));
    return client.diagnostics.get(uri) ?? [];
  }

  pi.on("tool_call", async (event) => {
    if (process.env.PI_LSP_COMMIT_GUARD === "0") return;
    if (!event || event.toolName !== "bash") return;
    const cmd = (event.input as { command?: unknown } | undefined)?.command;
    if (typeof cmd !== "string" || !isGitCommitOrPushCommand(cmd)) return;

    const blocking = [...unresolvedErrorsByFile.entries()].filter(([, n]) => n > 0);
    if (blocking.length === 0) return;

    const summary = blocking.map(([f, n]) => `${path.basename(f)}(${n})`).join(", ");
    return {
      block: true,
      reason: `Commit Guard (pi-lens): unresolved LSP errors in ${summary}. Fix diagnostics or run lsp diagnostics before commit/push.`,
    };
  });

  pi.on("tool_result", async (event, ctx) => {
    if (process.env.PI_LSP_DIAGNOSTICS_ON_EDIT === "0") return;
    if ((event.toolName !== "edit" && event.toolName !== "write") || event.isError) return;
    const rawPath = (event.input as { path?: unknown } | undefined)?.path;
    if (typeof rawPath !== "string" || !rawPath) return;
    const absPath = path.isAbsolute(rawPath) ? rawPath : path.resolve(ctx.cwd, rawPath);
    if (!fs.existsSync(absPath)) return;

    const match = matchLspServerForFile(config, absPath, ctx.cwd);
    if (!match) return;
    try {
      const client = await ensureClient(match.serverName, match.server, match.rootDir);
      const uri = await syncDocument(client, absPath);
      const diags = await fetchDiagnostics(client, absPath, uri);
      const prev = lastDiagnosticsByFile.get(absPath) ?? [];
      lastDiagnosticsByFile.set(absPath, diags);
      const errCount = diags.filter((d) => (d.severity ?? 1) === 1).length;
      if (errCount > 0) unresolvedErrorsByFile.set(absPath, errCount);
      else unresolvedErrorsByFile.delete(absPath);

      const delta = computeDeltaDiagnostics(prev, diags, true);
      const report = formatDeltaDiagnosticsReport(rawPath, delta, true);
      if (!report) return;
      return {
        content: [...event.content, { type: "text" as const, text: `\n[LSP diagnostics]\n${report}` }],
      };
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      const reason = msg.includes("timed out") ? "timeout" : msg.includes("not found") ? "unavailable" : "cold";
      return {
        content: [...event.content, { type: "text" as const, text: `\n${formatHonestyNotice(match.serverName, reason)}` }],
      };
    }
  });

  pi.registerTool({
    name: "lsp",
    exposure: "deferred",
    label: "LSP",
    description:
      "Language Server Protocol code intelligence: diagnostics, definition, type_definition, implementation, references, hover, symbols, workspace_symbols, rename, code_actions, format, status, reload.",
    parameters: Type.Object({
      action: Type.Union([
        Type.Literal("diagnostics"),
        Type.Literal("definition"),
        Type.Literal("type_definition"),
        Type.Literal("implementation"),
        Type.Literal("references"),
        Type.Literal("hover"),
        Type.Literal("symbols"),
        Type.Literal("workspace_symbols"),
        Type.Literal("rename"),
        Type.Literal("code_actions"),
        Type.Literal("format"),
        Type.Literal("status"),
        Type.Literal("reload"),
      ]),
      file: Type.Optional(Type.String({ description: "Target file path" })),
      line: Type.Optional(Type.Integer({ description: "1-based line number" })),
      character: Type.Optional(Type.Integer({ description: "1-based column number" })),
      query: Type.Optional(Type.String({ description: "Workspace symbol query or new name for rename" })),
      apply: Type.Optional(Type.Boolean({ description: "Apply edits for rename/code_actions (default false = preview)" })),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      if (params.action === "status") {
        const list = [...clients.values()].map((c) => `${c.serverName} (${c.rootDir}) pid=${c.proc.pid}`);
        return { content: [{ type: "text", text: list.length ? list.join("\n") : "No active LSP servers." }] };
      }
      if (params.action === "reload") {
        shutdownAll();
        config = loadLspConfig();
        return { content: [{ type: "text", text: `Reloaded LSP config (${Object.keys(config.servers).length} servers).` }] };
      }

      if (!params.file) {
        return { content: [{ type: "text", text: `LSP action '${params.action}' requires 'file'.` }], isError: true };
      }
      const absPath = path.isAbsolute(params.file) ? params.file : path.resolve(ctx.cwd, params.file);
      const match = matchLspServerForFile(config, absPath, ctx.cwd);
      if (!match) {
        return { content: [{ type: "text", text: `No LSP server configured for ${params.file}.` }], isError: true };
      }

      try {
        const client = await ensureClient(match.serverName, match.server, match.rootDir);
        const uri = await syncDocument(client, absPath);
        const pos = { line: Math.max(0, (params.line ?? 1) - 1), character: Math.max(0, (params.character ?? 1) - 1) };

        if (params.action === "diagnostics") {
          const diags = await fetchDiagnostics(client, absPath, uri);
          return { content: [{ type: "text", text: formatDiagnosticsReport(params.file, diags) || "No diagnostics." }] };
        }
        if (params.action === "hover") {
          const res = await sendRequest(client, "textDocument/hover", { textDocument: { uri }, position: pos });
          return { content: [{ type: "text", text: res ? JSON.stringify(res.contents, null, 2) : "No hover info." }] };
        }
        if (params.action === "definition" || params.action === "type_definition" || params.action === "implementation") {
          const methodMap = {
            definition: "textDocument/definition",
            type_definition: "textDocument/typeDefinition",
            implementation: "textDocument/implementation",
          };
          const res = await sendRequest(client, methodMap[params.action], { textDocument: { uri }, position: pos });
          return { content: [{ type: "text", text: JSON.stringify(res ?? [], null, 2) }] };
        }
        if (params.action === "references") {
          const res = await sendRequest(client, "textDocument/references", {
            textDocument: { uri },
            position: pos,
            context: { includeDeclaration: true },
          });
          return { content: [{ type: "text", text: JSON.stringify(res ?? [], null, 2) }] };
        }
        if (params.action === "symbols") {
          const res = await sendRequest(client, "textDocument/documentSymbol", { textDocument: { uri } });
          return { content: [{ type: "text", text: JSON.stringify(res ?? [], null, 2) }] };
        }
        if (params.action === "workspace_symbols") {
          const res = await sendRequest(client, "workspace/symbol", { query: params.query ?? "" });
          return { content: [{ type: "text", text: JSON.stringify(res ?? [], null, 2) }] };
        }
        if (params.action === "format") {
          const edits = (await sendRequest(client, "textDocument/formatting", {
            textDocument: { uri },
            options: { tabSize: 2, insertSpaces: true },
          })) as LspTextEdit[] | null;
          if (!Array.isArray(edits) || edits.length === 0) {
            return { content: [{ type: "text", text: "No formatting changes." }] };
          }
          const updated = applyNonOverlappingTextEdits(fs.readFileSync(absPath, "utf-8"), edits);
          fs.writeFileSync(absPath, updated, "utf-8");
          return { content: [{ type: "text", text: `Formatted ${params.file} (${edits.length} edits).` }] };
        }
        if (params.action === "rename") {
          const edit = await sendRequest(client, "textDocument/rename", {
            textDocument: { uri },
            position: pos,
            newName: params.query ?? "",
          });
          if (!params.apply || !edit?.changes) {
            return { content: [{ type: "text", text: JSON.stringify(edit ?? {}, null, 2) }] };
          }
          let count = 0;
          for (const [docUri, docEdits] of Object.entries(edit.changes as Record<string, LspTextEdit[]>)) {
            const p = new URL(docUri).pathname;
            const updated = applyNonOverlappingTextEdits(fs.readFileSync(p, "utf-8"), docEdits);
            fs.writeFileSync(p, updated, "utf-8");
            count++;
          }
          return { content: [{ type: "text", text: `Applied rename across ${count} file(s).` }] };
        }
        const actions = await sendRequest(client, "textDocument/codeAction", {
          textDocument: { uri },
          range: { start: pos, end: pos },
          context: { diagnostics: client.diagnostics.get(uri) ?? [] },
        });
        return { content: [{ type: "text", text: JSON.stringify(actions ?? [], null, 2) }] };
      } catch (err) {
        return { content: [{ type: "text", text: err instanceof Error ? err.message : String(err) }], isError: true };
      }
    },
    renderCall(args, theme) {
      return new Text(theme.fg("toolTitle", theme.bold("lsp ")) + theme.fg("accent", args.action) + (args.file ? theme.fg("dim", ` ${args.file}`) : ""), 0, 0);
    },
    renderResult(result, { expanded }, theme) {
      const container = new Container();
      const text = result.content[0]?.type === "text" ? result.content[0].text : "";
      const preview = expanded ? text : text.split("\n").slice(0, 10).join("\n");
      container.addChild(new Text(result.isError ? theme.fg("error", preview) : theme.fg("toolOutput", preview), 0, 0));
      return container;
    },
  });
}
