/**
 * Continual Harness Refinement Extension for Pi Coding Agent
 *
 * Monitors session failures and hook rejections to autonomously propose
 * and apply refinements to model routing, thinking budgets, and retry parameters.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
  scanSessionErrors,
  generateRefinements,
  validateProposalSyntax,
  applyProposal,
  type FailureSignature,
  type RefinementProposal,
} from "./lib/continual-harness-core";

export default function (pi: ExtensionAPI) {
  const getSessionsDir = (ctx?: any): string => {
    return path.join(os.homedir(), ".pi", "agent", "sessions");
  };

  const getRepoRoot = (ctx?: any): string => {
    return ctx?.cwd || process.cwd();
  };

  const loadCurrentConfigs = (repoRoot: string) => {
    const routingPath = path.join(repoRoot, "agent", "harnesses", "pi", "model-routing.json");
    const settingsPath = path.join(repoRoot, "agent", "harnesses", "pi", "settings.json");

    let routing: any = {};
    let settings: any = {};

    try {
      if (fs.existsSync(routingPath)) {
        routing = JSON.parse(fs.readFileSync(routingPath, "utf-8"));
      }
    } catch {
      // ignore
    }

    try {
      if (fs.existsSync(settingsPath)) {
        settings = JSON.parse(fs.readFileSync(settingsPath, "utf-8"));
      }
    } catch {
      // ignore
    }

    return { routing, settings };
  };

  // --------------------------------------------------------------------------
  // Tool: harness_refine
  // --------------------------------------------------------------------------
  const executeRefine = async (args: any, ctx: any) => {
    const mode = (args.mode || "scan").toLowerCase();
    const daysWindow = args.daysWindow || 7;
    const sessionsDir = getSessionsDir(ctx);
    const repoRoot = getRepoRoot(ctx);

    const signatures = scanSessionErrors(sessionsDir, daysWindow);

    if (mode === "scan") {
      if (signatures.length === 0) {
        return {
          content: [
            {
              type: "text",
              text: `No significant recurring failure signatures found in ${sessionsDir} (last ${daysWindow} days).`,
            },
          ],
        };
      }

      let report = `🔍 Found ${signatures.length} recurring failure signature(s) across recent sessions:\n\n`;
      for (const sig of signatures) {
        report += `• [${sig.category.toUpperCase()}] ${sig.signatureId} (${sig.occurrences}x)\n`;
        report += `  Sample: ${sig.sampleErrorMessage}\n`;
        report += `  Last seen: ${new Date(sig.lastSeen).toISOString()}\n\n`;
      }
      return { content: [{ type: "text", text: report.trim() }] };
    }

    const { routing, settings } = loadCurrentConfigs(repoRoot);
    const proposals = generateRefinements(signatures, routing, settings);

    if (mode === "dry-run") {
      if (proposals.length === 0) {
        return {
          content: [
            {
              type: "text",
              text: `Scanned ${signatures.length} signature(s). No harness adjustments required at this time.`,
            },
          ],
        };
      }

      let report = `📋 Proposed Harness Refinements (${proposals.length} proposal(s)):\n\n`;
      for (const prop of proposals) {
        report += `• Proposal: ${prop.id}\n`;
        report += `  Target File: ${prop.targetFile}\n`;
        report += `  Diff Type: ${prop.diffType} (confidence: ${(prop.confidence * 100).toFixed(0)}%)\n`;
        report += `  Rationale: ${prop.rationale}\n\n`;
      }
      report += `To apply these changes to the configuration, run '/refine apply' or call harness_refine with mode='apply'.`;
      return { content: [{ type: "text", text: report.trim() }] };
    }

    if (mode === "apply") {
      if (proposals.length === 0) {
        return {
          content: [
            {
              type: "text",
              text: "No candidate proposals to apply.",
            },
          ],
        };
      }

      const results: string[] = [];
      for (const prop of proposals) {
        const res = applyProposal(repoRoot, prop);
        if (res.success) {
          results.push(`✅ Applied ${prop.id} to ${res.modifiedPath} (backup: ${res.backupPath})`);
        } else {
          results.push(`❌ Failed to apply ${prop.id}: ${res.error}`);
        }
      }

      return {
        content: [{ type: "text", text: results.join("\n") }],
      };
    }

    return {
      content: [{ type: "text", text: `Unknown mode: ${mode}. Use 'scan', 'dry-run', or 'apply'.` }],
    };
  };

  pi.registerTool({
    name: "harness_refine",
    label: "Harness Continual Refinement",
    description:
      "Scan session logs, formulate candidate tuning proposals for model routing and settings, and apply validated refinements.",
    parameters: Type.Object({
      mode: Type.Optional(
        Type.Union([
          Type.Literal("scan"),
          Type.Literal("dry-run"),
          Type.Literal("apply"),
        ])
      ),
      daysWindow: Type.Optional(
        Type.Integer({
          description: "Number of past days to scan for failure logs (default 7)",
        })
      ),
    }),
    handler: async (args: any, ctx: any) => {
      return executeRefine(args, ctx);
    },
    execute: async (_toolCallId: string, params: any, _signal: any, _onUpdate: any, ctx: any) => {
      return executeRefine(params, ctx);
    },
  });

  // --------------------------------------------------------------------------
  // Slash Command: /refine
  // --------------------------------------------------------------------------
  pi.registerCommand("refine", {
    description: "Continual harness refinement (/refine [scan | dry-run | apply])",
    handler: async (args, ctx) => {
      const parts = (args || "").trim().split(/\s+/);
      const mode = parts[0]?.toLowerCase() || "scan";

      if (!["scan", "dry-run", "apply"].includes(mode)) {
        ctx.ui.notify("Usage: /refine [scan | dry-run | apply]", "warning");
        return;
      }

      const res = await executeRefine({ mode }, ctx);
      const text = res.content?.[0]?.text || "No output";
      ctx.ui.notify(text, "info");
    },
  });
}
