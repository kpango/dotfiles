/**
 * sandbox_run — run an untrusted command through agent/scripts/sandbox/gondolin-run.mjs.
 *
 * gondolin-run picks the strongest available backend (Gondolin micro-VM, else pa-sandbox `bwrap --clearenv`).
 * This extension only wires it up as a tool: the command is passed as an argv array (never a shell string),
 * egress is denied unless allowHosts is given (and that needs the gondolin backend — gondolin-run rejects it
 * for pa-sandbox instead of ignoring it). Host secrets are deliberately not exposed here.
 */

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export const BACKENDS = ["auto", "gondolin", "pa-sandbox"] as const;
export type SandboxBackend = (typeof BACKENDS)[number];

export interface SandboxRunParams {
  command: string[];
  backend?: string;
  allowHosts?: string[];
  timeoutSec?: number;
}

const DEFAULT_TIMEOUT_SEC = 120;
const MAX_TIMEOUT_SEC = 900;
const MAX_OUTPUT_CHARS = 20_000;
const HOST_RE = /^[A-Za-z0-9]([A-Za-z0-9.*-]*[A-Za-z0-9])?$/;

/** The gondolin-run.mjs next to the canonical (symlink-resolved) extension file, or $GONDOLIN_RUN_SCRIPT. */
export function resolveScriptPath(env: NodeJS.ProcessEnv = process.env): string {
  if (env.GONDOLIN_RUN_SCRIPT) return env.GONDOLIN_RUN_SCRIPT;
  const here = fs.realpathSync(fileURLToPath(import.meta.url));
  return path.resolve(path.dirname(here), "..", "..", "..", "scripts", "sandbox", "gondolin-run.mjs");
}

/** Validates the tool input and builds gondolin-run's argv (after the script path). Returns an error string on bad input. */
export function buildArgs(p: SandboxRunParams): { args: string[] } | { error: string } {
  if (!Array.isArray(p.command) || p.command.length === 0 || p.command.some((a) => typeof a !== "string")) {
    return { error: "command must be a non-empty array of strings" };
  }
  if (p.command.some((a) => a.includes("\0"))) return { error: "command contains a NUL byte" };
  const backend = p.backend ?? "auto";
  if (!(BACKENDS as readonly string[]).includes(backend)) {
    return { error: `backend must be one of ${BACKENDS.join(", ")}` };
  }
  const args = ["--backend", backend];
  for (const h of p.allowHosts ?? []) {
    if (typeof h !== "string" || !HOST_RE.test(h)) return { error: `invalid allowHosts entry: ${JSON.stringify(h)}` };
    args.push("--allow-host", h);
  }
  args.push("--", ...p.command);
  return { args };
}

function clip(s: string): string {
  return s.length > MAX_OUTPUT_CHARS ? `${s.slice(0, MAX_OUTPUT_CHARS)}\n... [truncated ${s.length - MAX_OUTPUT_CHARS} chars]` : s;
}

export function runSandbox(
  p: SandboxRunParams,
  cwd: string,
  env: NodeJS.ProcessEnv = process.env
): { ok: boolean; text: string } {
  const built = buildArgs(p);
  if ("error" in built) return { ok: false, text: `sandbox_run: ${built.error}` };
  let script: string;
  try {
    script = resolveScriptPath(env);
  } catch (e: any) {
    return { ok: false, text: `sandbox_run: cannot locate gondolin-run.mjs: ${e.message}` };
  }
  if (!fs.existsSync(script)) return { ok: false, text: `sandbox_run: ${script} does not exist` };
  const timeoutSec = Math.min(Math.max(Math.floor(p.timeoutSec ?? DEFAULT_TIMEOUT_SEC), 1), MAX_TIMEOUT_SEC);
  const res = spawnSync(process.execPath, [script, ...built.args], {
    cwd,
    encoding: "utf-8",
    timeout: timeoutSec * 1000,
    maxBuffer: 10 * 1024 * 1024,
    env,
  });
  if (res.error) {
    const timedOut = (res.error as NodeJS.ErrnoException).code === "ETIMEDOUT";
    return { ok: false, text: `sandbox_run: ${timedOut ? `timed out after ${timeoutSec}s` : res.error.message}` };
  }
  const body = [`exit=${res.status}`, res.stdout ? `stdout:\n${clip(res.stdout)}` : "", res.stderr ? `stderr:\n${clip(res.stderr)}` : ""]
    .filter(Boolean)
    .join("\n");
  return { ok: res.status === 0, text: body };
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "sandbox_run",
    exposure: "deferred",
    description:
      "Run an untrusted command in an isolated sandbox (Gondolin micro-VM when available, else pa-sandbox bwrap --clearenv). " +
      "command is an argv array, not a shell string. Network egress is denied unless allowHosts is set (gondolin backend only).",
    parameters: Type.Object({
      command: Type.Array(Type.String(), { description: "argv, e.g. [\"python3\", \"-c\", \"print(1)\"]" }),
      backend: Type.Optional(Type.String({ description: "auto (default) | gondolin | pa-sandbox. An explicit backend never falls back." })),
      allowHosts: Type.Optional(Type.Array(Type.String(), { description: "Egress allowlist hosts (gondolin backend only)." })),
      timeoutSec: Type.Optional(Type.Number({ description: `Timeout seconds (default ${DEFAULT_TIMEOUT_SEC}, max ${MAX_TIMEOUT_SEC}).` })),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const r = runSandbox(params as SandboxRunParams, ctx.cwd);
      return { content: [{ type: "text", text: r.text }] };
    },
  });
}
