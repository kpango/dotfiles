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
import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import {
  handleIntervalLoopCommand,
  handleUntilLoopCommand,
  stopGoalLoops,
  stopIntervalLoops,
} from "./loop-controller";

/**
 * Compute the Phase-5 gate verdict + status header. The gate is BLOCKED only by
 * blocker findings or a failed consensus, but the header must not overclaim
 * "All 8 Lenses Clean" when advisory WARNING findings are present (they are
 * shown in the adversarial report body). Mirrors the note-aware header fix in
 * adversarial-reviewer.formatAdversarialReport.
 */
export function computeSwarmGateStatus(
  findings: Array<{ severity: string }>,
  consensusApproved: boolean
): { overallPass: boolean; header: string } {
  const blockers = findings.filter((f) => f.severity === "blocker").length;
  const warnings = findings.filter((f) => f.severity === "warning").length;
  const notes = findings.filter((f) => f.severity === "note").length;
  const overallPass = blockers === 0 && consensusApproved;
  let header: string;
  if (!overallPass) {
    header = "\uD83D\uDEAB **SWARM PHASE 5 GATE: REJECTED (Remediation Required)**";
  } else if (warnings > 0) {
    header = `\uD83C\uDFC1 **SWARM PHASE 5 GATE: APPROVED (${warnings} advisory warning${warnings === 1 ? "" : "s"} to verify, 3/3 Unanimous Consensus)**`;
  } else if (notes > 0) {
    // No blockers/warnings but advisory notes exist: still don't claim fully clean.
    header = `\uD83C\uDFC1 **SWARM PHASE 5 GATE: APPROVED (${notes} advisory note${notes === 1 ? "" : "s"}, 3/3 Unanimous Consensus)**`;
  } else {
    header = "\uD83C\uDFC1 **SWARM PHASE 5 GATE: APPROVED (All 8 Lenses Clean & 3/3 Unanimous Consensus)**";
  }
  return { overallPass, header };
}

