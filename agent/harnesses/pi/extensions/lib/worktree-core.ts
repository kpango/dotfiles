/**
 * Git Worktree Isolation Helpers for OMP Subagent Orchestration
 *
 * Extracted from the retired worktree-manager extension so subagents.ts keeps
 * isolated worktree allocation/diff/cleanup without exposing a standalone tool.
 */

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

export interface AllocatedWorktree {
  worktreePath: string;
  branchName: string;
  taskId: string;
  createdAt: string;
}

export function getWorktreeBaseDir(repoRoot: string): string {
  return path.join(repoRoot, ".git", "pi-worktrees");
}

function runGit(cwd: string, args: string[]): string {
  const res = spawnSync("git", args, {
    cwd,
    stdio: ["ignore", "pipe", "pipe"],
    encoding: "utf-8",
  });
  if (res.error) throw res.error;
  if (typeof res.status === "number" && res.status !== 0) {
    throw new Error(`git ${args.join(" ")} failed (exit ${res.status}): ${(res.stderr || "").trim()}`);
  }
  return res.stdout || "";
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

  if (fs.existsSync(worktreePath)) {
    return { worktreePath, branchName, success: true };
  }

  try {
    runGit(repoRoot, ["worktree", "add", "-b", branchName, worktreePath, baseRef]);
    return { worktreePath, branchName, success: true };
  } catch {
    try {
      runGit(repoRoot, ["worktree", "add", worktreePath, branchName]);
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
    const diff = runGit(worktreePath, ["diff", baseRef]);
    const status = runGit(worktreePath, ["status", "--porcelain"]);
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
      runGit(repoRoot, ["worktree", "remove", "--force", worktreePath]);
    }
    if (branchName) {
      try {
        runGit(repoRoot, ["branch", "-D", branchName]);
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
