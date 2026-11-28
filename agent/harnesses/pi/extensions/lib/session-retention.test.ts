/**
 * lib/session-retention.ts のテスト。`bun test` の単一ファイル実行で動く PASS/FAIL カウンタ形式。
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { DEFAULT_SESSION_RETENTION_DAYS, pruneSessions, resolveRetentionDays, sessionProjectDirName } from "./session-retention";

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

const DAY = 24 * 60 * 60 * 1000;
const NOW = Date.UTC(2026, 10, 23);
const root = fs.mkdtempSync(path.join(os.tmpdir(), "session-retention-"));
const project = path.join(root, "-tmp-project");
fs.mkdirSync(project, { recursive: true });

function addSession(name: string, ageDays: number, bodyBytes = 100) {
  const file = path.join(project, `${name}.jsonl`);
  fs.writeFileSync(file, "x".repeat(bodyBytes));
  const sidecar = path.join(project, name);
  fs.mkdirSync(sidecar, { recursive: true });
  fs.writeFileSync(path.join(sidecar, "RedTests.jsonl"), "y".repeat(50));
  const lock = path.join(project, `.${name}.jsonl.lock.os`);
  fs.writeFileSync(lock, "");
  const t = new Date(NOW - ageDays * DAY);
  for (const p of [file, sidecar, path.join(sidecar, "RedTests.jsonl"), lock]) fs.utimesSync(p, t, t);
}

check("project dir: home-relative path", sessionProjectDirName("/home/u/go/src/x", "/home/u") === "-go-src-x");
check("project dir: outside home uses the absolute path", sessionProjectDirName("/tmp", "/home/u") === "-tmp");

try {
  addSession("2026-10-01_old", 40);
  addSession("2026-11-20_recent", 3);

  const dry = pruneSessions(root, { olderThanMs: 30 * DAY, now: NOW });
  check("dry run finds the old session", dry.targets.length === 1);
  check("dry run names the session", dry.targets[0]?.session === "2026-10-01_old.jsonl");
  check("dry run reports both jsonl and sidecar bytes", dry.freedBytes === 100 + 50);
  check("dry run keeps the file", fs.existsSync(path.join(project, "2026-10-01_old.jsonl")));
  check("dry run does not claim to be applied", dry.applied === false);

  const scoped = pruneSessions(root, { olderThanMs: 30 * DAY, now: NOW, projectDir: "-missing" });
  check("unknown project scope targets nothing", scoped.targets.length === 0);

  const applied = pruneSessions(root, { olderThanMs: 30 * DAY, now: NOW, apply: true });
  check("apply reports the target", applied.applied === true && applied.targets.length === 1);
  check("apply removes the jsonl", !fs.existsSync(path.join(project, "2026-10-01_old.jsonl")));
  check("apply removes the sidecar dir", !fs.existsSync(path.join(project, "2026-10-01_old")));
  check("apply removes the stale lock", !fs.existsSync(path.join(project, ".2026-10-01_old.jsonl.lock.os")));
  check("apply keeps the recent session", fs.existsSync(path.join(project, "2026-11-20_recent.jsonl")));
} finally {
  try { fs.rmSync(root, { recursive: true, force: true }); } catch { /* ignore */ }
}

// PI_SESSION_RETENTION_DAYS parsing: unset/invalid fall back to the default, 0/off disable.
{
  const d = DEFAULT_SESSION_RETENTION_DAYS;
  check("retention days: default is 30", d === 30);
  check("retention days: unset -> default", resolveRetentionDays(undefined) === d);
  check("retention days: blank -> default", resolveRetentionDays("   ") === d);
  check("retention days: 0 disables", resolveRetentionDays("0") === 0);
  check("retention days: off disables", resolveRetentionDays("OFF") === 0);
  check("retention days: numeric", resolveRetentionDays("14") === 14);
  check("retention days: floors fractions", resolveRetentionDays("7.9") === 7);
  check("retention days: invalid -> default", resolveRetentionDays("abc") === d);
  check("retention days: negative -> default", resolveRetentionDays("-3") === d);
}

console.log(`\nsession-retention: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
