import { buildHelixCommand } from "../helix-bridge";

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

// 1. Direct Helix command
const cmdDirect = buildHelixCommand("main.go", 42, false);
check("Direct cmd is hx", cmdDirect.cmd === "hx");
check("Direct target is main.go:42", cmdDirect.args[0] === "main.go:42");

// 2. Direct without line
const cmdDirectNoLine = buildHelixCommand("README.md", undefined, false);
check("Direct target without line", cmdDirectNoLine.args[0] === "README.md");

// 3. Tmux command
const cmdTmux = buildHelixCommand("main.go", 42, true);
check("Tmux cmd is tmux", cmdTmux.cmd === "tmux");
check("Tmux args has split-window", cmdTmux.args.includes("split-window"));
check("Tmux args includes hx target", cmdTmux.args.some(a => a.includes("hx \"main.go:42\"")));

console.log(`\nhelix-bridge: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
