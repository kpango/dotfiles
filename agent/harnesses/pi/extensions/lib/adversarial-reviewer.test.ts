import { evaluateDiffLenses, formatAdversarialReport } from "../adversarial-reviewer";

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

// 1. Security lens detection
const secretDiff = `
diff --git a/config.json b/config.json
--- a/config.json
+++ b/config.json
@@ -1,2 +1,3 @@
+{
+  "api_key": "sk-1234567890abcdef"
+}
`;
const secFindings = evaluateDiffLenses(secretDiff);
check("Security lens catches API key", secFindings.some(f => f.lens === "security" && f.severity === "blocker"));

// 2. Systems-lang lens detection
const goroutineDiff = `
diff --git a/main.go b/main.go
+++ b/main.go
@@ -10,1 +10,3 @@
+go func() {
+  doBackgroundWork()
+}()
`;
const sysFindings = evaluateDiffLenses(goroutineDiff);
check("Systems-lang lens catches bare goroutine", sysFindings.some(f => f.lens === "systems-lang"));

// 3. Clean diff report
const cleanDiff = `
diff --git a/calc.go b/calc.go
+++ b/calc.go
@@ -1,2 +1,3 @@
+func Add(a, b int) int {
+  return a + b
+}
`;
const cleanFindings = evaluateDiffLenses(cleanDiff);
check("Clean diff has no findings", cleanFindings.length === 0);
const cleanReport = formatAdversarialReport(cleanFindings, 10);
check("Clean diff report indicates PRE-SCREEN PASS", cleanReport.includes("PRE-SCREEN STATUS: PASS"));
check("Truly clean diff marks 'no heuristic findings'", cleanReport.includes("no heuristic findings"));
// pre-screen 位置づけ decision 2026-09-07: pre-screen は Phase 4.5 8-Agent レビューの代替ではないことを明示し、
// architecture/infra-config の死レーンを CLEAN と誤表示しないことを固定する。
check("pre-screen banner disclaims it is NOT the 8-agent review", cleanReport.includes("PRE-SCREEN ONLY") && cleanReport.includes("8-Agent"));
check("architecture lens shown as not covered by heuristic pre-screen",
  cleanReport.includes("not covered by heuristic pre-screen") && cleanReport.includes("architecture-adversarial-reviewer"));
check("no residual 'all 8 lenses' overclaim", !cleanReport.includes("all 8 lenses"));

// L3 regression: a diff with only advisory NOTE findings must PASS but must NOT
// claim a fully "clean" diff (the notes are listed in the body).
const noteOnlyDiff = `
diff --git a/x.go b/x.go
+++ b/x.go
@@ -1,1 +1,2 @@
+// TODO: revisit this allocation
+x := 1
`;
const noteFindings = evaluateDiffLenses(noteOnlyDiff);
check("note-only diff produces exactly note-severity findings",
  noteFindings.length > 0 && noteFindings.every((f) => f.severity === "note"));
const noteReport = formatAdversarialReport(noteFindings, 10);
check("note-only report still PRE-SCREEN PASSes", noteReport.includes("PRE-SCREEN STATUS: PASS"));
check("note-only report does NOT overclaim fully-clean", !noteReport.includes("no heuristic findings"));
check("note-only report acknowledges advisory note(s)", noteReport.includes("advisory note"));

console.log(`\nadversarial-reviewer: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
