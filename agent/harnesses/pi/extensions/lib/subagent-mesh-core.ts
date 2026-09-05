/**
 * Subagent Mesh Core Engine
 *
 * Implements the decentralized P2P blackboard pub/sub event bus, persistent
 * JSONL stream IPC, coordinator arbitration engine, Bayesian confidence propagation,
 * and autonomous peer handoff finite state machine.
 */

import * as child_process from "node:child_process";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

// ============================================================================
// Constants
// ============================================================================

export const GATE_CONFIDENCE_THRESHOLD = 0.95;
export const MAX_ATTEMPTS_HARD_CAP = 5;
export const SOFT_CHECKPOINT_ATTEMPT = 3;
export const DEFAULT_PRIOR_CONFIDENCE = 0.30;
export const DEFAULT_PRIOR_LOG_ODDS = -0.8472978603872037; // Math.log(0.30 / 0.70)

// ============================================================================
// Types & Interfaces
// ============================================================================

export type SubagentTopic = "spec" | "draft" | "critique" | "verification" | "blocker";
export type HandoffState = "INIT" | "DRAFTING" | "VERIFYING" | "REMEDIATING" | "GATE_READY" | "ESCALATED";

export interface MeshSender {
  id: string;
  role: string;
  model?: string;
}

export interface MeshMessage<T = unknown> {
  id: string;
  correlationId: string;
  parentMessageId?: string | null;
  timestamp: number;
  sender: MeshSender;
  recipient?: string;
  topic: SubagentTopic;
  payload: T;
  confidence?: ConfidenceScore;
  evidence?: ObjectiveVerificationEvidence;
}

export interface ConfidenceScore {
  score: number;
  value: number; // Compatibility alias
  prior: number;
  toolDelta: number;
  toolWeight: number; // alias
  peerDelta: number;
  peerWeight: number; // alias
  dissentDelta: number;
  dissentPenalty: number; // alias
  sycophancyDiscount: number;
  breakdown?: {
    testsPassed?: boolean;
    lintersPassed?: boolean;
    typecheckPassed?: boolean;
    peerApprovals?: number;
    activeBlockers?: number;
    activeWarnings?: number;
  };
}

export interface ObjectiveVerificationEvidence {
  command?: string;
  exitCode: number;
  stdoutSnippet?: string;
  stderrSnippet?: string;
  diffStats?: {
    filesChanged: number;
    insertions: number;
    deletions: number;
  };
  deterministicPass: boolean;
  toolSuccess?: boolean;
  lintersPassed?: boolean;
  typeCheckStatus?: "PASS" | "FAIL" | "SKIPPED";
  typecheckLog?: string;
  astAnalysis?: {
    tool: string;
    symbolsChanged: string[];
    syntaxValid: boolean;
  };
}

export interface SpecPayload {
  taskSlug: string;
  requirements: string[];
  invariants?: string[];
  preconditions?: string[];
  postconditions?: string[];
  affectedPackages?: string[];
  [key: string]: unknown;
}

export interface DraftPayload {
  taskSlug: string;
  worktreePath?: string;
  baseRef?: string;
  headSha?: string;
  patch: string;
  filesModified?: string[];
  summary?: string;
  authorConfidence?: number;
  authorInternalReasoning?: string;
  attemptNumber?: number;
  [key: string]: unknown;
}

export interface CritiquePayload {
  taskSlug: string;
  targetMessageId: string;
  lens: string;
  severity: "blocker" | "warning" | "advisory";
  reproCommand?: string;
  failingLine?: string;
  objection: string;
  remediationHint: string;
  [key: string]: unknown;
}

export interface VerificationPayload {
  taskSlug: string;
  targetDraftMessageId: string;
  verdict: "PASS" | "FAIL" | "CONDITIONAL";
  evaluatorId: string;
  evaluatorModel: string;
  evidence?: ObjectiveVerificationEvidence;
  findings?: CritiquePayload[];
  [key: string]: unknown;
}

