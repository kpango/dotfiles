import {
  computeOptimalThinkingLevel,
  computeReasoningSandwichLevel,
  estimateTokenCostSavings,
  inferSandwichPhase,
  resolveModelFamilyGuidance,
} from "../thinking-budget";

let pass = 0;
let fail = 0;

function check(name: string, ok: boolean, msg?: string) {
  if (ok) {
    console.log(`ok: ${name}`);
    pass++;
  } else {
    console.error(`FAIL: ${name}: ${msg || ""}`);
    fail++;
  }
}

// 1. Claude model optimization
const claudeExplore = computeOptimalThinkingLevel("explore", "anthropic/claude-sonnet-5-5");
check("Claude explore gets low thinking", claudeExplore.recommendedLevel === "low");

const claudeReview = computeOptimalThinkingLevel("review", "anthropic/claude-opus-5-5");
check("Claude review gets max thinking", claudeReview.recommendedLevel === "max");

const claudeImpl = computeOptimalThinkingLevel("implement", "anthropic/claude-sonnet-5-5");
check("Claude implement gets high thinking", claudeImpl.recommendedLevel === "high");

// 2. Gemini model optimization
const geminiResearch = computeOptimalThinkingLevel("research", "antigravity-cli/gemini-4-hydrogen");
check("Gemini research gets low thinking", geminiResearch.recommendedLevel === "low");

const geminiReview = computeOptimalThinkingLevel("review", "antigravity-cli/gemini-4-argon");
check("Gemini review gets high thinking", geminiReview.recommendedLevel === "high");

// 3. Prompt cache savings estimation
const savings = estimateTokenCostSavings(100000, 0.8);
check("Token cache estimate tracks cached volume", savings.cachedTokens === 80000);
check("Token cache savings ratio is ~72%", savings.savingsRatioPercent === 72);

// 4. Reasoning Sandwich (pi-agent-improvement.pdf #9)
check("sandwich phase: initial prompt -> plan", inferSandwichPhase([], "architect the cache layer") === "plan");
check("sandwich phase: after edit -> implement", inferSandwichPhase(["read", "edit"], "apply next fix") === "implement");
check("sandwich phase: verify prompt -> verify", inferSandwichPhase(["edit"], "run verify tests before commit") === "verify");
check("sandwich level: frontier implement -> high", computeReasoningSandwichLevel("implement", "anthropic/claude-opus-5-5") === "high");
check("sandwich level: frontier verify -> xhigh", computeReasoningSandwichLevel("verify", "anthropic/claude-opus-5-5") === "xhigh");
check("sandwich level: flash implement -> low", computeReasoningSandwichLevel("implement", "opencode-go/deepseek-v4.1-flash") === "low");
check("model family profile: claude", resolveModelFamilyGuidance("anthropic/claude-opus-5-5").family === "claude");
check("model family profile: openai", resolveModelFamilyGuidance("openai-codex/gpt-6.2-astra").family === "openai");
check("model family profile: gemini", resolveModelFamilyGuidance("antigravity/gemini-4-argon").family === "gemini");
check("model family profile: deepseek/kimi", resolveModelFamilyGuidance("opencode-go/kimi-k3.1-pro").family === "deepseek-kimi-qwen");

console.log(`\nthinking-budget: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
