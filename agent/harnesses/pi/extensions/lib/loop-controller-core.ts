/**
 * Hermes-Style Loop Controller Core
 */

export const MAX_ITERATIONS_HARD_CAP = 10;
export const CONSECUTIVE_FAILURES_ABORT_THRESHOLD = 5;

export type GoalConditionType = "exit" | "contains" | "regex" | "eval" | "judge";

export interface GoalCondition {
  type: GoalConditionType;
  raw: string;
  targetCode?: number;
  pattern?: string | RegExp;
  expr?: string;
  judgePrompt?: string;
}

export type LoopMode = "interval" | "goal";
export type LoopStatus = "IDLE" | "RUNNING" | "STOPPED" | "SATISFIED" | "EXHAUSTED" | "FAILED";

export interface LoopState {
  id: string;
  mode: LoopMode;
  prompt: string;
  intervalMs?: number;
  condition?: GoalCondition;
  iteration: number;
  maxIterations: number;
  consecutiveFailures: number;
  status: LoopStatus;
  lastOutput?: string;
  lastExitCode?: number;
  startedAt: number;
  completedAt?: number;
  failureReason?: string;
}

export function parseInterval(str: string): number | null {
  if (!str || typeof str !== "string") return null;
  const trimmed = str.trim().toLowerCase();
  if (!trimmed) return null;

  const msMatch = trimmed.match(/^(\d+)\s*ms$/);
  if (msMatch && msMatch[1]) {
    const val = parseInt(msMatch[1], 10);
    return val > 0 ? val : null;
  }

  const sMatch = trimmed.match(/^(\d+)\s*s(?:ec(?:ond)?s?)?$/);
  if (sMatch && sMatch[1]) {
    const val = parseInt(sMatch[1], 10);
    return val > 0 ? val * 1000 : null;
  }

  const mMatch = trimmed.match(/^(\d+)\s*m(?:in(?:ute)?s?)?$/);
  if (mMatch && mMatch[1]) {
    const val = parseInt(mMatch[1], 10);
    return val > 0 ? val * 60 * 1000 : null;
  }

  const hMatch = trimmed.match(/^(\d+)\s*h(?:our?s?)?$/);
  if (hMatch && hMatch[1]) {
    const val = parseInt(hMatch[1], 10);
    return val > 0 ? val * 3600 * 1000 : null;
  }

  if (/^\d+$/.test(trimmed)) {
    const val = parseInt(trimmed, 10);
    return val > 0 ? val : null;
  }

  return null;
}

export const parseIntervalMs = parseInterval;

export function parseGoalCondition(raw: string): GoalCondition {
  if (!raw || typeof raw !== "string") {
    throw new Error("Goal condition string cannot be empty");
  }
  const trimmed = raw.trim();

  if (/^exit:\s*(\d+)$/i.test(trimmed)) {
    const code = parseInt(trimmed.replace(/^exit:\s*/i, ""), 10);
    return { type: "exit", raw: trimmed, targetCode: code };
  }

  if (/^contains:/i.test(trimmed)) {
    const val = trimmed.slice("contains:".length).trim();
    return { type: "contains", raw: trimmed, pattern: val };
  }

  if (/^regex:/i.test(trimmed)) {
    const val = trimmed.slice("regex:".length).trim();
    try {
      const reg = new RegExp(val);
      return { type: "regex", raw: trimmed, pattern: reg };
    } catch (e: any) {
      throw new Error("Invalid regex in goal condition: " + e.message);
    }
  }

  if (/^eval:/i.test(trimmed)) {
    const expr = trimmed.slice("eval:".length).trim();
    return { type: "eval", raw: trimmed, expr };
  }

  if (/^judge:/i.test(trimmed)) {
    const prompt = trimmed.slice("judge:".length).trim();
    return { type: "judge", raw: trimmed, judgePrompt: prompt };
  }

  return { type: "contains", raw: trimmed, pattern: trimmed };
}

