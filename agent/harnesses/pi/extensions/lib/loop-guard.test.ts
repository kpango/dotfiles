import * as os from "node:os";
import * as path from "node:path";
import {
  LoopGuardTracker,
  buildLocalContextSummary,
  isVerificationBashCommand,
  normalizeTargetPath,
} from "./loop-guard-core";

let pass = 0;
let fail = 0;

function check(name: string, cond: boolean, detail?: string) {
  if (cond) pass++;
  else {
    fail++;
    console.error(`FAIL: ${name}${detail ? ` (${detail})` : ""}`);
  }
}

const t = new LoopGuardTracker({ editThreshold: 3, failThreshold: 3, turnBudget: 10 });
const fileA = path.join(os.tmpdir(), "demo-a.go");

// Read-Guard checks
check("Read-Guard skips new files not yet on disk", t.checkBlindEdit(fileA, false) === null);
check("Read-Guard flags blind edit on existing unread file", Boolean(t.checkBlindEdit(fileA, true)?.includes("Read-Guard")));
t.recordRead(fileA);
check("Read-Guard passes once file is read", t.checkBlindEdit(fileA, true) === null);

// Doom-Loop edit count + reset on verification
check("edit 1 no warning", t.recordEdit(fileA) === null);
check("edit 2 no warning", t.recordEdit(fileA) === null);
check("edit 3 triggers Doom-Loop notice", Boolean(t.recordEdit(fileA)?.includes("Doom-Loop")));
check("edit 4 warns once per cycle", t.recordEdit(fileA) === null);
t.recordVerificationPass();
check("verification pass clears edit count and unverified flag", !t.snapshot().hasUnverifiedEdits);
check("after verification, edit 1 starts clean", t.recordEdit(fileA) === null);

// Consecutive failure detection
check("fail 1 clean", t.recordToolOutcome({ toolName: "bash", command: "go test ./..." }, true) === null);
check("fail 2 clean", t.recordToolOutcome({ toolName: "bash", command: "go test ./..." }, true) === null);
check("fail 3 triggers repeated failure", Boolean(t.recordToolOutcome({ toolName: "bash", command: "go test ./..." }, true)?.includes("Repeated failure")));

// Passing verification via bash tool outcome resets edit state
t.recordEdit(fileA);
t.recordToolOutcome({ toolName: "bash", command: "go test ./..." }, false);
check("passing test command clears unverified edits", !t.snapshot().hasUnverifiedEdits);

// Turn budget check
t.recordEdit(fileA);
check("turn budget silent before window", t.checkTurnBudget(4) === null);
check("turn budget advises within <=5 turns remaining", Boolean(t.checkTurnBudget(6)?.includes("Turn Budget")));
check("turn budget advises only once", t.checkTurnBudget(7) === null);

// Path & verification command helpers
check("normalizeTargetPath strips hashline wrapper", normalizeTargetPath("[pkg/a.go#a1b2]", "/repo") === "/repo/pkg/a.go");
check("isVerificationBashCommand matches go test", isVerificationBashCommand("go test ./..."));
check("isVerificationBashCommand ignores cat", !isVerificationBashCommand("cat README.md"));

// Local context summary does not throw
const summary = buildLocalContextSummary(process.cwd());
check("buildLocalContextSummary includes Toolchains", summary.includes("Toolchains:"));

console.log(`\nloop-guard: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
