/**
 * Swarm Relay Cross-Session Messaging & Coordination Extension for Pi Coding Agent
 *
 * Implements the cross-session messaging protocol defined in agent/skills/swarm-relay/SKILL.md:
 * - Message format: [swarm-relay:EVENT] key1=val1 key2=val2 ...
 * - Events: init, precommit-check, handoff, gate-done
 * - Session discovery & concurrency awareness to prevent git index/HEAD conflicts across sessions
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { writeFileAtomic } from "./lib/fs-atomic";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export type RelayEventType = "init" | "precommit-check" | "handoff" | "gate-done";

export interface RelayMessage {
  event: RelayEventType;
  fields: Record<string, string>;
  raw: string;
}

export interface RelaySessionInfo {
  sessionId: string;
  pid: number;
  repo: string;
  mission: string;
  scale?: string;
  updatedAt: number;
}

export const RESERVED_DELIMITERS = /[ \t\r\n|\[\]]/;

export function getRelayDir(): string {
  return path.join(os.homedir(), ".pi", "agent", "relay");
}

export function formatRelayMessage(
  event: RelayEventType,
  fields: Record<string, string>
): string {
  const allowedEvents: RelayEventType[] = ["init", "precommit-check", "handoff", "gate-done"];
  if (!allowedEvents.includes(event)) {
    throw new Error(`Invalid swarm-relay event type: ${event}`);
  }

  const parts: string[] = [];
  for (const [k, v] of Object.entries(fields)) {
    if (RESERVED_DELIMITERS.test(k) || RESERVED_DELIMITERS.test(v)) {
      throw new Error(`swarm-relay: field '${k}=${v}' contains reserved delimiter (whitespace/newline/|/[])`);
    }
    parts.push(`${k}=${v}`);
  }

  if (parts.length === 0) {
    throw new Error("swarm-relay: at least one key=value field required");
  }

  return `[swarm-relay:${event}] ${parts.join(" ")}`;
}

export function parseRelayMessage(line: string): RelayMessage | null {
  const trimmed = line.trim();
  const match = trimmed.match(/^\[swarm-relay:(init|precommit-check|handoff|gate-done)\](.*)$/);
  if (!match) {
    return null;
  }

  const event = match[1] as RelayEventType;
  const rawFields = match[2].trim();
  const fields: Record<string, string> = {};

  if (rawFields) {
    const tokens = rawFields.split(/\s+/);
    for (const token of tokens) {
      const eqIdx = token.indexOf("=");
      if (eqIdx !== -1) {
        const k = token.slice(0, eqIdx);
        const v = token.slice(eqIdx + 1);
        fields[k] = v;
      }
    }
  }

  return {
    event,
    fields,
    raw: trimmed,
  };
}

export function registerActiveSession(
  relayDir: string,
  session: RelaySessionInfo,
  ttlSeconds = 300
): void {
  if (!fs.existsSync(relayDir)) {
    fs.mkdirSync(relayDir, { recursive: true });
  }

  const registryFile = path.join(relayDir, "active-sessions.json");
  let sessions: RelaySessionInfo[] = [];

  if (fs.existsSync(registryFile)) {
    try {
      sessions = JSON.parse(fs.readFileSync(registryFile, "utf-8"));
    } catch {
      sessions = [];
    }
  }

  const now = Date.now();
  // Prune expired sessions (older than ttlSeconds)
  sessions = sessions.filter(
    (s) => now - s.updatedAt < ttlSeconds * 1000 && s.sessionId !== session.sessionId
  );

  sessions.push({ ...session, updatedAt: now });

  // Atomic publish: write to a unique temp file in the same directory, then
  // rename over the registry. rename(2) is atomic on POSIX for same-filesystem
  // paths, so a concurrent reader always observes either the old or the new
  // complete document — never a half-written one. Without this, overlapping
  // writes from concurrent sessions (init + 60s heartbeats) produce torn reads;
  // because the file is a single JSON document, a torn read makes JSON.parse
  // throw and the fail-safe treats the whole registry as empty, which then
  // clobbers every other session's entry on the next write and silently
  // disables cross-session conflict detection (SWARM.md §0). Consolidated onto the
  // shared writeFileAtomic helper (single durable-write implementation).
  writeFileAtomic(registryFile, JSON.stringify(sessions, null, 2));
}

export function findSiblingSessions(
  relayDir: string,
  targetRepo: string,
  currentSessionId?: string,
  ttlSeconds = 300
): RelaySessionInfo[] {
  const registryFile = path.join(relayDir, "active-sessions.json");
  if (!fs.existsSync(registryFile)) return [];

  try {
    const sessions: RelaySessionInfo[] = JSON.parse(fs.readFileSync(registryFile, "utf-8"));
    const now = Date.now();
    const normTarget = path.resolve(targetRepo);

    return sessions.filter((s) => {
      if (currentSessionId && s.sessionId === currentSessionId) return false;
      if (now - s.updatedAt > ttlSeconds * 1000) return false;

      const normRepo = path.resolve(s.repo);
      return (
        normRepo === normTarget ||
        normRepo.startsWith(normTarget + path.sep) ||
        normTarget.startsWith(normRepo + path.sep)
      );
    });
  } catch {
    return [];
  }
}

export function appendRelayEvent(relayDir: string, eventMsg: string): void {
  if (!fs.existsSync(relayDir)) {
    fs.mkdirSync(relayDir, { recursive: true });
  }

  const logFile = path.join(relayDir, "events.log");
  const entry = `${Date.now()}\t${eventMsg}\n`;
  fs.appendFileSync(logFile, entry, "utf-8");

  // Bounded rotation: events.log is a persistent, cross-session, append-only log
  // that would otherwise grow without limit, and readRecentRelayEvents reads the
  // whole file on every call (returning only the last time-window). Cap it to a
  // bounded tail once it crosses a byte threshold. The stat check is cheap, so
  // the expensive read+rewrite only runs on rare rotations; the rewrite is atomic
  // (temp+rename) and fail-safe (a rotation error never breaks event logging).
  const RELAY_LOG_MAX_BYTES = 1_048_576; // 1 MiB
  const RELAY_LOG_KEEP_LINES = 2000;
  try {
    if (fs.statSync(logFile).size > RELAY_LOG_MAX_BYTES) {
      const lines = fs.readFileSync(logFile, "utf-8").split("\n").filter(Boolean);
      const kept = lines.slice(-RELAY_LOG_KEEP_LINES).join("\n") + "\n";
      writeFileAtomic(logFile, kept);
    }
  } catch {
    // rotation is best-effort; appends must never fail because of it
  }
}

export function readRecentRelayEvents(
  relayDir: string,
  targetRepo: string,
  sinceMs = 600000 // default 10 minutes
): RelayMessage[] {
  const logFile = path.join(relayDir, "events.log");
  if (!fs.existsSync(logFile)) return [];

  try {
    const lines = fs.readFileSync(logFile, "utf-8").trim().split("\n");
    const now = Date.now();
    const results: RelayMessage[] = [];
    const normTarget = path.resolve(targetRepo);

    for (const line of lines) {
      if (!line) continue;
      const tabIdx = line.indexOf("\t");
      if (tabIdx === -1) continue;

      const timestamp = parseInt(line.slice(0, tabIdx), 10);
      if (isNaN(timestamp) || now - timestamp > sinceMs) continue;

      const msgStr = line.slice(tabIdx + 1);
      const parsed = parseRelayMessage(msgStr);
      if (parsed) {
        const repo = parsed.fields["repo"] || parsed.fields["from-repo"] || "";
        // Match same/parent/child repo via a path-COMPONENT boundary (path.sep),
        // not a bare string prefix — otherwise `/x/vald` would spuriously match an
        // unrelated sibling `/x/vald2`. Mirrors findSiblingSessions' overlap check.
        const normRepo = repo ? path.resolve(repo) : "";
        if (
          !repo ||
          normRepo === normTarget ||
          normRepo.startsWith(normTarget + path.sep) ||
          normTarget.startsWith(normRepo + path.sep)
        ) {
          results.push(parsed);
        }
      }
    }

    return results;
  } catch {
    return [];
  }
}

export default function (pi: ExtensionAPI) {
  const relayDir = getRelayDir();
  const sessionId = `pi-${process.pid}-${Date.now()}`;

  // Periodic heartbeat registration
  const registerHeartbeat = () => {
    registerActiveSession(relayDir, {
      sessionId,
      pid: process.pid,
      repo: process.cwd(),
      mission: process.env.SWARM_MISSION || "adhoc",
      scale: process.env.SWARM_SCALE || "quick",
      updatedAt: Date.now(),
    });
  };

  registerHeartbeat();
  const interval = setInterval(registerHeartbeat, 60000);
  if (interval.unref) interval.unref();

  // Command: /relay
  pi.registerCommand("relay", {
    description: "Inspect active sibling sessions or broadcast swarm-relay messages (/relay [list|check|broadcast])",
    handler: async (args, ctx) => {
      const parts = (args || "").trim().split(/\s+/);
      const subcmd = parts[0]?.toLowerCase() || "list";

      if (subcmd === "list") {
        const siblings = findSiblingSessions(relayDir, ctx.cwd, sessionId);
        if (siblings.length === 0) {
          ctx.ui.notify(`[swarm-relay] No concurrent sessions detected for repository:\n${ctx.cwd}`, "info");
          return;
        }

        const lines = siblings.map(
          (s) => `• PID ${s.pid} [${s.mission}] (${s.scale || "adhoc"}) - ${s.repo}`
        );
        ctx.ui.notify(`[swarm-relay] Active concurrent sessions (${siblings.length}):\n${lines.join("\n")}`, "info");
      } else if (subcmd === "check") {
        const events = readRecentRelayEvents(relayDir, ctx.cwd, 300000);
        const precommits = events.filter((e) => e.event === "precommit-check");
        if (precommits.length > 0) {
          ctx.ui.notify(
            `⚠️ [swarm-relay] Detected ${precommits.length} recent precommit-check event(s) in this repository! Coordinate before committing:\n` +
              precommits.map((p) => p.raw).join("\n"),
            "warning"
          );
        } else {
          ctx.ui.notify("[swarm-relay] No recent precommit conflicts detected.", "info");
        }
      } else if (subcmd === "broadcast") {
        const eventType = parts[1] as RelayEventType;
        if (!eventType) {
          ctx.ui.notify("Usage: /relay broadcast <init|precommit-check|handoff|gate-done> <key=val...>", "error");
          return;
        }
        const fieldMap: Record<string, string> = {
          repo: ctx.cwd,
          mission: process.env.SWARM_MISSION || "adhoc",
        };
        for (let i = 2; i < parts.length; i++) {
          const eq = parts[i].indexOf("=");
          if (eq !== -1) {
            fieldMap[parts[i].slice(0, eq)] = parts[i].slice(eq + 1);
          }
        }
        try {
          const formatted = formatRelayMessage(eventType, fieldMap);
          appendRelayEvent(relayDir, formatted);
          ctx.ui.notify(`[swarm-relay] Broadcast sent:\n${formatted}`, "info");
        } catch (err: any) {
          ctx.ui.notify(`Failed to broadcast: ${err.message}`, "error");
        }
      } else {
        ctx.ui.notify("Usage: /relay [list|check|broadcast]", "info");
      }
    },
  });

  // Tool: relay_message
  pi.registerTool({
    name: "relay_message",
    description: "Send or inspect cross-session swarm-relay messages across concurrent agent sessions.",
    parameters: Type.Object({
      action: Type.Union([
        Type.Literal("list_siblings"),
        Type.Literal("broadcast"),
        Type.Literal("check_conflicts"),
      ]),
      event: Type.Optional(
        Type.Union([
          Type.Literal("init"),
          Type.Literal("precommit-check"),
          Type.Literal("handoff"),
          Type.Literal("gate-done"),
        ])
      ),
      fields: Type.Optional(Type.Record(Type.String(), Type.String())),
    }),
    async execute(_toolCallId: any, params: any, _signal: any, _onUpdate: any, ctx: any) {
      const actualParams = typeof _toolCallId === "string" ? params : _toolCallId;
      const actualCtx = typeof _toolCallId === "string" ? ctx : params;
      const effectiveCwd = actualCtx?.cwd || process.cwd();

      if (actualParams.action === "list_siblings") {
        const siblings = findSiblingSessions(relayDir, effectiveCwd, sessionId);
        const data = { total: siblings.length, siblings };
        return {
          content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
          details: data,
        };
      }

      if (actualParams.action === "check_conflicts") {
        const recent = readRecentRelayEvents(relayDir, effectiveCwd, 300000);
        const data = {
          conflictsDetected: recent.some((e) => e.event === "precommit-check"),
          events: recent,
        };
        return {
          content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
          details: data,
        };
      }

      if (actualParams.action === "broadcast") {
        if (!actualParams.event) {
          throw new Error("Missing 'event' parameter for broadcast action.");
        }
        const fields = actualParams.fields || {};
        if (!fields["repo"]) fields["repo"] = effectiveCwd;
        if (!fields["mission"]) fields["mission"] = process.env.SWARM_MISSION || "adhoc";

        const msg = formatRelayMessage(actualParams.event, fields);
        appendRelayEvent(relayDir, msg);
        const data = { sent: true, message: msg };
        return {
          content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
          details: data,
        };
      }

      throw new Error(`Unknown action: ${actualParams.action}`);
    },
    handler: async (args: any, ctx: any) => {
      const effectiveCwd = ctx?.cwd || process.cwd();

      if (args.action === "list_siblings") {
        const siblings = findSiblingSessions(relayDir, effectiveCwd, sessionId);
        const data = { total: siblings.length, siblings };
        return {
          content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
          details: data,
        };
      }

      if (args.action === "check_conflicts") {
        const recent = readRecentRelayEvents(relayDir, effectiveCwd, 300000);
        const data = {
          conflictsDetected: recent.some((e) => e.event === "precommit-check"),
          events: recent,
        };
        return {
          content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
          details: data,
        };
      }

      if (args.action === "broadcast") {
        if (!args.event) {
          throw new Error("Missing 'event' parameter for broadcast action.");
        }
        const fields = args.fields || {};
        if (!fields["repo"]) fields["repo"] = effectiveCwd;
        if (!fields["mission"]) fields["mission"] = process.env.SWARM_MISSION || "adhoc";

        const msg = formatRelayMessage(args.event, fields);
        appendRelayEvent(relayDir, msg);
        const data = { sent: true, message: msg };
        return {
          content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
          details: data,
        };
      }

      throw new Error(`Unknown action: ${args.action}`);
    },
  });
}
