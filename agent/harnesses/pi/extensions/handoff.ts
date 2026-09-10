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

/** Unquote a git C-style quoted porcelain path (paths with special chars are wrapped in "..."). */
function unquotePorcelainPath(p: string): string {
  if (p.length >= 2 && p.startsWith('"') && p.endsWith('"')) {
    try {
      return JSON.parse(p);
    } catch {
      return p.slice(1, -1);
    }
  }
  return p;
}

/**
 * Parse `git status --porcelain` output into the list of current paths. Each
 * line is `XY<space>PATH` (2-column status + 1 space + path). Renames/copies are
 * `ORIG -> DEST`; the current (DEST) path is recorded. The previous
 * `split(/\s+/)[1]` heuristic broke on quoted paths with spaces (`"a b.txt"`) and
 * reported the OLD name for renames.
 */
export function parsePorcelainPaths(statusOut: string): string[] {
  const modified: string[] = [];
  for (const line of statusOut.split("\n")) {
    // Need at least "XY P" (2 status cols + space + 1-char path).
    if (line.length < 4) continue;
    let pathPart = line.slice(3);
    const arrow = pathPart.indexOf(" -> ");
    if (arrow !== -1) pathPart = pathPart.slice(arrow + 4);
    pathPart = unquotePorcelainPath(pathPart);
    if (pathPart) modified.push(pathPart);
  }
  return modified;
}

export function extractGitContext(cwd: string): { branch: string; sha: string; modified: string[] } {
  try {
    const branch = execSync("git rev-parse --abbrev-ref HEAD", { cwd, encoding: "utf-8" }).trim();
    const sha = execSync("git rev-parse --short HEAD", { cwd, encoding: "utf-8" }).trim();
    const statusOut = execSync("git status --porcelain", { cwd, encoding: "utf-8" });
    return { branch, sha, modified: parsePorcelainPaths(statusOut) };
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
    // `--` separates the prompt from flags so a prompt starting with `-` is not
    // misparsed by codex (consistent with bridge-codex; today the prompt is the
    // fixed "Resume task: ..." template, so this is defensive robustness).
    return { bin: "codex", args: ["exec", "--", prompt] };
  }
}

/**
 * Single-quote an argument for a COPY-PASTE-SAFE displayed shell command. The
 * previous `a.includes(" ") ? "..." : a` only double-quoted on a space, so an arg
 * with shell metacharacters but no space (e.g. `fix$(rm -rf x)`) was shown
 * unquoted and a space-containing arg was double-quoted (which does not neutralize
 * $(...) / backticks) — pasting either would execute injected commands. Bare
 * shell-safe tokens are left unquoted for readability.
 */
export function shDisplayQuote(a: string): string {
  if (a !== "" && /^[\w@%+=:,./-]+$/.test(a)) return a;
  return `'${a.replace(/'/g, "'\\''")}'`;
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
    out += `${execInfo.bin} ${execInfo.args.map(shDisplayQuote).join(" ")}\n`;
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
