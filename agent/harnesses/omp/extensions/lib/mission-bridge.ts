/**
 * Mission / evolution / trail bridges for SoL-Pi.
 *
 * SoL-Pi is written against upstream (NVlabs/SoL-Pi), which knows nothing about
 * this repository's surrounding systems. These helpers connect its plan,
 * compaction and failure observations to them without importing runtime state:
 *
 * - Mission: a swarm mission writes `@fix_plan.md` at the mission worktree root
 *   and declares it the authoritative progress state (ConstraintRot mitigation,
 *   arXiv:2606.22528). A compact, deterministic snapshot is injected into the
 *   request system prompt, the boundary-compaction guidance and the
 *   post-compaction resume reminder, so a long mission survives summarization.
 * - Harness²: the offline pipeline (`agent/scripts/evolve/harness2-offline.py`)
 *   clusters failure traces with `{signature, task, target, message}`. SoL-Pi
 *   already observes deterministic validator failures; recording them in the
 *   pipeline's input shape closes the runtime -> self-evolution loop.
 * - Trail: `.trail/learnings/*.md` records what past sessions decided. OMP has
 *   no automatic SessionStart hook for it, so the compaction path carries a
 *   bounded reminder to consult it (`trail ask`) and to run `trail check`
 *   before committing.
 *
 * Everything here is pure or fs-only, bounded, and never throws to the caller:
 * a missing/unreadable file simply disables its bridge.
 */
import { createHash } from "node:crypto";
import * as fs from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";

// ---------------------------------------------------------------------------
// @fix_plan.md (swarm mission state)
// ---------------------------------------------------------------------------

const MAX_FIX_PLAN_LINES = 4000;
const MAX_MISSION_ITEMS = 5;
const MAX_GOAL_CHARS = 240;

export interface MissionSnapshot {
  /** Absolute path of the @fix_plan.md that produced this snapshot. */
  path: string;
  slug: string;
  goal: string;
  scale: string;
  definitionOfDone: { total: number; done: number; remaining: string[] };
  tasks: {
    total: number;
    done: number;
    inProgress: number;
    blocked: number;
    pending: number;
    /** Task ids that are not done yet (at most MAX_MISSION_ITEMS). */
    next: string[];
    blockedIds: string[];
  };
  /** Every task done and every DoD item checked: the mission is ready for the GATE. */
  gateReady: boolean;
}

export interface MissionCacheEntry {
  mtimeMs: number;
  size: number;
  snapshot: MissionSnapshot | null;
}

export interface MissionDetectOptions {
  maxBytes?: number;
  cache?: Map<string, MissionCacheEntry>;
}

const CHECKBOX_RE = /^\s*[-*]\s*\[([ xX])\]\s+(.+?)\s*$/u;
const HEADING_RE = /^##\s+(.+?)\s*$/u;

function checklistItems(lines: readonly string[]): { total: number; done: number; remaining: string[] } {
  let total = 0;
  let done = 0;
  const remaining: string[] = [];
  for (const line of lines) {
    const m = CHECKBOX_RE.exec(line);
    if (!m) continue;
    total++;
    if (m[1] !== " ") done++;
    else if (remaining.length < MAX_MISSION_ITEMS) remaining.push(m[2].slice(0, 160));
  }
  return { total, done, remaining };
}

type TaskStatus = "done" | "in_progress" | "blocked" | "pending";

