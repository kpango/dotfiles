/**
 * Ponytail Anti-Overengineering Guard Extension for Pi Coding Agent
 *
 * Enforces the 7-step logic ladder (YAGNI, codebase reuse, stdlib priority,
 * platform native, minimal dependency, minimal expression, surgical diff)
 * and verifies that minimalism never compromises safety or error handling.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { execFileSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
  getLadderSteps,
  auditCode,
  auditDiff,
  formatAuditReport,
  type AuditResult,
} from "./lib/ponytail-guard-core";

export default function (pi: ExtensionAPI) {
  const getRepoRoot = (ctx?: any): string => {
    return ctx?.cwd || process.cwd();
  };

  const executeAudit = async (args: any, ctx: any) => {
    const action = args.action || "ladder";
    const repoRoot = getRepoRoot(ctx);

    if (action === "ladder") {
      const steps = getLadderSteps();
      let md = `# 🪜 Ponytail 7-Step Anti-Overengineering Logic Ladder\n\n`;
      md += `*Always solve at the highest step possible before moving down:*\n\n`;
      for (const s of steps) {
        md += `### Step ${s.step}: ${s.name}\n`;
        md += `• **Question**: "${s.question}"\n`;
        md += `• **Rule**: ${s.rule}\n\n`;
      }
      return {
        content: [{ type: "text", text: md.trim() }],
        details: { stepsCount: steps.length },
      };
    }

    if (action === "audit_diff") {
      let diffContent = args.diff;
      if (!diffContent) {
        try {
          diffContent = execFileSync("git", ["diff", "HEAD"], {
            cwd: repoRoot,
            encoding: "utf-8",
            maxBuffer: 10 * 1024 * 1024,
          });
          if (!diffContent.trim()) {
            diffContent = execFileSync("git", ["diff", "--cached"], {
              cwd: repoRoot,
              encoding: "utf-8",
              maxBuffer: 10 * 1024 * 1024,
            });
          }
        } catch (err: any) {
          return {
            content: [
              {
                type: "text",
                text: `❌ Failed to execute git diff: ${err?.message || err}`,
              },
            ],
            details: { error: String(err) },
          };
        }
      }

      if (!diffContent || !diffContent.trim()) {
        return {
          content: [
            {
              type: "text",
              text: `ℹ️ Working tree is clean. No git diff detected to audit.`,
            },
          ],
          details: { emptyDiff: true },
        };
      }

      const res = auditDiff(diffContent);
      const report = formatAuditReport(res, "Active Git Diff");

      return {
        content: [{ type: "text", text: report }],
        details: {
          passed: res.passed,
          bloatScore: res.bloatScore,
          bloatFindingsCount: res.bloatFindings.length,
          safetyFindingsCount: res.safetyFindings.length,
        },
      };
    }

    if (action === "audit_code") {
      let codeText = args.code;
      let targetFile = args.path || "inline.ts";

      if (!codeText && args.path) {
        const fullPath = path.isAbsolute(args.path) ? args.path : path.join(repoRoot, args.path);
        if (!fs.existsSync(fullPath)) {
          return {
            content: [
              {
                type: "text",
                text: `❌ File not found: ${fullPath}`,
              },
            ],
            details: { notFound: fullPath },
          };
        }
        try {
          codeText = fs.readFileSync(fullPath, "utf-8");
          targetFile = args.path;
        } catch (err: any) {
          return {
            content: [
              {
                type: "text",
                text: `❌ Failed to read file ${fullPath}: ${err?.message || err}`,
              },
            ],
            details: { error: String(err) },
          };
        }
      }

      if (!codeText) {
        return {
          content: [
            {
              type: "text",
              text: `❌ No source code or valid file path provided for audit.`,
            },
          ],
          details: { missingInput: true },
        };
      }

      const res = auditCode(codeText, args.language, targetFile);
      const report = formatAuditReport(res, targetFile);

      return {
        content: [{ type: "text", text: report }],
        details: {
          passed: res.passed,
          bloatScore: res.bloatScore,
          bloatFindingsCount: res.bloatFindings.length,
          safetyFindingsCount: res.safetyFindings.length,
        },
      };
    }

    return {
      content: [{ type: "text", text: `Unknown action: ${action}. Use 'ladder', 'audit_code', or 'audit_diff'.` }],
    };
  };

  // --------------------------------------------------------------------------
  // Tool Registration: ponytail_audit
  // --------------------------------------------------------------------------
  pi.registerTool({
    name: "ponytail_audit",
    label: "Ponytail Anti-Overengineering Guard",
    description:
      "Audit source code, files, or git diffs against the Ponytail 7-step anti-overengineering logic ladder and safety guard.",
    parameters: Type.Object({
      action: Type.Union([
        Type.Literal("audit_code"),
        Type.Literal("audit_diff"),
        Type.Literal("ladder"),
      ]),
      code: Type.Optional(Type.String({ description: "Source code text to audit" })),
      language: Type.Optional(Type.String({ description: "Language (go, typescript, python, rust, shell, etc.)" })),
      diff: Type.Optional(Type.String({ description: "Unified git diff text to audit" })),
      path: Type.Optional(Type.String({ description: "Relative or absolute file path to audit" })),
    }),
    handler: async (args: any, ctx: any) => {
      return executeAudit(args, ctx);
    },
    execute: async (_toolCallId: string, params: any, _signal: any, _onUpdate: any, ctx: any) => {
      return executeAudit(params, ctx);
    },
  });

  // --------------------------------------------------------------------------
  // Slash Command: /ponytail
  // --------------------------------------------------------------------------
  pi.registerCommand("ponytail", {
    description: "Ponytail anti-overengineering audit (/ponytail [ladder | check <path> | diff])",
    handler: async (args, ctx) => {
      const parts = (args || "").trim().split(/\s+/);
      const subCommand = parts[0]?.toLowerCase() || "ladder";

      if (subCommand === "ladder") {
        const res = await executeAudit({ action: "ladder" }, ctx);
        const text = res.content?.[0]?.text || "No ladder data";
        if (ctx?.ui?.notify) ctx.ui.notify(text, "info");
        return;
      }

      if (subCommand === "check") {
        const filePath = parts[1];
        if (!filePath) {
          if (ctx?.ui?.notify) ctx.ui.notify("Usage: /ponytail check <filepath>", "warning");
          return;
        }

        const res = await executeAudit({ action: "audit_code", path: filePath }, ctx);
        const text = res.content?.[0]?.text || "No output";
        if (ctx?.ui?.notify) ctx.ui.notify(text, "info");
        return;
      }

      if (subCommand === "diff") {
        const res = await executeAudit({ action: "audit_diff" }, ctx);
        const text = res.content?.[0]?.text || "No diff";
        if (ctx?.ui?.notify) ctx.ui.notify(text, "info");
        return;
      }

      if (ctx?.ui?.notify) {
        ctx.ui.notify("Usage: /ponytail [ladder | check <path> | diff]", "warning");
      }
    },
  });
}
