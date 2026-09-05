/**
 * Session History Search & Context Recall Extension for Pi Coding Agent
 *
 * Provides high-speed semantic/text search across historical sessions in ~/.pi/agent/sessions/
 * to quickly recall previous solutions, commands, and architectural decisions.
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
    const files = fs.readdirSync(sessionsDir).filter((f) => f.endsWith(".json") || f.endsWith(".jsonl"));

    for (const f of files) {
      const fullPath = path.join(sessionsDir, f);
      try {
        const content = fs.readFileSync(fullPath, "utf-8");
        const lower = content.toLowerCase();

        const matchIdx = lower.indexOf(q);
        if (matchIdx !== -1) {
          // Extract snippet around match (100 chars before and after)
          const start = Math.max(0, matchIdx - 80);
          const end = Math.min(content.length, matchIdx + query.length + 120);
          const snippet = content.slice(start, end).replace(/\r?\n/g, " ").trim();

          results.push({
            sessionFile: f,
            matchedText: `...${snippet}...`,
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
