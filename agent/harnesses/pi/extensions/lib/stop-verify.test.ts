import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { computeVerifyTargets, parseGitStatusPaths, runStopVerify } from "../stop-verify";

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

// 1. parseGitStatusPaths
const root = "/repo";
const gs = parseGitStatusPaths(
  " M src/a.go\n?? new/b.json\nR  old/c.txt -> new/c.txt\nA  d.zsh\n\n",
  root,
);
check("parseGitStatus: modified file absolutized", gs.includes(path.join(root, "src/a.go")));
check("parseGitStatus: untracked file", gs.includes(path.join(root, "new/b.json")));
check("parseGitStatus: rename uses NEW path", gs.includes(path.join(root, "new/c.txt")) && !gs.includes(path.join(root, "old/c.txt")));
check("parseGitStatus: added file", gs.includes(path.join(root, "d.zsh")));
check("parseGitStatus: blank lines skipped", gs.length === 4);
check("parseGitStatus: empty input → []", parseGitStatusPaths("", root).length === 0);

// 2. computeVerifyTargets (session-edited ∩ git-changed)
const edited = [path.join(root, "a.go"), path.join(root, "b.json"), path.join(root, "unrelated.md")];
const changed = [path.join(root, "a.go"), path.join(root, "b.json"), path.join(root, "other-dirty.go")];
const targets = computeVerifyTargets(edited, changed);
check("targets: intersection only (edited ∩ changed)", targets.length === 2 && targets.includes(path.join(root, "a.go")) && targets.includes(path.join(root, "b.json")));
check("targets: unrelated edited (not dirty) excluded", !targets.includes(path.join(root, "unrelated.md")));
check("targets: unrelated dirty (not edited) excluded", !targets.includes(path.join(root, "other-dirty.go")));
check("targets: dedups repeated edited", computeVerifyTargets([path.join(root, "a.go"), path.join(root, "a.go")], [path.join(root, "a.go")]).length === 1);
check("targets: empty edited → []", computeVerifyTargets([], changed).length === 0);
check("targets: empty changed → []", computeVerifyTargets(edited, []).length === 0);

// 3. runStopVerify e2e (via shared stop-verify-lint.sh)
const scriptsDir = path.resolve(import.meta.dir, "../../../../skills/swarm-implement/scripts");
const helper = path.join(scriptsDir, "stop-verify-lint.sh");
if (fs.existsSync(helper)) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stop-verify-e2e-"));
  try {
    const okJson = path.join(tmp, "ok.json");
    const badJson = path.join(tmp, "bad.json");
    const okZsh = path.join(tmp, "ok.zsh");
    const badZsh = path.join(tmp, "bad.zsh");
    fs.writeFileSync(okJson, '{"a":1,"b":[2,3]}');
    fs.writeFileSync(badJson, '{"a":,}');
    fs.writeFileSync(okZsh, "echo hi\n");
    fs.writeFileSync(badZsh, "if true; then\n echo x\n"); // missing fi

    // 3a. empty targets → clean, no infra
    const empty = runStopVerify(scriptsDir, tmp, []);
    check("runStopVerify: empty targets → clean", empty.errors === "" && empty.infra === false);

    // 3b. all-clean targets → no errors
    const clean = runStopVerify(scriptsDir, tmp, [okJson, okZsh]);
    check("runStopVerify: clean files → no errors, no infra", clean.errors === "" && clean.infra === false);

    // 3c. bad json → error reported
    const badJ = runStopVerify(scriptsDir, tmp, [badJson]);
    check("runStopVerify: invalid JSON → error reported", badJ.infra === false && badJ.errors.includes("JSON invalid") && badJ.errors.includes("bad.json"));

    // 3d. bad zsh → error reported (only if zsh available; else skipped→clean)
    const zshAvail = (() => {
      try {
        const r = spawnSync("zsh", ["-c", "true"], { encoding: "utf-8" });
        return !r.error && r.status === 0;
      } catch {
        return false;
      }
    })();
    const badZ = runStopVerify(scriptsDir, tmp, [badZsh]);
    if (zshAvail) {
      check("runStopVerify: invalid zsh → error reported", badZ.infra === false && badZ.errors.includes("zsh syntax error"));
    } else {
      check("runStopVerify: zsh unavailable → skipped (clean)", badZ.infra === false && badZ.errors === "");
    }

    // 3e. mixed: bad among good → still reports the bad one
    const mixed = runStopVerify(scriptsDir, tmp, [okJson, badJson, okZsh]);
    check("runStopVerify: mixed → reports the invalid file", mixed.infra === false && mixed.errors.includes("bad.json"));

    // 3f. infra: missing scripts dir → infra=true, no errors surfaced
    const infra = runStopVerify(path.join(tmp, "nonexistent-scripts"), tmp, [badJson]);
    check("runStopVerify: missing helper dir → infra=true", infra.infra === true && infra.errors === "");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
} else {
  console.log("skip: runStopVerify e2e (stop-verify-lint.sh not found)");
}

console.log(`\nstop-verify: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
