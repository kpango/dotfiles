/**
 * Self-hosted DAP (Debug Adapter Protocol) Client Extension for Pi 1.7.0
 *
 * - Reads `~/.pi/agent/dap.json` (fallback `agent/harnesses/pi/dap.json`).
 * - Supports `dlv dap` (TCP socket) and `lldb-dap` (stdio).
 * - Registers `debug` tool for launch, attach, breakpoints, stepping, stack inspection,
 *   variable lookup, and expression evaluation.
 */

import { spawn, spawnSync, type ChildProcessWithoutNullStreams } from "node:child_process";
import * as net from "node:net";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import {
  DapMessageParser,
  encodeDapMessage,
  formatStackFrames,
  formatVariables,
  loadDapConfig,
  matchDapAdapter,
  parseDlvListenEndpoint,
  type DapAdapterConfig,
  type DapConfig,
  type DapStackFrame,
  type DapVariable,
} from "./lib/dap-core";

export * from "./lib/dap-core";

interface ActiveDapSession {
  id: string;
  adapterName: string;
  proc: ChildProcessWithoutNullStreams;
  socket: net.Socket | null;
  writeFn: (buf: Buffer) => void;
  nextSeq: number;
  pending: Map<number, { resolve: (v: any) => void; reject: (e: Error) => void }>;
  outputBuffer: string[];
  breakpoints: Map<string, number[]>;
  stoppedThreadId?: number;
  status: "running" | "stopped" | "terminated";
}

function commandExists(cmd: string): boolean {
  return spawnSync("which", [cmd], { stdio: "ignore" }).status === 0;
}

