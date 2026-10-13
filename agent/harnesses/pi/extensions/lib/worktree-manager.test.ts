import {
  allocateWorktree,
  collectWorktreeDiff,
  releaseWorktree,
  listAllocatedWorktrees,
  getWorktreeBaseDir,
} from "../worktree-manager";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { spawnSync } from "node:child_process";

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

// allocateWorktree/getWorktreeBaseDir create `<root>/.git/pi-worktrees`. In a
// linked git worktree (every swarm mission worktree) `.git` is a FILE (gitdir
// pointer), so using the checkout's own repo root would `mkdir .git/...` ->
// ENOTDIR. Use an isolated temp repo with a real `.git` directory so this test
// passes both in the main checkout and inside mission worktrees
// (feedback_arg_array_over_shell_and_worktree_test_env). Previously tests 1-5
// used `path.resolve(__dirname, "../../../../..")` and failed in every worktree;
// the old directory-mode `bun test` masked that unhandled error, the
// single-file gate (test-pi-extensions.sh) surfaces it.
const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-wt-root-"));
try {
  spawnSync("git", ["init", "-q"], { cwd: root });
  spawnSync("git", ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "--allow-empty", "-qm", "base"], { cwd: root });

  // 1. getWorktreeBaseDir
  const baseDir = getWorktreeBaseDir(root);
  check("getWorktreeBaseDir points to .git/pi-worktrees", baseDir.endsWith(path.join(".git", "pi-worktrees")));

  // 2. allocateWorktree
  const testTaskId = `unit-test-${Date.now()}`;
  const alloc = allocateWorktree(root, testTaskId);
  check("allocateWorktree succeeds", alloc.success, alloc.error);
  check("allocateWorktree creates worktreePath", alloc.worktreePath.includes(testTaskId));

  // 3. listAllocatedWorktrees
  const list = listAllocatedWorktrees(root);
  check("listAllocatedWorktrees includes newly created worktree", list.some((p) => p.includes(testTaskId)));

  // 4. collectWorktreeDiff
  const diffRes = collectWorktreeDiff(alloc.worktreePath);
  check("collectWorktreeDiff executes without throwing", Array.isArray(diffRes.files));

  // 5. releaseWorktree
  const rel = releaseWorktree(root, alloc.worktreePath, alloc.branchName);
  check("releaseWorktree succeeds", rel.success, rel.error);

  const afterList = listAllocatedWorktrees(root);
  check("worktree removed from list", !afterList.some((p) => p.includes(testTaskId)));
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}

// 6. L5 regression: a malicious baseRef must never reach the shell. Uses an
// isolated temp git repo (real .git directory). With spawnSync arg arrays an
// injected baseRef is a literal (invalid) ref -> allocate fails and NO
// shell side-effect file is created.
const tmpRepo = fs.mkdtempSync(path.join(os.tmpdir(), "pi-wt-inject-"));
try {
  spawnSync("git", ["init", "-q"], { cwd: tmpRepo });
  spawnSync("git", ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "--allow-empty", "-qm", "base"], { cwd: tmpRepo });
  const sentinel = path.join(tmpRepo, `pwned-${Date.now()}`);
  const injected = allocateWorktree(tmpRepo, `inject-${Date.now()}`, `HEAD"; touch "${sentinel}`);
  check("injected baseRef does not execute a shell side-effect (no sentinel file)", !fs.existsSync(sentinel));
  check("injected baseRef is treated as an invalid ref (allocate fails, not a crash)", injected.success === false);
  // A benign baseRef still works via the array path.
  const okAlloc = allocateWorktree(tmpRepo, `ok-${Date.now()}`, "HEAD");
  check("benign HEAD baseRef allocates successfully via spawnSync arg array", okAlloc.success === true);
} finally {
  fs.rmSync(tmpRepo, { recursive: true, force: true });
}

console.log(`\nworktree-manager: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
