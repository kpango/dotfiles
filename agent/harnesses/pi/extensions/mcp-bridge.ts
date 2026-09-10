/**
 * Model Context Protocol (MCP) Client Bridge Extension for Pi Coding Agent
 *
 * Connects to stdio MCP servers (codegraph, filesystem, memory, k8s, lsp, etc.)
 * configured in ~/.pi/agent/mcp.json, dynamically registering their tools into Pi.
 */

import { ChildProcess, spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Container, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";

interface McpServerConfig {
  command?: string;
  args?: string[];
  env?: Record<string, string>;
  /** Streamable-HTTP endpoint (e.g. the Executor gateway url). When set,
   *  the client speaks MCP over HTTP instead of spawning a stdio process. */
  url?: string;
  disabled?: boolean;
}

interface McpConfigFile {
  mcpServers?: Record<string, McpServerConfig>;
}

interface McpToolSchema {
  name: string;
  description?: string;
  inputSchema?: {
    type?: string;
    properties?: Record<string, any>;
    required?: string[];
  };
}

/**
 * MCP protocol version used by the stateless 2026-07-28 specification:
 * every request carries protocolVersion + client capabilities in `_meta`,
 * and capability/version discovery is done via the mandatory
 * `server/discover` request instead of the legacy initialize handshake.
 */
export const MCP_PROTOCOL_VERSION = "2026-07-28";

export class McpClient {
  private proc: ChildProcess | null = null;
  private messageId = 1;
  private pendingRequests = new Map<
    number,
    { resolve: (val: any) => void; reject: (err: any) => void; timer: NodeJS.Timeout }
  >();
  private buffer = "";
  private protocolVersion: string = MCP_PROTOCOL_VERSION;

  constructor(
    public readonly name: string,
    private readonly config: McpServerConfig,
    private readonly cwd: string
  ) {}

  async start(timeoutMs = 2000): Promise<void> {
    if (this.config.url) {
      await this.startHttp(timeoutMs);
      return;
    }
    if (!this.config.command || typeof this.config.command !== "string") {
      throw new Error(`MCP server "${this.name}" has no valid command specified`);
    }

    const env = { ...process.env, ...(this.config.env || {}) };
    this.proc = spawn(this.config.command, this.config.args || [], {
      cwd: this.cwd,
      env,
      stdio: ["pipe", "pipe", "ignore"],
    });

    this.proc.stdout?.on("data", (chunk: Buffer) => {
      this.buffer += chunk.toString("utf-8");
      this.processBuffer();
    });

    this.proc.on("error", (err) => {
      this.rejectAll(err);
      this.proc = null;
    });

    this.proc.on("close", (code) => {
      this.rejectAll(new Error(`MCP server "${this.name}" process closed with code ${code}`));
      this.proc = null;
    });

    // Legacy stdio servers: attempt the stateless server/discover
    // (2026-07-28) first, then fall back to the initialize handshake for
    // servers that predate it. A server that answers server/discover is
    // stateless; a 2024-11-05 server rejects it and expect initialize.
    try {
      await this.request(
        "server/discover",
        { _meta: { "io.modelcontextprotocol/protocolVersion": MCP_PROTOCOL_VERSION } },
        timeoutMs
      );
    } catch {
      this.protocolVersion = "2024-11-05";
      await this.request(
        "initialize",
        {
          protocolVersion: this.protocolVersion,
          capabilities: { tools: {} },
          clientInfo: { name: "pi-mcp-bridge", version: "1.0.0" },
        },
        timeoutMs
      );
      // Send initialized notification
      this.notify("notifications/initialized", {});
    }
  }

  /**
   * Start over streamable HTTP (e.g. Executor gateway at
   * http://127.0.0.1:4788/mcp). Stateless MCP 2026-07-28 sends every request
   * as a POST carrying `_meta`; we discover capabilities with
   * `server/discover` and cache the response. Legacy servers that reject
   * server/discover fall back to initialize.
   */
  private async startHttp(timeoutMs: number): Promise<void> {
    try {
      const res = await this.httpRequestJSONRPC(
        "server/discover",
        { _meta: { "io.modelcontextprotocol/protocolVersion": MCP_PROTOCOL_VERSION } },
        timeoutMs
      );
      // Discovery response is cacheable; supportedVersions lists the versions
      // the server accepts. If the server cannot speak our stateless version
      // (no match in supportedVersions / no supportedVersions field), fall
      // back to the legacy initialize handshake.
      const supported: string[] = Array.isArray(res?.supportedVersions)
        ? res.supportedVersions
        : [];
      if (supported.length === 0 || supported.includes(MCP_PROTOCOL_VERSION)) {
        this.protocolVersion = MCP_PROTOCOL_VERSION;
        return;
      }
      this.protocolVersion = "2024-11-05";
      await this.httpRequestJSONRPC(
        "initialize",
        {
          protocolVersion: this.protocolVersion,
          capabilities: { tools: {} },
          clientInfo: { name: "pi-mcp-bridge", version: "1.0.0" },
        },
        timeoutMs
      );
      this.notify("notifications/initialized", {});
    } catch {
      this.protocolVersion = "2024-11-05";
      await this.httpRequestJSONRPC(
        "initialize",
        {
          protocolVersion: this.protocolVersion,
          capabilities: { tools: {} },
          clientInfo: { name: "pi-mcp-bridge", version: "1.0.0" },
        },
        timeoutMs
      );
      this.notify("notifications/initialized", {});
    }
  }

  /**
   * Single JSON-RPC round trip over streamable HTTP. The protocol is
   * stateless, so no persistent connection is required, but each request
   * MUST carry a JSON-RPC id (a message without id is a notification and
   * receives no response). `_meta` carries the protocol version and
   * capabilities on every request. For SSE bodies, the first payload whose
   * JSON-RPC id matches the request id is used so progress/keep-alive
   * events before the real response are not mistaken for the reply.
   */
  private async httpRequestJSONRPC(
    method: string,
    params: any,
    timeoutMs: number
  ): Promise<any> {
    const url = this.config.url!;
    if (!isAllowedMcpUrl(url)) {
      throw new Error(
        `MCP server "${this.name}" uses disallowed url (only http(s)://localhost|127.0.0.1|::1 allowed)`
      );
    }
    const id = this.messageId++;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const meta: Record<string, unknown> = {
        "io.modelcontextprotocol/protocolVersion": this.protocolVersion,
        "io.modelcontextprotocol/clientInfo": {
          name: "pi-mcp-bridge",
          version: "1.0.0",
        },
      };
      const bodyParams = { ...(params || {}), _meta: meta };
      const payload = JSON.stringify({ jsonrpc: "2.0", id, method, params: bodyParams });
      const resp = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json, text/event-stream",
        },
        body: payload,
        signal: controller.signal,
        // Loopback allow-list is only meaningful if the connection actually
        // stays on the allowed URL. Follow redirects by default would let a
        // loopback endpoint bounce the request (and _meta/payload, and later
        // tool-call arguments) to an arbitrary external host. Stateless MCP
        // has no redirect semantics, so reject any 3xx outright.
        redirect: "manual",
      });
      if (resp.status >= 300 && resp.status < 400) {
        throw new Error(
          `MCP HTTP ${method} to "${this.name}" refused redirect (HTTP ${resp.status} Location: ${resp.headers.get("location") ?? ""})`
        );
      }
      if (!resp.ok) {
        throw new Error(`MCP HTTP ${method} to "${this.name}" failed: HTTP ${resp.status}`);
      }
      const text = await resp.text();
      // Streamable HTTP may answer with a single JSON object or an SSE
      // stream. Prefer the SSE payload whose JSON-RPC id matches our request;
      // fall back to the first data payload, then to the plain body.
      const body = extractSsePayload(text, id) ?? text;
      const msg = JSON.parse(body);
      if (msg.error) {
        throw new Error(msg.error.message || `MCP RPC Error (${method})`);
      }
      return msg.result;
    } finally {
      clearTimeout(timer);
    }
  }

  private rejectAll(err: Error) {
    for (const { reject, timer } of this.pendingRequests.values()) {
      clearTimeout(timer);
      reject(err);
    }
    this.pendingRequests.clear();
  }

  private processBuffer() {
    const lines = this.buffer.split("\n");
    this.buffer = lines.pop() || "";

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      try {
        const msg = JSON.parse(trimmed);
        // Our request ids are numbers (messageId++), but a server may echo the
        // id back as a string per JSON-RPC. The pendingRequests Map is keyed by
        // number, so coerce a numeric-string id back to a number before lookup;
        // otherwise the response never correlates and the request times out.
        const rid =
          typeof msg.id === "string" && msg.id !== "" && Number.isFinite(Number(msg.id))
            ? Number(msg.id)
            : msg.id;
        if (rid !== undefined && rid !== null && this.pendingRequests.has(rid)) {
          const { resolve, reject, timer } = this.pendingRequests.get(rid)!;
          clearTimeout(timer);
          this.pendingRequests.delete(rid);
          if (msg.error) {
            reject(new Error(msg.error.message || "MCP RPC Error"));
          } else {
            resolve(msg.result);
          }
        }
      } catch {
        // Skip non-JSON or partial frames
      }
    }
  }

  request(method: string, params: any, timeoutMs = 3000): Promise<any> {
    if (this.config.url) {
      return this.httpRequestJSONRPC(method, params, timeoutMs);
    }
    return new Promise((resolve, reject) => {
      if (!this.proc || !this.proc.stdin || this.proc.killed) {
        return reject(new Error(`MCP server "${this.name}" is not running`));
      }
      const id = this.messageId++;
      const timer = setTimeout(() => {
        if (this.pendingRequests.has(id)) {
          this.pendingRequests.delete(id);
          reject(new Error(`MCP request "${method}" to "${this.name}" timed out after ${timeoutMs}ms`));
        }
      }, timeoutMs);

      this.pendingRequests.set(id, { resolve, reject, timer });

      const payload = JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n";
      try {
        this.proc.stdin.write(payload, (err) => {
          if (err) {
            clearTimeout(timer);
            this.pendingRequests.delete(id);
            reject(err);
          }
        });
      } catch (err) {
        clearTimeout(timer);
        this.pendingRequests.delete(id);
        reject(err);
      }
    });
  }

  notify(method: string, params: any): void {
    if (this.config.url) {
      // Streamable HTTP can carry notifications as id-less POSTs; only legacy
      // handshake notifications use this path (stateless 2026-07-28 has no
      // connection-level notification channel). Fire-and-forget: a failed
      // notification must not break the caller. Keep the loopback allow-list
      // here too so any future direct notify() call cannot bypass the SSRF
      // guard that httpRequestJSONRPC enforces.
      if (!isAllowedMcpUrl(this.config.url)) return;
      void fetch(this.config.url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json, text/event-stream",
        },
        body: JSON.stringify({ jsonrpc: "2.0", method, params }),
        redirect: "manual",
      }).catch(() => {
        // ignore notification errors
      });
      return;
    }
    if (!this.proc || !this.proc.stdin || this.proc.killed) return;
    try {
      const payload = JSON.stringify({ jsonrpc: "2.0", method, params }) + "\n";
      this.proc.stdin.write(payload);
    } catch {
      // Ignore write errors on notification
    }
  }

  async listTools(timeoutMs = 2500): Promise<McpToolSchema[]> {
    const res = await this.request("tools/list", {}, timeoutMs);
    return res.tools || [];
  }

  async callTool(name: string, args: Record<string, any>, timeoutMs = 30000): Promise<any> {
    return await this.request("tools/call", { name, arguments: args }, timeoutMs);
  }

  stop() {
    this.rejectAll(new Error(`MCP server "${this.name}" stopped`));
    if (this.proc && !this.config.url) {
      try {
        this.proc.stdin?.end();
        this.proc.kill("SIGTERM");
      } catch {
        // ignore
      }
      this.proc = null;
    }
  }
}

