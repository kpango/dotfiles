/**
 * Hermes-Style Closed-Loop Skill Synthesis Extension for Pi Coding Agent
 *
 * Autonomously inspects completed execution trajectories (commands, diffs, test outcomes)
 * and distills generalized operational procedures into canonical SKILL.md specs with
 * strict YAML frontmatter.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

import {
  // Types & Interfaces
  TaskExecutionTrace,
  SkillFrontmatter,
  SkillSpec,
  SkillSynthesisResult,
  SaveSkillOptions,

  // Functions
  extractTrace,
  extractOperationalTrace,
  sanitizeSkillName,
  formatSkillMarkdown,
  validateSkillFrontmatter,
  discoverExistingSkills,
  synthesizeSkillFromTrace,
  saveSkill,
  persistSkill,
} from "./lib/skill-synthesizer-core";

// Re-export core functions and types
export * from "./lib/skill-synthesizer-core";

export default function (pi: ExtensionAPI) {
  const accumulatedEvents: any[] = [];
  let lastTrace: TaskExecutionTrace | null = null;

  // Hook: accumulate tool execution outcomes into execution trace
  pi.on("tool_result", async (event, ctx) => {
    accumulatedEvents.push({
      type: "tool_result",
      tool: (event as any)?.toolName || (event as any)?.tool,
      toolName: (event as any)?.toolName || (event as any)?.tool,
      params: (event as any)?.input || (event as any)?.params,
      result: (event as any)?.result,
      isError: (event as any)?.isError || (event as any)?.error,
      cwd: ctx?.cwd,
      timestamp: Date.now(),
    });
  });

  // Hook: snapshot completed turn and update trace on agent completion
  pi.on("agent_end", async (event, ctx) => {
    if ((event as any)?.messages && Array.isArray((event as any).messages)) {
      for (const msg of (event as any).messages) {
        accumulatedEvents.push(msg);
      }
    }
    lastTrace = extractTrace(accumulatedEvents);
    if (ctx?.cwd) lastTrace.cwd = ctx.cwd;
  });

  // ---------------------------------------------------------------------------
  // Tool: synthesize_skill
  // --------------------------------------------------------------------------
  pi.registerTool({
    name: "synthesize_skill",
    description:
      "Synthesize a reusable SKILL.md specification from the session execution trace (commands, git diffs, and verification evidence).",
    parameters: Type.Object({
      name: Type.Optional(Type.String({ description: "Suggested name for the skill (will be sanitized to kebab-case)." })),
      description: Type.Optional(Type.String({ description: "Explicit description for the skill frontmatter." })),
      overwrite: Type.Optional(Type.Boolean({ description: "Whether to overwrite existing skill if collision occurs (default: false)." })),
    }),
    handler: async (args, ctx) => {
      const trace = lastTrace || extractTrace(accumulatedEvents);
      if (ctx?.cwd && !trace.cwd) trace.cwd = ctx.cwd;

      if (trace.commands.length === 0 && trace.tools.length === 0) {
        return {
          content: [
            {
              type: "text",
              text: "No operational actions or commands recorded in the session execution trace. Perform actions before synthesizing.",
            },
          ],
        };
      }

      const spec = synthesizeSkillFromTrace(trace, args.name);
      if (args.description) {
        spec.frontmatter.description = args.description;
      }

      const result = saveSkill(spec, { overwrite: args.overwrite ?? false });

      if (!result.persisted) {
        return {
          content: [
            {
              type: "text",
              text: `Skill synthesis aborted: ${result.error || "Unknown error"}`,
            },
          ],
        };
      }

      return {
        content: [
          {
            type: "text",
            text: `Successfully synthesized skill "${result.skillName}" to: ${result.canonicalPath}\n\n\`\`\`markdown\n${result.markdownContent.trim()}\n\`\`\``,
          },
        ],
      };
    },
  });

  // --------------------------------------------------------------------------
  // Slash Command: /synthesize-skill
  // --------------------------------------------------------------------------
  pi.registerCommand("synthesize-skill", {
    description:
      "Synthesize a canonical SKILL.md from the current session's execution trace (/synthesize-skill [name] [--overwrite])",
    handler: async (args, ctx) => {
      const parts = (args || "").trim().split(/\s+/).filter(Boolean);
      let suggestedName: string | undefined;
      let overwrite = false;

      for (const part of parts) {
        if (part === "--overwrite" || part === "-f") {
          overwrite = true;
        } else if (!suggestedName) {
          suggestedName = part;
        }
      }

      const trace = lastTrace || extractTrace(accumulatedEvents);
      if (ctx?.cwd && !trace.cwd) trace.cwd = ctx.cwd;

      if (trace.commands.length === 0 && trace.tools.length === 0) {
        ctx.ui?.notify?.("No operational actions or commands recorded to synthesize.", "warning");
        return;
      }

      const spec = synthesizeSkillFromTrace(trace, suggestedName);
      const result = saveSkill(spec, { overwrite });

      if (!result.persisted) {
        ctx.ui?.notify?.(`Skill synthesis failed: ${ result.error }`, "error");
        return;
      }

      ctx.ui?.notify?.(`Skill synthesized: ${result.skillName} -> ${result.canonicalPath}`, "info");
    },
  });
}
