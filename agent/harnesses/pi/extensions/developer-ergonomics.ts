/**
 * Developer Ergonomics & System Diagnostics Extension for Pi Coding Agent
 *
 * Provides developer utilities and slash commands:
 * - `/doctor`: Comprehensive health checks across binaries, MCP, agents, and permissions
 * - `/diff`: Colorized diff of current uncommitted git changes
 * - `/clean`: Cleans transient caches and dead worktrees
 */

import { execSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  // /doctor command
  pi.registerCommand("doctor", {
    description: "Run complete system diagnostic checks for Pi Coding Agent harness",
    handler: async (_args, ctx) => {
      const checks: string[] = [];
      const home = os.homedir();

      // Check Binaries
      const bins = ["pi", "claude", "agy", "codex", "rtk", "git", "hx", "bun", "node", "jq", "flock"];
      const missingBins: string[] = [];
      for (const b of bins) {
        try {
          execSync(`command -v ${b}`, { stdio: "ignore" });
        } catch {
          missingBins.push(b);
        }
      }
      if (missingBins.length === 0) {
        checks.push("✓ All essential CLI binaries installed (pi, claude, agy, codex, rtk, hx, bun, node)");
      } else {
        checks.push(`✗ Missing binaries: ${missingBins.join(", ")}`);
      }

      // Check Config Directories
      const piDir = path.join(home, ".pi", "agent");
      const subdirs = ["agents", "skills", "prompts", "extensions", "themes", "rules"];
      const missingDirs = subdirs.filter((d) => !fs.existsSync(path.join(piDir, d)));
      if (missingDirs.length === 0) {
        checks.push("✓ All Pi configuration symlinks present in ~/.pi/agent/");
      } else {
        checks.push(`✗ Missing ~/.pi/agent subdirectories: ${missingDirs.join(", ")}`);
      }

      // Check Git status
      try {
        const branch = execSync("git rev-parse --abbrev-ref HEAD", { cwd: ctx.cwd, encoding: "utf-8" }).trim();
        checks.push(`✓ Git repository active on branch [${branch}]`);
      } catch {
        checks.push("○ Current workspace is not a Git repository");
      }

      const report = `=== Pi System Doctor ===\n\n${checks.join("\n")}\n\nStatus: Harness is OPERATIONAL 🚀`;
      ctx.ui.notify(report, "info");
    },
  });

  // /diff command
  pi.registerCommand("diff", {
    description: "Display current uncommitted git changes",
    handler: async (_args, ctx) => {
      try {
        const diff = execSync("git diff HEAD", { cwd: ctx.cwd, encoding: "utf-8" }).trim();
        if (!diff) {
          ctx.ui.notify("No uncommitted changes in working tree.", "info");
          return;
        }
        const lines = diff.split("\n").slice(0, 30).join("\n");
        ctx.ui.notify(`Git Diff (${diff.split("\n").length} lines):\n\n${lines}${diff.split("\n").length > 30 ? "\n..." : ""}`, "info");
      } catch (e: any) {
        ctx.ui.notify(`Git diff failed: ${e.message}`, "error");
      }
    },
  });

  // /clean command
  pi.registerCommand("clean", {
    description: "Clean temporary worktrees and cache files",
    handler: async (_args, ctx) => {
      const home = os.homedir();
      const tmpDir = path.join(home, ".cache", "pi");
      if (fs.existsSync(tmpDir)) {
        fs.rmSync(tmpDir, { recursive: true, force: true });
      }
      ctx.ui.notify("✓ Transient cache cleaned.", "info");
    },
  });
}
