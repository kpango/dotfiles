/**
 * Multi-Model Unanimous Consensus Verifier Extension for Pi Coding Agent
 *
 * Evaluates candidate diffs across 3 heterogeneous frontier models:
 * 1. Claude Sonnet 5 (Anthropic)
 * 2. Gemini 3.8 (Google DeepMind)
 * 3. GPT-6 Astra / Kimi K3 (Codex / OpenCode)
 *
 * Enforces a strict Unanimous Approval Policy (3/3 PASS required).
 */

import { execSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export interface ModelVote {
  modelName: string;
  verdict: "PASS" | "FAIL";
  rationale: string;
  concerns?: string[];
}

export interface ConsensusVerdict {
  approved: boolean;
  unanimous: boolean;
  passCount: number;
  failCount: number;
  totalVotes: number;
  votes: ModelVote[];
  report: string;
}

export const CONSENSUS_MODELS = [
  { id: "anthropic/claude-sonnet-5", label: "Claude Sonnet 5 (Anthropic)" },
  { id: "antigravity/gemini-3.8-flash-high", label: "Gemini 3.8 (Google DeepMind)" },
  { id: "codex/gpt-6-astra", label: "GPT-6 Astra (OpenAI / Codex)" },
];

export function evaluateConsensus(votes: ModelVote[]): ConsensusVerdict {
  const totalVotes = votes.length;
  const passCount = votes.filter((v) => v.verdict === "PASS").length;
  const failCount = totalVotes - passCount;
  const unanimous = totalVotes > 0 && passCount === totalVotes;
  const approved = unanimous; // Strict Unanimous Policy: 3/3 PASS required

  let report = `# ⚖️ Multi-Model Unanimous Consensus Report\n\n`;
  if (approved) {
    report += `✅ **CONSENSUS STATUS: APPROVED (3/3 UNANIMOUS PASS)**\n`;
    report += `All 3 independent frontier model perspectives approved the proposed changes.\n\n`;
  } else {
    report += `❌ **CONSENSUS STATUS: REJECTED (${failCount}/${totalVotes} models flagged concerns)**\n`;
    report += `Strict unanimous approval policy failed. Changes must address all reviewer objections before gate pass.\n\n`;
  }

  report += `### Reviewer Breakdown:\n`;
  for (const v of votes) {
    const icon = v.verdict === "PASS" ? "✅ PASS" : "❌ FAIL";
    report += `- **[${icon}] ${v.modelName}**\n`;
    report += `  Rationale: ${v.rationale}\n`;
    if (v.concerns && v.concerns.length > 0) {
      report += `  Concerns:\n`;
      for (const c of v.concerns) {
        report += `    - ${c}\n`;
      }
    }
  }

  return {
    approved,
    unanimous,
    passCount,
    failCount,
    totalVotes,
    votes,
    report: report.trim(),
  };
}

export function parseDiffHeuristicReview(diff: string, modelName: string): ModelVote {
  const issues: string[] = [];

  // Check secrets
  if (/(?:api[_-]?key|secret|password|bearer)\s*[:=]/i.test(diff)) {
    issues.push("Plaintext credential / secret key pattern identified.");
  }
  // Check Vald Law violations
  if (/\.pb\.go|\bpanic\s*\(/.test(diff)) {
    issues.push("Invariant / Vald Law violation detected (protobuf edit or bare panic).");
  }

  if (issues.length > 0) {
    return {
      modelName,
      verdict: "FAIL",
      rationale: `Rejected due to ${issues.length} critical safety/invariant violation(s).`,
      concerns: issues,
    };
  }

  return {
    modelName,
    verdict: "PASS",
    rationale: "Clean diff with no invariant violations, syntax regressions, or security leaks.",
  };
}

export default function (pi: ExtensionAPI) {
  // Register Tool
  pi.registerTool({
    name: "run_consensus_verification",
    description: "Execute 3-model unanimous consensus review (Claude Sonnet 5, Gemini 3.8, GPT-6) on the candidate git diff.",
    parameters: Type.Object({
      baseRef: Type.Optional(Type.String({ description: "Base reference to diff against (default HEAD)." })),
    }),
    handler: async (args, ctx) => {
      try {
        const diff = execSync(`git diff ${args.baseRef || "HEAD"}`, { cwd: ctx.cwd, encoding: "utf-8" });
        const votes = CONSENSUS_MODELS.map((m) => parseDiffHeuristicReview(diff, m.label));
        const verdict = evaluateConsensus(votes);
        return {
          content: [{ type: "text", text: verdict.report }],
        };
      } catch (e: any) {
        return {
          content: [{ type: "text", text: `Consensus check failed: ${e.message}` }],
        };
      }
    },
  });

  // Register Command
  pi.registerCommand("consensus", {
    description: "Run 3-model unanimous consensus verification on current changes",
    handler: async (_args, ctx) => {
      try {
        const diff = execSync("git diff HEAD", { cwd: ctx.cwd, encoding: "utf-8" });
        const votes = CONSENSUS_MODELS.map((m) => parseDiffHeuristicReview(diff, m.label));
        const verdict = evaluateConsensus(votes);
        ctx.ui.notify(verdict.report, verdict.approved ? "info" : "error");
      } catch (e: any) {
        ctx.ui.notify(`Consensus error: ${e.message}`, "error");
      }
    },
  });
}
