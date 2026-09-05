import {
  allocateWorktree,
  collectWorktreeDiff,
  releaseWorktree,
  listAllocatedWorktrees,
  getWorktreeBaseDir,
} from "../worktree-manager";
import * as path from "node:path";

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

const root = path.resolve(__dirname, "../../../../..");

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

console.log(`\nworktree-manager: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