export interface BlockerPayload {
  taskSlug: string;
  mastCategory?: string;
  reason: string;
  attemptCount?: number;
  escalationTarget?: string;
  [key: string]: unknown;
}

export interface ArbitrationResult {
  finalVerdict: "PASS" | "FAIL";
  blocked: boolean;
  reason?: string;
}

export interface BenchmarkResult {
  iterations: number;
  meanMs: number;
  p50Ms: number;
  p95Ms: number;
  p99Ms: number;
  maxMs: number;
}

export interface PeerReviewItem {
  score?: number;
  modelTier?: string;
  modelFamily?: string;
  sycophancyRisk?: number;
  claimsRepeatedWithoutEvidence?: boolean;
  observedConfidence?: boolean;
}

export interface CalculateConfidenceParams {
  prior?: number;
  toolEvidence?: ObjectiveVerificationEvidence;
  peerReviews?: PeerReviewItem[];
  critiques?: CritiquePayload[];
}

// ============================================================================
// Mathematical & Helper Functions
// ============================================================================

/**
 * Logistic sigmoid function with asymptotic numerical clamping.
 */
export function sigmoid(l: number): number {
  if (isNaN(l)) return 0.0;
  if (l > 700) return 1.0;
  if (l < -700) return 0.0;
  return 1.0 / (1.0 + Math.exp(-l));
}

/**
 * Log-odds transformation ln(p / (1 - p)).
 */
export function logOdds(p: number): number {
  const eps = 1e-15;
  const clamped = Math.max(eps, Math.min(1.0 - eps, p));
  return Math.log(clamped / (1.0 - clamped));
}

/**
 * Computes benchmark percentile statistics.
 */
export function calculatePercentiles(samples: number[]): BenchmarkResult {
  if (samples.length === 0) {
    return { iterations: 0, meanMs: 0, p50Ms: 0, p95Ms: 0, p99Ms: 0, maxMs: 0 };
  }
  const sorted = [...samples].sort((a, b) => a - b);
  const sum = sorted.reduce((acc, v) => acc + v, 0);
  const n = samples.length;
  return {
    iterations: n,
    meanMs: sum / n,
    p50Ms: sorted[Math.floor(n * 0.50)],
    p95Ms: sorted[Math.floor(n * 0.95)],
    p99Ms: sorted[Math.floor(n * 0.99)],
    maxMs: sorted[n - 1],
  };
}

let messageSeq = 0;

/**
 * Factory for creating typed MeshMessage instances.
 */
export function createMeshMessage<T = unknown>(params: {
  topic: SubagentTopic;
  sender: MeshSender | string;
  correlationId: string;
  payload: T;
  id?: string;
  parentMessageId?: string | null;
  recipient?: string;
  confidence?: ConfidenceScore;
  evidence?: ObjectiveVerificationEvidence;
  timestamp?: number;
}): MeshMessage<T> {
  const sender: MeshSender = typeof params.sender === "string"
    ? { id: params.sender, role: "worker" }
    : params.sender;

  return {
    id: params.id ?? `msg-${Date.now()}-${++messageSeq}-${Math.random().toString(36).slice(2, 6)}`,
    correlationId: params.correlationId,
    parentMessageId: params.parentMessageId ?? null,
    timestamp: params.timestamp ?? Date.now(),
    sender,
    recipient: params.recipient ?? "*",
    topic: params.topic,
    payload: params.payload,
    confidence: params.confidence,
    evidence: params.evidence,
  };
}

/**
 * Master Bayesian Confidence Calculator.
 *
 * Implements:
 * 1. Binary veto on deterministic test / linter failure or active blocker (C = 0.0).
 * 2. Log-odds prior L_0 = ln(0.30 / 0.70) ~ -0.8473.
 * 3. Deterministic tool boosts: tests (Delta L ~ +2.9755), linters (Delta L ~ +1.0986).
 * 4. Anti-sycophancy discounted peer review weights with Common Information Gain (CIG).
 * 5. Asymmetric dissent penalties (blocker = Inf, warning with repro = 3.5, heuristic = 1.5, advisory = 0.3).
 */
