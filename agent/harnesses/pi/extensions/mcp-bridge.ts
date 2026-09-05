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
  command: string;
  args?: string[];
  env?: Record<string, string>;
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

class McpClient {
  private proc: ChildProcess | null = null;
  private messageId = 1;
  private pendingRequests = new Map<number, { resolve: (val: any) => void; reject: (err: any) => void }>();
  private buffer = "";

  constructor(
    public readonly name: string,
    private readonly config: McpServerConfig,
    private readonly cwd: string
  ) {}

  async start(): Promise<void> {
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
      // Reject any pending requests
      for (const { reject } of this.pendingRequests.values()) {
        reject(err);
      }
      this.pendingRequests.clear();
    });

    // Send initialize request
    await this.request("initialize", {
      protocolVersion: "2024-11-05",
      capabilities: { tools: {} },
      clientInfo: { name: "pi-mcp-bridge", version: "1.0.0" },
    });

    // Send initialized notification
    this.notify("notifications/initialized", {});
  }

  private processBuffer() {
    const lines = this.buffer.split("\n");
    this.buffer = lines.pop() || "";

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      try {
        const msg = JSON.parse(trimmed);
        if (msg.id !== undefined && this.pendingRequests.has(msg.id)) {
          const { resolve, reject } = this.pendingRequests.get(msg.id)!;
          this.pendingRequests.delete(msg.id);
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

  request(method: string, params: any): Promise<any> {
    return new Promise((resolve, reject) => {
      if (!this.proc || !this.proc.stdin) {
        return reject(new Error(`MCP server "${this.name}" is not running`));
      }
      const id = this.messageId++;
      this.pendingRequests.set(id, { resolve, reject });
      const payload = JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n";
      this.proc.stdin.write(payload);
    });
  }

  notify(method: string, params: any): void {
    if (!this.proc || !this.proc.stdin) return;
    const payload = JSON.stringify({ jsonrpc: "2.0", method, params }) + "\n";
    this.proc.stdin.write(payload);
  }

  async listTools(): Promise<McpToolSchema[]> {
    const res = await this.request("tools/list", {});
    return res.tools || [];
  }

  async callTool(name: string, args: Record<string, any>): Promise<any> {
    return await this.request("tools/call", { name, arguments: args });
  }

  stop() {
    if (this.proc) {
      this.proc.kill("SIGTERM");
      this.proc = null;
    }
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
            if (!cfg.disabled && !configs[key]) {
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

    for (const [serverName, config] of Object.entries(serverConfigs)) {
      if (clients.has(serverName)) continue;

      try {
        const client = new McpClient(serverName, config, ctx.cwd);
        await client.start();
        clients.set(serverName, client);

        const tools = await client.listTools();
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
        // Skip failed servers gracefully
      }
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
