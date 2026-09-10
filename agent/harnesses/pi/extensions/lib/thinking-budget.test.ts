import { computeOptimalThinkingLevel, estimateTokenCostSavings } from "../thinking-budget";

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
const claudeExplore = computeOptimalThinkingLevel("explore", "anthropic/claude-sonnet-5");
check("Claude explore gets low thinking", claudeExplore.recommendedLevel === "low");

const claudeReview = computeOptimalThinkingLevel("review", "anthropic/claude-opus-5");
check("Claude review gets max thinking", claudeReview.recommendedLevel === "max");

const claudeImpl = computeOptimalThinkingLevel("implement", "anthropic/claude-sonnet-5");
check("Claude implement gets high thinking", claudeImpl.recommendedLevel === "high");

// 2. Gemini model optimization
const geminiResearch = computeOptimalThinkingLevel("research", "google/gemini-3.8-flash");
check("Gemini research gets low thinking", geminiResearch.recommendedLevel === "low");

const geminiReview = computeOptimalThinkingLevel("review", "google/gemini-3.8-pro");
check("Gemini review gets high thinking", geminiReview.recommendedLevel === "high");

// 3. Prompt cache savings estimation
const savings = estimateTokenCostSavings(100000, 0.8);
check("Token cache estimate tracks cached volume", savings.cachedTokens === 80000);
check("Token cache savings ratio is ~72%", savings.savingsRatioPercent === 72);

console.log(`\nthinking-budget: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
