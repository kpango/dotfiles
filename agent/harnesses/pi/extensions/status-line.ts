/**
 * Terminal Status Line Extension for Pi Coding Agent
 *
 * Displays live git repository context, branch status, dirty count,
 * current workspace path, active Model Tier, and session telemetry in the interactive TUI footer.
 */

import { execSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

function getGitStatus(cwd: string): { branch: string; staged: number; unstaged: number; untracked: number } | null {
  try {
    const branch = execSync("git rev-parse --abbrev-ref HEAD", { cwd, stdio: ["ignore", "pipe", "ignore"], encoding: "utf-8" }).trim();
    if (!branch) return null;

    const staged = execSync("git diff --cached --name-only", { cwd, stdio: ["ignore", "pipe", "ignore"], encoding: "utf-8" })
      .trim()
      .split("\n")
      .filter(Boolean).length;

    const unstaged = execSync("git diff --name-only", { cwd, stdio: ["ignore", "pipe", "ignore"], encoding: "utf-8" })
      .trim()
      .split("\n")
      .filter(Boolean).length;

    const untracked = execSync("git ls-files --others --exclude-standard", { cwd, stdio: ["ignore", "pipe", "ignore"], encoding: "utf-8" })
      .trim()
      .split("\n")
      .filter(Boolean).length;

    return { branch, staged, unstaged, untracked };
  } catch {
    return null;
  }
}

function formatCwd(cwd: string): string {
  const home = os.homedir();
  const rel = cwd.startsWith(home) ? `~${cwd.slice(home.length)}` : cwd;
  const parts = rel.split("/");
  if (parts.length > 5) {
    return `…/${parts.slice(-4).join("/")}`;
  }
  return rel;
}

export function getActiveTierInfo(modelId?: string): string {
  const searchPaths = [
    path.join(os.homedir(), ".pi", "agent", "model-routing.json"),
    path.join(os.homedir(), "go", "src", "github.com", "kpango", "dotfiles", "agent", "harnesses", "pi", "model-routing.json"),
  ];

  for (const p of searchPaths) {
    if (fs.existsSync(p)) {
      try {
        const raw = fs.readFileSync(p, "utf-8");
        const data = JSON.parse(raw);
        const defaultTier = data.default_tier || "High";
        const tierCfg = data.tiers?.[defaultTier];
        const m = modelId || tierCfg?.model || "anthropic/claude-sonnet-5";
        const shortName = m.split("/").pop() || m;
        return `🎯 [${defaultTier}: ${shortName}]`;
      } catch {
        // ignore and fallback
      }
    }
  }
  return "🎯 [High: claude-sonnet-5]";
}

export default function (pi: ExtensionAPI) {
  const updateStatus = (cwd: string, ctx: any) => {
    const dirStr = formatCwd(cwd);
    const git = getGitStatus(cwd);

    let statusText = `📁 ${dirStr}`;
    if (git) {
      statusText += ` | 🌿 ${git.branch}`;
      const badges: string[] = [];
      if (git.staged > 0) badges.push(`+${git.staged}`);
      if (git.unstaged > 0) badges.push(`!${git.unstaged}`);
      if (git.untracked > 0) badges.push(`?${git.untracked}`);
      if (badges.length > 0) statusText += ` [${badges.join(" ")}]`;
    }

    ctx.ui.setStatus("workspace", statusText);

    // Render active Tier badge in statusline
    const activeModel = ctx.model?.id || ctx.session?.model;
    const tierBadge = getActiveTierInfo(activeModel);
    ctx.ui.setStatus("tier", tierBadge);
  };

  pi.on("session_start", async (_event, ctx) => {
    updateStatus(ctx.cwd, ctx);
  });

  pi.on("agent_settled", async (_event, ctx) => {
    updateStatus(ctx.cwd, ctx);
  });
}