/**
 * Extract the first JSON payload from a Server-Sent Events stream when the
 * transport returns `text/event-stream`; returns null when the body is a
 * plain JSON document (the common case for streamable-HTTP JSON-RPC).
 */
/**
 * Extract the JSON-RPC payload from a streamable-HTTP response body.
 * Prefers an SSE `data:` payload whose JSON-RPC `id` equals `requestId`
 * (so progress/keep-alive events are not misread as the final reply),
 * then falls back to the first data payload, then the plain JSON body.
 */
export function extractSsePayload(text: string, requestId: number): string | null {
  // Proper SSE event framing: per the spec, consecutive `data:` lines within a
  // single event are concatenated with "\n", and a blank line dispatches the
  // event. Treating every `data:` line as a standalone payload mis-splits a
  // multi-line JSON-RPC data event so it never parses; here we accumulate the
  // data lines of each event and emit the joined payload on the dispatch
  // (blank-line) boundary.
  const payloads: string[] = [];
  let current: string[] = [];
  const flush = () => {
    if (current.length > 0) {
      const joined = current.join("\n").trim();
      if (joined) payloads.push(joined);
      current = [];
    }
  };
  for (const line of text.split(/\r?\n/)) {
    if (line.trim() === "") {
      // blank line = event dispatch boundary
      flush();
      continue;
    }
    if (line.startsWith("data:")) {
      // Strip exactly one leading space after the colon (SSE convention).
      let value = line.slice(5);
      if (value.startsWith(" ")) value = value.slice(1);
      current.push(value);
    }
    // Other SSE fields (event:, id:, retry:, comments) are irrelevant here.
  }
  flush();
  if (payloads.length === 0) return null;
  for (const p of payloads) {
    try {
      const parsed = JSON.parse(p);
      // JSON-RPC ids may be echoed as a number OR a string (the spec allows
      // both), so compare by string form. A strict `===` misses a string-echoed
      // id and then the payloads[0] fallback can return an unrelated event (a
      // notification, or a response to a different request) as this request's
      // result. Notifications (no id -> "undefined") never match.
      if (parsed && parsed.id !== undefined && parsed.id !== null && String(parsed.id) === String(requestId)) {
        return p;
      }
    } catch {
      // non-JSON event, keep scanning
    }
  }
  return payloads[0];
}