export function calculateConfidence(params: CalculateConfidenceParams): ConfidenceScore {
  const prior = params.prior !== undefined ? params.prior : DEFAULT_PRIOR_LOG_ODDS;
  const toolEvidence = params.toolEvidence;
  const peerReviews = params.peerReviews ?? [];
  const critiques = params.critiques ?? [];

  // 1. Binary Veto Checks
  let binaryVeto = false;

  if (toolEvidence) {
    if (toolEvidence.deterministicPass === false || toolEvidence.exitCode !== 0) {
      binaryVeto = true;
    }
  }

  for (const c of critiques) {
    if (c.severity === "blocker") {
      binaryVeto = true;
      break;
    }
  }

  if (binaryVeto) {
    return {
      score: 0.0,
      value: 0.0,
      prior,
      toolDelta: 0.0,
      toolWeight: 0.0,
      peerDelta: 0.0,
      peerWeight: 0.0,
      dissentDelta: 0.0,
      dissentPenalty: 0.0,
      sycophancyDiscount: 0.0,
      breakdown: {
        testsPassed: toolEvidence ? (toolEvidence.deterministicPass && toolEvidence.exitCode === 0) : false,
        lintersPassed: false,
        typecheckPassed: false,
        peerApprovals: 0,
        activeBlockers: critiques.filter((c) => c.severity === "blocker").length,
        activeWarnings: critiques.filter((c) => c.severity === "warning").length,
      },
    };
  }

  // 2. Tool Evidence Delta
  let toolDelta = 0.0;
  let testsPassed = false;
  let lintersPassed = false;

  if (toolEvidence && toolEvidence.deterministicPass && toolEvidence.exitCode === 0) {
    testsPassed = true;
    const deltaTest = 2.9755347; // ln(19.6) sensitivity 0.98 / false-pass 0.05

    // Check if linter/typecheck verification is satisfied:
    // Explicit linter flag, typecheck status/log, or command mentioning lint/typecheck.
    // NOTE: Peer reviews MUST NOT count as or artificially boost linter evidence.
    const hasLintIndicator =
      Boolean(toolEvidence.lintersPassed) ||
      toolEvidence.typeCheckStatus === "PASS" ||
      Boolean(toolEvidence.typecheckLog) ||
      Boolean(toolEvidence.command?.includes("lint")) ||
      Boolean(toolEvidence.command?.includes("typecheck"));

    if (hasLintIndicator) {
      lintersPassed = true;
      const deltaLint = 1.0986123; // ln(3.0)
      toolDelta = deltaTest + deltaLint; // ~ +4.0741
    } else {
      toolDelta = deltaTest; // ~ +2.9755
    }
  }

  // 3. Peer Review Delta with Sycophancy & CIG Discounting
  let peerDelta = 0.0;
  const seenFamilies = new Set<string>();
  const discounts: number[] = [];

  for (const rev of peerReviews) {
    const tier = rev.modelTier ?? "High";
    let alpha = 0.75;
    if (tier === "XHigh" || tier === "Max") {
      alpha = 1.0;
    } else if (tier === "High") {
      alpha = 0.75;
    } else {
      alpha = 0.30;
    }

    // Behavioral Entanglement (Common Information Gain)
    let cig = 0.20; // cross-family baseline
    if (rev.modelFamily) {
      if (seenFamilies.has(rev.modelFamily)) {
        cig = 0.70; // intra-family entanglement
      }
      seenFamilies.add(rev.modelFamily);
    }

    // Sycophancy Risk Assessment
    let risk = 0.05;
    if (rev.sycophancyRisk !== undefined) {
      risk = rev.sycophancyRisk;
    } else if (rev.claimsRepeatedWithoutEvidence) {
      risk = 0.80;
    } else if (rev.observedConfidence) {
      risk = 0.50;
    }

    discounts.push(risk);

    const w = ((1.0 - risk) / (1.0 + cig)) * alpha;
    const scoreVal = rev.score ?? 1.0;
    peerDelta += w * Math.log(4.0) * scoreVal; // ln(4.0) ~ 1.38629436
  }

  const avgSycophancyDiscount = discounts.length > 0
    ? discounts.reduce((acc, v) => acc + v, 0) / discounts.length
    : 0.0;

  // 4. Asymmetric Dissent Penalty
  let dissentDelta = 0.0;
  for (const c of critiques) {
    if (c.severity === "warning") {
      if (c.reproCommand && c.reproCommand.trim().length > 0) {
        dissentDelta += 3.5;
      } else {
        dissentDelta += 1.5;
      }
    } else if (c.severity === "advisory") {
      dissentDelta += 0.3;
    }
  }

  // 5. Total Log-Odds and Logistic Sigmoid
  const logOddsValue = prior + toolDelta + peerDelta - dissentDelta;
  const finalScore = sigmoid(logOddsValue);

  return {
    score: finalScore,
    value: finalScore,
    prior,
    toolDelta,
    toolWeight: toolDelta,
    peerDelta,
    peerWeight: peerDelta,
    dissentDelta,
    dissentPenalty: dissentDelta,
    sycophancyDiscount: avgSycophancyDiscount,
    breakdown: {
      testsPassed,
      lintersPassed,
      typecheckPassed: lintersPassed,
      peerApprovals: peerReviews.length,
      activeBlockers: critiques.filter((c) => c.severity === "blocker").length,
      activeWarnings: critiques.filter((c) => c.severity === "warning").length,
    },
  };
}

