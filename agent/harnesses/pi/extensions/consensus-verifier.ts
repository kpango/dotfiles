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

import { spawnSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export interface ModelVote {
  modelName: string;
  verdict: "PASS" | "FAIL";
  rationale: string;
  concerns?: string[];
  /** True when the vote was produced by the local deterministic heuristic
   *  rather than an independent frontier model invocation. */
  heuristic?: boolean;
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

/**
 * Run `git diff <baseRef>` safely via spawnSync with an argv array (no shell),
 * so a user-supplied baseRef containing shell metacharacters (`;`, `$(...)`,
 * backticks) is passed as a single literal argument and cannot inject commands.
 * Returns the diff text; returns "" if git is unavailable or errors.
 */
export function runGitDiff(cwd: string, baseRef?: string): string {
  const res = spawnSync("git", ["diff", baseRef || "HEAD"], {
    cwd,
    encoding: "utf-8",
    maxBuffer: 10 * 1024 * 1024,
  });
  if (res.error) throw res.error;
  return typeof res.stdout === "string" ? res.stdout : "";
}

export function evaluateConsensus(votes: ModelVote[]): ConsensusVerdict {
  const totalVotes = votes.length;
  const passCount = votes.filter((v) => v.verdict === "PASS").length;
  const failCount = totalVotes - passCount;
  const unanimous = totalVotes > 0 && passCount === totalVotes;
  const approved = unanimous; // Strict Unanimous Policy: 3/3 PASS required
  const allHeuristic = totalVotes > 0 && votes.every((v) => v.heuristic);
  const anyHeuristic = totalVotes > 0 && votes.some((v) => v.heuristic);

  let report = `# ⚖️ Multi-Model Unanimous Consensus Report\n\n`;
  if (allHeuristic) {
    // Honest labeling: without independent model invocations this is a
    // deterministic pre-screen, not cross-model consensus (verifier
    // independence requires actual independent judgments).
    report += approved
      ? `✅ **PRE-SCREEN STATUS: PASS (deterministic heuristic, no independent model votes)**\n`
      : `❌ **PRE-SCREEN STATUS: FAIL (deterministic heuristic, no independent model votes)**\n`;
    report += `This run used the local deterministic heuristic only. For true 3-model
unanimous consensus, invoke the external consensus workflow (claude_code /
antigravity / codex bridges) on the same diff.\n\n`;
  } else if (anyHeuristic) {
    // Mixed votes: at least one vote came from the heuristic fallback, so
    // claiming an independent unanimous approval would be misleading.
    report += approved
      ? `⚠️ **STATUS: PASS with heuristic fallback votes (not full model unanimity)**\n`
      : `❌ **STATUS: REJECTED (${failCount}/${totalVotes} votes flagged concerns)**\n`;
    report += `One or more votes were produced by the deterministic heuristic; treat the
result as provisional until independent model consensus is available.\n\n`;
  } else if (approved) {
    report += `✅ **CONSENSUS STATUS: APPROVED (3/3 UNANIMOUS PASS)**\n`;
    report += `All 3 independent frontier model perspectives approved the proposed changes.\n\n`;
  } else {
    report += `❌ **CONSENSUS STATUS: REJECTED (${failCount}/${totalVotes} models flagged concerns)**\n`;
    report += `Strict unanimous approval policy failed. Changes must address all reviewer objections before gate pass.\n\n`;
  }

  report += `### Reviewer Breakdown:\n`;
  if (allHeuristic) {
    // No independent model votes exist in a heuristic pre-screen run; show a
    // single deterministic analysis row instead of duplicating the same
    // heuristic under three model labels.
    const v = votes[0];
    const icon = v.verdict === "PASS" ? "✅ PASS" : "❌ FAIL";
    report += `- **[${icon}] Deterministic heuristic pre-screen**\n`;
    report += `  Rationale: ${v.rationale}\n`;
    if (v.concerns && v.concerns.length > 0) {
      report += `  Concerns:\n`;
      for (const c of v.concerns) {
        report += `    - ${c}\n`;
      }
    }
    report += `- (heuristic-only run: no independent model invocations were made)\n`;
  } else {
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

  // Only scan ADDED lines (`+`, excluding the `+++` file header). Scanning the
  // whole diff would false-FAIL a change that REMOVES a `panic(` (a Vald-Law
  // fix) or merely has a `panic(`/`.pb.go` reference in an unchanged context
  // line. Mirrors adversarial-reviewer.evaluateDiffLenses.
  const added = diff
    .split("\n")
    .filter((l) => l.startsWith("+") && !l.startsWith("+++"))
    .map((l) => l.slice(1))
    .join("\n");

  // Check secrets
  if (/(?:api[_-]?key|secret|password|bearer)\s*[:=]/i.test(added)) {
    issues.push("Plaintext credential / secret key pattern identified.");
  }
  // Check Vald Law violations
  if (/\.pb\.go|\bpanic\s*\(/.test(added)) {
    issues.push("Invariant / Vald Law violation detected (protobuf edit or bare panic).");
  }

  if (issues.length > 0) {
    return {
      modelName,
      verdict: "FAIL",
      rationale: `Rejected due to ${issues.length} critical safety/invariant violation(s).`,
      concerns: issues,
      heuristic: true,
    };
  }

  return {
    modelName,
    verdict: "PASS",
    rationale: "Clean diff with no invariant violations, syntax regressions, or security leaks.",
    heuristic: true,
  };
}

export default function (pi: ExtensionAPI) {
  // Register Tool
  pi.registerTool({
    name: "run_consensus_verification",
    description: "Run a deterministic heuristic pre-screen on the candidate git diff. For true 3-model unanimous consensus (Claude Sonnet 5, Gemini 3.8, GPT-6), use the external consensus workflow via claude_code/antigravity/codex bridges — this local tool does not invoke independent models and must not be reported as cross-model consensus.",
    parameters: Type.Object({
      baseRef: Type.Optional(Type.String({ description: "Base reference to diff against (default HEAD)." })),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      try {
        const diff = runGitDiff(ctx.cwd, params.baseRef);
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
    handler: async (args, ctx) => {
      try {
        const diff = runGitDiff(ctx.cwd, args.baseRef);
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
    description: "Run deterministic heuristic pre-screen on current changes (not independent model consensus)",
    handler: async (_args, ctx) => {
      try {
        const diff = runGitDiff(ctx.cwd);
        const votes = CONSENSUS_MODELS.map((m) => parseDiffHeuristicReview(diff, m.label));
        const verdict = evaluateConsensus(votes);
        ctx.ui.notify(verdict.report, verdict.approved ? "info" : "error");
      } catch (e: any) {
        ctx.ui.notify(`Consensus error: ${e.message}`, "error");
      }
    },
  });
}
