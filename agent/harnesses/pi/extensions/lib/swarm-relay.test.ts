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

    // L2 regression: a sibling repo whose path is a string-prefix of the target
    // (`/home/kpango/repo-a2` vs target `/home/kpango/repo-a`) must NOT match
    // (path-component boundary, consistent with findSiblingSessions).
    const boundaryDir = fs.mkdtempSync(path.join(os.tmpdir(), "relay-bound-"));
    try {
      appendRelayEvent(boundaryDir, formatRelayMessage("precommit-check", { mission: "m", repo: "/x/repo-a2" }));
      appendRelayEvent(boundaryDir, formatRelayMessage("precommit-check", { mission: "m", repo: "/x/repo-a/sub" }));
      appendRelayEvent(boundaryDir, formatRelayMessage("precommit-check", { mission: "m", repo: "/x/repo-a" }));
      const be = readRecentRelayEvents(boundaryDir, "/x/repo-a", 60000);
      const repos = be.map((e) => e.fields.repo).sort();
      assert(!repos.includes("/x/repo-a2"), "unrelated prefix sibling /x/repo-a2 is NOT matched");
      assert(repos.includes("/x/repo-a") && repos.includes("/x/repo-a/sub"),
        "exact repo and child subdir ARE matched");
      assert(be.length === 2, "exactly the exact + child events match (not the prefix sibling)");
    } finally {
      fs.rmSync(boundaryDir, { recursive: true, force: true });
    }

    // 5. Atomic registry write: no stray temp files remain, file stays valid JSON,
    //    and sequential registrations preserve prior sessions (no clobber).
    const atomicDir = fs.mkdtempSync(path.join(os.tmpdir(), "relay-atomic-"));
    try {
      registerActiveSession(atomicDir, { sessionId: "a1", pid: 111, repo: "/home/kpango/repo-x", mission: "m", updatedAt: Date.now() });
      registerActiveSession(atomicDir, { sessionId: "a2", pid: 222, repo: "/home/kpango/repo-x", mission: "m", updatedAt: Date.now() });
      const regFile = path.join(atomicDir, "active-sessions.json");
      const parsed = JSON.parse(fs.readFileSync(regFile, "utf-8"));
      assert(Array.isArray(parsed) && parsed.length === 2, "atomic write preserves both sequential registrations");
      const ids = parsed.map((s: any) => s.sessionId).sort();
      assert(ids[0] === "a1" && ids[1] === "a2", "atomic write does not clobber prior session entry");
      const stray = fs.readdirSync(atomicDir).filter((f) => f.includes(".tmp"));
      assert(stray.length === 0, "atomic write leaves no stray .tmp files");
    } finally {
      fs.rmSync(atomicDir, { recursive: true, force: true });
    }

    // 6. Bounded rotation: events.log is capped once it crosses the byte
    //    threshold, keeping a recent tail and still parsing after rotation.
    const rotDir = fs.mkdtempSync(path.join(os.tmpdir(), "relay-rot-"));
    try {
      // Write enough events to exceed the 1 MiB threshold (~71B/line -> need >14.7k).
      const rotCount = 20000;
      for (let i = 0; i < rotCount; i++) {
        appendRelayEvent(rotDir, formatRelayMessage("init", { mission: `m${i}`, repo: "/home/kpango/repo-rot" }));
      }
      const rotFile = path.join(rotDir, "events.log");
      const sizeAfter = fs.statSync(rotFile).size;
      assert(sizeAfter <= 1_048_576, "events.log stays within byte cap after rotation");
      const lineCount = fs.readFileSync(rotFile, "utf-8").split("\n").filter(Boolean).length;
      // The byte cap is the true bound; between rotations the tail regrows, so the
      // invariant is that rotation happened (far fewer than the 12000 appended)
      // and each rotation trims back to the keep-tail.
      assert(lineCount < rotCount && lineCount >= 2000, "rotation trims the log to a bounded recent tail");
      const stray = fs.readdirSync(rotDir).filter((f) => f.includes(".tmp"));
      assert(stray.length === 0, "rotation leaves no stray .tmp files");
      const recent = readRecentRelayEvents(rotDir, "/home/kpango/repo-rot", 600000);
      assert(recent.length > 0, "readRecentRelayEvents still parses rotated log");
    } finally {
      fs.rmSync(rotDir, { recursive: true, force: true });
    }
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }

  console.log("\nswarm-relay: 18 passed, 0 failed");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