/**
 * Class wrapper for ConfidenceEngine.
 */
export class ConfidenceEngine {
  static calculate(params: CalculateConfidenceParams): ConfidenceScore {
    return calculateConfidence(params);
  }

  static sigmoid(l: number): number {
    return sigmoid(l);
  }

  static logOdds(p: number): number {
    return logOdds(p);
  }
}

// ============================================================================
// SubagentMesh (In-Memory Pub/Sub)
// ============================================================================

export class SubagentMesh {
  private subscribers = new Map<string, Set<(msg: MeshMessage) => void>>();
  private history: MeshMessage[] = [];

  subscribe(topic: SubagentTopic | "*", handler: (msg: MeshMessage) => void): () => void {
    if (!this.subscribers.has(topic)) {
      this.subscribers.set(topic, new Set());
    }
    this.subscribers.get(topic)!.add(handler);

    return () => {
      this.unsubscribe(topic, handler);
    };
  }

  unsubscribe(topic: SubagentTopic | "*", handler: (msg: MeshMessage) => void): boolean {
    const set = this.subscribers.get(topic);
    if (set) {
      return set.delete(handler);
    }
    return false;
  }

  publish(msg: MeshMessage): void {
    this.history.push(msg);

    const topicHandlers = this.subscribers.get(msg.topic);
    if (topicHandlers) {
      for (const h of topicHandlers) {
        try {
          h(msg);
        } catch (err) {
          console.error(`SubagentMesh handler error on topic '${msg.topic}':`, err);
        }
      }
    }

    const wildcardHandlers = this.subscribers.get("*");
    if (wildcardHandlers) {
      for (const h of wildcardHandlers) {
        try {
          h(msg);
        } catch (err) {
          console.error("SubagentMesh handler error on wildcard topic '*':", err);
        }
      }
    }
  }

  getHistory(filter?: { topic?: SubagentTopic; correlationId?: string }): MeshMessage[] {
    let result = this.history;
    if (filter?.topic) {
      result = result.filter((m) => m.topic === filter.topic);
    }
    if (filter?.correlationId) {
      result = result.filter((m) => m.correlationId === filter.correlationId);
    }
    return [...result];
  }

  subscriberCount(topic?: SubagentTopic | "*"): number {
    if (topic) {
      return this.subscribers.get(topic)?.size ?? 0;
    }
    let total = 0;
    for (const set of this.subscribers.values()) {
      total += set.size;
    }
    return total;
  }

