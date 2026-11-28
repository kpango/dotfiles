import * as path from "node:path";
import {
  CasUndoStore,
  annotateFileWithHashlines,
  applyEditToContent,
  computeFileSnapshotTag,
  createHashlineState,
  findUniqueRebasedLine,
  lineHashTag,
  unwrapHashlinePath,
} from "./hashline-core";

let pass = 0;
let fail = 0;
function check(name: string, cond: boolean, detail?: string) {
  if (cond) {
    pass++;
  } else {
    fail++;
    console.error(`FAIL: ${name}${detail ? ` (${detail})` : ""}`);
  }
}

const state = createHashlineState();
const sample = "alpha\nbeta\ngamma";
const ann = annotateFileWithHashlines("/tmp/sample.txt", sample, state, 1);

check("annotateFileWithHashlines prepends [path#TAG]", ann.text.startsWith(`[${"/tmp/sample.txt"}#${ann.snapshotTag}]\n`));
check("annotateFileWithHashlines numbers lines with 4-hex tags", ann.text.includes(`2#${lineHashTag("beta")}|beta`));
check("unwrapHashlinePath removes [path#TAG]", unwrapHashlinePath("/tmp/sample.txt#a1b2") === "/tmp/sample.txt#a1b2");
check("unwrapHashlinePath unwraps bracketed header", unwrapHashlinePath("[/tmp/sample.txt#a1b2]") === "/tmp/sample.txt");

// Hashline replace edit
const betaTag = lineHashTag("beta");
const res = applyEditToContent(
  "/tmp/sample.txt",
  sample,
  {
    path: "/tmp/sample.txt",
    file_tag: ann.snapshotTag,
    edits: [{ anchor: `2#${betaTag}`, op: "replace", content: "BETA_UPDATED" }],
  },
  state,
);
check("hashline replace updates target line", res.changed && res.nextContent === "alpha\nBETA_UPDATED\ngamma");
check("hashline diff preview includes + line", res.diffPreview.includes("+ 2#"));

// Duplicate edit guard on unchanged file
let dupThrew = false;
try {
  applyEditToContent(
    "/tmp/sample.txt",
    res.nextContent,
    {
      path: "/tmp/sample.txt",
      file_tag: ann.snapshotTag,
      edits: [{ anchor: `2#${betaTag}`, op: "replace", content: "BETA_UPDATED" }],
    },
    state,
  );
} catch (e) {
  dupThrew = String(e).includes("E_DUPLICATE_EDIT");
}
check("E_DUPLICATE_EDIT fires on identical repeat payload", dupThrew);

// Stale snapshot guard
let staleThrew = false;
try {
  applyEditToContent(
    "/tmp/sample.txt",
    res.nextContent,
    {
      path: "/tmp/sample.txt",
      file_tag: "0000",
      edits: [{ anchor: `1#${lineHashTag("alpha")}`, op: "replace", content: "x" }],
    },
    state,
  );
} catch (e) {
  staleThrew = String(e).includes("E_STALE_SNAPSHOT");
}
check("E_STALE_SNAPSHOT fires on snapshot mismatch", staleThrew);

// Unseen line guard
const state2 = createHashlineState();
annotateFileWithHashlines("/tmp/unseen.txt", "l1\nl2\nl3", state2, 1);
state2.seenLines.get(path.resolve("/tmp/unseen.txt"))!.delete(3);
let unseenThrew = false;
try {
  applyEditToContent(
    "/tmp/unseen.txt",
    "l1\nl2\nl3",
    {
      path: "/tmp/unseen.txt",
      edits: [{ anchor: `3#${lineHashTag("l3")}`, op: "delete" }],
    },
    state2,
  );
} catch (e) {
  unseenThrew = String(e).includes("E_UNSEEN_LINE");
}
check("E_UNSEEN_LINE rejects editing unread line", unseenThrew);

// Noop loop guard (3 consecutive noops)
const state3 = createHashlineState();
const noopContent = "one\ntwo";
annotateFileWithHashlines("/tmp/noop.txt", noopContent, state3, 1);
const noopInput = {
  path: "/tmp/noop.txt",
  edits: [{ anchor: `1#${lineHashTag("one")}`, op: "replace" as const, content: "one" }],
};
const r1 = applyEditToContent("/tmp/noop.txt", noopContent, noopInput, state3);
const r2 = applyEditToContent("/tmp/noop.txt", noopContent, noopInput, state3);
check("noop 1 and 2 warn without throwing", !r1.changed && !r2.changed && r2.diffPreview.includes("2/3"));
let noopThrew = false;
try {
  applyEditToContent("/tmp/noop.txt", noopContent, noopInput, state3);
} catch (e) {
  noopThrew = String(e).includes("E_NOOP_LOOP");
}
check("E_NOOP_LOOP fires on 3rd consecutive noop", noopThrew);

// Fallback exact-text edit + dialect normalization
const fb = applyEditToContent(
  "/tmp/fb.txt",
  "hello\nworld",
  { path: "/tmp/fb.txt", oldText: "world", newText: "```ts\r\npi\r\n```" },
  createHashlineState(),
);
check("exact fallback normalizes fenced CRLF dialect", fb.changed && fb.nextContent === "hello\npi");
check("snapshot tag changes on edit", computeFileSnapshotTag("hello\nworld") !== fb.snapshotTag);

// Unique hash auto-rebase + ambiguous fail-closed rejection
{
  const rbState = createHashlineState();
  annotateFileWithHashlines("/tmp/rebase.txt", "top\ntarget_unique\nbottom", rbState, 1);
  const shifted = "inserted_1\ninserted_2\ntop\ntarget_unique\nbottom";
  const rbRes = applyEditToContent(
    "/tmp/rebase.txt",
    shifted,
    { path: "/tmp/rebase.txt", edits: [{ anchor: `2#${lineHashTag("target_unique")}`, op: "replace", content: "target_done" }] },
    rbState,
  );
  check("unique hash auto-rebases drifted line L2->L4", rbRes.changed && rbRes.nextContent.includes("target_done") && rbRes.diffPreview.includes("[rebased L2->L4]"));

  const dupLines = ["dup", "x", "dup", "y"];
  check("findUniqueRebasedLine fails closed when >=2 matches in window", findUniqueRebasedLine(dupLines, 1, lineHashTag("dup"), 10) === null);
}

// CAS undo stack
{
  const cas = new CasUndoStore(2);
  cas.push("/tmp/u.txt", "v1");
  cas.push("/tmp/u.txt", "v2");
  cas.push("/tmp/u.txt", "v3");
  check("CasUndoStore enforces maxEntries cap", cas.list().length === 2);
  check("CasUndoStore pops latest snapshot v3 then v2", cas.pop("/tmp/u.txt")?.content === "v3" && cas.pop("/tmp/u.txt")?.content === "v2");
}

console.log(`hashline-core: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
