/**
 * RTK Optimizer Extension for Pi Coding Agent
 *
 * Intercepts bash tool calls and rewrites eligible commands to use `rtk` (Rust Token Killer),
 * drastically compressing CLI outputs and saving up to 60-90% LLM tokens.
 */

import { execSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

let isRtkAvailable: boolean | null = null;

function checkRtkAvailable(): boolean {
  if (isRtkAvailable !== null) return isRtkAvailable;
  try {
    execSync("command -v rtk", { stdio: "ignore" });
    isRtkAvailable = true;
  } catch {
    isRtkAvailable = false;
  }
  return isRtkAvailable;
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, _ctx) => {
    if (event.toolName !== "bash") return;
    if (!checkRtkAvailable()) return;

    const command = (event.input.command as string) || "";
    const trimmed = command.trim();
    if (!trimmed || trimmed.startsWith("rtk ")) return;

    try {
      const rewritten = execSync(`rtk rewrite "${trimmed.replace(/"/g, '\\"')}"`, {
        encoding: "utf-8",
        timeout: 2000,
        stdio: ["ignore", "pipe", "ignore"],
      }).trim();

      if (rewritten && rewritten.startsWith("rtk ") && rewritten !== trimmed) {
        event.input.command = rewritten;
      }
    } catch {
      // Fallback silently if rtk rewrite fails
    }
  });
}