  clear(): void {
    this.subscribers.clear();
    this.history = [];
  }
}

// ============================================================================
// BlackboardStream (Persistent JSONL IPC)
// ============================================================================

export class BlackboardStream {
  private basePath: string;
  private correlationId: string;
  private filePath: string;

  constructor(options: { basePath?: string; correlationId: string }) {
    this.correlationId = options.correlationId;
    this.basePath = options.basePath ?? path.join(os.homedir(), ".pi", "agent", "relay", "blackboard");
    if (!fs.existsSync(this.basePath)) {
      fs.mkdirSync(this.basePath, { recursive: true });
    }
    this.filePath = path.join(this.basePath, `${this.correlationId}.jsonl`);
  }

  getFilePath(): string {
    return this.filePath;
  }

  async append(msg: MeshMessage): Promise<void> {
    const line = JSON.stringify(msg) + "\n";
    const lockPath = `${this.filePath}.lock`;

    return new Promise<void>((resolve, reject) => {
      let resolved = false;
      const safeResolve = () => {
        if (!resolved) {
          resolved = true;
          resolve();
        }
      };
      const safeReject = (err: Error) => {
        if (!resolved) {
          resolved = true;
          reject(err);
        }
      };

      try {
        const proc = child_process.spawn(
          "flock",
          ["-x", lockPath, "tee", "-a", this.filePath],
          { stdio: ["pipe", "ignore", "pipe"] }
        );

        proc.stdin.on("error", () => {
          fs.promises.appendFile(this.filePath, line, "utf-8").then(safeResolve, safeReject);
        });

        proc.on("error", () => {
          fs.promises.appendFile(this.filePath, line, "utf-8").then(safeResolve, safeReject);
        });

        proc.on("close", (code) => {
          if (code === 0) {
            safeResolve();
          } else {
            fs.promises.appendFile(this.filePath, line, "utf-8").then(safeResolve, safeReject);
          }
        });

        proc.stdin.write(line, "utf-8", (err) => {
          if (err) {
            fs.promises.appendFile(this.filePath, line, "utf-8").then(safeResolve, safeReject);
          } else {
            proc.stdin.end();
          }
        });
      } catch {
        fs.promises.appendFile(this.filePath, line, "utf-8").then(safeResolve, safeReject);
      }
    });
  }

  async readAll(): Promise<MeshMessage[]> {
    if (!fs.existsSync(this.filePath)) {
      return [];
    }
    const content = await fs.promises.readFile(this.filePath, "utf-8");
    const lines = content.split("\n");
    const messages: MeshMessage[] = [];

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      try {
        const parsed = JSON.parse(trimmed);
        if (typeof parsed === "object" && parsed !== null && parsed.id && parsed.topic) {
          messages.push(parsed);
        }
      } catch {
        // Graceful corrupt line recovery
      }
    }

    return messages;
  }

  async readRecent(limit = 10): Promise<MeshMessage[]> {
    const all = await this.readAll();
    return all.slice(-limit);
  }

  close(): void {
    // Stream resource cleanup
  }
}

// ============================================================================
// CoordinatorEngine (Deduplication, Conflict Arbitration & DAG)
// ============================================================================

export class CoordinatorEngine {
  private deduplicationWindowSize: number;
  private deduplicationTtlMs: number;
  private seenHashes = new Map<string, number>();
  private hashQueue: string[] = [];
  private messagesByCorrelation = new Map<string, MeshMessage[]>();

  constructor(options?: { deduplicationWindowSize?: number; deduplicationTtlMs?: number }) {
    this.deduplicationWindowSize = options?.deduplicationWindowSize ?? 10000;
    this.deduplicationTtlMs = options?.deduplicationTtlMs ?? 600000;
  }

  private computeSemanticHash(msg: MeshMessage): string {
    const senderId = typeof msg.sender === "string" ? msg.sender : (msg.sender?.id ?? "");
    const raw = `${msg.topic}:${msg.correlationId}:${senderId}:${JSON.stringify(msg.payload)}`;
    return crypto.createHash("sha256").update(raw).digest("hex");
  }