export function evaluateGoalPredicate(
  predicate: string | GoalCondition,
  result: { output?: string; exitCode?: number } | string,
  exitCode?: number
): boolean {
  let condition: GoalCondition;
  if (typeof predicate === "string") {
    condition = parseGoalCondition(predicate);
  } else {
    condition = predicate;
  }

  let outputText = "";
  let actualExitCode = exitCode !== undefined ? exitCode : 0;

  if (typeof result === "string") {
    outputText = result;
  } else if (result && typeof result === "object") {
    outputText = result.output || "";
    if (result.exitCode !== undefined) {
      actualExitCode = result.exitCode;
    }
  }

  switch (condition.type) {
    case "exit":
      return actualExitCode === condition.targetCode;
    case "contains":
      if (!condition.pattern) return false;
      return outputText.includes(String(condition.pattern));
    case "regex": {
      if (!condition.pattern) return false;
      const reg = typeof condition.pattern === "string" ? new RegExp(condition.pattern) : condition.pattern;
      return reg.test(outputText);
    }
    case "eval":
      if (!condition.expr) return false;
      try {
        const fn = new Function("output", "exitCode", "return Boolean(" + condition.expr + ");");
        return fn(outputText, actualExitCode);
      } catch {
        return false;
      }
    case "judge": {
      const lower = outputText.toLowerCase();
      return lower.includes("pass") || lower.includes("success") || lower.includes("ok") || lower.includes("completed");
    }
    default:
      return false;
  }
}

export const evaluateGoalCondition = evaluateGoalPredicate;
/**
 * LoopController manages interval loops and goal iterations.
 */
export class LoopController {
  private state: LoopState | null = null;
  private timerHandle: any = null;
  private onTickCallback?: (iteration: number) => Promise<void> | void;

  getState(): LoopState | null {
    return this.state ? { ...this.state } : null;
  }

  startIntervalLoop(options: {
    id?: string;
    prompt: string;
    intervalMs: number;
    maxIterations?: number;
    onTick?: (iteration: number) => Promise<void> | void;
  }): LoopState {
    this.stop();

    const maxIterations = Math.min(options.maxIterations ?? MAX_ITERATIONS_HARD_CAP, MAX_ITERATIONS_HARD_CAP);
    this.state = {
      id: options.id || "loop-" + Date.now(),
      mode: "interval",
      prompt: options.prompt,
      intervalMs: options.intervalMs,
      iteration: 0,
      maxIterations,
      consecutiveFailures: 0,
      status: "RUNNING",
      startedAt: Date.now(),
    };
    this.onTickCallback = options.onTick;

    return { ...this.state };
  }

  startGoalLoop(options: {
    id?: string;
    prompt: string;
    condition: string | GoalCondition;
    maxIterations?: number;
  }): LoopState {
    this.stop();

    const condition =
      typeof options.condition === "string"
        ? parseGoalCondition(options.condition)
        : options.condition;

    const maxIterations = Math.min(options.maxIterations ?? 5, MAX_ITERATIONS_HARD_CAP);

    this.state = {
      id: options.id || "goal-" + Date.now(),
      mode: "goal",
      prompt: options.prompt,
      condition,
      iteration: 0,
      maxIterations,
      consecutiveFailures: 0,
      status: "RUNNING",
      startedAt: Date.now(),
    };

    return { ...this.state };
  }

