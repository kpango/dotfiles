/**
 * Context & Token Economy Extension for Pi Coding Agent
 *
 * Monitors prompt-cache hit rates, input/output token counts, estimated API costs,
 * and renders real-time token economy metrics in the TUI statusline.
 */

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { evaluateOnlineCompaction, loadSolPiConfig, type CompactionAdvice, type SolPiConfig } from "./lib/sol-pi-core";

export interface SessionTokenStats {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  turnCount: number;
}

// Approximate cost calculation (Sonnet average baseline: ~$3/M in, $15/M out,
// $0.30/M cache read, ~$3.75/M cache write = 1.25x base input for cache
// creation). Cache-write (cacheCreationInputTokens) is the most expensive input
// class; omitting it systematically under-reports session cost even though the
// tokens are tracked and shown in the report. Exported as a pure function so the
// accounting is unit-testable.
/**
 * Cache hit rate as a percentage of all prompt-side input (fresh input + cache
 * reads + cache writes). Including cache writes keeps the metric consistent with
 * estimateSessionCost and avoids overstating the rate on cache-creating turns.
 */
export function cacheHitRatePercent(s: SessionTokenStats): number {
  const totalInput = s.inputTokens + s.cacheReadTokens + s.cacheWriteTokens;
  return totalInput > 0 ? (s.cacheReadTokens / totalInput) * 100 : 0;
}

export function estimateSessionCost(s: SessionTokenStats): number {
  return (
    (s.inputTokens / 1_000_000) * 3.0 +
    (s.outputTokens / 1_000_000) * 15.0 +
    (s.cacheReadTokens / 1_000_000) * 0.3 +
    (s.cacheWriteTokens / 1_000_000) * 3.75
  );
}

export interface TurnUsage {
  inputTokens?: number;
  promptTokens?: number;
  cacheReadInputTokens?: number;
  cacheReadTokens?: number;
  cacheCreationInputTokens?: number;
  cacheWriteTokens?: number;
}

/** Prompt-side size of one turn (same formula as sol-pi.ts turn_end). */
export function contextTokensFromUsage(u: TurnUsage | undefined): number {
  if (!u) return 0;
  return (
    (u.inputTokens || u.promptTokens || 0) +
    (u.cacheReadInputTokens || u.cacheReadTokens || 0) +
    (u.cacheCreationInputTokens || u.cacheWriteTokens || 0)
  );
}

/**
 * Next-step guidance for the current context pressure. Advisory text only: nothing
 * here compacts or switches models (grill D3). Thresholds/levels come from
 * sol-pi-core's evaluateOnlineCompaction (single source: agent/models/catalog.json compaction_threshold).
 * Returns "" at level "ok".
 */
export function nextStepGuidance(advice: CompactionAdvice, cacheWriteReadRatio: number): string {
  const pct = Math.round((advice.inputTokens / advice.cliff) * 100);
  if (advice.level === "exceeded") {
    return `Pricing Cliff 超過 (${pct}%): 次の一手 → /compact を手動実行。cache write は read の ${cacheWriteReadRatio}x なので、このまま続行すると毎ターン割高。別モデルへ移る場合も cache が cold になり全文脈が cache write で再課金される (自動実行はしません)`;
  }
  if (advice.level === "warn") {
    return `Cliff 接近 (${pct}%): 次の subtask 境界で /compact を計画 (cache write は read の ${cacheWriteReadRatio}x。自動実行はしません)`;
  }
  return "";
}

