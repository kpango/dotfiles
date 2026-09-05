/**
 * Unit tests for swarm-relay cross-session messaging extension
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  formatRelayMessage,
  parseRelayMessage,
  registerActiveSession,
  findSiblingSessions,
  appendRelayEvent,
  readRecentRelayEvents,
} from "../swarm-relay";

function assert(condition: boolean, msg: string) {
  if (!condition) {
    console.error(`FAIL: ${msg}`);
    process.exit(1);
  }
  console.log(`ok: ${msg}`);
}

async function main() {
  console.log("=== Running swarm-relay tests ===");

  // 1. formatRelayMessage tests
  const msg1 = formatRelayMessage("init", { mission: "test-mission", repo: "/tmp/repo", scale: "quick" });
  assert(
    msg1 === "[swarm-relay:init] mission=test-mission repo=/tmp/repo scale=quick",
    "formatRelayMessage generates valid init message"
  );

  const msg2 = formatRelayMessage("precommit-check", { mission: "m1", repo: "/a/b", phase: "execute" });
  assert(
    msg2 === "[swarm-relay:precommit-check] mission=m1 repo=/a/b phase=execute",
    "formatRelayMessage generates valid precommit-check message"
  );

  let throwsDelimiter = false;
  try {
    formatRelayMessage("init", { invalid: "has space" });
  } catch {
    throwsDelimiter = true;
  }
  assert(throwsDelimiter, "formatRelayMessage throws on space in field value");

  let throwsUnknown = false;
  try {
    formatRelayMessage("invalid-event" as any, { k: "v" });
  } catch {
    throwsUnknown = true;
  }
  assert(throwsUnknown, "formatRelayMessage throws on invalid event type");

  // 2. parseRelayMessage tests
  const parsed1 = parseRelayMessage("[swarm-relay:init] mission=test-mission repo=/tmp/repo scale=quick");
  assert(parsed1 !== null, "parseRelayMessage parses valid message");
  assert(parsed1?.event === "init", "parseRelayMessage extracts event");
  assert(parsed1?.fields["mission"] === "test-mission", "parseRelayMessage extracts fields");
  assert(parsed1?.fields["scale"] === "quick", "parseRelayMessage extracts scale");

  const parsedInvalid = parseRelayMessage("random unstructured log");
  assert(parsedInvalid === null, "parseRelayMessage returns null on invalid line");

  // 3. registerActiveSession & findSiblingSessions tests
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-relay-test-"));
  try {
    const s1 = {
      sessionId: "s1",
      pid: 1001,
      repo: "/home/kpango/repo-a",
      mission: "mission-1",
      updatedAt: Date.now(),
    };
    const s2 = {
      sessionId: "s2",
      pid: 1002,
      repo: "/home/kpango/repo-a/.git/pi-worktrees/wt-1",
      mission: "mission-2",
      updatedAt: Date.now(),
    };
    const s3 = {
      sessionId: "s3",
      pid: 1003,
      repo: "/home/kpango/repo-b",
      mission: "mission-3",
      updatedAt: Date.now(),
    };

    registerActiveSession(tmpDir, s1);
    registerActiveSession(tmpDir, s2);
    registerActiveSession(tmpDir, s3);

    const siblings = findSiblingSessions(tmpDir, "/home/kpango/repo-a", "s1");
    assert(siblings.length === 1, "findSiblingSessions finds concurrent worktree session");
    assert(siblings[0].sessionId === "s2", "findSiblingSessions excludes current session");

    // 4. appendRelayEvent & readRecentRelayEvents
    appendRelayEvent(tmpDir, formatRelayMessage("init", { mission: "m1", repo: "/home/kpango/repo-a" }));
    appendRelayEvent(tmpDir, formatRelayMessage("precommit-check", { mission: "m1", repo: "/home/kpango/repo-a", phase: "gate" }));

    const events = readRecentRelayEvents(tmpDir, "/home/kpango/repo-a", 60000);
    assert(events.length === 2, "readRecentRelayEvents retrieves logged events for repo");
    assert(events[1].event === "precommit-check", "readRecentRelayEvents parses event correctly");
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }

  console.log("\nswarm-relay: 11 passed, 0 failed");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