function taskStatus(cell: string): TaskStatus {
  const s = cell.toLowerCase().replace(/[`*]/g, "").trim();
  if (/blocked|escalat/.test(s)) return "blocked";
  if (/^(done|completed|merged|closed)\b/.test(s)) return "done";
  if (/in.?progress|running|active|doing|wip/.test(s)) return "in_progress";
  return "pending";
}

function parseTaskTable(lines: readonly string[]): MissionSnapshot["tasks"] {
  const out: MissionSnapshot["tasks"] = {
    total: 0,
    done: 0,
    inProgress: 0,
    blocked: 0,
    pending: 0,
    next: [],
    blockedIds: [],
  };
  let idCol = 0;
  let statusCol = -1;
  let header: string[] | undefined;
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("|")) continue;
    const cells = trimmed
      .replace(/^\|/u, "")
      .replace(/\|$/u, "")
      .split("|")
      .map((c) => c.trim());
    if (cells.every((c) => /^:?-{3,}:?$/u.test(c))) continue; // separator row
    if (!header) {
      header = cells.map((c) => c.toLowerCase());
      idCol = Math.max(0, header.findIndex((c) => /task.?id|id/u.test(c)));
      statusCol = header.findIndex((c) => /status|state/u.test(c));
      continue;
    }
    if (cells.length < 2 || (statusCol >= 0 && statusCol >= cells.length)) continue;
    const id = cells[idCol] || `task-${out.total + 1}`;
    const status = taskStatus(statusCol >= 0 ? cells[statusCol] : cells[cells.length - 1]);
    out.total++;
    if (status === "done") out.done++;
    else {
      if (status === "in_progress") out.inProgress++;
      else if (status === "blocked") out.blocked++;
      else out.pending++;
      if (out.next.length < MAX_MISSION_ITEMS) out.next.push(id.slice(0, 40));
      if (status === "blocked" && out.blockedIds.length < MAX_MISSION_ITEMS) out.blockedIds.push(id.slice(0, 40));
    }
  }
  return out;
}

export function parseFixPlan(text: string, file = ""): MissionSnapshot | null {
  if (!text) return null;
  const lines = text.split(/\r?\n/u).slice(0, MAX_FIX_PLAN_LINES);
  const head = lines.slice(0, 40).join("\n");
  if (!/@fix_plan\.md/u.test(head) && !/^\s*-\s*goal:/mu.test(text) && !/^##\s+Tasks\s*$/mu.test(text)) return null;

  const slugMatch = /^#\s+@fix_plan\.md\s*[—–-]\s*mission:\s*(\S+)/mu.exec(head) ?? /mission:\s*(\S+)/u.exec(head);
  const goalMatch = /^\s*-\s*goal:\s*(.+?)\s*$/mu.exec(text);
  const scaleMatch = /^\s*-\s*scale:\s*([A-Za-z]+)/mu.exec(text);

  const dodLines: string[] = [];
  const taskLines: string[] = [];
  let section: "dod" | "tasks" | "other" = "other";
  for (const line of lines) {
    const h = HEADING_RE.exec(line);
    if (h) {
      const name = h[1].toLowerCase();
      section = name.includes("definition of done") ? "dod" : name.includes("tasks") ? "tasks" : "other";
      continue;
    }
    if (section === "dod") dodLines.push(line);
    else if (section === "tasks") taskLines.push(line);
  }

  const definitionOfDone = checklistItems(dodLines);
  const tasks = parseTaskTable(taskLines);
  const slug = (slugMatch?.[1] ?? (file ? path.basename(path.dirname(file)) : "")).slice(0, 80);
  const goal = (goalMatch?.[1] ?? "").slice(0, MAX_GOAL_CHARS);
  const gateReady =
    definitionOfDone.total > 0 &&
    definitionOfDone.done === definitionOfDone.total &&
    tasks.total > 0 &&
    tasks.done === tasks.total;

  return {
    path: file,
    slug,
    goal,
    scale: (scaleMatch?.[1] ?? "").toLowerCase(),
    definitionOfDone,
    tasks,
    gateReady,
  };
}

/** Walk up to 4 levels from `cwd` looking for the mission's @fix_plan.md. */
export async function detectMission(cwd: string, opts: MissionDetectOptions = {}): Promise<MissionSnapshot | null> {
  const maxBytes = opts.maxBytes ?? 262144;
  let dir = path.resolve(cwd);
  for (let level = 0; level < 4; level++) {
    const candidate = path.join(dir, "@fix_plan.md");
    const stat = await fs.stat(candidate).catch(() => null);
    if (stat?.isFile()) {
      if (stat.size > maxBytes) return null;
      const cached = opts.cache?.get(candidate);
      if (cached && cached.mtimeMs === stat.mtimeMs && cached.size === stat.size) return cached.snapshot;
      const text = await fs.readFile(candidate, "utf8").catch(() => "");
      const snapshot = parseFixPlan(text, candidate);
      opts.cache?.set(candidate, { mtimeMs: stat.mtimeMs, size: stat.size, snapshot });
      return snapshot;
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

/** Walk up to the nearest `.git` (a directory or a worktree's file) or `@fix_plan.md`. */
export async function findRepoRoot(startDir: string): Promise<string> {
  const start = path.resolve(startDir);
  let dir = start;
  for (let level = 0; level < 8; level++) {
    if ((await fs.stat(path.join(dir, ".git")).catch(() => null)) !== null) return dir;
    if ((await fs.stat(path.join(dir, "@fix_plan.md")).catch(() => null)) !== null) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return start;
}

/** One-to-three-line mission summary, bounded to ~600 chars by construction. */
export function formatMissionSnapshot(m: MissionSnapshot): string {
  const dod = `${m.definitionOfDone.done}/${m.definitionOfDone.total}`;
  const t = m.tasks;
  const counts = `${t.done}/${t.total} done, ${t.inProgress} in progress, ${t.blocked} blocked, ${t.pending} pending`;
  const parts = [
    `Mission "${m.slug || "(unnamed)"}"${m.scale ? ` (${m.scale})` : ""}: ${m.goal || "(goal not stated)"}`,
    `DoD ${dod}; tasks ${counts}${t.blockedIds.length > 0 ? ` (blocked: ${t.blockedIds.join(", ")})` : t.next.length > 0 ? ` (next: ${t.next.join(", ")})` : ""}`,
  ];
  return parts.join("\n");
}

/** Guidance appended to the boundary-compaction instructions. */
export function missionCompactionGuidance(m: MissionSnapshot | null): string {
  if (!m) return "";
  const lines = [
    "Mission progress (@fix_plan.md is authoritative; never rebuild it from this summary):",
    formatMissionSnapshot(m),
    "Re-read @fix_plan.md after this compaction before deciding the next step.",
  ];
  if (m.gateReady) {
    lines.push(
      "All Definition-of-Done items and tasks are complete: proceed to the adversarial review / GATE (run verify.sh) and request human approval.",
    );
  }
  return lines.join("\n");
}

/** Line appended to the post-compaction resume reminder. */
export function missionResumeReminder(m: MissionSnapshot | null): string {
  if (!m) return "";
  const dod = `${m.definitionOfDone.done}/${m.definitionOfDone.total}`;
  const tasks = `${m.tasks.done}/${m.tasks.total}`;
  const name = m.slug || "(unnamed)";
  if (m.gateReady) {
    return `Mission "${name}" is gate-ready (DoD ${dod}, tasks ${tasks}): run verify.sh and \`trail check\`, then request human approval at the GATE.`;
  }
  if (m.tasks.blocked > 0) {
    const ids = m.tasks.blockedIds.length > 0 ? `: ${m.tasks.blockedIds.join(", ")}` : "";
    return `Mission "${name}" has ${m.tasks.blocked} blocked task(s)${ids} (DoD ${dod}, tasks ${tasks}); escalate to the human before continuing.`;
  }
  return `Mission "${name}": DoD ${dod}, tasks ${tasks} done. Re-read @fix_plan.md for the authoritative task list before continuing.`;
}

// ---------------------------------------------------------------------------
// Trail learnings
// ---------------------------------------------------------------------------

export interface TrailLearning {
  file: string;
  title: string;
  mtimeMs: number;
}

export interface TrailIndex {
  count: number;
  /** Up to `limit` newest learnings; entries without a title are omitted. */
  newest: TrailLearning[];
}

export async function readTrailIndex(repoRoot: string, limit = 5): Promise<TrailIndex> {
  const dir = path.join(repoRoot, ".trail", "learnings");
  const names = await fs.readdir(dir).catch(() => [] as string[]);
  const entries: TrailLearning[] = [];
  for (const name of names) {
    if (!name.endsWith(".md")) continue;
    const stat = await fs.stat(path.join(dir, name)).catch(() => null);
    if (!stat?.isFile()) continue;
    entries.push({ file: name, title: "", mtimeMs: stat.mtimeMs });
  }
  entries.sort((a, b) => b.mtimeMs - a.mtimeMs || (a.file < b.file ? 1 : -1));
  for (const entry of entries.slice(0, Math.max(1, limit))) {
    const text = await fs.readFile(path.join(dir, entry.file), "utf8").catch(() => "");
    const title = text.split(/\r?\n/u).find((line) => line.startsWith("# "));
    entry.title = (title ?? "").slice(2).trim().slice(0, 120);
  }
  return { count: entries.length, newest: entries.slice(0, limit).filter((e) => e.title) };
}

/** Trail reminder for compaction guidance (empty when the repo has no learnings). */
export function trailCompactionHint(index: TrailIndex | undefined): string {
  if (!index || index.count === 0) return "";
  const newest = index.newest[0]?.title ? ` (newest: ${index.newest[0].title})` : "";
  return (
    `Trail: ${index.count} learnings in this repo${newest}. ` +
    'After this compaction, run `trail ask "<current goal>" --source` before re-exploring, and `trail check` before committing or opening a PR.'
  );
}

// ---------------------------------------------------------------------------
// Harness² traces
// ---------------------------------------------------------------------------

export interface EvolutionTrace {
  signature: string;
  task: string;
  target: string;
  message?: string;
}

/** harness2-offline.py check_target allowlist; anything else makes the whole traces file fail closed. */
const TRACE_TARGET_RE = /^[A-Za-z0-9._/@+-]+$/u;

export function isValidTraceTarget(target: string): boolean {
  if (!target || target.includes("\\") || target.includes("\x00")) return false;
  if (path.posix.isAbsolute(target)) return false;
  const normalized = path.posix.normalize(target);
  if (normalized === "." || normalized === ".." || normalized.startsWith("../") || normalized.includes("/../")) return false;
  return TRACE_TARGET_RE.test(normalized);
}

/** Strict-mode safe: harness2 rejects every control/invisible/line-separator character in signature/task/target. */
export function sanitizeTraceText(value: string, max: number): string {
  return value
    .replace(/[\u0000-\u001f\u007f]/gu, " ")
    .replace(/[\u200b-\u200f\u2028\u2029\ufeff]/gu, " ")
    .replace(/\s+/gu, " ")
    .trim()
    .slice(0, max)
    .trim();
}

const ANSI_RE = /\x1b\[[0-9;]*[A-Za-z]/gu;

function firstNonEmptyLine(text: string): string {
  for (const raw of text.split(/\r?\n/u)) {
    const line = raw.replace(ANSI_RE, "").trim();
    if (line) return line;
  }
  return "";
}

/**
 * Stable root-cause signature for Harness² clustering: the first error line with
 * paths, digests and numbers normalized, so the same failure clusters across runs
 * and machines while unrelated failures stay apart.
 */
export function normalizeFailureSignature(kind: string, output: string, fallback = "failed"): string {
  const line = firstNonEmptyLine(output).toLowerCase();
  const normalized = line
    .replace(/\b[0-9a-f]{8,}\b/gu, "<hash>")
    .replace(/(?:\/[\w.@+-]+){2,}/gu, "<path>")
    .replace(/\d+/gu, "#")
    .replace(/\s+/gu, " ")
    .trim();
  const composed = `${kind}:${normalized || fallback}`.replace(/\d+/gu, "#");
  return sanitizeTraceText(composed, 200) || sanitizeTraceText(`${kind}:${fallback}`, 200);
}

/** Per-repo trace file shared by every session of this checkout. */
export function evolutionTracePath(repoRoot: string, home: string = os.homedir()): string {
  const base = path.basename(repoRoot).replace(/[^A-Za-z0-9._-]/gu, "-") || "repo";
  const digest = createHash("sha256").update(path.resolve(repoRoot)).digest("hex").slice(0, 12);
  return path.join(home, ".claude", "session-data", "swarm", "evolve-traces", `${base}-${digest}.jsonl`);
}

/** Append one JSONL record; false when the cap is reached or the write fails (never throws). */
export async function appendEvolutionTrace(file: string, trace: EvolutionTrace, maxBytes: number): Promise<boolean> {
  try {
    await fs.mkdir(path.dirname(file), { recursive: true });
    const stat = await fs.stat(file).catch(() => null);
    if (stat && stat.size >= maxBytes) return false;
    await fs.appendFile(file, `${JSON.stringify(trace)}\n`, "utf8");
    return true;
  } catch {
    return false;
  }
}