export default function (pi: ExtensionAPI, deps: { loadConfig?: () => SolPiConfig } = {}) {
  const config: SolPiConfig = (deps.loadConfig ?? loadSolPiConfig)();
  // Latest context pressure. Surfaced ONLY via the persistent statusline badge and
  // /economy (no notify): the one-shot transition toast is owned by sol-pi.ts turn_end,
  // so this extension never produces a second notification for the same crossing.
  let advice: CompactionAdvice | undefined;
  const stats: SessionTokenStats = {
    inputTokens: 0,
    outputTokens: 0,
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
    turnCount: 0,
  };

  const computeEstimatedCost = estimateSessionCost;

  const updateStatusWidget = (ctx: any) => {
    const cacheHitRate = Math.round(cacheHitRatePercent(stats));
    const totalTokens = stats.inputTokens + stats.outputTokens + stats.cacheReadTokens;
    const cost = computeEstimatedCost(stats);

    const formattedTokens = totalTokens > 1000 ? `${(totalTokens / 1000).toFixed(1)}k` : `${totalTokens}`;
    const costStr = `$${cost.toFixed(3)}`;

    const cacheBadge = cacheHitRate > 0 ? ctx.ui.theme.fg("success", `⚡ ${cacheHitRate}% cache`) : ctx.ui.theme.fg("muted", "⚡ 0% cache");
    const tokenBadge = ctx.ui.theme.fg("accent", `${formattedTokens} tok`);
    const costBadge = ctx.ui.theme.fg("dim", `(${costStr})`);

    let pressure = "";
    if (advice && advice.level !== "ok") {
      const pct = Math.round((advice.inputTokens / advice.cliff) * 100);
      pressure = ` | ${ctx.ui.theme.fg("warning", advice.level === "exceeded" ? `🔴 cliff ${pct}%` : `⚠ ${pct}% of cliff`)}`;
    }
    ctx.ui.setStatus("economy", `${cacheBadge} | ${tokenBadge} ${costBadge}${pressure}`);
  };

  pi.on("turn_end", async (event, ctx) => {
    stats.turnCount++;
    const usage = (event.message as any)?.usage;
    if (usage) {
      stats.inputTokens += usage.inputTokens || usage.promptTokens || 0;
      stats.outputTokens += usage.outputTokens || usage.completionTokens || 0;
      stats.cacheReadTokens += usage.cacheReadInputTokens || usage.cacheReadTokens || 0;
      stats.cacheWriteTokens += usage.cacheCreationInputTokens || usage.cacheWriteTokens || 0;
      if (config.pricingCliffAdvisoryConfig.enabled) {
        const modelId = String((event.message as any)?.model ?? ctx.model?.id ?? "");
        advice = evaluateOnlineCompaction(contextTokensFromUsage(usage), modelId, config.cacheWriteReadRatio, config);
      }
    }
    updateStatusWidget(ctx);
  });

  const renderEconomyReport = (): string => {
    const hitRate = cacheHitRatePercent(stats).toFixed(1);
    const total = stats.inputTokens + stats.outputTokens + stats.cacheReadTokens;

    const cost = computeEstimatedCost(stats);
    const g = advice ? nextStepGuidance(advice, config.cacheWriteReadRatio) : "";
    const guidance = advice
      ? `\n• Context: ${advice.inputTokens.toLocaleString()}/${advice.cliff.toLocaleString()} tokens${g ? `\n• ${g}` : ""}`
      : "";

    return `Session Token Economics:
• Total Turns: ${stats.turnCount}
• Total Tokens: ${total.toLocaleString()}
• Direct Input Tokens: ${stats.inputTokens.toLocaleString()}
• Cached Read Tokens: ${stats.cacheReadTokens.toLocaleString()} (${hitRate}% hit rate)
• Cache Written Tokens: ${stats.cacheWriteTokens.toLocaleString()}
• Output Tokens: ${stats.outputTokens.toLocaleString()}
• Estimated Cost: $${cost.toFixed(4)}${guidance}`;
  };

  pi.registerCommand("economy", {
    description: "Display session token economics, cache hit rates, and estimated cost",
    handler: async (_args, ctx) => {
      ctx.ui.notify(renderEconomyReport(), "info");
    },
  });

  pi.registerCommand("tokens", {
    description: "Alias for /economy",
    handler: async (_args, ctx) => {
      // Render the report directly instead of round-tripping through
      // sendUserMessage (which would re-enter the model loop, costing a
      // full turn for a deterministic command).
      ctx.ui.notify(renderEconomyReport(), "info");
    },
  });
}
