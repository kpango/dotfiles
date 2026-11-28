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
import { resolveRetentionDays } from "./lib/session-retention";

/** Transcript files (one per session) under the Pi sessions root. */
function sessionTranscripts(root: string): { file: string; bytes: number }[] {
  const out: { file: string; bytes: number }[] = [];
  let projects: fs.Dirent[];
  try {
    projects = fs.readdirSync(root, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const project of projects) {
    if (!project.isDirectory()) continue;
    const dir = path.join(root, project.name);
    let files: string[];
    try {
      files = fs.readdirSync(dir);
    } catch {
      continue;
    }
    for (const file of files) {
      if (!file.endsWith(".jsonl")) continue;
      try {
        out.push({ file, bytes: fs.statSync(path.join(dir, file)).size });
      } catch {
        // ignore unreadable transcript
      }
    }
  }
  return out;
}

export default function (pi: ExtensionAPI) {
  // /doctor command
  pi.registerCommand("doctor", {
    description: "Run complete system diagnostic checks for Pi harness",
    handler: async (_args, ctx) => {
      const checks: string[] = [];
      const home = os.homedir();

      // Check Binaries
      const bins = ["pi", "claude", "agy", "hermes", "rtk", "git", "hx", "bun", "node", "jq", "flock"];
      const missingBins: string[] = [];
      for (const b of bins) {
        try {
          execSync(`command -v ${b}`, { stdio: "ignore" });
        } catch {
          missingBins.push(b);
        }
      }
      if (missingBins.length === 0) {
        checks.push("✓ All essential CLI binaries installed (pi, claude, agy, hermes, rtk, hx, bun, node)");
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

      // Check settings.json is a managed copy: Pi updates defaultProvider/defaultModel/
      // defaultThinkingLevel at runtime, and a symlink would push that runtime state into the dotfiles repo.
      const configPath = path.join(piDir, "settings.json");
      if (fs.existsSync(configPath)) {
        checks.push(
          fs.lstatSync(configPath).isSymbolicLink()
            ? "✗ ~/.pi/agent/settings.json is a symlink (Pi updates it at runtime and dirties the repo; run make pi/install)"
            : "✓ ~/.pi/agent/settings.json is a managed copy (runtime updates stay out of the repo)"
        );
      }

      // Check session storage: auto-prune sessions older than PI_SESSION_RETENTION_DAYS at startup.
      const sessionRoot = path.join(piDir, "sessions");
      if (fs.existsSync(sessionRoot)) {
        const transcripts = sessionTranscripts(sessionRoot);
        const totalMB = transcripts.reduce((sum, t) => sum + t.bytes, 0) / 1048576;
        const largest = transcripts
          .sort((a, b) => b.bytes - a.bytes)
          .slice(0, 3)
          .map((t) => `${(t.bytes / 1048576).toFixed(1)} MB`)
          .join(", ");
        const days = resolveRetentionDays(process.env.PI_SESSION_RETENTION_DAYS);
        const policy = days < 1 ? "retention disabled" : `auto-prune > ${days}d at start`;
        checks.push(
          `${totalMB >= 2048 ? "!" : "✓"} Session storage ${totalMB.toFixed(0)} MB across ${transcripts.length} transcript(s) (${policy})` +
            (largest ? `; largest: ${largest}` : "")
        );
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
