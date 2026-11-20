/**
 * Tests for Grill Elicitation Core Library
 *
 * Verifies design-tree interview sessions, question navigation,
 * answer recording, CONTEXT.md synthesis, and status reporting.
 */

import {
  createInterviewSession,
  addQuestionNode,
  recordAnswer,
  getNextPendingQuestion,
  generateDefaultInterviewTree,
  formatQuestionPrompt,
  resolveSelectedOptionIndex,
  synthesizeContext,
  formatStatusReport,
  type InterviewSession,
} from "./grill-elicitation-core";

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

console.log("=== Running Grill Elicitation Core Tests ===\n");

// --------------------------------------------------------------------------
// Test 1: Session Creation
// --------------------------------------------------------------------------
const session = createInterviewSession("Pi Grilling Extension");
check("Session has valid grill ID prefix", session.id.startsWith("grill-"));
check("Session records correct topic", session.topic === "Pi Grilling Extension");
check("Session initializes as in_progress", session.status === "in_progress");
check("Session starts with 0 nodes", session.nodes.length === 0);
check("Session starts with question index 0", session.currentQuestionIndex === 0);
check("Session has valid timestamps", Boolean(session.createdAt && session.updatedAt));

// Default session with fallback topic
const emptySession = createInterviewSession("");
check("Empty topic falls back to default", emptySession.topic === "System Design");

// --------------------------------------------------------------------------
// Test 2: Adding Question Nodes & Hierarchy
// --------------------------------------------------------------------------
const defaultNodes = generateDefaultInterviewTree("Pi Grilling Extension");
check("Default tree provides 4 levels", defaultNodes.length === 4);
check("Level 1 is Architecture & Boundaries", defaultNodes[0].level === 1 && defaultNodes[0].category === "Architecture & Boundaries");
check("Level 2 is Behavior & Edge Cases", defaultNodes[1].level === 2 && defaultNodes[1].category === "Behavior & Edge Cases");
check("Level 3 is Consistency & Compatibility", defaultNodes[2].level === 3 && defaultNodes[2].category === "Consistency & Compatibility");
check("Level 4 is Implementation & Tests", defaultNodes[3].level === 4 && defaultNodes[3].category === "Implementation & Tests");

for (const n of defaultNodes) {
  const added = addQuestionNode(session, n);
  check(`Added node ${added.id} has matching category`, added.category === n.category);
  check(`Added node ${added.id} has tagged recommended option`, added.options[added.recommendedIndex].recommended === true);
}

check("Session now contains 4 nodes", session.nodes.length === 4);

// --------------------------------------------------------------------------
// Test 3: Question Prompt Formatting (1问1答 protocol)
// --------------------------------------------------------------------------
const pendingQ = getNextPendingQuestion(session);
check("Pending question is Q1", pendingQ !== null && pendingQ.id === "q1");

const promptQ1 = formatQuestionPrompt(pendingQ!);
check("Prompt includes [Grill Q1]", promptQ1.includes("### [Grill Q1]"));
check("Prompt contains [Recommended] badge", promptQ1.includes("[Recommended]"));
check("Prompt contains 推奨理由", promptQ1.includes("**推奨理由**:"));

// --------------------------------------------------------------------------
// Test 4: Answering Questions & Progression
// --------------------------------------------------------------------------
// Answer Q1 with recommended option
const q1Rec = pendingQ!.options[pendingQ!.recommendedIndex].label;
const ans1Ok = recordAnswer(session, "q1", q1Rec);
check("recordAnswer for q1 succeeds", ans1Ok);
check("Session currentQuestionIndex advanced to 1", session.currentQuestionIndex === 1);
check("Q1 selectedOption recorded", session.nodes[0].selectedOption === q1Rec);
check("Session status still in_progress", session.status === "in_progress");

// Next pending question is Q2
const pendingQ2 = getNextPendingQuestion(session);
check("Next pending is Q2", pendingQ2 !== null && pendingQ2.id === "q2");

// Answer Q2, Q3, Q4
recordAnswer(session, "q2", session.nodes[1].options[0].label, "Deterministic error returns prevent crashes");
recordAnswer(session, "q3", session.nodes[2].options[0].label, "SSoT alignment");
recordAnswer(session, "q4", session.nodes[3].options[0].label, "Automated tests ensure zero regressions");

