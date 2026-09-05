/**
 * ast-grep (Tree-sitter AST search) Bridge Extension for Pi Coding Agent
 *
 * Provides structural, syntax-aware code search and rewriting tools:
 * - ast_grep_search: Match structural code patterns without regex false positives.
 * - ast_grep_replace: Perform AST-aware replacements.
 */

import { execSync, spawnSync } from "node:child_process";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export interface AstGrepMatch {
  file: string;
  line: number;
  column: number;
  text: string;
}

export function detectAstGrepBinary(): string | null {
  for (const bin of ["ast-grep", "sg"]) {
    try {
      const res = spawnSync(bin, ["--version"], { encoding: "utf-8" });
      if (res.status === 0) return bin;
    } catch {
      // continue
    }
  }
  return null;
}

export function buildSearchCommand(
  bin: string,
  pattern: string,
  language?: string,
  targetPath?: string
): { cmd: string; args: string[] } {
  const args = ["run", "--pattern", pattern, "--json"];
  if (language) {
    args.push("--lang", language);
  }
  if (targetPath) {
    args.push(targetPath);
  }
  return { cmd: bin, args };
}

export function parseAstGrepJson(output: string): AstGrepMatch[] {
  if (!output || !output.trim()) return [];
  try {
    const raw = JSON.parse(output);
    if (!Array.isArray(raw)) return [];
    return raw.map((item: any) => ({
      file: item.file || item.path || "",
      line: item.range?.start?.line ?? item.lines?.start ?? 1,
      column: item.range?.start?.column ?? 1,
      text: item.text || item.lines || "",
    }));
  } catch {
    return [];
  }
}

export function runAstSearch(
  pattern: string,
  cwd: string,
  language?: string,
  targetPath?: string
): { success: boolean; matches: AstGrepMatch[]; message: string } {
  const bin = detectAstGrepBinary();
  if (!bin) {
    return {
      success: false,
      matches: [],
      message: "ast-grep (sg) is not installed. Install via `paru -S ast-grep-bin` or `cargo install ast-grep --locked`.",
    };
  }

  const { cmd, args } = buildSearchCommand(bin, pattern, language, targetPath);
  try {
    const res = spawnSync(cmd, args, { cwd, encoding: "utf-8", maxBuffer: 10 * 1024 * 1024 });
    if (res.status !== 0 && res.stderr && !res.stdout) {
      return {
        success: false,
        matches: [],
        message: `ast-grep error: ${res.stderr.trim()}`,
      };
    }
    const matches = parseAstGrepJson(res.stdout || "");
    return {
      success: true,
      matches,
      message: `Found ${matches.length} structural matches for pattern: ${pattern}`,
    };
  } catch (e: any) {
    return {
      success: false,
      matches: [],
      message: `Execution failed: ${e.message}`,
    };
  }
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "ast_grep_search",
    description: "Search for code structures using Tree-sitter AST patterns (e.g. `if err != nil { $$$ }` or `fn $NAME($$$ARGS) -> $RET`). Much more accurate and token-efficient than regex grep.",
    parameters: Type.Object({
      pattern: Type.String({ description: "ast-grep structural pattern to search for." }),
      language: Type.Optional(Type.String({ description: "Language (go, rust, ts, tsx, c, cpp, python, etc.). Inferred if omitted." })),
      path: Type.Optional(Type.String({ description: "Specific sub-directory or file path to limit the search." })),
    }),
    handler: async (args, ctx) => {
      const result = runAstSearch(args.pattern, ctx.cwd, args.language, args.path);
      if (!result.success) {
        return {
          content: [{ type: "text", text: result.message }],
        };
      }

      let text = `${result.message}\n\n`;
      for (const m of result.matches.slice(0, 25)) {
        text += `${m.file}:${m.line}:${m.column}\n\`\`\`\n${m.text.trim()}\n\`\`\`\n\n`;
      }
      if (result.matches.length > 25) {
        text += `\n... ${result.matches.length - 25} more matches truncated.`;
      }

      return {
        content: [{ type: "text", text: text.trim() }],
      };
    },
  });
}
