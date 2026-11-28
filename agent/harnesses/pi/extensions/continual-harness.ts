/**
 * Continual Harness Refinement Extension for Pi
 *
 * Monitors session failures and hook rejections to autonomously propose
 * and apply refinements to model routing, thinking budgets, and retry parameters.
 */

import { execFileSync } from "node:child_process";
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
  computeSessionFriction,
  defaultRefinementLedgerPath,
  evaluateRegressionStep,
  loadRefinementLedger,
  rollbackRefinementFromBackup,
  saveRefinementLedger,
  evaluateTargetBudget,
  readHarnessTextFile,
  validateHarnessTarget,
  type AppliedRefinementRecord,
  type FailureSignature,
  type RefinementProposal,
} from "./lib/continual-harness-core";
import { resolveCatalogPath } from "./lib/model-catalog";

export default function (pi: ExtensionAPI) {
  const getSessionsDir = (_ctx?: any): string => {
    return path.join(os.homedir(), ".pi", "agent", "sessions");
  };

  const evaluateAppliedRegressions = (sessionsDir: string, ledgerPath = defaultRefinementLedgerPath()): string[] => {
    const records = loadRefinementLedger(ledgerPath);
    const active = records.filter((r) => !r.rolledBackAt);
    if (active.length === 0) return [];

    const currentFriction = computeSessionFriction(scanSessionErrors(sessionsDir, 7));
    const notices: string[] = [];
    const updated: AppliedRefinementRecord[] = records.map((r) => {
      if (r.rolledBackAt) return r;
      const step = evaluateRegressionStep(r, currentFriction, 2);
      if (step.shouldRollback && step.next.backupPath) {
        const rb = rollbackRefinementFromBackup(step.next);
        if (rb.success) {
          notices.push(`Auto-rolled back refinement '${r.id}' (${path.basename(r.modifiedPath)}) after 2 consecutive regressions.`);
          return { ...step.next, rolledBackAt: Date.now() };
        }
        notices.push(`Rollback failed for '${r.id}': ${rb.error}`);
      }
      return step.next;
    });
    saveRefinementLedger(updated, ledgerPath);
    return notices;
  };

  pi.on("session_start", async (_event, ctx) => {
    if (process.env.PI_SUBAGENT === "1") return;
    try {
      const notices = evaluateAppliedRegressions(getSessionsDir(ctx));
      if (notices.length > 0) {
        ctx?.ui?.notify?.(`[continual-harness] ${notices.join(" | ")}`, "warning");
      }
    } catch {
      // Never block session startup on ledger check failures.
    }
  });

  const getRepoRoot = (ctx?: any): string => {
    return ctx?.cwd || process.cwd();
  };

  const loadCurrentConfigs = (repoRoot: string) => {
    const routingPath = path.join(repoRoot, "agent", "harnesses", "pi", "model-routing.json");
    const settingsJsonPath = path.join(repoRoot, "agent", "harnesses", "pi", "settings.json");
    const solPiPath = path.join(repoRoot, "agent", "harnesses", "pi", "sol-pi.json");

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
      if (fs.existsSync(settingsJsonPath)) {
        settings.settingsJsonPath = settingsJsonPath;
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
        // apply / sync は agent/models/catalog.json と各 model-routing.json(いずれも Tier B)を書き、fetch 版は外部データを元にする。
        // モデルが呼べるツールが人間の確認なしに書くと承認境界を迂回するため、dry-run / check 以外は確認必須(UI が無ければ拒否)。
        if (subAction !== "dry-run" && subAction !== "check") {
          const ok = typeof ctx?.ui?.confirm === "function"
            ? (await ctx.ui.confirm("Update the model catalog?", `models-update ${subAction} rewrites agent/models/catalog.json and the model-routing.json files`)) === true
            : false;
          if (!ok) {
            return { content: [{ type: "text", text: `models-update ${subAction} cancelled: user confirmation is required (no UI, or declined). Nothing was modified.` }] };
          }
        }
        const out = runModelCatalogUpdate(repoRoot, subAction);
        return { content: [{ type: "text", text: out || "Catalog check complete." }] };
      } catch (e: any) {
        return { content: [{ type: "text", text: `Model catalog update failed: ${e.message}` }] };
      }
    }

    if (mode === "net-budget") {
      // Harness² Net Token Budget (delta <= 0 for always-loaded C1/C2/C4/C6). Files are read only from inside the
      // repo, as bounded regular UTF-8 files (see readHarnessTextFile); a missing beforeFile argument means a new file.
      try {
        if (typeof args.afterFile !== "string") throw new Error("net-budget needs target and afterFile (beforeFile is optional for a new file)");
        const target = validateHarnessTarget(args.target);
        const before = typeof args.beforeFile === "string" ? readHarnessTextFile(repoRoot, args.beforeFile) : "";
        const v = evaluateTargetBudget(target, before, readHarnessTextFile(repoRoot, args.afterFile));
        const verdict = v.accepted ? "OK" : `REJECTED (${v.reason})`;
        return {
          content: [
            {
              type: "text",
              text: `Net Token Budget ${verdict}: ${target} component=${v.component ?? "unclassified"} enforced=${v.enforced} tokens ${v.before} -> ${v.after} (delta ${v.delta})`,
            },
          ],
        };
      } catch (e: any) {
        return { content: [{ type: "text", text: `Net Token Budget check failed: ${e.message}` }] };
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

      // 適用先(sol-pi.json / model-routing.json)は Tier B で、提案はセッションログ(fetch 結果等の外部テキストを含みうる)から
      // 作られる。モデルが呼べるツールが人間の確認なしに書くと Tier B の承認境界を迂回するため、確認必須(UI が無ければ拒否)。
      const targets = [...new Set(proposals.map((p) => p.targetFile))].join(", ");
      const confirmed = typeof ctx?.ui?.confirm === "function"
        ? (await ctx.ui.confirm("Apply harness refinements?", `${proposals.length} proposal(s) will modify: ${targets}`)) === true
        : false;
      if (!confirmed) {
        return {
          content: [{ type: "text", text: "Apply cancelled: user confirmation is required (no UI, or declined). Nothing was modified." }],
        };
      }

      const results: string[] = [];
      const baselineFriction = computeSessionFriction(signatures);
      const ledgerPath = defaultRefinementLedgerPath();
      const ledger = loadRefinementLedger(ledgerPath);
      for (const prop of proposals) {
        const res = applyProposal(repoRoot, prop);
        if (res.success) {
          if (res.backupPath) {
            ledger.push({
              id: prop.id,
              appliedAt: Date.now(),
              modifiedPath: res.modifiedPath,
              backupPath: res.backupPath,
              baselineFriction,
              consecutiveRegressions: 0,
            });
          }
          results.push(`✅ Applied ${prop.id} to ${res.modifiedPath} (backup: ${res.backupPath})`);
        } else {
          results.push(`❌ Failed to apply ${prop.id}: ${res.error}`);
        }
      }
      saveRefinementLedger(ledger.slice(-50), ledgerPath);

      return {
        content: [{ type: "text", text: results.join("\n") }],
      };
    }

    if (mode === "check-regressions") {
      const notices = evaluateAppliedRegressions(sessionsDir);
      return {
        content: [
          {
            type: "text",
            text: notices.length > 0 ? notices.join("\n") : "No consecutive regressions triggered across applied refinements.",
          },
        ],
      };
    }

    return {
      content: [{ type: "text", text: `Unknown mode: ${mode}. Use 'scan', 'dry-run', 'apply', 'check-regressions', 'models-update', or 'net-budget'.` }],
    };
  };

  pi.registerTool({
    name: "harness_refine",
    exposure: "deferred",
    label: "Harness Continual Refinement",
    description:
      "Scan session logs, formulate candidate tuning proposals for model routing and settings, and apply validated refinements.",
    parameters: Type.Object({
      mode: Type.Optional(
        Type.Union([
          Type.Literal("scan"),
          Type.Literal("dry-run"),
          Type.Literal("apply"),
          Type.Literal("check-regressions"),
          Type.Literal("models-update"),
          Type.Literal("net-budget"),
        ])
      ),
      target: Type.Optional(Type.String({ description: "net-budget: repo-relative target path (selects the Harness² component)" })),
      beforeFile: Type.Optional(Type.String({ description: "net-budget: file inside the repo holding the current text (omit for a new file)" })),
      afterFile: Type.Optional(Type.String({ description: "net-budget: file inside the repo holding the proposed text" })),
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
    description: "Continual harness refinement (/refine [scan | dry-run | apply | check-regressions | models-update])",
    handler: async (args, ctx) => {
      const parts = (args || "").trim().split(/\s+/);
      const mode = parts[0]?.toLowerCase() || "scan";

      if (!["scan", "dry-run", "apply", "check-regressions", "models-update"].includes(mode)) {
        ctx.ui.notify("Usage: /refine [scan | dry-run | apply | check-regressions | models-update]", "warning");
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
