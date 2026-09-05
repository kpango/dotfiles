import {
  parseInterval,
  parseIntervalMs,
  parseGoalCondition,
  evaluateGoalPredicate,
  evaluateGoalCondition,
  LoopController,
  LoopControllerRegistry,
  MAX_ITERATIONS_HARD_CAP,
  CONSECUTIVE_FAILURES_ABORT_THRESHOLD,
  GoalCondition,
} from "./loop-controller-core";

let pass = 0;
let fail = 0;

function check(name: string, ok: boolean, msg?: string) {
  if (ok) {
    console.log("ok: " + name);
    pass++;
  } else {
    console.error("FAIL: " + name + ": " + (msg || ""));
    fail++;
  }
}

function eq<T>(name: string, actual: T, expected: T) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  check(name, ok, "expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual));
}

console.log("=== Loop Controller Unit Tests ===");

// 1. parseInterval & parseIntervalMs
eq("interval: 10s", parseInterval("10s"), 10000);
eq("interval: 30sec", parseInterval("30sec"), 30000);
eq("interval: 10seconds", parseInterval("10seconds"), 10000);
eq("interval: 1m", parseInterval("1m"), 60000);
eq("interval: 5m", parseInterval("5m"), 300000);
eq("interval: 5minutes", parseInterval("5minutes"), 300000);
eq("interval: 1h", parseInterval("1h"), 3600000);
eq("interval: 2hours", parseInterval("2hours"), 7200000);
eq("interval: 500ms", parseInterval("500ms"), 500);
eq("interval: bare number", parseInterval("2500"), 2500);
eq("interval: invalid string abc", parseInterval("abc"), null);
eq("interval: invalid negative", parseInterval("-10s"), null);
eq("interval: empty string", parseInterval(""), null);
eq("interval: null input", parseInterval(null as any), null);
eq("interval: alias parseIntervalMs", parseIntervalMs("10s"), 10000);

// 2. parseGoalCondition
const exitCond = parseGoalCondition("exit:0");
eq("parseGoalCondition: exit:0 type", exitCond.type, "exit");
eq("parseGoalCondition: exit:0 targetCode", exitCond.targetCode, 0);

const exitCond2 = parseGoalCondition("exit: 2");
eq("parseGoalCondition: exit:2 targetCode", exitCond2.targetCode, 2);

const containsCond = parseGoalCondition("contains:ALL_TESTS_PASS");
eq("parseGoalCondition: contains type", containsCond.type, "contains");
eq("parseGoalCondition: contains pattern", containsCond.pattern, "ALL_TESTS_PASS");

const regexCond = parseGoalCondition("regex:pass \d+/\d+");
eq("parseGoalCondition: regex type", regexCond.type, "regex");
check("parseGoalCondition: regex pattern is RegExp", regexCond.pattern instanceof RegExp);

const evalCond = parseGoalCondition("eval:exitCode === 0 && output.includes('OK')");
eq("parseGoalCondition: eval type", evalCond.type, "eval");
eq("parseGoalCondition: eval expr", evalCond.expr, "exitCode === 0 && output.includes('OK')");

const judgeCond = parseGoalCondition("judge:check code correctness");
eq("parseGoalCondition: judge type", judgeCond.type, "judge");

const bareCond = parseGoalCondition("PASS");
eq("parseGoalCondition: bare string fallback to contains", bareCond.type, "contains");
eq("parseGoalCondition: bare string pattern", bareCond.pattern, "PASS");

let regexErrorThrown = false;
try {
  parseGoalCondition("regex:[a-");
} catch {
  regexErrorThrown = true;
}
check("parseGoalCondition: invalid regex throws error", regexErrorThrown);

// 3. evaluateGoalPredicate & evaluateGoalCondition
check("evaluateGoalPredicate: exit:0 passes on exitCode 0", evaluateGoalPredicate("exit:0", { output: "failed", exitCode: 0 }));
check("evaluateGoalPredicate: exit:0 fails on exitCode 1", !evaluateGoalPredicate("exit:0", { output: "done", exitCode: 1 }));
check("evaluateGoalPredicate: contains passes when present", evaluateGoalPredicate("contains:SUCCESS", { output: "BUILD SUCCESS in 12s", exitCode: 0 }));
check("evaluateGoalPredicate: contains fails when missing", !evaluateGoalPredicate("contains:SUCCESS", { output: "BUILD FAILED", exitCode: 1 }));
check("evaluateGoalPredicate: regex matches pattern", evaluateGoalPredicate("regex:pass \\d+/\\d+", { output: "all test results: pass 15/15", exitCode: 0 }));
check("evaluateGoalPredicate: regex fails non-matching", !evaluateGoalPredicate("regex:pass \\d+/\\d+", { output: "failed 0/15", exitCode: 1 }));
check("evaluateGoalPredicate: eval expression passes", evaluateGoalPredicate("eval:exitCode === 0 && output.length > 5", { output: "123456", exitCode: 0 }));
check("evaluateGoalPredicate: eval expression fails", !evaluateGoalPredicate("eval:exitCode === 0 && output.length > 5", { output: "123", exitCode: 0 }));
check("evaluateGoalPredicate: judge condition matches success", evaluateGoalPredicate("judge:did it work", { output: "All tests completed with status OK" }));
check("evaluateGoalCondition: alias works identically", evaluateGoalCondition("contains:OK", "OK"));

