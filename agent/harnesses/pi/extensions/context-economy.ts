/**
 * Context & Token Economy Extension for Pi Coding Agent
 *
 * Monitors prompt-cache hit rates, input/output token counts, estimated API costs,
 * and renders real-time token economy metrics in the TUI statusline.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

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

export default function (pi: ExtensionAPI) {
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

    ctx.ui.setStatus("economy", `${cacheBadge} | ${tokenBadge} ${costBadge}`);
  };

  pi.on("turn_end", async (event, ctx) => {
    stats.turnCount++;
    const usage = (event.message as any)?.usage;
    if (usage) {
      stats.inputTokens += usage.inputTokens || usage.promptTokens || 0;
      stats.outputTokens += usage.outputTokens || usage.completionTokens || 0;
      stats.cacheReadTokens += usage.cacheReadInputTokens || usage.cacheReadTokens || 0;
      stats.cacheWriteTokens += usage.cacheCreationInputTokens || usage.cacheWriteTokens || 0;
    }
    updateStatusWidget(ctx);
  });

  const renderEconomyReport = (): string => {
    const hitRate = cacheHitRatePercent(stats).toFixed(1);
    const total = stats.inputTokens + stats.outputTokens + stats.cacheReadTokens;

    const cost = computeEstimatedCost(stats);

    return `Session Token Economics:
• Total Turns: ${stats.turnCount}
• Total Tokens: ${total.toLocaleString()}
• Direct Input Tokens: ${stats.inputTokens.toLocaleString()}
• Cached Read Tokens: ${stats.cacheReadTokens.toLocaleString()} (${hitRate}% hit rate)
• Cache Written Tokens: ${stats.cacheWriteTokens.toLocaleString()}
• Output Tokens: ${stats.outputTokens.toLocaleString()}
• Estimated Cost: $${cost.toFixed(4)}`;
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
