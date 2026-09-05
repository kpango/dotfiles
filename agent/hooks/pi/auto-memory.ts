/**
 * Auto-Memory & Knowledge Consolidation Extension for Pi Coding Agent
 *
 * Automatically consolidates architectural decisions, project conventions, and lessons
 * into ~/.pi/agent/memory/ and injects them into new sessions and before compactions.
 *
 * `~/.claude/memory/`(claude/agyが共有するトピック別知識ベース)は元々piからは一切読まれて
 * いなかった(claudeは`~/.claude/memory`のみ・agyは`~/.gemini/memory`と`~/.claude/memory`の
 * 両方を読むのに対し、piだけこの知識ベースへのアクセスを持たない非対称があった)。本ファイルの
 * `~/.pi/agent/memory/`(global-memory.md・プロジェクト単位memory・`/memory`コマンド用)は
 * ユーザーが直接編集する別用途のメモリであり置き換えない — `~/.claude/memory`の注入はこれに
 * 追加する形で行う(2026-09-03、agent/scripts/hooks/memory_context.py + decide.py 経由、
 * agent/hooks/claude/session-start.sh・agent/hooks/agy/session-start.shと同じ共有エンジンを再利用)。
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { callDecide, repoRoot } from "./lib/shared";

function getMemoryDir(): string {
  const memDir = path.join(os.homedir(), ".pi", "agent", "memory");
  if (!fs.existsSync(memDir)) {
    fs.mkdirSync(memDir, { recursive: true });
  }
  return memDir;
}

function getProjectMemoryFile(cwd: string): string {
  const safeName = path.basename(cwd).replace(/[^\w.-]+/g, "_");
  return path.join(getMemoryDir(), `${safeName}-memory.md`);
}

function loadClaudeMemoryContext(): string | null {
  const root = repoRoot(import.meta.url);
  if (!root) return null;
  const result = callDecide<{ context?: string }>(
    root,
    {
      family: "memory_context",
      memory_dirs: [path.join(os.homedir(), ".claude", "memory")],
      local_files: [],
      cwd: process.cwd(),
      index_head: 200,
      topic_head: 150,
      multi_dir_labels: false,
    },
    {},
  );
  return result.context?.trim() || null;
}

export default function (pi: ExtensionAPI) {
  // Inject memory on session start
  pi.on("before_agent_start", async (_event) => {
    const memDir = getMemoryDir();
    const globalMem = path.join(memDir, "global-memory.md");
    let injected = "";

    if (fs.existsSync(globalMem)) {
      injected += `[Global Memory]:\n${fs.readFileSync(globalMem, "utf-8").trim()}\n\n`;
    }

    const claudeMemory = loadClaudeMemoryContext();
    if (claudeMemory) {
      injected += `[Claude Memory (~/.claude/memory)]:\n${claudeMemory}\n\n`;
    }

    if (injected.trim()) {
      return {
        message: {
          customType: "memory-context",
          content: injected.trim(),
          display: false,
        },
      };
    }
  });

  // Slash Command /memory
  pi.registerCommand("memory", {
    description: "View or edit project persistent memory",
    handler: async (_args, ctx) => {
      const projMem = getProjectMemoryFile(ctx.cwd);
      let content = fs.existsSync(projMem) ? fs.readFileSync(projMem, "utf-8") : "# Project Memory\n\n- (No memories recorded yet)";

      if (ctx.hasUI) {
        const edited = await ctx.ui.editor("Edit Project Memory:", content);
        if (edited !== undefined && edited.trim() !== content.trim()) {
          fs.writeFileSync(projMem, edited.trim(), "utf-8");
          ctx.ui.notify("✓ Memory updated successfully.", "info");
        }
      } else {
        ctx.ui.notify(`Project Memory:\n${content}`, "info");
      }
    },
  });
}
