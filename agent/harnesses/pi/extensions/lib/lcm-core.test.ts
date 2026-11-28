import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  ImmutableLcmStore,
  SubtaskStackMachine,
  escalateCompact,
  utf8SafeTruncate,
} from "./lcm-core";

let pass = 0;
let fail = 0;
function check(name: string, cond: boolean, detail?: string) {
  if (cond) pass++;
  else {
    fail++;
    console.error(`FAIL: ${name}${detail ? ` (${detail})` : ""}`);
  }
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "lcm-core-test-"));
try {
  const store = new ImmutableLcmStore("test-sess", tmp);
  const r1 = store.append("diag-log", "ERROR pkg/a.go:42: undefined foo\nnoise line 1\nnoise line 2");
  check("ImmutableLcmStore assigns lcm-<hex> id", /^lcm-[0-9a-f]{10}$/.test(r1.id));

  const dirMode = fs.statSync(store.storeDir).mode & 0o777;
  const fileMode = fs.statSync(store.storeFile).mode & 0o777;
  check("ImmutableLcmStore uses 0700 dir and 0600 file permissions", dirMode === 0o700 && fileMode === 0o600);

  const got = store.getById(r1.id);
  check("getById returns exact verbatim content", got?.content === r1.content);

  const hits = store.search("undefined foo", 5);
  check("search locates archived record cleanly", hits.length === 1 && hits[0].id === r1.id);

  // Escalating convergence levels 1 -> 2 -> 3
  const lv1 = escalateCompact("short line", 100, r1.id);
  check("escalateCompact level 1 keeps short text untouched", lv1.level === 1 && lv1.text === "short line");

  const big = [
    "# Summary",
    "ERROR main.go:10: failure A",
    ...Array.from({ length: 20 }, (_, i) => `filler debug line number ${i} without signal`),
  ].join("\n");
  const lv2 = escalateCompact(big, 220, r1.id);
  check("escalateCompact level 2 keeps structural lines and pointer", lv2.level === 2 && lv2.text.includes("ERROR main.go:10") && lv2.text.includes(r1.id));

  const huge = "日本語テスト文字列".repeat(80);
  const lv3 = escalateCompact(huge, 140, r1.id);
  check("escalateCompact level 3 fits within budget + has no U+FFFD", lv3.level === 3 && Buffer.byteLength(lv3.text, "utf-8") <= 140 && !lv3.text.includes("\uFFFD"));
  check("utf8SafeTruncate avoids splitting multi-byte codepoints", !utf8SafeTruncate("あいうえお", 5).includes("\uFFFD"));

  // Subtask Stack Machine push / nested pop / collapse
  const stack = new SubtaskStackMachine(store);
  stack.push("outer-task", 1);
  stack.push("inner-probe", 2);
  const innerPop = stack.pop(4, "inner ok", "raw inner transcript");
  check("inner pop creates CollapsedSpan [2..4]", Boolean(innerPop && innerPop.startIndex === 2 && innerPop.endIndex === 4));

  const messages = ["sys", "m1", "inner1", "inner2", "m4-active"];
  const afterInner = stack.applyCollapsedSpans(messages, (s) => `COLLAPSED(${s.name}:${s.pointerId})`);
  check(
    "applyCollapsedSpans replaces finalized span while keeping active tail",
    afterInner.length === 4 && afterInner[0] === "sys" && afterInner[1] === "m1" && afterInner[2].startsWith("COLLAPSED(inner-probe:") && afterInner[3] === "m4-active",
    JSON.stringify(afterInner),
  );

  const outerPop = stack.pop(5, "outer summary");
  check("outer pop subsumes inner span", Boolean(outerPop && stack.getCollapsedSpans().length === 1));
  const afterOuter = stack.applyCollapsedSpans(messages, (s) => `COLLAPSED(${s.name})`);
  check("outer collapsed span cleanly replaces [1..5]", afterOuter.length === 2 && afterOuter[0] === "sys" && afterOuter[1] === "COLLAPSED(outer-task)");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}

console.log(`lcm-core: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
