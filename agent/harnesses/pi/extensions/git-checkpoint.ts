/**
 * Git Checkpoint & Rollback Extension for Pi Coding Agent
 *
 * Automatically records git checkpoints per turn, enabling instant
 * `/undo` / `/rollback` commands and seamless branch code restoration.
 */

import { execSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  const checkpoints = new Map<string, string>(); // entryId -> stash commit hash
  let lastStashHash: string | null = null;
  let currentEntryId: string | undefined;

  const isGitRepo = (cwd: string): boolean => {
    try {
      execSync("git rev-parse --is-inside-work-tree", { cwd, stdio: "ignore" });
      return true;
    } catch {
      return false;
    }
  };

  // Track the current entry ID when tool results are saved
  pi.on("tool_result", async (_event, ctx) => {
    const leaf = ctx.sessionManager.getLeafEntry();
    if (leaf) currentEntryId = leaf.id;
  });

  pi.on("turn_start", async (_event, ctx) => {
    if (!isGitRepo(ctx.cwd)) return;

    try {
      const out = execSync("git stash create", { cwd: ctx.cwd, encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] }).trim();
      if (out) {
        lastStashHash = out;
        if (currentEntryId) {
          checkpoints.set(currentEntryId, out);
        }
      }
    } catch {
      // Ignore git stash errors
    }
  });

  // Slash Command /undo or /rollback
  pi.registerCommand("undo", {
    description: "Rollback file modifications made in the most recent turn",
    handler: async (_args, ctx) => {
      if (!isGitRepo(ctx.cwd)) {
        ctx.ui.notify("Not in a git repository", "warning");
        return;
      }

      if (!lastStashHash) {
        ctx.ui.notify("No turn checkpoint available to restore", "warning");
        return;
      }

      if (ctx.hasUI) {
        const ok = await ctx.ui.confirm("Undo File Changes", "Restore modified files to before the last turn?");
        if (!ok) return;
      }

      try {
        // Reset working tree to checkpoint
        execSync(`git stash apply --index "${lastStashHash}" || git stash apply "${lastStashHash}"`, {
          cwd: ctx.cwd,
          stdio: "ignore",
        });
        ctx.ui.notify("✓ Successfully restored files to previous turn checkpoint.", "info");
      } catch (e: any) {
        ctx.ui.notify(`Failed to apply checkpoint: ${e.message}`, "error");
      }
    },
  });

  pi.registerCommand("rollback", {
    description: "Alias for /undo",
    handler: async (args, ctx) => {
      const undoCmd = pi as any;
      if (undoCmd) {
        ctx.sendUserMessage("/undo");
      }
    },
  });

  // Restore code state on session fork
  pi.on("session_before_fork", async (event, ctx) => {
    const ref = checkpoints.get(event.entryId);
    if (!ref || !ctx.hasUI) return;

    const choice = await ctx.ui.select("Restore code state to fork point?", [
      "Yes, restore workspace to that point",
      "No, keep current code",
    ]);

    if (choice?.startsWith("Yes")) {
      try {
        execSync(`git stash apply "${ref}"`, { cwd: ctx.cwd, stdio: "ignore" });
        ctx.ui.notify("Code restored to fork checkpoint", "info");
      } catch (e: any) {
        ctx.ui.notify(`Could not restore checkpoint: ${e.message}`, "warning");
      }
    }
  });
}