/**
 * True when a config entry can be connected: either a legacy stdio server
 * (command) or a streamable-HTTP gateway (url). Shared by config loading and
 * the session_start connect loop so the skip/accept logic cannot drift.
 */
export function isUsableMcpConfig(cfg: McpServerConfig): boolean {
  return Boolean(
    (cfg.command && typeof cfg.command === "string") ||
      (typeof cfg.url === "string" && cfg.url.length > 0)
  );
}

/**
 * Restrict url-based MCP endpoints to the local Executor gateway (or an
 * explicit localhost dev endpoint). Arbitrary remote URLs would let a
 * repository-controlled .pi/mcp.json trigger SSRF on session start and
 * install attacker-defined tools that exfiltrate tool-call arguments.
 */
export function isAllowedMcpUrl(url: string): boolean {
  try {
    const u = new URL(url);
    if (u.protocol !== "http:" && u.protocol !== "https:") return false;
    // Node's URL keeps brackets for IPv6 literal hosts ("[::1]"); normalize
    // by stripping them so localhost/loopback matching is consistent.
    const host = u.hostname.replace(/^\[|\]$/g, "");
    return host === "127.0.0.1" || host === "localhost" || host === "::1";
  } catch {
    return false;
  }
}

function loadMcpConfigs(cwd: string): Record<string, McpServerConfig> {
  const home = os.homedir();
  const candidates = [
    path.join(home, ".pi", "agent", "mcp.json"),
    path.join(cwd, ".pi", "mcp.json"),
    path.join(home, ".claude", "settings.json"),
  ];

  const configs: Record<string, McpServerConfig> = {};

  for (const file of candidates) {
    if (fs.existsSync(file)) {
      try {
        const raw = fs.readFileSync(file, "utf-8");
        const json: McpConfigFile = JSON.parse(raw);
        if (json.mcpServers) {
          for (const [key, cfg] of Object.entries(json.mcpServers)) {
            // Accept both legacy stdio servers (command) and streamable-HTTP
            // gateways such as Executor (url). A config without either is
            // unusable and skipped; duplication keeps the first candidate.
            if (!cfg.disabled && isUsableMcpConfig(cfg) && !configs[key]) {
              configs[key] = cfg;
            }
          }
        }
      } catch {
        // Skip unreadable files
      }
    }
  }
  return configs;
}