  processMessage(msg: MeshMessage): { accepted: boolean; duplicate: boolean; reason?: string } {
    const now = Date.now();
    const hash = this.computeSemanticHash(msg);
    const existingTs = this.seenHashes.get(hash);

    if (existingTs !== undefined && now - existingTs < this.deduplicationTtlMs) {
      return { accepted: false, duplicate: true, reason: "Duplicate semantic hash" };
    }

    while (this.hashQueue.length >= this.deduplicationWindowSize) {
      const oldest = this.hashQueue.shift();
      if (oldest) {
        this.seenHashes.delete(oldest);
      }
    }

    this.seenHashes.set(hash, now);
    this.hashQueue.push(hash);

    if (!this.messagesByCorrelation.has(msg.correlationId)) {
      this.messagesByCorrelation.set(msg.correlationId, []);
    }
    this.messagesByCorrelation.get(msg.correlationId)!.push(msg);

    return { accepted: true, duplicate: false };
  }

  arbitrateConflict(verdicts: VerificationPayload[], critiques: CritiquePayload[]): ArbitrationResult {
    // Rule 1: Deterministic failure supremacy
    for (const v of verdicts) {
      if (v.evidence && (!v.evidence.deterministicPass || v.evidence.exitCode !== 0)) {
        return { finalVerdict: "FAIL", blocked: true, reason: "Deterministic tool failure veto" };
      }
    }

    // Rule 2: Asymmetric safety veto (blocker)
    const hasBlocker =
      critiques.some((c) => c.severity === "blocker") ||
      verdicts.some((v) => v.findings?.some((f) => f.severity === "blocker"));

    if (hasBlocker) {
      return { finalVerdict: "FAIL", blocked: true, reason: "Active blocker critique" };
    }

    // Rule 3: Peer verdict consensus
    const hasFail = verdicts.some((v) => v.verdict === "FAIL");
    if (hasFail) {
      return { finalVerdict: "FAIL", blocked: false, reason: "Peer verification rejected" };
    }

    const allPass = verdicts.length > 0 && verdicts.every((v) => v.verdict === "PASS");
    if (allPass) {
      return { finalVerdict: "PASS", blocked: false };
    }

    return { finalVerdict: "FAIL", blocked: false, reason: "Inconclusive verification" };
  }

  buildCausalDag(correlationId: string): Map<string, MeshMessage[]> {
    const dag = new Map<string, MeshMessage[]>();
    const messages = this.messagesByCorrelation.get(correlationId) || [];

    for (const msg of messages) {
      if (msg.parentMessageId) {
        if (!dag.has(msg.parentMessageId)) {
          dag.set(msg.parentMessageId, []);
        }
        dag.get(msg.parentMessageId)!.push(msg);
      }
    }

    return dag;
  }

  renderStatusLine(correlationId: string): string {
    const state = this.getActiveState(correlationId);
    return `[SUBAGENT MESH] Task: ${correlationId} | Status: ${state.status} | Confidence: ${(state.confidence * 100).toFixed(1)}% | Attempt: ${state.attempt} | Blockers: ${state.openBlockers} | Warnings: ${state.openWarnings}`;
  }

  getActiveState(correlationId: string): {
    status: string;
    confidence: number;
    openBlockers: number;
    openWarnings: number;
    attempt: number;
  } {
    const msgs = this.messagesByCorrelation.get(correlationId) || [];
    let blockers = 0;
    let warnings = 0;
    let latestConf = DEFAULT_PRIOR_CONFIDENCE;
    let status = "INIT";

    for (const m of msgs) {
      if (m.confidence) {
        latestConf = m.confidence.score;
      }
      if (m.topic === "critique") {
        const c = m.payload as CritiquePayload;
        if (c.severity === "blocker") blockers++;
        if (c.severity === "warning") warnings++;
      }
      if (m.topic === "verification") {
        const v = m.payload as VerificationPayload;
        if (v.verdict === "PASS" && latestConf >= GATE_CONFIDENCE_THRESHOLD && blockers === 0) {
          status = "GATE_READY";
        } else {
          status = "REMEDIATING";
        }
      } else if (m.topic === "draft") {
        status = "VERIFYING";
      }
    }

    return {
      status,
      confidence: latestConf,
      openBlockers: blockers,
      openWarnings: warnings,
      attempt: 1,
    };
  }
}

