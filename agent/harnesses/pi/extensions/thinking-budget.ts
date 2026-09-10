/**
 * Dynamic Thinking Budget & Prompt Cache Optimizer Extension for Pi Coding Agent
 *
 * Dynamically adjusts extended thinking levels based on task profile and active model,
 * optimizing token latency, prompt cache alignment, and cost efficiency.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export type ThinkingLevel = "off" | "low" | "medium" | "high" | "max";

export interface ThinkingOptimizationResult {
  recommendedLevel: ThinkingLevel;
  maxThinkingTokens?: number;
  rationale: string;
}

/**
 * Determine optimal thinking level based on task nature and model family.
 */
export function computeOptimalThinkingLevel(
  taskProfile: "explore" | "research" | "implement" | "review" | "general",
  modelId: string
): ThinkingOptimizationResult {
  const normModel = modelId.toLowerCase();

  // Gemini models (Gemini 3.8 Flash uses effort levels)
  if (normModel.includes("gemini")) {
    if (taskProfile === "explore" || taskProfile === "research") {
      return {
        recommendedLevel: "low",
        maxThinkingTokens: 2048,
        rationale: "Gemini research profile: fast low-effort reasoning maximizes speed and cache reuse.",
      };
    }
    if (taskProfile === "review" || taskProfile === "implement") {
      return {
        recommendedLevel: "high",
        maxThinkingTokens: 16384,
        rationale: "Gemini review profile: high effort ensures rigorous verification.",
      };
    }
  }

  // Claude models (Claude Sonnet 5 / Opus 5)
  if (normModel.includes("claude")) {
    if (taskProfile === "explore" || taskProfile === "research") {
      return {
        recommendedLevel: "low",
        maxThinkingTokens: 4096,
        rationale: "Claude explore profile: bounded thinking prevents token bloat on survey queries.",
      };
    }
    if (taskProfile === "review") {
      return {
        recommendedLevel: "max",
        maxThinkingTokens: 32768,
        rationale: "Claude review profile: maximum thinking depth for Phase 5 verifier independence.",
      };
    }
    if (taskProfile === "implement") {
      return {
        recommendedLevel: "high",
        maxThinkingTokens: 16384,
        rationale: "Claude implement profile: high thinking budget for surgical edits.",
      };
    }
  }

  // Default fallback
  return {
    recommendedLevel: "medium",
    maxThinkingTokens: 8192,
    rationale: "Standard balanced thinking budget.",
  };
}

/**
 * Estimate token cost reduction with prompt cache and optimal thinking.
 */
export function estimateTokenCostSavings(
  baseTokens: number,
  cacheHitRatio: number
): { cachedTokens: number; savingsRatioPercent: number } {
  const hit = Math.max(0, Math.min(1, cacheHitRatio));
  const cached = Math.round(baseTokens * hit);
  // Cached prompt reads are ~90% cheaper on modern frontier models
  const costReduction = hit * 0.9;
  return {
    cachedTokens: cached,
    savingsRatioPercent: Math.round(costReduction * 100),
  };
}

export default function (pi: ExtensionAPI) {
  // Command: /thinking-budget ("thinking" collides with the built-in interactive command)
  pi.registerCommand("thinking-budget", {
    description: "Inspect or override dynamic thinking budget (/thinking-budget [off|low|medium|high|max])",
    handler: async (args, ctx) => {
      const level = (args || "").trim().toLowerCase() as ThinkingLevel;
      const actions = ctx as unknown as {
        getThinkingLevel?: () => ThinkingLevel;
        setThinkingLevel?: (l: ThinkingLevel) => void;
      };
      if (!level) {
        const activeModel = ctx.model?.id || "anthropic/claude-sonnet-5";
        const current = computeOptimalThinkingLevel("general", activeModel);
        const activeLevel =
          typeof actions.getThinkingLevel === "function" ? actions.getThinkingLevel() : "(unknown)";
        ctx.ui.notify(`Active Model: ${activeModel}\nCurrent Thinking: ${String(activeLevel).toUpperCase()}\nRecommended Thinking: ${current.recommendedLevel.toUpperCase()} (${current.maxThinkingTokens || 8192} tokens)\nRationale: ${current.rationale}`, "info");
        return;
      }

      if (["off", "low", "medium", "high", "max"].includes(level)) {
        // Actually apply the override to the live session (not just notify). The API is
        // guarded because the command context surface can vary by pi version.
        if (typeof actions.setThinkingLevel === "function") {
          actions.setThinkingLevel(level);
          const applied =
            typeof actions.getThinkingLevel === "function" ? actions.getThinkingLevel() : level;
          ctx.ui.notify(`Thinking level applied: ${String(applied).toUpperCase()}`, "info");
        } else {
          ctx.ui.notify(`Thinking override unsupported in this context; recommended level: ${level.toUpperCase()}`, "warning");
        }
      } else {
        ctx.ui.notify("Valid levels: off, low, medium, high, max", "warning");
      }
    },
  });
}
