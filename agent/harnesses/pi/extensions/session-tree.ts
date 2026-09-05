/**
 * Session Tree & Checkpoint Branching Extension for Pi Coding Agent
 *
 * Provides tree-based checkpointing and rewind capabilities:
 * - /checkpoint [name]: Capture current git head, timestamp, and step notes.
 * - /tree: Display checkpoint lineage tree.
 * - /rewind <name>: Rewind working tree or branch to a previous checkpoint.
 */

import { execSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export interface SessionCheckpoint {
  id: string;
  name: string;
  timestamp: string;
  gitSha: string;
  branch: string;
  notes?: string;
  parentId?: string;
}

export interface CheckpointStore {
  activeId: string | null;
  checkpoints: SessionCheckpoint[];
}

export function addCheckpoint(
  store: CheckpointStore,
  name: string,
  gitSha: string,
  branch: string,
  notes?: string
): SessionCheckpoint {
  const id = `cp-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
  const cp: SessionCheckpoint = {
    id,
    name,
    timestamp: new Date().toISOString(),
    gitSha,
    branch,
    notes,
    parentId: store.activeId || undefined,
  };
  store.checkpoints.push(cp);
  store.activeId = id;
  return cp;
}

export function findCheckpoint(store: CheckpointStore, identifier: string): SessionCheckpoint | null {
  const norm = identifier.toLowerCase();
  return (
    store.checkpoints.find(c => c.id.toLowerCase() === norm || c.name.toLowerCase() === norm) || null
  );
}

export function renderCheckpointTree(store: CheckpointStore): string {
  if (store.checkpoints.length === 0) {
    return "No checkpoints recorded yet. Use `/checkpoint <name>` to record one.";
  }

  let out = "🌲 **Session Checkpoint Tree**:\n\n";
  for (const cp of store.checkpoints) {
    const isCurrent = cp.id === store.activeId;
    const marker = isCurrent ? "📍 (current)" : "  ";
    out += `${marker} **${cp.name}** (\`${cp.id}\` | \`${cp.gitSha.slice(0, 7)}\`)\n`;
    out += `     Time: ${cp.timestamp.split("T")[1]?.slice(0, 8) || cp.timestamp} | Branch: \`${cp.branch}\`\n`;
    if (cp.notes) {
      out += `     Note: ${cp.notes}\n`;
    }
  }
  return out.trim();
}

function getStorePath(cwd: string): string {
  return path.join(cwd, ".git", "pi-checkpoints.json");
}

export function loadStore(cwd: string): CheckpointStore {
  const p = getStorePath(cwd);
  if (fs.existsSync(p)) {
    try {
      return JSON.parse(fs.readFileSync(p, "utf-8"));
    } catch {
      // return default
    }
  }
  return { activeId: null, checkpoints: [] };
}

export function saveStore(cwd: string, store: CheckpointStore): void {
  const p = getStorePath(cwd);
  const dir = path.dirname(p);
  if (fs.existsSync(dir)) {
    fs.writeFileSync(p, JSON.stringify(store, null, 2), "utf-8");
  }
}

export default function (pi: ExtensionAPI) {
  // Command: /checkpoint
  pi.registerCommand("checkpoint", {
    description: "Create a session checkpoint (/checkpoint <name> [notes])",
    handler: async (args, ctx) => {
      const parts = (args || "").trim().split(/\s+/);
      const name = parts[0] || `checkpoint-${Date.now()}`;
      const notes = parts.slice(1).join(" ") || undefined;

      try {
        const sha = execSync("git rev-parse HEAD", { cwd: ctx.cwd, encoding: "utf-8" }).trim();
        const branch = execSync("git rev-parse --abbrev-ref HEAD", { cwd: ctx.cwd, encoding: "utf-8" }).trim();
        const store = loadStore(ctx.cwd);
        const cp = addCheckpoint(store, name, sha, branch, notes);
        saveStore(ctx.cwd, store);
        ctx.ui.notify(`Saved checkpoint '${cp.name}' (${cp.gitSha.slice(0, 7)})`, "info");
      } catch (e: any) {
        ctx.ui.notify(`Failed to create checkpoint: ${e.message}`, "error");
      }
    },
  });

  // Command: /tree
  pi.registerCommand("tree", {
    description: "View session checkpoint tree and rewind history",
    handler: async (_args, ctx) => {
      const store = loadStore(ctx.cwd);
      const tree = renderCheckpointTree(store);
      ctx.ui.notify(tree, "info");
    },
  });

  // Command: /rewind
  pi.registerCommand("rewind", {
    description: "Rewind session to a named checkpoint (/rewind <name-or-id>)",
    handler: async (args, ctx) => {
      const target = (args || "").trim();
      if (!target) {
        ctx.ui.notify("Usage: /rewind <checkpoint-name-or-id>", "warning");
        return;
      }

      const store = loadStore(ctx.cwd);
      const cp = findCheckpoint(store, target);
      if (!cp) {
        ctx.ui.notify(`Checkpoint '${target}' not found. Run /tree to view available checkpoints.`, "error");
        return;
      }

      store.activeId = cp.id;
      saveStore(ctx.cwd, store);
      ctx.ui.notify(`Rewound active checkpoint pointer to '${cp.name}' (${cp.gitSha.slice(0, 7)}). To restore git state: \`git reset --soft ${cp.gitSha}\``, "info");
    },
  });
}
