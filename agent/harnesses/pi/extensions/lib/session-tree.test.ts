import { addCheckpoint, findCheckpoint, renderCheckpointTree, CheckpointStore } from "../session-tree";

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

console.log(`\nsession-tree: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
