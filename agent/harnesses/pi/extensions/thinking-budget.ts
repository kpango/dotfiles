/**
 * Dynamic Thinking Budget & Prompt Cache Optimizer Extension for Pi
 *
 * Dynamically adjusts extended thinking levels based on task profile and active model,
 * optimizing token latency, prompt cache alignment, and cost efficiency.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { getPiDefaultModel } from "./lib/model-catalog";

export type ThinkingLevel = "off" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max";
export type SandwichPhase = "plan" | "implement" | "verify";

const EDIT_TOOL_NAMES = new Set(["edit", "write"]);
const VERIFY_TOOL_NAMES = new Set([
  "lsp",
  "run_adversarial_review",
  "run_consensus_verification",
  "ponytail_audit",
]);

/**
 * Infer Reasoning Sandwich phase (pi-agent-improvement.pdf #9):
 * - plan/explore/initial -> "plan"
 * - middle edit/write implementation -> "implement"
 * - post-edit verification/test/review -> "verify"
 */
export function inferSandwichPhase(recentTools: string[], promptText?: string): SandwichPhase {
  const prompt = (promptText || "").toLowerCase();
  if (/\b(?:verify|review|test|audit|check|lint|diff|commit|gate)\b/.test(prompt)) {
    return "verify";
  }
  const tail = recentTools.slice(-4);
  if (tail.length === 0) {
    return /\b(?:implement|fix|refactor|write|edit|patch|add)\b/.test(prompt) ? "implement" : "plan";
  }
  const last = tail[tail.length - 1];
  if (VERIFY_TOOL_NAMES.has(last)) return "verify";
  if (EDIT_TOOL_NAMES.has(last)) return "implement";
  if (tail.some((t) => EDIT_TOOL_NAMES.has(t))) {
    return /\b(?:plan|design|architect|explore|investigate)\b/.test(prompt) ? "plan" : "verify";
  }
  return "plan";
}

/**
 * Compute Reasoning Sandwich effort (plan=high/xhigh, implement=low/high, verify=xhigh/high).
 */
export function computeReasoningSandwichLevel(phase: SandwichPhase, modelId: string): ThinkingLevel {
  const m = modelId.toLowerCase();
  const isFastTier = /haiku|flash|hydrogen|gpt-oss|lfm2|deepseek|qwen2\.5/.test(m);
  if (isFastTier) {
    if (phase === "verify") return "high";
    if (phase === "plan") return "medium";
    return "low";
  }
  if (phase === "implement") return "high";
  return "xhigh";
}