check("All nodes answered", session.nodes.every((n) => Boolean(n.selectedOption)));
check("Session transitions to completed", session.status === "completed");
check("getNextPendingQuestion returns null when complete", getNextPendingQuestion(session) === null);

// Non-existent node answer returns false
const invalidAnswer = recordAnswer(session, "non_existent_id", "foo");
check("recordAnswer returns false for unknown nodeId", invalidAnswer === false);

// --------------------------------------------------------------------------
// Test 5: CONTEXT.md Synthesis
// --------------------------------------------------------------------------
const contextMd = synthesizeContext(session);
check("CONTEXT contains header", contextMd.includes("# CONTEXT — Pi Grilling Extension"));
check("CONTEXT contains Domain Glossary", contextMd.includes("## 1. ドメイン用語集 (Domain Glossary)"));
check("CONTEXT contains System Invariants", contextMd.includes("## 2. システム不変条件 (System Invariants)"));
check("CONTEXT contains Boundary & Contracts", contextMd.includes("## 3. 責務境界と入出力規約 (Boundary & Contracts)"));
check("CONTEXT contains Constraints & Non-Goals", contextMd.includes("## 4. 既知の制約と非目標 (Constraints & Non-Goals)"));

// Merging with existing context
const existingCtx = `# CONTEXT — Existing Project\n\n## 1. ドメイン用語集 (Domain Glossary)\n- **OldTerm**: Previous definition\n\n## 2. システム不変条件 (System Invariants)\n- Invariant-0: Existing constraint\n\n## 3. 責務境界と入出力規約 (Boundary & Contracts)\n\n## 4. 既知の制約と非目標 (Constraints & Non-Goals)\n`;
const mergedCtx = synthesizeContext(session, existingCtx);
check("Merged CONTEXT retains existing terms", mergedCtx.includes("- **OldTerm**: Previous definition"));
check("Merged CONTEXT adds new domain choices", mergedCtx.includes("Design Choice"));
check("Merged CONTEXT retains existing invariants", mergedCtx.includes("Invariant-0: Existing constraint"));

// --------------------------------------------------------------------------
// Test 6: Status Report Formatting
// --------------------------------------------------------------------------
const report = formatStatusReport(session);
check("Status report shows 100% completed", report.includes("100%"));
check("Status report lists answered Q1", report.includes("✅ **Q1"));
check("Status report shows selected options", report.includes("Selected:"));

// Uncompleted session status report
const partialSession = createInterviewSession("Partial", defaultNodes);
const partialReport = formatStatusReport(partialSession);
check("Partial report shows 0% and in_progress", partialReport.includes("IN_PROGRESS") && partialReport.includes("0%"));
check("Partial report shows Next Question section", partialReport.includes("Next Question To Answer:"));

// --------------------------------------------------------------------------
// L1 regression: substring option labels must not double-select. Selecting "AB"
// must resolve ONLY "AB" (not the shorter "A") in the recorded rationale.
{
  const sub = createInterviewSession("Cache Strategy");
  addQuestionNode(sub, {
    category: "Architecture", question: "Which cache?", level: 1, recommendedIndex: 1,
    options: [
      { label: "A", description: "opt A", rationale: "rationale-A" },
      { label: "AB", description: "opt AB", rationale: "rationale-AB" },
      { label: "C", description: "opt C" },
    ],
  } as any);
  const subNodeId = sub.nodes[0].id;
  recordAnswer(sub, subNodeId, "AB");
  check("L1: recordAnswer picks the exact option's rationale (not a substring)", sub.nodes[0].rationale === "rationale-AB");
  // Helper edge cases.
  check("L1: resolveSelectedOptionIndex exact match", resolveSelectedOptionIndex([{ label: "A" }, { label: "AB" }] as any, "AB") === 1);
  check("L1: resolveSelectedOptionIndex longest substring wins", resolveSelectedOptionIndex([{ label: "A" }, { label: "AB" }] as any, "AB extra") === 1);
  check("L1: resolveSelectedOptionIndex no match -> -1", resolveSelectedOptionIndex([{ label: "X" }] as any, "Y") === -1);
}

// Summary
// --------------------------------------------------------------------------
console.log(`\ngrill-elicitation-core: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
