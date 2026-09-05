/**
 * Agent Handoff & Session Export Extension for Pi Coding Agent
 *
 * Implements smooth handoffs between agent sessions and multi-agent harnesses:
 * - /handoff [target]: Summarizes current objectives, modified files, and next tasks.
 * - Formats output for immediate delegation to Claude Code, Antigravity, or Codex.
 */

import { execSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export interface HandoffData {
  objective: string;
  modifiedFiles: string[];
  currentGitBranch: string;
  currentGitSha: string;
  nextSteps: string[];
  recommendedAgent?: string;
  notes?: string;
}

export function extractGitContext(cwd: string): { branch: string; sha: string; modified: string[] } {
  try {
    const branch = execSync("git rev-parse --abbrev-ref HEAD", { cwd, encoding: "utf-8" }).trim();
    const sha = execSync("git rev-parse --short HEAD", { cwd, encoding: "utf-8" }).trim();
    const statusOut = execSync("git status --porcelain", { cwd, encoding: "utf-8" });
    const modified: string[] = [];
    for (const line of statusOut.split("\n")) {
      const trimmed = line.trim();
      if (trimmed) {
        // e.g. "M file.ts" or "?? new.ts"
        const parts = trimmed.split(/\s+/);
        if (parts[1]) modified.push(parts[1]);
      }
    }
    return { branch, sha, modified };
  } catch {
    return { branch: "unknown", sha: "unknown", modified: [] };
  }
}

export function buildHandoffExecutionCommand(
  targetHarness: "claude" | "agy" | "codex",
  objective: string,
  modifiedFiles: string[] = []
): { bin: string; args: string[] } {
  const prompt = `Resume task: ${objective}. Modified files: ${modifiedFiles.join(", ") || "none"}`;
  if (targetHarness === "claude") {
    return { bin: "claude", args: ["-p", prompt] };
  } else if (targetHarness === "agy") {
    return { bin: "agy", args: ["-p", prompt] };
  } else {
    return { bin: "codex", args: ["exec", prompt] };
  }
}

export function formatHandoffMarkdown(data: HandoffData, targetHarness?: "claude" | "agy" | "codex" | "file"): string {
  let out = `# 🤝 Agent Handoff Document\n\n`;
  out += `**Objective**: ${data.objective}\n`;
  out += `**Branch**: \`${data.currentGitBranch}\` (\`${data.currentGitSha}\`)\n\n`;

  out += `### 📁 Modified Files (${data.modifiedFiles.length})\n`;
  if (data.modifiedFiles.length > 0) {
    for (const f of data.modifiedFiles) {
      out += `- \`${f}\`\n`;
    }
  } else {
    out += `*(clean working tree)*\n`;
  }
  out += "\n";

  out += `### 📋 Next Immediate Steps\n`;
  if (data.nextSteps.length > 0) {
    for (const step of data.nextSteps) {
      out += `- [ ] ${step}\n`;
    }
  } else {
    out += `- [ ] Continue task verification and execute test suite\n`;
  }
  out += "\n";

  if (data.notes) {
    out += `### 💡 Context & Invariant Notes\n${data.notes}\n\n`;
  }

  if (targetHarness && targetHarness !== "file") {
    const execInfo = buildHandoffExecutionCommand(targetHarness, data.objective, data.modifiedFiles);
    out += `### 🚀 Handoff CLI Command\n\`\`\`bash\n`;
    out += `${execInfo.bin} ${execInfo.args.map((a) => (a.includes(" ") ? `"${a}"` : a)).join(" ")}\n`;
    out += `\`\`\`\n`;
  }

  return out.trim();
}

export default function (pi: ExtensionAPI) {
  // Command: /handoff
  pi.registerCommand("handoff", {
    description: "Export current session context and generate handoff document (/handoff [claude|agy|codex|file])",
    handler: async (args, ctx) => {
      const target = (args || "file").trim().toLowerCase() as any;
      const git = extractGitContext(ctx.cwd);

      const data: HandoffData = {
        objective: "Multi-agent task continuation",
        modifiedFiles: git.modified,
        currentGitBranch: git.branch,
        currentGitSha: git.sha,
        nextSteps: ["Run test suite and verify changes", "Commit validated progress"],
      };

      const md = formatHandoffMarkdown(data, target);
      if (target === "file") {
        const outPath = path.join(ctx.cwd, "handoff.md");
        fs.writeFileSync(outPath, md, "utf-8");
        ctx.ui.notify(`Saved handoff report to ${outPath}`, "info");
      } else {
        ctx.ui.notify(md, "info");
      }
    },
  });
}