export default function (pi: ExtensionAPI) {
  // Unified SWARM entry: every mode dispatches into the protocol skill that
  // owns the phase rules. The prompt templates (/swarm-meta, /swarm-loop,
  // /swarm-graph) were removed in favour of this single entry.
  const swarmModes: Record<string, { skill: string; start: string }> = {
    auto: { skill: "swarm-meta", start: "M0 PROFILE 抽出" },
    loop: { skill: "swarm-loop", start: "Phase -1 SCALE 判定" },
    graph: { skill: "swarm-graph", start: "Phase G-1（相0 Quick 判定）" },
    architect: { skill: "swarm-architect", start: "スポット診断の条件判定" },
    evolve: { skill: "swarm-evolve", start: "差分検出と提案" },
    gate: { skill: "swarm-release-gate", start: "verify.sh 全パス確認" },
    memory: { skill: "swarm-memory-sync", start: "GATE/PLAN 同期" },
    relay: { skill: "swarm-relay", start: "Phase 0/G0 調整" },
  };

  function dispatchMode(ctx: ExtensionCommandContext, mode: string, goal: string): void {
    const target = swarmModes[mode];
    const text = [
      `[SWARM ENTRY] mode=--${mode}`,
      "",
      "Read ~/.pi/agent/skills/swarm/SKILL.md and follow its §1 dispatch table.",
      `Then read ~/.pi/agent/skills/${target.skill}/SKILL.md and start at ${target.start}.`,
      "Do not skip phases or the GATE; escalate to the human where the protocol requires it.",
      "",
      "Goal:",
      goal,
    ].join("\n");
    // An explicit follow-up can stay queued in a fresh session with no turn to resume.
    void pi.sendUserMessage(text, ctx.isIdle() ? undefined : { deliverAs: "followUp" });
  }

  // Register Slash Command /swarm
  pi.registerCommand("swarm", {
    description:
      "SWARM unified entry: /swarm [--auto|--loop|--graph|--architect|--evolve|--gate|--memory|--relay <goal>] [--every <interval> <task>] [--until <condition> <task>] [--stop] [status|verify|gate|cleanup]",
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
          ctx.ui.notify("No active SWARM mission in current directory. Run `/swarm --loop <objective>` to start.", "info");
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
          const { loadEvidenceFromDisk, evaluateEvidenceGate, evidenceLedgerPathForRoot } = require("./lib/evidence-ledger");

          const findings = evaluateDiffLenses(diff);
          const advReport = formatAdversarialReport(findings, diff.split("\n").length);

          const votes = CONSENSUS_MODELS.map((m: any) => parseDiffHeuristicReview(diff, m.label));
          const consensus = evaluateConsensus(votes);

          let evidenceRoot = ctx.cwd;
          try {
            evidenceRoot = execSync("git rev-parse --show-toplevel", { cwd: ctx.cwd, encoding: "utf-8" }).trim() || ctx.cwd;
          } catch {
            // Fall back to ctx.cwd outside git repositories.
          }
          const ledgerPath = evidenceLedgerPathForRoot(evidenceRoot);
          const changedFiles = execSync("git diff --name-only HEAD", { cwd: ctx.cwd, encoding: "utf-8" })
            .split("\n")
            .map((s) => s.trim())
            .filter(Boolean);
          const evidenceState = loadEvidenceFromDisk(ledgerPath);
          const evidenceGate = evaluateEvidenceGate(evidenceState.records, changedFiles, ctx.cwd);
          const evidenceLine = evidenceState.records.length > 0
            ? `\n\n### Evidence Ledger\n- ${evidenceGate.ok ? "FRESH" : "STALE"}: ${evidenceGate.reason}`
            : "\n\n### Evidence Ledger\n- No recorded verification runs yet in this session.";

          const { overallPass, header: statusHeader } = computeSwarmGateStatus(findings, consensus.approved);

          ctx.ui.notify(`${statusHeader}\n\n${advReport}\n\n---\n\n${consensus.report}${evidenceLine}`, overallPass ? "info" : "error");
        } catch (e: any) {
          ctx.ui.notify(`SWARM Gate error: ${e.message}`, "error");
        }
      } else if (sub === "--stop") {
        stopIntervalLoops();
        const cancelled = stopGoalLoops();
        ctx.ui.notify(`Stopped interval loops and ${cancelled} goal loop(s).`, "info");
      } else if (sub.startsWith("--every") || sub === "--every") {
        const parsed = sub.match(/^--every\s+(\S+)\s+([\s\S]+)$/);
        if (!parsed) {
          ctx.ui.notify("Usage: /swarm --every <interval> <task>  (e.g. /swarm --every 30m make lint)", "warning");
        } else {
          await handleIntervalLoopCommand(pi, `${parsed[1]} ${parsed[2]}`, ctx);
        }
      } else if (sub.startsWith("--until") || sub === "--until") {
        const parsed = sub.match(/^--until\s+(\S+)\s+([\s\S]+)$/);
        if (!parsed) {
          ctx.ui.notify('Usage: /swarm --until <condition> <task>  (e.g. /swarm --until exit:0 make test)', "warning");
        } else {
          await handleUntilLoopCommand(pi, `${parsed[1]} ${parsed[2]}`, ctx);
        }
      } else if (sub.startsWith("--")) {
        const [token, ...rest] = sub.split(/\s+/);
        const mode = token.slice(2);
        const goal = rest.join(" ").trim();
        if (!swarmModes[mode]) {
          ctx.ui.notify(
            `Unknown SWARM mode "--${mode}". Available: ${Object.keys(swarmModes).map((m) => `--${m}`).join(", ")}, --every, --until, --stop`,
            "warning"
          );
        } else if (!goal) {
          ctx.ui.notify(`Usage: /swarm --${mode} <goal>`, "warning");
        } else {
          dispatchMode(ctx, mode, goal);
        }
      } else {
        dispatchMode(ctx, "auto", sub);
      }
    },
  });
}