export default async function (pi: ExtensionAPI) {
  const clients = new Map<string, McpClient>();
  const toolRegistry = new Map<string, { server: string; origName: string }>();

  pi.on("session_start", async (_event, ctx) => {
    const serverConfigs = loadMcpConfigs(ctx.cwd);

    const connectPromise = Promise.allSettled(
      Object.entries(serverConfigs).map(async ([serverName, config]) => {
        if (clients.has(serverName)) return;
        if (!isUsableMcpConfig(config)) return;

        const client = new McpClient(serverName, config, ctx.cwd);
        try {
          await client.start(2000);
          const tools = await client.listTools(2000);
          clients.set(serverName, client);

          for (const tool of tools) {
            const toolName = `mcp__${serverName}__${tool.name}`;
            toolRegistry.set(toolName, { server: serverName, origName: tool.name });

            pi.registerTool({
              name: toolName,
              label: `MCP: ${serverName}/${tool.name}`,
              description: tool.description || `MCP Tool from ${serverName}`,
              parameters: Type.Record(Type.String(), Type.Any()),

              async execute(_id, params, _signal, _onUpdate, _ctx) {
                try {
                  const res = await client.callTool(tool.name, params);
                  const content = res.content || [{ type: "text", text: JSON.stringify(res) }];
                  return { content, isError: res.isError || false };
                } catch (e: any) {
                  return { content: [{ type: "text", text: `MCP Error: ${e.message}` }], isError: true };
                }
              },

              renderCall(args, theme) {
                return new Text(theme.fg("toolTitle", theme.bold(`mcp:${serverName}/${tool.name}`)) + ` ${JSON.stringify(args)}`, 0, 0);
              },

              renderResult(result, { expanded }, theme) {
                const container = new Container();
                const icon = result.isError ? theme.fg("error", "✗ MCP Tool Error") : theme.fg("success", "✓ MCP Tool Complete");
                container.addChild(new Text(icon, 0, 0));
                const raw = result.content[0]?.type === "text" ? result.content[0].text : "(no output)";
                const lines = expanded ? raw : raw.split("\n").slice(0, 5).join("\n");
                container.addChild(new Text(theme.fg("toolOutput", lines), 0, 0));
                return container;
              },
            });
          }
        } catch {
          // Clean up failed client process
          client.stop();
        }
      })
    );

    // Wait up to 1000ms for fast servers to connect during startup;
    // any remaining servers will finish initializing in the background without blocking session_start.
    // The timer is unref'd and cleared so it never keeps the event loop alive
    // (or fires into nothing) once the connections settle first.
    let startupTimer: ReturnType<typeof setTimeout> | undefined;
    try {
      await Promise.race([
        connectPromise,
        new Promise((resolve) => {
          startupTimer = setTimeout(resolve, 1000);
          startupTimer.unref?.();
        }),
      ]);
    } finally {
      if (startupTimer) clearTimeout(startupTimer);
    }
  });

  pi.registerCommand("mcp", {
    description: "List connected Model Context Protocol (MCP) servers and tools",
    handler: async (_args, ctx) => {
      if (clients.size === 0) {
        ctx.ui.notify("No active MCP servers configured in ~/.pi/agent/mcp.json", "info");
        return;
      }
      let summary = `Connected MCP Servers (${clients.size}):\n`;
      for (const [name] of clients.entries()) {
        const toolList = Array.from(toolRegistry.entries())
          .filter(([, v]) => v.server === name)
          .map(([k, v]) => `  • ${v.origName} (${k})`);
        summary += `\n[${name}]:\n${toolList.join("\n") || "  (no tools)"}\n`;
      }
      ctx.ui.notify(summary, "info");
    },
  });

  pi.on("session_shutdown", async () => {
    for (const client of clients.values()) {
      client.stop();
    }
    clients.clear();
  });
}