// ============================================================================
// PeerHandoffController (Autonomous Fix-Reverify State Machine)
// ============================================================================

export interface PeerHandoffControllerOptions {
  correlationId: string;
  maxAttempts?: number;
  onGateReady?: (verdict: VerificationPayload) => void | Promise<void>;
}

export class PeerHandoffController {
  private state: HandoffState = "DRAFTING";
  private attempt = 1;
  private maxAttempts: number;
  private correlationId: string;
  private onGateReady?: (verdict: VerificationPayload) => void | Promise<void>;

  constructor(options: PeerHandoffControllerOptions) {
    this.correlationId = options.correlationId;
    this.maxAttempts = options.maxAttempts ?? MAX_ATTEMPTS_HARD_CAP;
    this.onGateReady = options.onGateReady;
  }

  getState(): HandoffState {
    return this.state;
  }

  getAttemptCount(): number {
    return this.attempt;
  }

  submitDraft(
    payload: DraftPayload,
    _evidence?: ObjectiveVerificationEvidence
  ): { maskedPayload: DraftPayload; state: HandoffState } {
    this.state = "VERIFYING";

    // Outcome Non-Disclosure: mask author's confidence and internal reasoning
    const raw = { ...payload } as Record<string, unknown>;
    delete raw.authorConfidence;
    delete raw.authorInternalReasoning;
    delete raw.attemptNumber;
    delete raw.selfScore;

    return {
      maskedPayload: raw as DraftPayload,
      state: this.state,
    };
  }

  receiveCritiques(critiques: CritiquePayload[]): { state: HandoffState; softCheckpoint?: boolean } {
    const hasIssues = critiques.some((c) => c.severity === "blocker" || c.severity === "warning");
    if (hasIssues) {
      this.state = "REMEDIATING";
    }

    return {
      state: this.state,
      softCheckpoint: this.attempt === SOFT_CHECKPOINT_ATTEMPT,
    };
  }

  receiveVerification(verdict: VerificationPayload): {
    state: HandoffState;
    actionRequired?: string;
    softCheckpoint?: boolean;
  } {
    const passEvidence = Boolean(
      verdict.evidence &&
      verdict.evidence.deterministicPass === true &&
      verdict.evidence.exitCode === 0
    );
    const noBlockers = !verdict.findings || !verdict.findings.some((f) => f.severity === "blocker");

    const conf = calculateConfidence({
      toolEvidence: verdict.evidence,
      peerReviews: [{ score: verdict.verdict === "PASS" ? 1.0 : 0.0, modelTier: "XHigh" }],
      critiques: verdict.findings,
    });

    if (verdict.verdict === "PASS" && passEvidence && noBlockers && conf.score >= GATE_CONFIDENCE_THRESHOLD) {
      this.state = "GATE_READY";
      if (this.onGateReady) {
        try {
          this.onGateReady(verdict);
        } catch {}
      }
    } else {
      this.state = "REMEDIATING";
    }

    return { state: this.state };
  }

  remediate(): { attempt: number; softCheckpoint: boolean; escalated: boolean } {
    this.attempt++;

    if (this.attempt > this.maxAttempts) {
      this.state = "ESCALATED";
      return { attempt: this.attempt, softCheckpoint: false, escalated: true };
    }

    const soft = this.attempt === SOFT_CHECKPOINT_ATTEMPT;
    return { attempt: this.attempt, softCheckpoint: soft, escalated: false };
  }
}
