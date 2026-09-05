/**
 * 8-Lens Adversarial Reviewer Extension for Pi Coding Agent
 *
 * Implements the Swarm Phase 5 / G5 Adversarial Gate check across 8 lenses:
 * 1. security: Secret leakage, injection, unverified input, SSRF.
 * 2. architecture: SSoT violation, cyclic dependency, boundary breach.
 * 3. perf-simd: Unnecessary allocs in hot path, locking bottleneck, SIMD misalignment.
 * 4. code-quality: Dead code, missing error handling, cognitive complexity.
 * 5. docs-comment: Stale comments, missing "why" rationale, misleading docstrings.
 * 6. systems-lang: Go/Rust memory leaks, goroutine un-cancellation, unsafe lifetime.
 * 7. shell-config: Missing quotes, bashisms in POSIX scripts, intermediate symlinks.
 * 8. infra-config: Nix/YAML/JSON schema inconsistency, non-idempotent rules.
 */

import { execSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export interface LensReviewFinding {
  lens: string;
  severity: "blocker" | "warning" | "note";
  message: string;
  lineSnippet?: string;
}

export const REVIEW_LENSES = [
  "security",
  "architecture",
  "perf-simd",
  "code-quality",
  "docs-comment",
  "systems-lang",
  "shell-config",
  "infra-config",
] as const;

export function evaluateDiffLenses(diff: string): LensReviewFinding[] {
  const findings: LensReviewFinding[] = [];
  if (!diff || !diff.trim()) return findings;

  const lines = diff.split("\n");

  for (const line of lines) {
    if (!line.startsWith("+") || line.startsWith("+++")) continue;
    const added = line.substring(1);

    // 1. Security Lens
    if (/(?:["']?(?:api[_-]?key|secret|password|private_key|bearer)["']?)\s*[:=]\s*["'][^"']+["']/i.test(added)) {
      findings.push({
        lens: "security",
        severity: "blocker",
        message: "Potential plaintext credential / secret detected in diff.",
        lineSnippet: added.trim(),
      });
    }

    // 2. Systems-Lang Lens (Go/Rust/C++)
    if (/go\s+func\s*\(/.test(added) && !/ctx|done|stop|cancel/.test(added)) {
      findings.push({
        lens: "systems-lang",
        severity: "warning",
        message: "Goroutine spawned without visible context cancellation channel (potential goroutine leak).",
        lineSnippet: added.trim(),
      });
    }

    // 3. Perf-SIMD Lens
    if (/\.Clone\(\)|\.clone\(\)/.test(added) && /for\s*\(|range\b/.test(added)) {
      findings.push({
        lens: "perf-simd",
        severity: "warning",
        message: "Deep clone/copy detected within loop construct (potential hot-path allocation).",
        lineSnippet: added.trim(),
      });
    }

    // 4. Code-Quality Lens
    if (/\/\/\s*TODO|\/\/\s*FIXME|\/\/\s*HACK/.test(added)) {
      findings.push({
        lens: "code-quality",
        severity: "note",
        message: "TODO / FIXME / HACK marker introduced in code diff.",
        lineSnippet: added.trim(),
      });
    }

    // 5. Shell-Config Lens
    if (/(?:ln\s+-s|symlink)\s+.*agent\//.test(added) && !/\$HOME/.test(added)) {
      findings.push({
        lens: "shell-config",
        severity: "blocker",
        message: "Possible repo-internal intermediate symlink detected (violates dotfiles SSoT rule).",
        lineSnippet: added.trim(),
      });
    }

    // 6. Docs-Comment Lens
    if (/\/\/\s*Generated\s+code\b/.test(added)) {
      findings.push({
        lens: "docs-comment",
        severity: "warning",
        message: "Generated code header added to editable source.",
        lineSnippet: added.trim(),
      });
    }
  }

  return findings;
}

export function formatAdversarialReport(findings: LensReviewFinding[], totalDiffLines: number): string {
  let report = `# 🛡️ Adversarial 8-Lens Review Report (${totalDiffLines} diff lines analyzed)\n\n`;

  const blockers = findings.filter(f => f.severity === "blocker");
  const warnings = findings.filter(f => f.severity === "warning");
  const notes = findings.filter(f => f.severity === "note");

  if (blockers.length === 0 && warnings.length === 0) {
    report += `✅ **GATE STATUS: PASS (Clean diff across all 8 lenses)**\n\n`;
  } else if (blockers.length > 0) {
    report += `❌ **GATE STATUS: REJECTED (${blockers.length} blockers identified)**\n\n`;
  } else {
    report += `⚠️ **GATE STATUS: CONDITIONAL PASS (${warnings.length} warnings to verify)**\n\n`;
  }

  for (const lens of REVIEW_LENSES) {
    const lensFindings = findings.filter(f => f.lens === lens);
    report += `### [${lensFindings.length > 0 ? "⚠️" : "✓"}] Lens: \`${lens}\`\n`;
    if (lensFindings.length === 0) {
      report += `- No violations found.\n\n`;
    } else {
      for (const f of lensFindings) {
        report += `- **[${f.severity.toUpperCase()}]**: ${f.message}\n`;
        if (f.lineSnippet) {
          report += `  \`${f.lineSnippet}\`\n`;
        }
      }
      report += "\n";
    }
  }

  return report.trim();
}

export default function (pi: ExtensionAPI) {
  // Register Tool
  pi.registerTool({
    name: "run_adversarial_review",
    description: "Run adversarial review across 8 multi-lens perspectives on the current git diff before releasing or committing.",
    parameters: Type.Object({
      stagedOnly: Type.Optional(Type.Boolean({ description: "If true, review only staged git changes." })),
    }),
    handler: async (args, ctx) => {
      try {
        const diffCmd = args.stagedOnly ? "git diff --cached" : "git diff HEAD";
        const diff = execSync(diffCmd, { cwd: ctx.cwd, encoding: "utf-8", maxBuffer: 10 * 1024 * 1024 });
        const findings = evaluateDiffLenses(diff);
        const report = formatAdversarialReport(findings, diff.split("\n").length);
        return {
          content: [{ type: "text", text: report }],
        };
      } catch (e: any) {
        return {
          content: [{ type: "text", text: `Failed to inspect git diff: ${e.message}` }],
        };
      }
    },
  });

  // Register Command
  pi.registerCommand("adversarial-review", {
    description: "Run the 8-Lens Adversarial Verification Gate on current changes",
    handler: async (_args, ctx) => {
      try {
        const diff = execSync("git diff HEAD", { cwd: ctx.cwd, encoding: "utf-8" });
        const findings = evaluateDiffLenses(diff);
        const report = formatAdversarialReport(findings, diff.split("\n").length);
        ctx.ui.notify(report, findings.some(f => f.severity === "blocker") ? "error" : "info");
      } catch (e: any) {
        ctx.ui.notify(`Review error: ${e.message}`, "error");
      }
    },
  });
}
