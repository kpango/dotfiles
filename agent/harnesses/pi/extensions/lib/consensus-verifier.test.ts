import { evaluateConsensus, ModelVote, parseDiffHeuristicReview } from "../consensus-verifier";

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

// 1. Unanimous PASS (3/3)
const unanimousVotes: ModelVote[] = [
  { modelName: "Claude Sonnet 5", verdict: "PASS", rationale: "Approved" },
  { modelName: "Gemini 3.8", verdict: "PASS", rationale: "Approved" },
  { modelName: "GPT-6 Astra", verdict: "PASS", rationale: "Approved" },
];
const uVerdict = evaluateConsensus(unanimousVotes);
check("Unanimous votes approved", uVerdict.approved);
check("Unanimous flag is true", uVerdict.unanimous);
check("Report indicates APPROVED", uVerdict.report.includes("CONSENSUS STATUS: APPROVED"));

// 2. Majority PASS but non-unanimous (2/3) -> should FAIL under strict unanimous policy
const splitVotes: ModelVote[] = [
  { modelName: "Claude Sonnet 5", verdict: "PASS", rationale: "Approved" },
  { modelName: "Gemini 3.8", verdict: "PASS", rationale: "Approved" },
  { modelName: "GPT-6 Astra", verdict: "FAIL", rationale: "Found potential edge case", concerns: ["Missing test"] },
];
const sVerdict = evaluateConsensus(splitVotes);
check("2/3 PASS is REJECTED under strict unanimous policy", !sVerdict.approved);
check("Split vote is not unanimous", !sVerdict.unanimous);
check("Report indicates REJECTED", sVerdict.report.includes("CONSENSUS STATUS: REJECTED"));
check("Report includes objection details", sVerdict.report.includes("Missing test"));

// 3. parseDiffHeuristicReview with clean diff
const cleanVote = parseDiffHeuristicReview("func Add(a, b int) int { return a + b }", "Model A");
check("Clean diff yields PASS", cleanVote.verdict === "PASS");

// 4. parseDiffHeuristicReview with secret leak
const dirtyVote = parseDiffHeuristicReview("const apiKey = 'sk-12345'", "Model B");
check("Dirty diff yields FAIL", dirtyVote.verdict === "FAIL");

console.log(`\nconsensus-verifier: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
