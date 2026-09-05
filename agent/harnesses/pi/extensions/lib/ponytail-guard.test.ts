/**
 * Tests for Ponytail Guard Core Library
 *
 * Verifies the 7-step anti-overengineering logic ladder, code bloat auditing,
 * safety invariant enforcement (error suppression, shell injection), diff auditing,
 * and report formatting.
 */

import {
  getLadderSteps,
  auditCode,
  auditDiff,
  formatAuditReport,
} from "./ponytail-guard-core";

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

console.log("=== Running Ponytail Guard Core Tests ===\n");

// --------------------------------------------------------------------------
// Test 1: 7-Step Logic Ladder Structure
// --------------------------------------------------------------------------
const steps = getLadderSteps();
check("getLadderSteps returns exactly 7 steps", steps.length === 7);

const expectedStepNames = [
  "YAGNI",
  "Codebase reuse",
  "Stdlib first",
  "Platform native",
  "Minimal dependency",
  "Minimal expression",
  "Surgical minimal diff",
];

steps.forEach((s, idx) => {
  check(`Step ${idx + 1} has correct index`, s.step === idx + 1);
  check(`Step ${idx + 1} name is ${expectedStepNames[idx]}`, s.name === expectedStepNames[idx]);
  check(`Step ${idx + 1} has non-empty question`, typeof s.question === "string" && s.question.length > 0);
  check(`Step ${idx + 1} has non-empty rule`, typeof s.rule === "string" && s.rule.length > 0);
});

// --------------------------------------------------------------------------
// Test 2: Clean Minimal Code Audit (Should PASS with 0 Bloat)
// --------------------------------------------------------------------------
const cleanTsCode = `
export function filterActiveUsers(users: Array<{ id: string; active: boolean }>): string[] {
  if (!Array.isArray(users)) {
    throw new TypeError("users must be an array");
  }
  return users.filter((u) => u.active).map((u) => u.id);
}
`;

const cleanResult = auditCode(cleanTsCode, "typescript", "users.ts");
check("Clean code passes audit", cleanResult.passed === true);
check("Clean code has bloatScore 0", cleanResult.bloatScore === 0);
check("Clean code has 0 bloat findings", cleanResult.bloatFindings.length === 0);
check("Clean code has 0 safety findings", cleanResult.safetyFindings.length === 0);

// --------------------------------------------------------------------------
// Test 3: Bloated Code Audit (Speculative Builders, Heavy Deps, Utils Class)
// --------------------------------------------------------------------------
const bloatedTsCode = `
import _ from "lodash";
import moment from "moment";
import axios from "axios";

export class UserQueryBuilder {
  private query: any = {};
  public withId(id: string): this {
    this.query.id = id;
    return this;
  }
  public build(): any {
    return this.query;
  }
}

export class StringUtils {
  public static capitalize(s: string): string {
    return s.toUpperCase();
  }
}
`;

const bloatedResult = auditCode(bloatedTsCode, "typescript", "bloated.ts");
check("Bloated code fails or has bloatScore > 20", bloatedResult.bloatScore > 20);
check("Bloated code flags lodash import", bloatedResult.bloatFindings.some((f) => f.ruleName.includes("Stdlib First") && f.message.includes("lodash")));
check("Bloated code flags moment import", bloatedResult.bloatFindings.some((f) => f.ruleName.includes("Stdlib First") && f.message.includes("moment")));
check("Bloated code flags axios import", bloatedResult.bloatFindings.some((f) => f.ruleName.includes("Stdlib First") && f.message.includes("axios")));
check("Bloated code flags Builder pattern", bloatedResult.bloatFindings.some((f) => f.step === 1 && f.message.includes("Builder")));
check("Bloated code flags static utility class", bloatedResult.bloatFindings.some((f) => f.step === 6 && f.message.includes("utility class")));

// --------------------------------------------------------------------------
// Test 4: Safety Guard — Error Discarding (Vald Law 5 & Ponytail Invariants)
// --------------------------------------------------------------------------
// Go: _ = err
const goCodeWithIgnoredError = `
package main

import "os"

func writeData(data []byte) error {
  f, err := os.Create("out.txt")
  if err != nil {
    return err
  }
  defer f.Close()
  _, err = f.Write(data)
  _ = err // Discarding error
  return nil
}
`;

