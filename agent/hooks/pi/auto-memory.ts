/**
 * Auto-Memory & Knowledge Consolidation Extension for Pi Coding Agent
 *
 * Injects relevant knowledge into new sessions via the locally self-hosted
 * supermemory server (RAG semantic retrieval) and exposes on-demand memory search.
 *
 * MIGRATION (2026-09-08, supermemory-migration mission): the previous behavior read
 * the entire `~/.claude/memory/` markdown corpus (156 entries) through
 * decide.py `memory_context` and dumped index+topic heads into every session. That
 * legacy read path has been removed (decision-4: no backward compatibility). The
 * corpus is now migrated into supermemory (containerTag `claude-memory`) and injected
 * as a small, query-relevant subset instead of the full dump — see
 * `lib/memory-adapter.ts`. supermemory runs at http://localhost:6767 with embeddings
 * local (Xenova/bge, offline); LLM extraction is routed through the OpenCode Go
 * (opencode.ai/zen) provider via a local header-injecting proxy.
 *
 * `~/.pi/agent/memory/` (global-memory.md + per-project `/memory`) remains a separate,
 * user-edited store and is unchanged.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { searchMemories, formatMemoryInjection, type SupermemoryMemory } from "./lib/memory-adapter";

const KB_TAG = "claude-memory";
const ALL_TAGS = ["claude-memory", "skill-memory", "agent-memory"];

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

/**
 * Retrieve a compact, project-relevant memory block from supermemory for session
 * injection. Query is derived from the project directory name plus general knowledge
 * facets. Scoped to the migrated `claude-memory` knowledge base to bound token cost.
 * Returns null on empty/unavailable (advisory; never throws).
 */
async function loadSupermemoryContext(cwd: string): Promise<string | null> {
  const project = path.basename(cwd).replace(/[^\w.-]+/g, " ").trim();
  const query = `${project} conventions decisions architecture pitfalls preferences`.trim();
  const memories = await searchMemories(query, { tags: [KB_TAG], limit: 10, timeoutMs: 3500 });
  const block = formatMemoryInjection(memories, "Relevant Memory (supermemory)");
  return block || null;
}

/** Merge per-tag searches (robust to containerTag AND/OR semantics), dedupe, rank. */
async function searchAllTags(query: string, limit: number): Promise<SupermemoryMemory[]> {
  const perTag = await Promise.all(ALL_TAGS.map((t) => searchMemories(query, { tags: [t], limit, timeoutMs: 4000 })));
  const seen = new Set<string>();
  const merged: SupermemoryMemory[] = [];
  for (const list of perTag) {
    for (const m of list) {
      const key = m.memory.trim();
      if (!key || seen.has(key)) continue;
      seen.add(key);
      merged.push(m);
    }
  }
  merged.sort((a, b) => (b.score ?? 0) - (a.score ?? 0));
  return merged.slice(0, limit);
}

export default function (pi: ExtensionAPI) {
  // Inject memory on session start (skip in isolated subagent processes to prevent token overflow)
  pi.on("before_agent_start", async (_event) => {
    if (process.env.PI_SUBAGENT === "1") {
      return;
    }
    const memDir = getMemoryDir();
    const globalMem = path.join(memDir, "global-memory.md");
    let injected = "";

    if (fs.existsSync(globalMem)) {
      injected += `[Global Memory]:\n${fs.readFileSync(globalMem, "utf-8").trim()}\n\n`;
    }

    const smContext = await loadSupermemoryContext(process.cwd());
    if (smContext) {
      injected += `${smContext}\n\n`;
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

  // Slash Command /memory — view or edit per-project persistent memory (user-edited)
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

  // Slash Command /memory-search — semantic recall across the migrated knowledge base
  pi.registerCommand("memory-search", {
    description: "Semantic search across supermemory (claude/skill/agent memory)",
    handler: async (args, ctx) => {
      const q = (typeof args === "string" ? args : "").trim();
      if (!q) {
        ctx.ui.notify("Usage: /memory-search <query>", "info");
        return;
      }
      const hits = await searchAllTags(q, 8);
      if (hits.length === 0) {
        ctx.ui.notify(`No matching memories for "${q}".`, "info");
        return;
      }
      const out = hits.map((h, i) => `${i + 1}. ${h.memory}`).join("\n");
      ctx.ui.notify(`Memory search "${q}":\n${out}`, "info");
    },
  });
}