// 4. LoopController - Goal Iteration Satisfaction
const ctrl1 = new LoopController();
const state1 = ctrl1.startGoalLoop({
  prompt: "Fix failing tests",
  condition: "exit:0",
  maxIterations: 5,
});
eq("LoopController: initial status is RUNNING", state1.status, "RUNNING");
eq("LoopController: initial iteration is 0", state1.iteration, 0);

const att1 = ctrl1.recordGoalAttempt({ output: "tests failed", exitCode: 1 });
check("LoopController: att1 not satisfied", !att1.satisfied);
check("LoopController: att1 continueLoop", att1.continueLoop);
eq("LoopController: att1 iteration is 1", att1.state.iteration, 1);
eq("LoopController: att1 consecutiveFailures is 1", att1.state.consecutiveFailures, 1);

const att2 = ctrl1.recordGoalAttempt({ output: "all tests passed", exitCode: 0 });
check("LoopController: att2 satisfied", att2.satisfied);
check("LoopController: att2 continueLoop is false", !att2.continueLoop);
eq("LoopController: att2 status is SATISFIED", att2.state.status, "SATISFIED");
eq("LoopController: att2 consecutiveFailures reset to 0", att2.state.consecutiveFailures, 0);

// 5. LoopController - Max Iteration Cap Enforcement
const ctrl2 = new LoopController();
const state2 = ctrl2.startGoalLoop({
  prompt: "Endless task",
  condition: "contains:NEVER_MATCH",
  maxIterations: 15,
});
eq("LoopController: maxIterations clamped to 10", state2.maxIterations, MAX_ITERATIONS_HARD_CAP);

for (let i = 1; i <= 9; i++) {
  ctrl2.recordSuccess();
  const res = ctrl2.recordGoalAttempt({ output: "attempt " + i, exitCode: 1 });
  check("LoopController: iteration " + i + " continues", res.continueLoop);
}

ctrl2.recordSuccess();
const att10 = ctrl2.recordGoalAttempt({ output: "attempt 10", exitCode: 1 });
check("LoopController: 10th attempt does not continue", !att10.continueLoop);
eq("LoopController: 10th attempt status is EXHAUSTED", att10.state.status, "EXHAUSTED");
check("LoopController: failureReason populated", Boolean(att10.state.failureReason && att10.state.failureReason.includes("Max iterations")));

// 6. LoopController - 5 Consecutive Failures Auto-Abort
const ctrl3 = new LoopController();
ctrl3.startGoalLoop({
  prompt: "Failing task",
  condition: "exit:0",
  maxIterations: 10,
});

for (let i = 1; i <= 4; i++) {
  const res = ctrl3.recordGoalAttempt({ output: "error", exitCode: 1 });
  check("LoopController: fail attempt " + i + " continues", res.continueLoop);
  eq("LoopController: consecutiveFailures is " + i, res.state.consecutiveFailures, i);
}

const att5 = ctrl3.recordGoalAttempt({ output: "error 5", exitCode: 1 });
check("LoopController: 5th failure aborts loop", !att5.continueLoop);
eq("LoopController: 5th failure status is FAILED", att5.state.status, "FAILED");
check("LoopController: 5th failure reason mentions 5 consecutive failures", Boolean(att5.state.failureReason && att5.state.failureReason.includes("5 consecutive failures")));

// 7. LoopController - Cancellation via stop()
const ctrl4 = new LoopController();
ctrl4.startIntervalLoop({
  prompt: "Periodic monitor",
  intervalMs: 5000,
});
eq("LoopController: interval loop starts RUNNING", ctrl4.getState()?.status, "RUNNING");
const stoppedState = ctrl4.stop();
eq("LoopController: stoppedState status is STOPPED", stoppedState?.status, "STOPPED");
eq("LoopController: getState() is STOPPED", ctrl4.getState()?.status, "STOPPED");

// 8. LoopControllerRegistry
const registry = new LoopControllerRegistry();
const registered = registry.registerLoop(ctrl4);
check("registry: registers controller", registered === ctrl4);
check("registry: gets registered state", registry.getLoop(ctrl4.getState()!.id)?.id === ctrl4.getState()!.id);
check("registry: lists active loops", registry.listLoops().length >= 1);

const runningCtrl = new LoopController();
runningCtrl.startIntervalLoop({ prompt: "tick", intervalMs: 10000 });
registry.registerLoop(runningCtrl);
eq("registry: stopAll stops active running loops", registry.stopAll(), 1);
eq("registry: runningCtrl now STOPPED", runningCtrl.getState()?.status, "STOPPED");

console.log("\nloop-controller.test: " + pass + " passed, " + fail + " failed");
if (fail > 0) process.exit(1);
