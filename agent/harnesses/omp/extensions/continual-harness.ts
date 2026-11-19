/**
 * Continual Harness Refinement Extension for Oh My Pi (OMP)
 *
 * Monitors session failures and hook rejections to autonomously propose
 * and apply refinements to model routing, thinking budgets, and retry parameters.
 */

import { execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { Type } from "typebox";
import {
  scanSessionErrors,
  generateRefinements,
  validateProposalSyntax,
  applyProposal,
  type FailureSignature,
  type RefinementProposal,
} from "./lib/continual-harness-core";
import { resolveCatalogPath } from "./lib/model-catalog";

export default function (pi: ExtensionAPI) {
  const getSessionsDir = (_ctx?: any): string => {
    return path.join(os.homedir(), ".omp", "agent", "sessions");
  };

  const getRepoRoot = (ctx?: any): string => {
    return ctx?.cwd || process.cwd();
  };

  const loadCurrentConfigs = (repoRoot: string) => {
    const routingPath = path.join(repoRoot, "agent", "harnesses", "omp", "model-routing.json");
    const configYmlPath = path.join(repoRoot, "agent", "harnesses", "omp", "config.yml");
    const solPiPath = path.join(repoRoot, "agent", "harnesses", "omp", "sol-pi.json");

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
      if (fs.existsSync(solPiPath)) {
        settings = JSON.parse(fs.readFileSync(solPiPath, "utf-8"));
      }
      if (fs.existsSync(configYmlPath)) {
        settings.configYmlPath = configYmlPath;
      }
    } catch {
      // ignore
    }

    return { routing, settings };
  };

  const runModelCatalogUpdate = (repoRoot: string, action = "dry-run"): string => {
    const catalogPath = resolveCatalogPath(repoRoot);
    const baseRoot = catalogPath ? path.resolve(path.dirname(catalogPath), "..", "..") : repoRoot;
    const scriptPath = path.join(baseRoot, "agent", "scripts", "update-model-catalog.py");
    if (!fs.existsSync(scriptPath)) {
      return `Model catalog updater not found at ${scriptPath}`;
    }
    const argMap: Record<string, string[]> = {
      check: ["--check"],
      sync: ["--sync-only"],
      "dry-run": ["--fetch", "--optimize", "--dry-run", "--report"],
      apply: ["--fetch", "--optimize", "--report"],
    };
    const cliArgs = argMap[action] || ["--fetch", "--optimize", "--dry-run", "--report"];
    return execFileSync("python3", [scriptPath, ...cliArgs], {
      cwd: baseRoot,
      encoding: "utf-8",
      timeout: 30000,
    }).trim();
  };

  // --------------------------------------------------------------------------
  // Tool: harness_refine
  // --------------------------------------------------------------------------
  const executeRefine = async (args: any, ctx: any) => {
    const mode = (args.mode || "scan").toLowerCase();
    const daysWindow = args.daysWindow || 7;
    const sessionsDir = getSessionsDir(ctx);
    const repoRoot = getRepoRoot(ctx);

    if (mode === "models-update") {
      try {
        const subAction = args.apply ? "apply" : (args.catalogAction || "dry-run");
        const out = runModelCatalogUpdate(repoRoot, subAction);
        return { content: [{ type: "text", text: out || "Catalog check complete." }] };
      } catch (e: any) {
        return { content: [{ type: "text", text: `Model catalog update failed: ${e.message}` }] };
      }
    }

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
      content: [{ type: "text", text: `Unknown mode: ${mode}. Use 'scan', 'dry-run', 'apply', or 'models-update'.` }],
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
          Type.Literal("models-update"),
        ])
      ),
      apply: Type.Optional(
        Type.Boolean({
          description: "When mode is 'models-update', apply catalog updates instead of dry-run",
        })
      ),
      catalogAction: Type.Optional(
        Type.Union([
          Type.Literal("check"),
          Type.Literal("dry-run"),
          Type.Literal("apply"),
          Type.Literal("sync"),
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
    description: "Continual harness refinement (/refine [scan | dry-run | apply | models-update])",
    handler: async (args, ctx) => {
      const parts = (args || "").trim().split(/\s+/);
      const mode = parts[0]?.toLowerCase() || "scan";

      if (!["scan", "dry-run", "apply", "models-update"].includes(mode)) {
        ctx.ui.notify("Usage: /refine [scan | dry-run | apply | models-update]", "warning");
        return;
      }

      const res = await executeRefine({ mode }, ctx);
      const text = res.content?.[0]?.text || "No output";
      ctx.ui.notify(text, "info");
    },
  });

  // --------------------------------------------------------------------------
  // Slash Command: /models-update
  // --------------------------------------------------------------------------
  pi.registerCommand("models-update", {
    description: "Update & Pareto-optimize SSoT model catalog (/models-update [check | dry-run | apply | sync])",
    handler: async (args, ctx) => {
      const parts = (args || "").trim().split(/\s+/);
      const action = parts[0]?.toLowerCase() || "dry-run";
      if (!["check", "dry-run", "apply", "sync"].includes(action)) {
        ctx.ui.notify("Usage: /models-update [check | dry-run | apply | sync]", "warning");
        return;
      }
      const res = await executeRefine({ mode: "models-update", catalogAction: action }, ctx);
      const text = res.content?.[0]?.text || "No output";
      ctx.ui.notify(text, "info");
    },
  });
}
