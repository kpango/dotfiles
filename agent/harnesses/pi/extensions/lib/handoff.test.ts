import { formatHandoffMarkdown, HandoffData, buildHandoffExecutionCommand, parsePorcelainPaths, shDisplayQuote } from "../handoff";

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
// L2 regression: codex prompt is separated from flags by `--`.
check("codex args place -- before the prompt", codexCmd.args[1] === "--" && codexCmd.args[2].startsWith("Resume task: Run bench"));
check("codex has exactly one -- separator", codexCmd.args.filter((a) => a === "--").length === 1);

// 5. L1 regression: parsePorcelainPaths handles quoted paths (spaces) and renames.
check("porcelain: quoted spaced path is unquoted",
  JSON.stringify(parsePorcelainPaths('M  "a b.txt"\n')) === JSON.stringify(["a b.txt"]));
check("porcelain: rename reports the NEW (dest) path",
  JSON.stringify(parsePorcelainPaths('R  old.txt -> new.txt\n')) === JSON.stringify(["new.txt"]));
check("porcelain: quoted rename reports unquoted new path",
  JSON.stringify(parsePorcelainPaths('R  "old a.txt" -> "new b.txt"\n')) === JSON.stringify(["new b.txt"]));
check("porcelain: untracked + staged + unstaged parsed by current path",
  JSON.stringify(parsePorcelainPaths('?? new.ts\n M mod.go\nA  added.rs\n')) === JSON.stringify(["new.ts", "mod.go", "added.rs"]));
check("porcelain: empty output -> empty list", parsePorcelainPaths("").length === 0);

// L1 regression: the displayed handoff CLI command must be copy-paste-safe.
// The old `includes(" ") ? "..." : a` left metacharacter args (no space)
// unquoted and double-quoted space args (which do not neutralize $(...) ).
check("shDisplayQuote leaves a bare shell-safe token unquoted", shDisplayQuote("exec") === "exec" && shDisplayQuote("-m") === "-m");
check("shDisplayQuote single-quotes a metacharacter arg (no space)", shDisplayQuote("fix$(x)") === "'fix$(x)'");
check("shDisplayQuote single-quotes a space arg", shDisplayQuote("a b") === "'a b'");
check("shDisplayQuote escapes an inner single quote", shDisplayQuote("it's") === "'it'\\''s'");
{
  const md = formatHandoffMarkdown(
    { objective: "fix$(touch pwn)", currentGitBranch: "main", currentGitSha: "abc", modifiedFiles: ["a b.ts"], nextSteps: [], notes: "" } as HandoffData,
    "codex"
  );
  const cmd = md.split("```bash")[1]?.split("```")[0] ?? "";
  check("handoff command wraps a $(...) objective in single quotes (inert)", cmd.includes("'Resume task: fix$(touch pwn)"));
}

console.log(`\nhandoff: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