const goResult = auditCode(goCodeWithIgnoredError, "go", "main.go");
check("Go code with _ = err FAILS audit", goResult.passed === false);
check("Flags error_suppression for Go _ = err", goResult.safetyFindings.some((f) => f.type === "error_suppression" && f.message.includes("_ = err")));

// TypeScript: Empty catch block
const tsEmptyCatch = `
export function loadConfig(path: string): any {
  try {
    return JSON.parse(path);
  } catch (err) {
  }
  return null;
}
`;

const tsCatchResult = auditCode(tsEmptyCatch, "typescript", "config.ts");
check("TS code with empty catch FAILS audit", tsCatchResult.passed === false);
check("Flags error_suppression for empty catch", tsCatchResult.safetyFindings.some((f) => f.type === "error_suppression" && f.message.includes("Empty catch")));

// Python: except: pass
const pyPass = `
def parse():
    try:
        do_something()
    except Exception:
        pass
`;
const pyResult = auditCode(pyPass, "python", "script.py");
check("Python code with except: pass flags safety error", pyResult.safetyFindings.some((f) => f.type === "error_suppression" && f.message.includes("pass")));

// --------------------------------------------------------------------------
// Test 5: Safety Guard — Shell Injection Detection
// --------------------------------------------------------------------------
const tsInjectionCode = `
import { execSync } from "child_process";

export function runUserCommand(input: string) {
  execSync(\`git checkout \${input}\`);
}
`;

const injectionResult = auditCode(tsInjectionCode, "typescript", "git.ts");
check("Shell interpolation flags security_violation", injectionResult.safetyFindings.some((f) => f.type === "security_violation"));

// --------------------------------------------------------------------------
// Test 6: Diff Auditing (`auditDiff`)
// --------------------------------------------------------------------------
// Clean surgical minimal diff
const cleanDiff = `
diff --git a/src/math.ts b/src/math.ts
index e69de29..b857438 100644
--- a/src/math.ts
+++ b/src/math.ts
@@ -1,3 +1,3 @@
-export function add(a: number, b: number) { return a - b; }
+export function add(a: number, b: number) { return a + b; }
`;

const cleanDiffResult = auditDiff(cleanDiff);
check("Clean surgical diff passes", cleanDiffResult.passed === true);
check("Clean surgical diff has bloatScore 0", cleanDiffResult.bloatScore === 0);

// Diff introducing error suppression
const dirtyDiff = `
diff --git a/pkg/service.go b/pkg/service.go
--- a/pkg/service.go
+++ b/pkg/service.go
@@ -10,3 +10,4 @@ func Run() {
+    _ = err
`;

const dirtyDiffResult = auditDiff(dirtyDiff);
check("Diff introducing _ = err FAILS", dirtyDiffResult.passed === false);
check("Flags error_suppression in diff", dirtyDiffResult.safetyFindings.some((f) => f.type === "error_suppression"));

// Diff introducing heavy dependencies
const depDiff = `
diff --git a/index.ts b/index.ts
--- a/index.ts
+++ b/index.ts
@@ -1,1 +1,2 @@
+import _ from "lodash";
`;
const depDiffResult = auditDiff(depDiff);
check("Diff adding lodash flags Step 3", depDiffResult.bloatFindings.some((f) => f.step === 3));

// --------------------------------------------------------------------------
// Test 7: Report Formatting (`formatAuditReport`)
// --------------------------------------------------------------------------
const reportPass = formatAuditReport(cleanResult, "clean-module");
check("ReportPass contains PASSED", reportPass.includes("PASSED"));
check("ReportPass contains Bloat Score 0 / 100", reportPass.includes("0 / 100"));
check("ReportPass contains Suggestions section", reportPass.includes("Actionable Ponytail Suggestions"));

const reportFail = formatAuditReport(bloatedResult, "bloated-module");
check("ReportFail contains Overengineering & Bloat Findings", reportFail.includes("Overengineering & Bloat Findings"));
check("ReportFail includes Step 1 YAGNI", reportFail.includes("Step 1:"));

const reportSafety = formatAuditReport(goResult, "go-service");
check("ReportSafety includes Safety & Invariant Violations", reportSafety.includes("Safety & Invariant Violations"));

// --------------------------------------------------------------------------
// Summary
// --------------------------------------------------------------------------
console.log(`\nponytail-guard-core: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
