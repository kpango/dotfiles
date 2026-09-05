/**
 * Context & Token Economy Extension for Pi Coding Agent
 *
 * Monitors prompt-cache hit rates, input/output token counts, estimated API costs,
 * and renders real-time token economy metrics in the TUI statusline.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

interface SessionTokenStats {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  turnCount: number;
}

export default function (pi: ExtensionAPI) {
  const stats: SessionTokenStats = {
    inputTokens: 0,
    outputTokens: 0,
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
    turnCount: 0,
  };

  const updateStatusWidget = (ctx: any) => {
    const totalInput = stats.inputTokens + stats.cacheReadTokens;
    const cacheHitRate = totalInput > 0 ? Math.round((stats.cacheReadTokens / totalInput) * 100) : 0;
    const totalTokens = stats.inputTokens + stats.outputTokens + stats.cacheReadTokens;

    // Approximate cost calculation (Sonnet average baseline: ~$3/M in, $15/M out, $0.30/M cache read)
    const cost =
      (stats.inputTokens / 1_000_000) * 3.0 +
      (stats.outputTokens / 1_000_000) * 15.0 +
      (stats.cacheReadTokens / 1_000_000) * 0.3;

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

  pi.registerCommand("economy", {
    description: "Display session token economics, cache hit rates, and estimated cost",
    handler: async (_args, ctx) => {
      const totalInput = stats.inputTokens + stats.cacheReadTokens;
      const hitRate = totalInput > 0 ? ((stats.cacheReadTokens / totalInput) * 100).toFixed(1) : "0.0";
      const total = stats.inputTokens + stats.outputTokens + stats.cacheReadTokens;

      const cost =
        (stats.inputTokens / 1_000_000) * 3.0 +
        (stats.outputTokens / 1_000_000) * 15.0 +
        (stats.cacheReadTokens / 1_000_000) * 0.3;

      const report = `Session Token Economics:
• Total Turns: ${stats.turnCount}
• Total Tokens: ${total.toLocaleString()}
• Direct Input Tokens: ${stats.inputTokens.toLocaleString()}
• Cached Read Tokens: ${stats.cacheReadTokens.toLocaleString()} (${hitRate}% hit rate)
• Cache Written Tokens: ${stats.cacheWriteTokens.toLocaleString()}
• Output Tokens: ${stats.outputTokens.toLocaleString()}
• Estimated Cost: $${cost.toFixed(4)}`;

      ctx.ui.notify(report, "info");
    },
  });

  pi.registerCommand("tokens", {
    description: "Alias for /economy",
    handler: async (args, ctx) => {
      const cmd = pi as any;
      if (cmd) {
        ctx.sendUserMessage("/economy");
      }
    },
  });
}
