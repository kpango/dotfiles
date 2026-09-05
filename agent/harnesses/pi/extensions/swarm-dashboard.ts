/**
 * SWARM Mission Dashboard Extension for Pi Coding Agent
 *
 * Visualizes SWARM loop progression, @fix_plan.md task status,
 * attempt counters, and active git worktrees within the terminal UI.
 */

import { execSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export interface FixPlanTask {
  title: string;
  completed: boolean;
  raw: string;
}

export interface FixPlanSummary {
  missionTitle?: string;
  totalTasks: number;
  completedTasks: number;
  tasks: FixPlanTask[];
  currentPhase?: string;
}

export function parseFixPlan(content: string): FixPlanSummary {
  const lines = content.split("\n");
  const tasks: FixPlanTask[] = [];
  let missionTitle: string | undefined;
  let currentPhase: string | undefined;

  for (const line of lines) {
    const trimmed = line.trim();
    if (!missionTitle && trimmed.startsWith("# ")) {
      missionTitle = trimmed.substring(2).trim();
    }
    if (trimmed.startsWith("## ") || trimmed.startsWith("### ")) {
      if (/phase|step/i.test(trimmed)) {
        currentPhase = trimmed.replace(/^#+\s*/, "");
      }
    }
    // Match checklist items - [ ] or - [x]
    const checkMatch = trimmed.match(/^[-*]\s*\[([ xX])\]\s*(.*)$/);
    if (checkMatch) {
      const completed = checkMatch[1].toLowerCase() === "x";
      const title = checkMatch[2].trim();
      tasks.push({ title, completed, raw: trimmed });
    }
  }

  const completedTasks = tasks.filter(t => t.completed).length;
  return {
    missionTitle,
    totalTasks: tasks.length,
    completedTasks,
    tasks,
    currentPhase,
  };
}

export function getWorktreeList(cwd: string): string[] {
  try {
    const out = execSync("git worktree list --porcelain", { cwd, encoding: "utf-8" });
    const worktrees: string[] = [];
    for (const line of out.split("\n")) {
      if (line.startsWith("worktree ")) {
        worktrees.push(line.substring(9).trim());
      }
    }
    return worktrees;
  } catch {
    return [];
  }
}

export function renderDashboardText(summary: FixPlanSummary, worktrees: string[]): string {
  let out = "📊 **SWARM Mission Progress Dashboard**\n\n";

  if (summary.missionTitle) {
    out += `🎯 **Objective**: ${summary.missionTitle}\n`;
  }
  if (summary.currentPhase) {
    out += `🔄 **Phase**: \`${summary.currentPhase}\`\n`;
  }

  // Progress Bar
  const pct = summary.totalTasks > 0 ? Math.round((summary.completedTasks / summary.totalTasks) * 100) : 0;
  const barLen = 20;
  const filled = Math.round((pct / 100) * barLen);
  const bar = "█".repeat(filled) + "░".repeat(barLen - filled);
  out += `\n**Progress**: [${bar}] ${pct}% (${summary.completedTasks}/${summary.totalTasks} tasks)\n\n`;

  // Task list
  if (summary.tasks.length > 0) {
    out += `**Task Queue**:\n`;
    for (const t of summary.tasks.slice(0, 10)) {
      out += `  ${t.completed ? "✅" : "⏳"} ${t.title}\n`;
    }
    if (summary.tasks.length > 10) {
      out += `  ... and ${summary.tasks.length - 10} more tasks\n`;
    }
    out += "\n";
  } else {
    out += `*No checklist tasks found in @fix_plan.md*\n\n`;
  }

  // Worktrees
  out += `**Active Git Worktrees** (${worktrees.length}):\n`;
  for (const wt of worktrees) {
    out += `  📁 \`${wt}\`\n`;
  }

  return out.trim();
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("swarm-dashboard", {
    description: "Display visual progress dashboard for the active SWARM mission",
    handler: async (_args, ctx) => {
      const planPath = path.join(ctx.cwd, "@fix_plan.md");
      let planContent = "";
      if (fs.existsSync(planPath)) {
        try {
          planContent = fs.readFileSync(planPath, "utf-8");
        } catch {
          // ignore
        }
      }

      const summary = parseFixPlan(planContent);
      const worktrees = getWorktreeList(ctx.cwd);
      const rendered = renderDashboardText(summary, worktrees);

      ctx.ui.notify(rendered, "info");
    },
  });
}
