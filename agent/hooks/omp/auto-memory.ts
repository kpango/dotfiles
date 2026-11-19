/**
 * Auto-Memory & Knowledge Consolidation Extension for Oh My Pi (OMP)
 *
 * Injects local persistent memories (`~/.omp/agent/memory/global-memory.md` and
 * per-project `*-memory.md`) into new sessions and exposes on-demand memory search.
 * Optionally queries an external supermemory server if `SUPERMEMORY_API_URL` is configured.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { searchMemories, formatMemoryInjection, type SupermemoryMemory } from "./lib/memory-adapter";

const KB_TAG = "claude-memory";
const ALL_TAGS = ["claude-memory", "skill-memory", "agent-memory"];

function getMemoryDir(): string {
  const memDir = path.join(os.homedir(), ".omp", "agent", "memory");
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

/** Search local markdown memory files under ~/.omp/agent/memory/ (case-insensitive substring match). */
function searchLocalMemories(query: string, cwd: string, limit = 8): string[] {
  const memDir = getMemoryDir();
  const needle = query.toLowerCase();
  const candidates = new Set<string>([
    path.join(memDir, "global-memory.md"),
    getProjectMemoryFile(cwd),
  ]);
  try {
    for (const entry of fs.readdirSync(memDir)) {
      if (entry.endsWith(".md")) {
        candidates.add(path.join(memDir, entry));
      }
    }
  } catch {
    // ignore unreadable directory
  }

  const hits: string[] = [];
  for (const filePath of candidates) {
    if (!fs.existsSync(filePath)) continue;
    let content = "";
    try {
      content = fs.readFileSync(filePath, "utf-8");
    } catch {
      continue;
    }
    const label = path.basename(filePath);
    for (const rawLine of content.split(/\r?\n/)) {
      const line = rawLine.trim();
      if (!line || line.startsWith("#")) continue;
      if (line.toLowerCase().includes(needle)) {
        hits.push(`[${label}] ${line}`);
        if (hits.length >= limit) return hits;
      }
    }
  }
  return hits;
}

export default function (pi: ExtensionAPI) {
  // Inject memory on session start (skip in isolated subagent processes to prevent token overflow)
  pi.on("before_agent_start", async (_event) => {
    if (process.env.PI_SUBAGENT === "1") {
      return;
    }
    const memDir = getMemoryDir();
    const globalMem = path.join(memDir, "global-memory.md");
    const projMem = getProjectMemoryFile(process.cwd());
    let injected = "";

    if (fs.existsSync(globalMem)) {
      const globalContent = fs.readFileSync(globalMem, "utf-8").trim();
      if (globalContent) {
        injected += `[Global Memory]:\n${globalContent}\n\n`;
      }
    }

    if (fs.existsSync(projMem)) {
      const projContent = fs.readFileSync(projMem, "utf-8").trim();
      if (projContent) {
        injected += `[Project Memory]:\n${projContent}\n\n`;
      }
    }

    if (process.env.SUPERMEMORY_API_URL) {
      const smContext = await loadSupermemoryContext(process.cwd());
      if (smContext) {
        injected += `${smContext}\n\n`;
      }
    }

    if (injected.trim()) {
      return {
        message: {
          customType: "memory-context",
          content: `<auto_memory_context>\n${injected.trim()}\n</auto_memory_context>`,
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

  // Slash Command /memory-search — local markdown + optional remote memory recall
  pi.registerCommand("memory-search", {
    description: "Search persistent memories (local markdown + optional remote store)",
    handler: async (args, ctx) => {
      const q = (typeof args === "string" ? args : "").trim();
      if (!q) {
        ctx.ui.notify("Usage: /memory-search <query>", "info");
        return;
      }
      const localHits = searchLocalMemories(q, ctx.cwd, 8);
      const remoteHits = process.env.SUPERMEMORY_API_URL ? await searchAllTags(q, 8) : [];
      const seen = new Set<string>(localHits);
      const combined = [...localHits];
      for (const h of remoteHits) {
        const text = h.memory.trim();
        if (text && !seen.has(text)) {
          seen.add(text);
          combined.push(text);
        }
      }
      if (combined.length === 0) {
        ctx.ui.notify(`No matching memories for "${q}".`, "info");
        return;
      }
      const out = combined.slice(0, 8).map((line, i) => `${i + 1}. ${line}`).join("\n");
      ctx.ui.notify(`Memory search "${q}":\n${out}`, "info");
    },
  });
}
