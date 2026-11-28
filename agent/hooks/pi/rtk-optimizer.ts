/**
 * RTK Optimizer Extension for Pi Coding Agent
 *
 * Intercepts bash tool calls and rewrites eligible commands to use `rtk` (Rust Token Killer),
 * drastically compressing CLI outputs and saving up to 60-90% LLM tokens.
 */

import { execFileSync, execSync } from "node:child_process";
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

const RTK_WHITELIST_PREFIXES = [
  "go test",
  "cargo test",
  "cargo check",
  "cargo clippy",
  "cargo build",
  "pytest",
  "npm test",
  "pnpm test",
  "bun test",
  "make",
  "git status",
  "git log",
  "git diff",
  "docker ps",
  "docker logs",
  "kubectl get",
  "kubectl logs",
  "gh pr checks",
] as const;

/**
 * Strictly whitelist high-volume test, build, and status commands only (RTK Issue #582).
 * NEVER rewrite cat/head/tail/read/grep/ls/echo — those return immediately in 0ms without spawning rtk.
 *
 * Parity contract with agent/hooks/claude/rtk-rewrite.sh (`case "$cmd" in "go test"*|...`):
 * raw-string prefix match only — no trim, no env-assignment/sudo stripping, no word boundary,
 * case-sensitive. Keep both lists and semantics identical (rtk-optimizer.test.ts enforces it).
 */
export function isWhitelistedForRtk(cmd: string): boolean {
  if (typeof cmd !== "string" || cmd === "") return false;
  return RTK_WHITELIST_PREFIXES.some((prefix) => cmd.startsWith(prefix));
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, _ctx) => {
    if (event.toolName !== "bash") return;

    const command = (event.input.command as string) || "";
    if (!isWhitelistedForRtk(command)) return;
    if (!checkRtkAvailable()) return;

    try {
      // execFileSync (no shell): the command is untrusted text and must never be shell-expanded.
      const rewritten = execFileSync("rtk", ["rewrite", command], {
        encoding: "utf-8",
        timeout: 2000,
        stdio: ["ignore", "pipe", "ignore"],
      }).trim();

      if (rewritten && rewritten.startsWith("rtk ") && rewritten !== command) {
        event.input.command = rewritten;
      }
    } catch {
      // Fallback silently if rtk rewrite fails
    }
  });
}
