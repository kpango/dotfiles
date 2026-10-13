import { addCheckpoint, findCheckpoint, renderCheckpointTree, CheckpointStore, saveStore, loadStore, getWorktreeStorePath } from "../session-tree";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { execSync } from "node:child_process";

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

const store: CheckpointStore = {
  activeId: null,
  checkpoints: [],
};

// 1. Add checkpoint
const cp1 = addCheckpoint(store, "initial-state", "abcdef1234567890", "main", "base commit");
check("addCheckpoint assigns id", Boolean(cp1.id));
check("addCheckpoint sets activeId", store.activeId === cp1.id);
check("addCheckpoint tracks gitSha", cp1.gitSha === "abcdef1234567890");

// 2. Add second checkpoint (child)
const cp2 = addCheckpoint(store, "after-refactor", "123456abcdef7890", "feature-branch", "extracted helper");
check("Second checkpoint parent is cp1", cp2.parentId === cp1.id);
check("Store tracks 2 checkpoints", store.checkpoints.length === 2);

// 3. Find checkpoint
const foundByName = findCheckpoint(store, "initial-state");
check("findCheckpoint by name", foundByName?.id === cp1.id);

const foundById = findCheckpoint(store, cp2.id);
check("findCheckpoint by id", foundById?.name === "after-refactor");

// 4. Render tree
const rendered = renderCheckpointTree(store);
check("renderCheckpointTree contains initial-state", rendered.includes("initial-state"));
check("renderCheckpointTree marks active checkpoint", rendered.includes("📍 (current)"));

// 5. Atomic checkpoint store persistence (cycle3 L5): saveStore must write via
// temp+rename so a torn write can never wipe checkpoint history, and no stray
// .tmp file may remain after a successful save.
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-cptree-test-"));
try {
  execSync("git init -q", { cwd: tmpDir });
  const roundtrip: CheckpointStore = { activeId: null, checkpoints: [] };
  addCheckpoint(roundtrip, "one", "aaaaaaaaaaaa", "main");
  const b = addCheckpoint(roundtrip, "two", "bbbbbbbbbbbb", "main");
  saveStore(tmpDir, roundtrip);

  const storePath = getWorktreeStorePath(tmpDir);
  check("saveStore persists to resolved git-dir path", fs.existsSync(storePath));
  check("no stray .tmp file remains after atomic rename",
    // writeFileAtomic names its temp `.<basename>.<pid>.<ts>.tmp` (leading dot);
    // match any leftover temp for this store, not a specific prefix.
    fs.readdirSync(path.dirname(storePath)).every((f) => !(f.includes("pi-checkpoints.json") && f.endsWith(".tmp"))));

  const reloaded = loadStore(tmpDir);
  check("loadStore round-trips both checkpoints", reloaded.checkpoints.length === 2);
  check("loadStore preserves activeId (last added)", reloaded.activeId === b.id);
  check("persisted store is valid JSON", (() => { try { JSON.parse(fs.readFileSync(storePath, "utf-8")); return true; } catch { return false; } })());

  // A second save must not leave the store empty/torn (simulate concurrent-safe overwrite).
  const second: CheckpointStore = { activeId: null, checkpoints: [] };
  addCheckpoint(second, "three", "cccccccccccc", "main");
  saveStore(tmpDir, second);
  check("overwrite save keeps a complete store (not wiped)", loadStore(tmpDir).checkpoints.length === 1);
} finally {
  fs.rmSync(tmpDir, { recursive: true, force: true });
}

console.log(`\nsession-tree: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
