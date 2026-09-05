import { formatHandoffMarkdown, HandoffData, buildHandoffExecutionCommand } from "../handoff";

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

const sampleData: HandoffData = {
  objective: "Implement parallel subagent pool",
  modifiedFiles: ["subagents.ts", "subagents.test.ts"],
  currentGitBranch: "feature/subagent-pool",
  currentGitSha: "7b8a9c0",
  nextSteps: ["Run test suite", "Verify sync"],
  notes: "Follow Vald Laws and zero intermediate symlink rule.",
};

// 1. Basic formatting
const md = formatHandoffMarkdown(sampleData, "file");
check("formatHandoffMarkdown contains objective", md.includes("Implement parallel subagent pool"));
check("formatHandoffMarkdown lists modified files", md.includes("subagents.ts"));
check("formatHandoffMarkdown includes notes", md.includes("Follow Vald Laws"));

// 2. Claude CLI handoff command
const claudeMd = formatHandoffMarkdown(sampleData, "claude");
check("formatHandoffMarkdown generates claude -p command", claudeMd.includes("claude -p"));

// 3. Antigravity CLI handoff command
const agyMd = formatHandoffMarkdown(sampleData, "agy");
check("formatHandoffMarkdown generates agy -p command", agyMd.includes("agy -p"));

// 4. buildHandoffExecutionCommand
const claudeCmd = buildHandoffExecutionCommand("claude", "Refactor models", ["models.json"]);
check("buildHandoffExecutionCommand claude binary", claudeCmd.bin === "claude");
check("buildHandoffExecutionCommand claude flag", claudeCmd.args[0] === "-p");

const codexCmd = buildHandoffExecutionCommand("codex", "Run bench");
check("buildHandoffExecutionCommand codex binary", codexCmd.bin === "codex");
check("buildHandoffExecutionCommand codex subcommand", codexCmd.args[0] === "exec");

console.log(`\nhandoff: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
