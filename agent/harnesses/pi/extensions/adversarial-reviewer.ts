/**
 * Adversarial Review PRE-SCREEN Extension for Pi Coding Agent
 *
 * **重要（位置づけ）**: この `run_adversarial_review` ツール/`/adversarial-review` コマンドは、
 * git diff の追加行に対する軽量な**正規表現ヒューリスティック事前スクリーニング**である。
 * SWARM.md §2 / swarm-loop Phase 4.5・swarm-graph Phase G4.5 が要求する**本番の8-Agent敵対的
 * レビューの代替ではない** — 本番レビューは `agent/agents/*-adversarial-reviewer.md`(8体、
 * 実ファイルを Read/Grep して意味的に判断する)を pi の `subagent` ツールで個別起動して行う
 * (pre-screen 位置づけ decision 2026-09-07)。本事前スクリーンで CLEAN でも Phase 4.5 の
 * 8体 subagent 起動を省略してはならない。
 *
 * ヒューリスティックで判定する 6 レンズ(HEURISTIC_LENSES):
 *   security / perf-simd / code-quality / docs-comment / systems-lang / shell-config
 * ヒューリスティック未実装で subagent レビューのみが判定する 2 レンズ:
 *   architecture(SSoT violation/cyclic dependency/boundary breach)・
 *   infra-config(Nix/YAML/JSON schema inconsistency/non-idempotent rules)
 *   — これらは本事前スクリーンでは「未カバー」として明示し、CLEAN と誤認させない。
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

// ヒューリスティック(正規表現)で実際に判定するレンズ。architecture / infra-config は
// evaluateDiffLenses に判定分岐が無く(意図的、pre-screen 位置づけ decision 2026-09-07: 正規表現は
// 実装せず位置づけ明記で対応)、subagent レビューのみが判定する。formatAdversarialReport は
// この集合を使って「未カバー」レンズを CLEAN(✓)と誤表示しない。
export const HEURISTIC_LENSES: ReadonlySet<string> = new Set([
  "security",
  "perf-simd",
  "code-quality",
  "docs-comment",
  "systems-lang",
  "shell-config",
]);

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
  let report = `# 🛡️ Adversarial Review PRE-SCREEN — heuristic (${totalDiffLines} diff lines analyzed)\n\n`;
  // 位置づけバナー(pre-screen 位置づけ decision 2026-09-07): このレポートを Phase 4.5 の8-Agentレビュー完了と
  // 誤解させないため、先頭で必ず事前スクリーニングである旨を宣言する。
  report += `> ⚠️ **PRE-SCREEN ONLY** — これは正規表現ベースの軽量な事前スクリーニングであり、`;
  report += `swarm-loop Phase 4.5 / swarm-graph Phase G4.5 の**8-Agent 敵対的レビューの代替ではありません**。\n`;
  report += `> 本番は \`agent/agents/*-adversarial-reviewer.md\`(8体)を pi の \`subagent\` ツールで個別起動して実ファイルを意味的に検査すること。\n\n`;

  const blockers = findings.filter(f => f.severity === "blocker");
  const warnings = findings.filter(f => f.severity === "warning");
  const notes = findings.filter(f => f.severity === "note");

  if (blockers.length === 0 && warnings.length === 0) {
    // Notes are advisory (non-blocking) but still findings: do not claim a fully
    // "clean" diff when advisory notes are present, or the header contradicts the
    // note findings listed in the body below.
    report += notes.length === 0
      ? `✅ **PRE-SCREEN STATUS: PASS (no heuristic findings across ${HEURISTIC_LENSES.size} heuristic lenses; architecture/infra-config require subagent review)**\n\n`
      : `✅ **PRE-SCREEN STATUS: PASS (${notes.length} advisory note${notes.length === 1 ? "" : "s"}, no blockers/warnings; architecture/infra-config require subagent review)**\n\n`;
  } else if (blockers.length > 0) {
    report += `❌ **PRE-SCREEN STATUS: REJECTED (${blockers.length} blocker${blockers.length === 1 ? "" : "s"} in heuristic pre-screen; still requires Phase 4.5 8-agent review)**\n\n`;
  } else {
    report += `⚠️ **PRE-SCREEN STATUS: CONDITIONAL (${warnings.length} warning${warnings.length === 1 ? "" : "s"} to verify; still requires Phase 4.5 8-agent review)**\n\n`;
  }

  for (const lens of REVIEW_LENSES) {
    const lensFindings = findings.filter(f => f.lens === lens);
    // ヒューリスティック未実装のレンズ(architecture/infra-config)は「未カバー」と明示し、
    // 所見 0 件を CLEAN(✓)と誤表示しない(pre-screen 位置づけ decision 2026-09-07)。
    if (!HEURISTIC_LENSES.has(lens)) {
      report += `### [—] Lens: \`${lens}\` (not covered by heuristic pre-screen)\n`;
      report += `- Requires \`${lens}-adversarial-reviewer\` subagent (semantic file review) at Phase 4.5 / G4.5. Heuristic result is NOT authoritative for this lens.\n\n`;
      continue;
    }
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
    description: "Run a lightweight HEURISTIC PRE-SCREEN (regex-based, 6 heuristic lenses) on the current git diff. This is a PRE-SCREEN ONLY — NOT a substitute for the Phase 4.5/G4.5 8-agent adversarial review (which invokes the 8 *-adversarial-reviewer subagents via the subagent tool to read files semantically). A clean pre-screen does NOT let you skip the 8 subagent reviews.",
    parameters: Type.Object({
      stagedOnly: Type.Optional(Type.Boolean({ description: "If true, review only staged git changes." })),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      try {
        const diffCmd = params.stagedOnly ? "git diff --cached" : "git diff HEAD";
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
    description: "Run the heuristic adversarial PRE-SCREEN on current changes (NOT a substitute for the Phase 4.5 8-agent subagent review)",
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
