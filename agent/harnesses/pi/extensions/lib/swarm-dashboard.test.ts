import { parseFixPlan, renderDashboardText, FixPlanSummary } from "../swarm-dashboard";

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

// 1. parseFixPlan tests
const planSample = `
# Multi-Harness Intelligent Routing Mission

## Phase 3: Implementation
- [x] Task 1: Consolidate model routing
- [x] Task 2: Implement fallback chains
- [ ] Task 3: Add unit tests
- [ ] Task 4: Run verify.sh
`;

const summary = parseFixPlan(planSample);
check("parseFixPlan parses mission title", summary.missionTitle === "Multi-Harness Intelligent Routing Mission");
check("parseFixPlan parses current phase", summary.currentPhase?.includes("Implementation") ?? false);
check("parseFixPlan parses total tasks", summary.totalTasks === 4);
check("parseFixPlan parses completed tasks", summary.completedTasks === 2);
check("parseFixPlan task 1 is completed", summary.tasks[0].completed);
check("parseFixPlan task 3 is pending", !summary.tasks[2].completed);

// 2. renderDashboardText tests
const rendered = renderDashboardText(summary, ["/worktree/feature-1", "/worktree/feature-2"]);
check("renderDashboardText contains progress 50%", rendered.includes("50%"));
check("renderDashboardText lists worktrees", rendered.includes("/worktree/feature-1"));
check("renderDashboardText displays task queue", rendered.includes("Task 1: Consolidate model routing"));

console.log(`\nswarm-dashboard: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
