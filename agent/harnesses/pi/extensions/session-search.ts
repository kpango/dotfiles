/**
 * Session History Search & Context Recall Extension for Pi Coding Agent
 *
 * Provides fast case-insensitive text search across historical sessions in
 * ~/.pi/agent/sessions/ (substring matching, newest-first ordering) to
 * quickly recall previous solutions, commands, and architectural decisions.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export interface SessionSearchResult {
  sessionFile: string;
  matchedText: string;
  timestamp?: string;
  score?: number;
}

export function getSessionsDir(): string {
  return path.join(os.homedir(), ".pi", "agent", "sessions");
}

export function searchSessionFiles(
  sessionsDir: string,
  query: string,
  maxResults = 10
): SessionSearchResult[] {
  if (!fs.existsSync(sessionsDir)) return [];
  const results: SessionSearchResult[] = [];
  const q = query.toLowerCase();

  try {
    const entries: { name: string; mtimeMs: number }[] = [];
    for (const e of fs.readdirSync(sessionsDir, { withFileTypes: true })) {
      if (e.isFile() && (e.name.endsWith(".json") || e.name.endsWith(".jsonl"))) {
        try {
          const stat = fs.statSync(path.join(sessionsDir, e.name));
          entries.push({ name: e.name, mtimeMs: stat.mtimeMs });
        } catch {
          // skip files that disappear between readdir and stat
        }
      }
    }

    // Prefer the most recent sessions first: readdirSync orders by name
    // (ascending), which for timestamped session files means oldest first.
    // Truncating at maxResults from that order would drop the newest matches.
    entries.sort((a, b) => b.mtimeMs - a.mtimeMs);

    for (const e of entries) {
      const fullPath = path.join(sessionsDir, e.name);
      try {
        const content = fs.readFileSync(fullPath, "utf-8");
        const lower = content.toLowerCase();

        const matchIdx = lower.indexOf(q);
        if (matchIdx !== -1) {
          // Extract snippet around match (80 chars before, 120 after
          // query end) so the surrounding context is visible in the result.
          const start = Math.max(0, matchIdx - 80);
          const end = Math.min(content.length, matchIdx + query.length + 120);
          const snippet = content.slice(start, end).replace(/\r?\n/g, " ").trim();

          results.push({
            sessionFile: e.name,
            matchedText: `...${snippet}...`,
            timestamp: new Date(e.mtimeMs).toISOString(),
          });

          if (results.length >= maxResults) break;
        }
      } catch {
        // skip unreadable session file
      }
    }
  } catch {
    // return whatever found
  }

  return results;
}

export function formatSessionSearchResults(results: SessionSearchResult[], query: string): string {
  if (results.length === 0) {
    return `No historical sessions matched query: '${query}'.`;
  }

  let out = `🔍 **Found ${results.length} historical session match(es) for '${query}'**:\n\n`;
  for (const r of results) {
    out += `- **Session**: \`${r.sessionFile}\`\n`;
    out += `  \`${r.matchedText}\`\n\n`;
  }
  return out.trim();
}

export default function (pi: ExtensionAPI) {
  // Register Tool
  pi.registerTool({
    name: "search_sessions",
    description: "Search historical Pi agent conversation sessions (~/.pi/agent/sessions/) for past solutions, commands, and code discussions.",
    parameters: Type.Object({
      query: Type.String({ description: "Keyword or topic to search for across past sessions." }),
      limit: Type.Optional(Type.Integer({ description: "Max results to return (default 5)." })),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, _ctx) {
      const dir = getSessionsDir();
      const results = searchSessionFiles(dir, params.query, params.limit || 5);
      const text = formatSessionSearchResults(results, params.query);
      return {
        content: [{ type: "text", text }],
      };
    },
    handler: async (args, ctx) => {
      const dir = getSessionsDir();
      const results = searchSessionFiles(dir, args.query, args.limit || 5);
      const text = formatSessionSearchResults(results, args.query);
      return {
        content: [{ type: "text", text }],
      };
    },
  });

  // Register Command: /sessions
  pi.registerCommand("sessions", {
    description: "Search historical sessions (/sessions <query>)",
    handler: async (args, ctx) => {
      const q = (args || "").trim();
      if (!q) {
        ctx.ui.notify("Usage: /sessions <search query>", "warning");
        return;
      }

      const dir = getSessionsDir();
      const results = searchSessionFiles(dir, q, 5);
      const text = formatSessionSearchResults(results, q);
      ctx.ui.notify(text, "info");
    },
  });
}