  recordGoalAttempt(result: { output: string; exitCode?: number }): {
    satisfied: boolean;
    continueLoop: boolean;
    state: LoopState;
  } {
    if (!this.state || this.state.mode !== "goal" || this.state.status !== "RUNNING") {
      throw new Error("No active goal loop running");
    }

    this.state.iteration++;
    this.state.lastOutput = result.output;
    this.state.lastExitCode = result.exitCode;

    const satisfied = evaluateGoalPredicate(this.state.condition!, result);

    if (satisfied) {
      this.state.status = "SATISFIED";
      this.state.consecutiveFailures = 0;
      this.state.completedAt = Date.now();
      return { satisfied: true, continueLoop: false, state: { ...this.state } };
    }

    this.state.consecutiveFailures++;

    if (this.state.consecutiveFailures >= CONSECUTIVE_FAILURES_ABORT_THRESHOLD) {
      this.state.status = "FAILED";
      this.state.failureReason = "Auto-aborted: " + this.state.consecutiveFailures + " consecutive failures";
      this.state.completedAt = Date.now();
      return { satisfied: false, continueLoop: false, state: { ...this.state } };
    }

    if (this.state.iteration >= this.state.maxIterations) {
      this.state.status = "EXHAUSTED";
      this.state.failureReason = "Max iterations (" + this.state.maxIterations + ") exceeded without satisfying goal";
      this.state.completedAt = Date.now();
      return { satisfied: false, continueLoop: false, state: { ...this.state } };
    }

    return { satisfied: false, continueLoop: true, state: { ...this.state } };
  }

  recordFailure(reason?: string): { autoAborted: boolean; state: LoopState } {
    if (!this.state || this.state.status !== "RUNNING") {
      throw new Error("No active loop running");
    }

    this.state.consecutiveFailures++;
    if (this.state.consecutiveFailures >= CONSECUTIVE_FAILURES_ABORT_THRESHOLD) {
      this.state.status = "FAILED";
      this.state.failureReason = reason || "Auto-aborted: " + this.state.consecutiveFailures + " consecutive failures";
      this.state.completedAt = Date.now();
      this.clearTimer();
      return { autoAborted: true, state: { ...this.state } };
    }

    return { autoAborted: false, state: { ...this.state } };
  }

  recordSuccess(): void {
    if (this.state) {
      this.state.consecutiveFailures = 0;
    }
  }

  stop(): LoopState | null {
    this.clearTimer();
    if (this.state && this.state.status === "RUNNING") {
      this.state.status = "STOPPED";
      this.state.completedAt = Date.now();
      return { ...this.state };
    }
    return this.state ? { ...this.state } : null;
  }

  private clearTimer(): void {
    if (this.timerHandle) {
      clearInterval(this.timerHandle);
      clearTimeout(this.timerHandle);
      this.timerHandle = null;
    }
  }
}

export class LoopControllerRegistry {
  private loops = new Map<string, LoopController>();

  registerLoop(stateOrCtrl: LoopController | LoopState): LoopController {
    if (stateOrCtrl instanceof LoopController) {
      const id = stateOrCtrl.getState()?.id || "loop-" + Date.now();
      this.loops.set(id, stateOrCtrl);
      return stateOrCtrl;
    } else {
      const ctrl = new LoopController();
      if (stateOrCtrl.mode === "interval") {
        ctrl.startIntervalLoop({
          id: stateOrCtrl.id,
          prompt: stateOrCtrl.prompt,
          intervalMs: stateOrCtrl.intervalMs || 10000,
          maxIterations: stateOrCtrl.maxIterations,
        });
      } else {
        ctrl.startGoalLoop({
          id: stateOrCtrl.id,
          prompt: stateOrCtrl.prompt,
          condition: stateOrCtrl.condition || "exit:0",
          maxIterations: stateOrCtrl.maxIterations,
        });
      }
      this.loops.set(stateOrCtrl.id, ctrl);
      return ctrl;
    }
  }

  getLoop(id: string): LoopState | undefined {
    return this.loops.get(id)?.getState() || undefined;
  }

  getController(id: string): LoopController | undefined {
    return this.loops.get(id);
  }

  listLoops(): LoopState[] {
    const list: LoopState[] = [];
    for (const ctrl of this.loops.values()) {
      const s = ctrl.getState();
      if (s) list.push(s);
    }
    return list;
  }

  stopLoop(id: string): boolean {
    const ctrl = this.loops.get(id);
    if (ctrl) {
      ctrl.stop();
      return true;
    }
    return false;
  }

  stopAll(): number {
    let count = 0;
    for (const ctrl of this.loops.values()) {
      if (ctrl.getState()?.status === "RUNNING") {
        ctrl.stop();
        count++;
      }
    }
    return count;
  }
}
