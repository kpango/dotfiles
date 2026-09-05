/**
 * Helix Editor & Tmux Bridge Extension for Pi Coding Agent
 *
 * Integrates Pi seamlessly with Helix (`hx`) editor and Tmux:
 * - open_in_helix tool: Open any file directly at a target line inside Helix.
 * - /hx slash command: Quick shortcut to inspect code in Helix.
 */

import { execSync, spawnSync } from "node:child_process";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export function isTmuxActive(): boolean {
  return Boolean(process.env.TMUX);
}

export function buildHelixCommand(
  file: string,
  line?: number,
  inTmux = false
): { cmd: string; args: string[] } {
  const target = line ? `${file}:${line}` : file;

  if (inTmux) {
    // Open Helix in a new tmux split or window
    return {
      cmd: "tmux",
      args: ["split-window", "-h", `hx "${target}"`],
    };
  }

  return {
    cmd: "hx",
    args: [target],
  };
}

export function openHelix(
  file: string,
  line: number | undefined,
  cwd: string
): { success: boolean; message: string } {
  const inTmux = isTmuxActive();
  const absPath = path.isAbsolute(file) ? file : path.resolve(cwd, file);
  const { cmd, args } = buildHelixCommand(absPath, line, inTmux);

  try {
    if (inTmux) {
      const res = spawnSync(cmd, args, { encoding: "utf-8" });
      if (res.status === 0) {
        return { success: true, message: `Opened ${file}${line ? `:${line}` : ""} in adjacent Tmux pane.` };
      }
      return { success: false, message: `Tmux error: ${res.stderr || "Failed to split window"}` };
    } else {
      return { success: true, message: `Run 'hx ${absPath}${line ? `:${line}` : ""}' to open in Helix.` };
    }
  } catch (e: any) {
    return { success: false, message: `Failed to invoke Helix: ${e.message}` };
  }
}

export default function (pi: ExtensionAPI) {
  // Register open_in_helix tool
  pi.registerTool({
    name: "open_in_helix",
    description: "Open a specified file at an optional line number in the Helix (hx) editor via Tmux split pane.",
    parameters: Type.Object({
      file: Type.String({ description: "Relative or absolute file path to open." }),
      line: Type.Optional(Type.Integer({ description: "Target line number (1-indexed)." })),
    }),
    handler: async (args, ctx) => {
      const res = openHelix(args.file, args.line, ctx.cwd);
      return {
        content: [{ type: "text", text: res.message }],
      };
    },
  });

  // Register /hx command
  pi.registerCommand("hx", {
    description: "Open file in Helix editor (/hx <path> [line])",
    handler: async (args, ctx) => {
      const parts = (args || "").trim().split(/\s+/);
      if (!parts[0]) {
        ctx.ui.notify("Usage: /hx <filename> [line]", "warning");
        return;
      }
      const line = parts[1] ? parseInt(parts[1], 10) : undefined;
      const res = openHelix(parts[0], line, ctx.cwd);
      ctx.ui.notify(res.message, res.success ? "info" : "error");
    },
  });
}
