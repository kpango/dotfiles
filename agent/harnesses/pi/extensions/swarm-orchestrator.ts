/**
 * SWARM Orchestrator Extension for Pi Coding Agent
 *
 * Implements interactive SWARM status checking, worktree allocation,
 * budget tracking, and multi-agent coordination tools within Pi.
 */

import { execSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  // Register Slash Command /swarm
  pi.registerCommand("swarm", {
    description: "SWARM multi-agent loop status and management (/swarm [status|plan|cleanup])",
    handler: async (args, ctx) => {
      const sub = (args || "status").trim();

      if (sub === "status") {
        const home = os.homedir();
        const scriptPath = path.join(home, ".pi", "agent", "skills", "swarm-loop", "scripts", "loop-status.sh");
        if (fs.existsSync(scriptPath)) {
          try {
            const out = execSync(`bash "${scriptPath}"`, { cwd: ctx.cwd, encoding: "utf-8" });
            ctx.ui.notify(`SWARM Status:\n\n${out.trim()}`, "info");
            return;
          } catch (e: any) {
            ctx.ui.notify(`SWARM Status error: ${e.message}`, "warning");
            return;
          }
        }

        const planPath = path.join(ctx.cwd, "@fix_plan.md");
        if (fs.existsSync(planPath)) {
          const planContent = fs.readFileSync(planPath, "utf-8");
          const lines = planContent.split("\n").slice(0, 15).join("\n");
          ctx.ui.notify(`@fix_plan.md preview:\n\n${lines}...`, "info");
        } else {
          ctx.ui.notify("No active SWARM mission in current directory. Run `/swarm-loop <objective>` to start.", "info");
        }
      } else if (sub === "cleanup") {
        const home = os.homedir();
        const scriptPath = path.join(home, ".pi", "agent", "skills", "swarm-implement", "scripts", "mission-cleanup.sh");
        if (fs.existsSync(scriptPath)) {
          try {
            const out = execSync(`bash "${scriptPath}" --release-worktrees`, { cwd: ctx.cwd, encoding: "utf-8" });
            ctx.ui.notify(`SWARM Cleanup:\n${out}`, "info");
          } catch (e: any) {
            ctx.ui.notify(`SWARM Cleanup error: ${e.message}`, "warning");
          }
        } else {
          ctx.ui.notify("mission-cleanup.sh script not found.", "warning");
        }
      } else if (sub === "verify" || sub === "gate") {
        try {
          const diff = execSync("git diff HEAD", { cwd: ctx.cwd, encoding: "utf-8" });
          const { evaluateDiffLenses, formatAdversarialReport } = require("./adversarial-reviewer");
          const { evaluateConsensus, parseDiffHeuristicReview, CONSENSUS_MODELS } = require("./consensus-verifier");

          const findings = evaluateDiffLenses(diff);
          const advReport = formatAdversarialReport(findings, diff.split("\n").length);

          const votes = CONSENSUS_MODELS.map((m: any) => parseDiffHeuristicReview(diff, m.label));
          const consensus = evaluateConsensus(votes);

          const overallPass = !findings.some((f: any) => f.severity === "blocker") && consensus.approved;
          const statusHeader = overallPass
            ? "🏁 **SWARM PHASE 5 GATE: APPROVED (All 8 Lenses Clean & 3/3 Unanimous Consensus)**"
            : "🚫 **SWARM PHASE 5 GATE: REJECTED (Remediation Required)**";

          ctx.ui.notify(`${statusHeader}\n\n${advReport}\n\n---\n\n${consensus.report}`, overallPass ? "info" : "error");
        } catch (e: any) {
          ctx.ui.notify(`SWARM Gate error: ${e.message}`, "error");
        }
      } else {
        ctx.ui.notify("Usage: /swarm [status|verify|cleanup]", "warning");
      }
    },
  });
}
