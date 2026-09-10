import { evaluateConsensus, ModelVote, parseDiffHeuristicReview, runGitDiff } from "../consensus-verifier";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { execSync } from "node:child_process";

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

// 3. parseDiffHeuristicReview with clean diff (diff-formatted: added lines use `+`)
const cleanVote = parseDiffHeuristicReview("+func Add(a, b int) int { return a + b }", "Model A");
check("Clean diff yields PASS", cleanVote.verdict === "PASS");
check("Clean diff marked as heuristic", cleanVote.heuristic === true);

// 4. parseDiffHeuristicReview with secret leak in an ADDED line
const dirtyVote = parseDiffHeuristicReview("+const apiKey = 'sk-12345'", "Model B");
check("Dirty diff yields FAIL", dirtyVote.verdict === "FAIL");
check("Dirty diff marked as heuristic", dirtyVote.heuristic === true);

// 4b. L1 regression: only ADDED (`+`, not `+++`) lines are scanned. A removed
// panic (a fix) or a panic in an unchanged context line must NOT trigger FAIL.
check("L1: removing a panic() is PASS (not scanned as a violation)",
  parseDiffHeuristicReview("--- a/x.go\n+++ b/x.go\n func f(){\n-  panic(\"bad\")\n+  return err\n }", "m").verdict === "PASS");
check("L1: a panic() only in a context line is PASS",
  parseDiffHeuristicReview(" if x { panic(\"existing\") }\n-var a=1\n+var a=2", "m").verdict === "PASS");
check("L1: adding a panic() is FAIL",
  parseDiffHeuristicReview("+++ b/z.go\n+  panic(\"new\")", "m").verdict === "FAIL");
check("L1: the +++ file header is not mistaken for an added line",
  parseDiffHeuristicReview("+++ b/api.pb.go\n+var x = 1", "m").verdict === "PASS");

// 5. All-heuristic votes are honestly reported as a pre-screen, not as
//    independent 3-model consensus (verifier independence).
const heuristicVotes: ModelVote[] = [cleanVote, cleanVote, cleanVote];
const hVerdict = evaluateConsensus(heuristicVotes);
check("Heuristic-only votes are approved", hVerdict.approved);
check(
  "Heuristic-only report states PRE-SCREEN (not model consensus)",
  hVerdict.report.includes("PRE-SCREEN STATUS: PASS")
);
check(
  "Heuristic-only report avoids claiming independent model votes",
  !hVerdict.report.includes("UNANIMOUS PASS")
);

// 6. Real model votes retain the 3/3 wording.
const realVotes: ModelVote[] = [
  { modelName: "Claude Sonnet 5", verdict: "PASS", rationale: "Approved", heuristic: false },
  { modelName: "Gemini 3.8", verdict: "PASS", rationale: "Approved", heuristic: false },
  { modelName: "GPT-6 Astra", verdict: "PASS", rationale: "Approved", heuristic: false },
];
const rVerdict = evaluateConsensus(realVotes);
check("Real model votes keep 3/3 wording", rVerdict.report.includes("UNANIMOUS PASS"));

// 7. Mixed real + heuristic votes must NOT claim model unanimity.
const mixedVotes: ModelVote[] = [
  { modelName: "Claude Sonnet 5", verdict: "PASS", rationale: "Approved", heuristic: false },
  { modelName: "Gemini 3.8", verdict: "PASS", rationale: "Approved", heuristic: false },
  { modelName: "GPT-6 Astra", verdict: "PASS", rationale: "Clean diff", heuristic: true },
];
const mVerdict = evaluateConsensus(mixedVotes);
check("Mixed votes do not claim UNANIMOUS PASS", !mVerdict.report.includes("UNANIMOUS PASS"));
check("Mixed votes mention heuristic fallback", mVerdict.report.includes("heuristic fallback"));

// L1 regression: runGitDiff passes baseRef as a literal argv element, so a
// baseRef with shell metacharacters cannot execute commands.
{
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "cv-inj-"));
  try {
    execSync("git init -q && git -c user.email=a@b -c user.name=a commit -q --allow-empty -m x", { cwd: tmp });
    const marker = path.join(tmp, "pwned");
    for (const payload of [`HEAD; touch ${marker}`, `HEAD$(touch ${marker})`, "HEAD`touch " + marker + "`"]) {
      try { runGitDiff(tmp, payload); } catch { /* invalid ref -> git errors, expected */ }
    }
    check("L1: baseRef shell metacharacters do not execute commands", !fs.existsSync(marker));
    check("L1: normal baseRef 'HEAD' returns a string diff", typeof runGitDiff(tmp, "HEAD") === "string");
    check("L1: default (undefined) baseRef returns a string diff", typeof runGitDiff(tmp) === "string");
  } finally {
    try { fs.rmSync(tmp, { recursive: true, force: true }); } catch {}
  }
}

console.log(`\nconsensus-verifier: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