export default function (pi: ExtensionAPI) {
  let config: DapConfig = loadDapConfig();
  const sessions = new Map<string, ActiveDapSession>();
  let sessionCounter = 0;

  const closeSession = (session: ActiveDapSession) => {
    try {
      session.socket?.destroy();
    } catch {
      // Ignore cleanup error.
    }
    try {
      session.proc.kill("SIGTERM");
    } catch {
      // Ignore cleanup error.
    }
    session.status = "terminated";
    sessions.delete(session.id);
  };

  pi.on("session_shutdown", async () => {
    for (const s of [...sessions.values()]) {
      closeSession(s);
    }
  });

  async function sendDapRequest(session: ActiveDapSession, command: string, args?: Record<string, unknown>, timeoutMs = 15_000): Promise<any> {
    const seq = session.nextSeq++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        session.pending.delete(seq);
        reject(new Error(`DAP ${command} timed out after ${timeoutMs}ms`));
      }, timeoutMs);
      session.pending.set(seq, {
        resolve: (v) => {
          clearTimeout(timer);
          resolve(v);
        },
        reject: (e) => {
          clearTimeout(timer);
          reject(e);
        },
      });
      session.writeFn(encodeDapMessage({ seq, type: "request", command, arguments: args }));
    });
  }

  function handleMessages(session: ActiveDapSession, parser: DapMessageParser, chunk: Buffer) {
    for (const msg of parser.push(chunk)) {
      if (msg.type === "response") {
        const reqSeq = msg.request_seq as number;
        const p = session.pending.get(reqSeq);
        if (!p) continue;
        session.pending.delete(reqSeq);
        if (msg.success) {
          p.resolve(msg.body ?? {});
        } else {
          p.reject(new Error(String(msg.message ?? "DAP request failed")));
        }
      } else if (msg.type === "event") {
        const ev = String(msg.event ?? "");
        const body = (msg.body ?? {}) as Record<string, unknown>;
        if (ev === "output" && typeof body.output === "string") {
          session.outputBuffer.push(body.output);
          if (session.outputBuffer.length > 500) session.outputBuffer.shift();
        } else if (ev === "stopped") {
          session.status = "stopped";
          if (typeof body.threadId === "number") session.stoppedThreadId = body.threadId;
        } else if (ev === "continued") {
          session.status = "running";
        } else if (ev === "terminated" || ev === "exited") {
          session.status = "terminated";
        }
      }
    }
  }

  async function connectAdapter(adapterName: string, adapter: DapAdapterConfig, cwd: string): Promise<ActiveDapSession> {
    if (!commandExists(adapter.command)) {
      throw new Error(`DAP adapter command '${adapter.command}' not found on PATH.`);
    }

    const id = `dap-${++sessionCounter}`;
    const outputBuffer: string[] = [];
    const pending = new Map<number, { resolve: (v: any) => void; reject: (e: Error) => void }>();
    const parser = new DapMessageParser();

    const mode = adapter.connectMode ?? adapter.transport ?? "stdio";
    if (mode === "socket") {
      const baseArgs = [...(adapter.args ?? ["dap"])];
      if (!baseArgs.some((a) => a.startsWith("--listen"))) {
        baseArgs.push("--listen=127.0.0.1:0");
      }
      const proc = spawn(adapter.command, baseArgs, { cwd, stdio: ["pipe", "pipe", "pipe"] });
      const endpoint = await new Promise<{ host: string; port: number }>((resolve, reject) => {
        const timer = setTimeout(() => {
          proc.kill("SIGTERM");
          reject(new Error(`${adapter.command} did not announce DAP socket port within 10s`));
        }, 10_000);
        const onChunk = (buf: Buffer) => {
          const text = buf.toString("utf-8");
          outputBuffer.push(text);
          const ep = parseDlvListenEndpoint(text);
          if (ep) {
            clearTimeout(timer);
            proc.stdout.off("data", onChunk);
            proc.stderr.off("data", onChunk);
            resolve(ep);
          }
        };
        proc.stdout.on("data", onChunk);
        proc.stderr.on("data", onChunk);
        proc.once("exit", (code) => {
          clearTimeout(timer);
          reject(new Error(`${adapter.command} exited early (${code ?? "unknown"})`));
        });
      });

      const socket = await new Promise<net.Socket>((resolve, reject) => {
        const s = net.createConnection(endpoint.port, endpoint.host, () => resolve(s));
        s.once("error", reject);
      });

      const session: ActiveDapSession = {
        id,
        adapterName,
        proc,
        socket,
        writeFn: (b) => socket.write(b),
        nextSeq: 1,
        pending,
        outputBuffer,
        breakpoints: new Map(),
        status: "running",
      };
      socket.on("data", (chunk: Buffer) => handleMessages(session, parser, chunk));
      proc.on("exit", () => {
        session.status = "terminated";
      });
      await sendDapRequest(session, "initialize", {
        adapterID: adapterName,
        clientID: "pi",
        clientName: "Pi Coding Agent",
        linesStartAt1: true,
        columnsStartAt1: true,
        pathFormat: "path",
      });
      sessions.set(id, session);
      return session;
    }

    const proc = spawn(adapter.command, adapter.args ?? [], { cwd, stdio: ["pipe", "pipe", "pipe"] });
    const session: ActiveDapSession = {
      id,
      adapterName,
      proc,
      socket: null,
      writeFn: (b) => proc.stdin.write(b),
      nextSeq: 1,
      pending,
      outputBuffer,
      breakpoints: new Map(),
      status: "running",
    };
    proc.stdout.on("data", (chunk: Buffer) => handleMessages(session, parser, chunk));
    proc.stderr.on("data", (chunk: Buffer) => {
      outputBuffer.push(chunk.toString("utf-8"));
    });
    proc.on("exit", () => {
      session.status = "terminated";
    });
    await sendDapRequest(session, "initialize", {
      adapterID: adapterName,
      clientID: "pi",
      clientName: "Pi Coding Agent",
      linesStartAt1: true,
      columnsStartAt1: true,
      pathFormat: "path",
    });
    sessions.set(id, session);
    return session;
  }

  function requireSession(sessionId?: string): ActiveDapSession {
    if (sessionId) {
      const s = sessions.get(sessionId);
      if (!s) throw new Error(`Unknown DAP session: ${sessionId}`);
      return s;
    }
    const last = [...sessions.values()].at(-1);
    if (!last) throw new Error("No active DAP session. Run action 'launch' or 'attach' first.");
    return last;
  }

  pi.registerTool({
    name: "debug",
    exposure: "deferred",
    label: "DAP Debug",
    description:
      "Interact with local Debug Adapters (dlv for Go, lldb-dap for C/C++/Rust) via DAP. Actions: launch, attach, terminate, sessions, output, set_breakpoint, remove_breakpoint, continue, step_over, step_in, step_out, pause, stack_trace, threads, scopes, variables, evaluate.",
    promptSnippet: "Launch and inspect breakpoints, stacks, variables, and expressions via DAP (dlv / lldb-dap)",
    parameters: Type.Object({
      action: Type.Union([
        Type.Literal("launch"),
        Type.Literal("attach"),
        Type.Literal("terminate"),
        Type.Literal("sessions"),
        Type.Literal("output"),
        Type.Literal("set_breakpoint"),
        Type.Literal("remove_breakpoint"),
        Type.Literal("continue"),
        Type.Literal("step_over"),
        Type.Literal("step_in"),
        Type.Literal("step_out"),
        Type.Literal("pause"),
        Type.Literal("stack_trace"),
        Type.Literal("threads"),
        Type.Literal("scopes"),
        Type.Literal("variables"),
        Type.Literal("evaluate"),
      ]),
      sessionId: Type.Optional(Type.String()),
      adapter: Type.Optional(Type.String({ description: "Adapter name in dap.json (e.g. dlv, lldb-dap)" })),
      program: Type.Optional(Type.String({ description: "Executable or package path to launch" })),
      pid: Type.Optional(Type.Number({ description: "Process ID for attach" })),
      args: Type.Optional(Type.Array(Type.String())),
      file: Type.Optional(Type.String({ description: "Source file path for breakpoint" })),
      line: Type.Optional(Type.Number({ description: "1-based line number for breakpoint" })),
      condition: Type.Optional(Type.String()),
      threadId: Type.Optional(Type.Number()),
      frameId: Type.Optional(Type.Number()),
      variablesReference: Type.Optional(Type.Number()),
      expression: Type.Optional(Type.String()),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      config = loadDapConfig();
      const action = params.action;

      if (action === "sessions") {
        if (sessions.size === 0) {
          return {
            content: [{ type: "text", text: `No active DAP sessions. Configured adapters: ${Object.keys(config.adapters).join(", ") || "(none)"}` }],
          };
        }
        const rows = [...sessions.values()].map((s) => `${s.id} [${s.adapterName}] status=${s.status} thread=${s.stoppedThreadId ?? "-"}`);
        return { content: [{ type: "text", text: rows.join("\n") }] };
      }

      if (action === "launch" || action === "attach") {
        const matched = matchDapAdapter(config, params.program ?? params.file, params.adapter, ctx.cwd);
        if (!matched) {
          throw new Error(`No matching DAP adapter for '${params.program ?? params.adapter ?? "unknown"}' in dap.json`);
        }
        const session = await connectAdapter(matched.adapterName, matched.adapter, matched.rootDir);
        if (action === "launch") {
          const launchArgs = {
            ...(matched.adapter.launchDefaults ?? {}),
            program: params.program,
            args: params.args ?? [],
            cwd: matched.rootDir,
          };
          await sendDapRequest(session, "launch", launchArgs);
        } else {
          await sendDapRequest(session, "attach", {
            processId: params.pid,
            program: params.program,
          });
        }
        await sendDapRequest(session, "configurationDone", {});
        return {
          content: [{ type: "text", text: `Started DAP session ${session.id} (${matched.adapterName}) in ${matched.rootDir}` }],
        };
      }

      const session = requireSession(params.sessionId);

      if (action === "terminate") {
        try {
          await sendDapRequest(session, "disconnect", { terminateDebuggee: true }, 3_000);
        } catch {
          // Proceed with process kill.
        }
        closeSession(session);
        return { content: [{ type: "text", text: `Terminated DAP session ${session.id}` }] };
      }

      if (action === "output") {
        const text = session.outputBuffer.splice(0).join("");
        return { content: [{ type: "text", text: text || "(no buffered output)" }] };
      }

      if (action === "set_breakpoint") {
        if (!params.file || !params.line) throw new Error("file and line are required for set_breakpoint");
        const existing = session.breakpoints.get(params.file) ?? [];
        const lines = [...new Set([...existing, params.line])];
        session.breakpoints.set(params.file, lines);
        const body = await sendDapRequest(session, "setBreakpoints", {
          source: { path: params.file },
          breakpoints: lines.map((l) => (l === params.line && params.condition ? { line: l, condition: params.condition } : { line: l })),
        });
        return { content: [{ type: "text", text: JSON.stringify(body.breakpoints ?? [], null, 2) }] };
      }

      if (action === "remove_breakpoint") {
        if (!params.file || !params.line) throw new Error("file and line are required for remove_breakpoint");
        const existing = (session.breakpoints.get(params.file) ?? []).filter((l) => l !== params.line);
        session.breakpoints.set(params.file, existing);
        const body = await sendDapRequest(session, "setBreakpoints", {
          source: { path: params.file },
          breakpoints: existing.map((l) => ({ line: l })),
        });
        return { content: [{ type: "text", text: JSON.stringify(body.breakpoints ?? [], null, 2) }] };
      }

      const threadId = params.threadId ?? session.stoppedThreadId ?? 1;

      if (action === "continue") {
        await sendDapRequest(session, "continue", { threadId });
        session.status = "running";
        return { content: [{ type: "text", text: `Continued thread ${threadId}` }] };
      }
      if (action === "step_over") {
        await sendDapRequest(session, "next", { threadId });
        return { content: [{ type: "text", text: `Stepped over thread ${threadId}` }] };
      }
      if (action === "step_in") {
        await sendDapRequest(session, "stepIn", { threadId });
        return { content: [{ type: "text", text: `Stepped into thread ${threadId}` }] };
      }
      if (action === "step_out") {
        await sendDapRequest(session, "stepOut", { threadId });
        return { content: [{ type: "text", text: `Stepped out thread ${threadId}` }] };
      }
      if (action === "pause") {
        await sendDapRequest(session, "pause", { threadId });
        return { content: [{ type: "text", text: `Paused thread ${threadId}` }] };
      }
      if (action === "threads") {
        const body = await sendDapRequest(session, "threads", {});
        return { content: [{ type: "text", text: JSON.stringify(body.threads ?? [], null, 2) }] };
      }
      if (action === "stack_trace") {
        const body = await sendDapRequest(session, "stackTrace", { threadId, levels: 25 });
        return { content: [{ type: "text", text: formatStackFrames((body.stackFrames ?? []) as DapStackFrame[]) }] };
      }
      if (action === "scopes") {
        if (params.frameId === undefined) throw new Error("frameId is required for scopes");
        const body = await sendDapRequest(session, "scopes", { frameId: params.frameId });
        return { content: [{ type: "text", text: JSON.stringify(body.scopes ?? [], null, 2) }] };
      }
      if (action === "variables") {
        if (params.variablesReference === undefined) throw new Error("variablesReference is required for variables");
        const body = await sendDapRequest(session, "variables", { variablesReference: params.variablesReference });
        return { content: [{ type: "text", text: formatVariables((body.variables ?? []) as DapVariable[]) }] };
      }
      if (action === "evaluate") {
        if (!params.expression) throw new Error("expression is required for evaluate");
        const body = await sendDapRequest(session, "evaluate", {
          expression: params.expression,
          frameId: params.frameId,
          context: "repl",
        });
        return { content: [{ type: "text", text: `${body.result ?? "(undefined)"}${body.type ? ` (${body.type})` : ""}` }] };
      }

      throw new Error(`Unsupported DAP action: ${action}`);
    },
    renderResult(result) {
      const text = result.content[0]?.type === "text" ? result.content[0].text : "";
      const preview = text.split("\n").slice(0, 12).join("\n");
      return new Text(preview, 0, 0);
    },
  });
}