export function resolveModelFamilyGuidance(modelId: string): { family: string; hint: string } {
  const m = (modelId || "").toLowerCase();
  if (m.includes("claude") || m.includes("fable")) {
    return {
      family: "claude",
      hint: "Prefer concise structure, preserve existing comments/types, and use tool_search/codemode for deferred tools.",
    };
  }
  if (m.includes("gpt") || m.includes("codex") || m.includes("openai")) {
    return {
      family: "openai",
      hint: "Keep edits minimal and verified after each change; use Reasoning Sandwich xhigh on plan/verify and high on implement.",
    };
  }
  if (m.includes("gemini")) {
    return {
      family: "gemini",
      hint: "Anchor edits strictly via hashline tags and summarize multi-file diffs before modifying.",
    };
  }
  if (/(deepseek|kimi|qwen)/.test(m)) {
    return {
      family: "deepseek-kimi-qwen",
      hint: "Favor Action Fusion validators, single-file surgical diffs, and avoid unrequested multi-file refactors.",
    };
  }
  return {
    family: "generic",
    hint: "Follow Read -> Hashline Edit -> Deterministic Verify loop with minimal surgical diffs.",
  };
}

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

  // Gemini models (Gemini 4 Hydrogen / Argon use effort levels)
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

  // Claude models (Claude Sonnet 5.5 / Opus 5.5 / Fable 5.2)
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
  let sandwichEnabled = process.env.PI_REASONING_SANDWICH !== "0" && process.env.PI_SUBAGENT !== "1";
  let recentTools: string[] = [];

  const getActiveThinking = (ctx: any): ThinkingLevel | undefined => {
    const api = pi as unknown as { getThinkingLevel?: () => ThinkingLevel };
    if (typeof api.getThinkingLevel === "function") return api.getThinkingLevel();
    const c = ctx as unknown as { getThinkingLevel?: () => ThinkingLevel };
    return typeof c?.getThinkingLevel === "function" ? c.getThinkingLevel() : undefined;
  };

  const applyThinking = (ctx: any, level: ThinkingLevel): boolean => {
    const api = pi as unknown as { setThinkingLevel?: (l: ThinkingLevel) => void };
    if (typeof api.setThinkingLevel === "function") {
      api.setThinkingLevel(level);
      return true;
    }
    const c = ctx as unknown as { setThinkingLevel?: (l: ThinkingLevel) => void };
    if (typeof c?.setThinkingLevel === "function") {
      c.setThinkingLevel(level);
      return true;
    }
    return false;
  };

  pi.on("session_start", async () => {
    recentTools = [];
  });

  pi.on("tool_result", async (event) => {
    if (!event?.toolName) return;
    recentTools.push(event.toolName);
    if (recentTools.length > 12) recentTools = recentTools.slice(-12);
  });

  pi.on("before_agent_start", async (event, ctx) => {
    if (!sandwichEnabled) return;
    const promptText = typeof (event as { prompt?: unknown } | undefined)?.prompt === "string"
      ? (event as { prompt: string }).prompt
      : undefined;
    const phase = inferSandwichPhase(recentTools, promptText);
    const activeModel = ctx?.model?.id || getPiDefaultModel(ctx?.cwd || process.cwd());
    const targetLevel = computeReasoningSandwichLevel(phase, activeModel);
    const currentLevel = getActiveThinking(ctx);
    if (currentLevel !== targetLevel) {
      applyThinking(ctx, targetLevel);
    }
  });

  // Command: /thinking-budget ("thinking" collides with the built-in interactive command)
  pi.registerCommand("thinking-budget", {
    description: "Inspect or override dynamic thinking budget (/thinking-budget [off|minimal|low|medium|high|xhigh|max|sandwich on|off|status])",
    handler: async (args, ctx) => {
      const parts = (args || "").trim().toLowerCase().split(/\s+/).filter(Boolean);
      const level = (parts[0] || "") as ThinkingLevel | "sandwich" | "profile";

      if (level === "profile") {
        const activeModel = ctx.model?.id || getPiDefaultModel(ctx.cwd);
        const prof = resolveModelFamilyGuidance(activeModel);
        ctx.ui.notify(`Model Family Profile (${prof.family} | ${activeModel}):\n${prof.hint}`, "info");
        return;
      }

      if (level === "sandwich") {
        const sub = parts[1] || "status";
        if (sub === "on") sandwichEnabled = true;
        else if (sub === "off") sandwichEnabled = false;
        const phase = inferSandwichPhase(recentTools);
        const activeModel = ctx.model?.id || getPiDefaultModel(ctx.cwd);
        ctx.ui.notify(
          `Reasoning Sandwich: ${sandwichEnabled ? "ON" : "OFF"} (phase=${phase}, target=${computeReasoningSandwichLevel(phase, activeModel)})`,
          "info",
        );
        return;
      }

      if (!level) {
        const activeModel = ctx.model?.id || getPiDefaultModel(ctx.cwd);
        const current = computeOptimalThinkingLevel("general", activeModel);
        const activeLevel = getActiveThinking(ctx) ?? "(unknown)";
        const phase = inferSandwichPhase(recentTools);
        ctx.ui.notify(
          `Active Model: ${activeModel}\nCurrent Thinking: ${String(activeLevel).toUpperCase()}\nReasoning Sandwich: ${sandwichEnabled ? `ON (phase=${phase}, target=${computeReasoningSandwichLevel(phase, activeModel).toUpperCase()})` : "OFF"}\nRecommended General: ${current.recommendedLevel.toUpperCase()} (${current.maxThinkingTokens || 8192} tokens)\nRationale: ${current.rationale}`,
          "info",
        );
        return;
      }

      if (["off", "minimal", "low", "medium", "high", "xhigh", "max"].includes(level)) {
        if (applyThinking(ctx, level as ThinkingLevel)) {
          const applied = getActiveThinking(ctx) ?? level;
          ctx.ui.notify(`Thinking level applied: ${String(applied).toUpperCase()}`, "info");
        } else {
          ctx.ui.notify(`Thinking override unsupported in this context; recommended level: ${level.toUpperCase()}`, "warning");
        }
      } else {
        ctx.ui.notify("Valid options: off, minimal, low, medium, high, xhigh, max, sandwich [on|off|status]", "warning");
      }
    },
  });
}
