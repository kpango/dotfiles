/**
 * LangChain Middleware Guardrails Core (pi-agent-improvement.pdf #6)
 *
 * Pure state machine + local context probe for:
 * - Doom-Loop Detection (per-file edit cap & consecutive identical failures)
 * - Read-Guard (warn/block blind edits to existing unread files)
 * - Turn-Budget Steering (verify-before-finish nudge near budget limit)
 * - LocalContext Summary (/env-context on-demand probe without mutating systemPrompt)
 */

import { execFileSync, spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

export interface LoopGuardOptions {
  editThreshold?: number;
  failThreshold?: number;
  turnBudget?: number;
}

export interface FailureKeyInput {
  toolName: string;
  path?: string;
  command?: string;
}

export function normalizeTargetPath(rawPath: string, cwd: string): string {
  const cleaned = rawPath.replace(/^\[([^#\]]+?)(?:#[0-9a-fA-F]{4})?\]$/, "$1").trim();
  if (!cleaned) return "";
  return path.isAbsolute(cleaned) ? path.normalize(cleaned) : path.resolve(cwd, cleaned);
}

export function isVerificationBashCommand(command: string): boolean {
  const normalized = command.trim();
  if (!normalized) return false;
  return (
    /(?:^|\s|&&|\|\||;)(?:go\s+test|go\s+vet|cargo\s+(?:test|check|clippy)|bun\s+(?:test|run)|pytest|npm\s+test|make\s+test|golangci-lint|bash\s+-n|nix-instantiate\b|ruff\s+check)/.test(
      normalized,
    ) || /(?:^|\/)test-[A-Za-z0-9_.-]+\.sh\b/.test(normalized) || /(?:^|\/)validate-harness\.sh\b/.test(normalized)
  );
}

export function failureSignatureKey(input: FailureKeyInput): string {
  const tool = String(input.toolName || "unknown").toLowerCase();
  if (input.path) return `${tool}:path:${input.path}`;
  if (input.command) {
    const head = input.command.trim().replace(/\s+/g, " ").slice(0, 120);
    return `${tool}:cmd:${head}`;
  }
  return `${tool}:generic`;
}

export class LoopGuardTracker {
  readonly editThreshold: number;
  readonly failThreshold: number;
  readonly turnBudget: number;

  private readFiles = new Set<string>();
  private createdFiles = new Set<string>();
  private editCounts = new Map<string, number>();
  private advisedEditFiles = new Set<string>();
  private lastFailKey = "";
  private consecutiveFails = 0;
  private hasUnverifiedEdits = false;
  private turnBudgetAdvised = false;

  constructor(opts: LoopGuardOptions = {}) {
    this.editThreshold = opts.editThreshold ?? 5;
    this.failThreshold = opts.failThreshold ?? 3;
    this.turnBudget = opts.turnBudget ?? 40;
  }

  reset(): void {
    this.readFiles.clear();
    this.createdFiles.clear();
    this.editCounts.clear();
    this.advisedEditFiles.clear();
    this.lastFailKey = "";
    this.consecutiveFails = 0;
    this.hasUnverifiedEdits = false;
    this.turnBudgetAdvised = false;
  }

  recordRead(absPath: string): void {
    if (absPath) this.readFiles.add(absPath);
  }

  recordCreated(absPath: string): void {
    if (absPath) {
      this.createdFiles.add(absPath);
      this.readFiles.add(absPath);
    }
  }

  hasSeenFile(absPath: string): boolean {
    return this.readFiles.has(absPath) || this.createdFiles.has(absPath);
  }

  checkBlindEdit(absPath: string, existsOnDisk: boolean): string | null {
    if (!absPath || !existsOnDisk) return null;
    if (this.hasSeenFile(absPath)) return null;
    return `[loop-guard] Read-Guard: '${path.basename(absPath)}' was edited before reading it in this session. Read the target lines first to avoid stale edits or assumptions.`;
  }

  recordEdit(absPath: string): string | null {
    if (!absPath) return null;
    this.hasUnverifiedEdits = true;
    const count = (this.editCounts.get(absPath) ?? 0) + 1;
    this.editCounts.set(absPath, count);
    if (count >= this.editThreshold && !this.advisedEditFiles.has(absPath)) {
      this.advisedEditFiles.add(absPath);
      return `[loop-guard] Doom-Loop notice: '${path.basename(absPath)}' has been edited ${count} times without a passing verification run. Pause, re-read failing output, and question the current hypothesis before editing again.`;
    }
    return null;
  }

  recordVerificationPass(): void {
    this.editCounts.clear();
    this.advisedEditFiles.clear();
    this.hasUnverifiedEdits = false;
  }

  recordToolOutcome(input: FailureKeyInput, isError: boolean): string | null {
    if (!isError) {
      const sig = failureSignatureKey(input);
      if (sig === this.lastFailKey) {
        this.lastFailKey = "";
        this.consecutiveFails = 0;
      }
      if (input.toolName === "bash" && input.command && isVerificationBashCommand(input.command)) {
        this.recordVerificationPass();
      }
      return null;
    }

    const sig = failureSignatureKey(input);
    if (sig === this.lastFailKey) {
      this.consecutiveFails++;
    } else {
      this.lastFailKey = sig;
      this.consecutiveFails = 1;
    }

    if (this.consecutiveFails >= this.failThreshold) {
      const count = this.consecutiveFails;
      this.consecutiveFails = 0;
      return `[loop-guard] Repeated failure (${count}x consecutive) on ${sig}. Stop repeating the identical command/edit and inspect root cause or ask the user.`;
    }
    return null;
  }

  checkTurnBudget(turnCount: number, hasUnverified = this.hasUnverifiedEdits): string | null {
    if (this.turnBudget <= 0 || this.turnBudgetAdvised || !hasUnverified) return null;
    const remaining = this.turnBudget - turnCount;
    if (remaining <= 5) {
      this.turnBudgetAdvised = true;
      return `[loop-guard] Time/Turn Budget notice: ${Math.max(0, remaining)} turns remaining before budget (${this.turnBudget}) with unverified edits pending. Switch to running deterministic tests/lints now.`;
    }
    return null;
  }

  snapshot() {
    return {
      readCount: this.readFiles.size,
      editedFiles: Object.fromEntries(this.editCounts.entries()),
      hasUnverifiedEdits: this.hasUnverifiedEdits,
      lastFailKey: this.lastFailKey,
      consecutiveFails: this.consecutiveFails,
    };
  }
}

export function buildLocalContextSummary(cwd: string): string {
  const lines: string[] = [];
  try {
    const branch = execFileSync("git", ["rev-parse", "--abbrev-ref", "HEAD"], {
      cwd,
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    const dirty = execFileSync("git", ["status", "--short"], {
      cwd,
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "ignore"],
    })
      .split("\n")
      .filter((l) => l.trim().length > 0).length;
    lines.push(`Workspace: ${cwd} (git: ${branch || "detached"}, ${dirty} dirty)`);
  } catch {
    lines.push(`Workspace: ${cwd} (non-git)`);
  }

  const probe = ["go", "rustc", "bun", "python3", "make", "nix", "docker", "rtk", "trail"];
  const available = probe.filter((bin) => spawnSync("which", [bin], { stdio: "ignore" }).status === 0);
  lines.push(`Toolchains: ${available.length > 0 ? available.join(", ") : "(none detected)"}`);
  return lines.join("\n");
}
