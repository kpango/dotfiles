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
check("Clean diff report indicates PASS", cleanReport.includes("GATE STATUS: PASS"));

console.log(`\nadversarial-reviewer: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
