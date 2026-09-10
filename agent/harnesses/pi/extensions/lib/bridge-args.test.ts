import { buildClaudeArgs } from "../bridge-claude";
import { buildCodexArgs } from "../bridge-codex";

let pass = 0;
let fail = 0;
function check(desc: string, ok: boolean) {
  if (ok) {
    console.log(`ok: ${desc}`);
    pass++;
  } else {
    console.log(`FAIL: ${desc}`);
    fail++;
  }
}

// L1 regression: the prompt must be separated from flags by `--` so a
// dash-leading prompt is not misparsed as a CLI option.

// --- claude ---
const c = buildClaudeArgs({ prompt: "--help me refactor", model: "sonnet" });
check("claude args start with --print", c[0] === "--print");
check("claude args include --model sonnet", c.includes("--model") && c[c.indexOf("--model") + 1] === "sonnet");
check("claude args end with -- then the prompt", c[c.length - 2] === "--" && c[c.length - 1] === "--help me refactor");
check("claude places exactly one -- separator immediately before the prompt",
  c.filter((a) => a === "--").length === 1 && c.indexOf("--") === c.length - 2);
// default skip-perms on
check("claude default includes --dangerously-skip-permissions", c.includes("--dangerously-skip-permissions"));
const cNoSkip = buildClaudeArgs({ prompt: "hi", dangerouslySkipPermissions: false });
check("claude skip-perms=false omits the flag", !cNoSkip.includes("--dangerously-skip-permissions"));
check("claude benign prompt still separated by --", cNoSkip[cNoSkip.length - 2] === "--" && cNoSkip[cNoSkip.length - 1] === "hi");

// --- codex ---
const x = buildCodexArgs({ prompt: "-v explain", model: "o3", sandbox: "read-only", search: true }, "/work/dir");
check("codex args start with exec", x[0] === "exec");
check("codex args include -m o3", x.includes("-m") && x[x.indexOf("-m") + 1] === "o3");
check("codex args include -s read-only", x.includes("-s") && x[x.indexOf("-s") + 1] === "read-only");
check("codex args include --search", x.includes("--search"));
check("codex args include -C /work/dir", x.includes("-C") && x[x.indexOf("-C") + 1] === "/work/dir");
check("codex args end with -- then the prompt", x[x.length - 2] === "--" && x[x.length - 1] === "-v explain");
check("codex places exactly one -- separator immediately before the prompt",
  x.filter((a) => a === "--").length === 1 && x.indexOf("--") === x.length - 2);

console.log(`\nbridge-args: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
