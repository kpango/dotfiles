/**
 * Autonomous Git Worktree Isolation Manager Extension for Pi Coding Agent
 *
 * Automatically manages isolated worktrees under .git/worktrees/ for concurrent tasks,
 * preventing cross-agent git index contamination and enabling conflict-free parallel implementation.
 */

import { execSync, spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export interface AllocatedWorktree {
  worktreePath: string;
  branchName: string;
  taskId: string;
  createdAt: string;
}

export function getWorktreeBaseDir(repoRoot: string): string {
  return path.join(repoRoot, ".git", "pi-worktrees");
}

export function allocateWorktree(
  repoRoot: string,
  taskId: string,
  baseRef = "HEAD"
): { worktreePath: string; branchName: string; success: boolean; error?: string } {
  const safeId = taskId.replace(/[^\w.-]+/g, "-");
  const branchName = `pi-wt-${safeId}`;
  const baseDir = getWorktreeBaseDir(repoRoot);

  if (!fs.existsSync(baseDir)) {
    fs.mkdirSync(baseDir, { recursive: true });
  }

  const worktreePath = path.join(baseDir, safeId);

  // If already exists, return existing
  if (fs.existsSync(worktreePath)) {
    return { worktreePath, branchName, success: true };
  }

  try {
    // git worktree add -b <branchName> <worktreePath> <baseRef>
    const cmd = `git worktree add -b "${branchName}" "${worktreePath}" "${baseRef}"`;
    execSync(cmd, { cwd: repoRoot, stdio: ["ignore", "pipe", "pipe"], encoding: "utf-8" });
    return { worktreePath, branchName, success: true };
  } catch (e: any) {
    // If branch already exists, fallback to checking out existing branch
    try {
      const fallbackCmd = `git worktree add "${worktreePath}" "${branchName}"`;
      execSync(fallbackCmd, { cwd: repoRoot, stdio: ["ignore", "pipe", "pipe"], encoding: "utf-8" });
      return { worktreePath, branchName, success: true };
    } catch (err: any) {
      return { worktreePath, branchName, success: false, error: err.message };
    }
  }
}

export function collectWorktreeDiff(
  worktreePath: string,
  baseRef = "HEAD"
): { diff: string; files: string[] } {
  try {
    const diff = execSync(`git diff ${baseRef}`, { cwd: worktreePath, encoding: "utf-8" });
    const status = execSync("git status --porcelain", { cwd: worktreePath, encoding: "utf-8" });
    const files = status
      .split("\n")
      .map((l) => l.trim().split(/\s+/)[1])
      .filter(Boolean);
    return { diff, files };
  } catch {
    return { diff: "", files: [] };
  }
}

export function releaseWorktree(
  repoRoot: string,
  worktreePath: string,
  branchName?: string
): { success: boolean; error?: string } {
  try {
    if (fs.existsSync(worktreePath)) {
      execSync(`git worktree remove --force "${worktreePath}"`, {
        cwd: repoRoot,
        stdio: ["ignore", "pipe", "pipe"],
        encoding: "utf-8",
      });
    }
    if (branchName) {
      try {
        execSync(`git branch -D "${branchName}"`, {
          cwd: repoRoot,
          stdio: ["ignore", "pipe", "pipe"],
          encoding: "utf-8",
        });
      } catch {
        // branch might not exist or already deleted
      }
    }
    return { success: true };
  } catch (e: any) {
    return { success: false, error: e.message };
  }
}

export function listAllocatedWorktrees(repoRoot: string): string[] {
  const baseDir = getWorktreeBaseDir(repoRoot);
  if (!fs.existsSync(baseDir)) return [];
  try {
    return fs.readdirSync(baseDir).map((entry) => path.join(baseDir, entry));
  } catch {
    return [];
  }
}

export default function (pi: ExtensionAPI) {
  // Command: /worktree
  pi.registerCommand("worktree", {
    description: "Manage autonomous task worktrees (/worktree [list|cleanup])",
    handler: async (args, ctx) => {
      const sub = (args || "list").trim().toLowerCase();

      if (sub === "list") {
        const list = listAllocatedWorktrees(ctx.cwd);
        if (list.length === 0) {
          ctx.ui.notify("No active task worktrees under .git/pi-worktrees/", "info");
        } else {
          ctx.ui.notify(`Active Task Worktrees (${list.length}):\n` + list.map((p) => `- ${p}`).join("\n"), "info");
        }
      } else if (sub === "cleanup") {
        const list = listAllocatedWorktrees(ctx.cwd);
        let cleaned = 0;
        for (const wt of list) {
          const res = releaseWorktree(ctx.cwd, wt);
          if (res.success) cleaned++;
        }
        ctx.ui.notify(`Cleaned up ${cleaned}/${list.length} task worktrees.`, "info");
      } else {
        ctx.ui.notify("Usage: /worktree [list|cleanup]", "warning");
      }
    },
  });
}
