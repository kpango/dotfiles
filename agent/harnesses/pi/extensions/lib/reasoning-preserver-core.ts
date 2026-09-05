/**
 * Reasoning Token Preservation & Overthinking Prevention Core
 *
 * Provides DeepSeekHarness-style thinking token preservation across multi-turn
 * tool execution loops, token budget compaction, and circular reasoning loop detection.
 */

export interface ReasoningPreservationConfig {
  maxReasoningTokens: number;
  loopDetectionWindow: number;
  compressionThreshold: number;
  targetSummaryTokens?: number;
}

export const DEFAULT_REASONING_CONFIG: ReasoningPreservationConfig = {
  maxReasoningTokens: 16384,
  loopDetectionWindow: 3,
  compressionThreshold: 12288,
  targetSummaryTokens: 1024,
};

export interface ExtractedThinking {
  thinking: string;
  visibleText: string;
  answer: string; // alias for visibleText for backward/spec compatibility
  hasUnclosedTag: boolean;
}

export interface PreservedTurnContext {
  turnId: string;
  rawReasoningText: string;
  preservedText: string;
  tokenEstimate: number;
  isLoopDetected: boolean;
  isCompressed: boolean;
  hasToolCall: boolean;
  timestamp: number;
}

/**
 * Estimate token count using standard heuristic (~4 chars/token).
 */
export function estimateTokens(text: string): number {
  if (!text) return 0;
  return Math.ceil(text.length / 4);
}

/**
 * Extract <think>...</think> blocks from message content.
 * Handles unclosed <think> tags gracefully by capturing text up to end of message.
 */
export function extractThinkingBlocks(text: string): ExtractedThinking {
  if (!text) {
    return { thinking: "", visibleText: "", answer: "", hasUnclosedTag: false };
  }

  const thinkRegex = /<think>([\s\S]*?)(?:<\/think>|$)/gi;
  const thinkBlocks: string[] = [];
  let visibleText = "";
  let lastIndex = 0;
  let hasUnclosedTag = false;

  let match: RegExpExecArray | null;
  while ((match = thinkRegex.exec(text)) !== null) {
    // Collect visible text before the <think> tag
    const preText = text.slice(lastIndex, match.index);
    if (preText) {
      visibleText += preText;
    }

    const content = match[1] ?? "";
    thinkBlocks.push(content.trim());

    // Check if tag was unclosed
    const fullMatch = match[0];
    if (!/<\/think>/i.test(fullMatch)) {
      hasUnclosedTag = true;
    }

    lastIndex = match.index + fullMatch.length;
  }

  // Trailing text after last match
  if (lastIndex < text.length) {
    visibleText += text.slice(lastIndex);
  }

  const thinking = thinkBlocks.filter(Boolean).join("\n\n").trim();
  const cleanedVisible = visibleText.trim();

  return {
    thinking,
    visibleText: cleanedVisible,
    answer: cleanedVisible,
    hasUnclosedTag,
  };
}

/**
 * Alias conforming to spec miner specification.
 */
export function extractReasoningBlocks(text: string): { thinking: string; answer: string } {
  const res = extractThinkingBlocks(text);
  return {
    thinking: res.thinking,
    answer: res.visibleText,
  };
}

/**
 * Normalize a line for repetition and loop detection.
 */
function normalizeReasoningLine(line: string): string {
  return line
    .toLowerCase()
    .replace(/[^\w\s]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Extract word-level n-grams from text.
 */
function extractNgrams(words: string[], n: number): Set<string> {
  const ngrams = new Set<string>();
  for (let i = 0; i <= words.length - n; i++) {
    ngrams.add(words.slice(i, i + n).join(" "));
  }
  return ngrams;
}

/**
 * Detect circular reasoning loops across historical turns.
 * Checks for repeating n-grams or identical reasoning lines across >3 turns without tool calls.
 */
export function detectReasoningLoops(
  reasoningHistory: string[],
  windowSize = 3
): boolean {
  if (!reasoningHistory || reasoningHistory.length < windowSize) {
    return false;
  }

  const window = reasoningHistory.slice(-windowSize);

  // 1. Check exact or near-exact identical reasoning across all turns in window
  const normalizedTurns = window.map((r) => normalizeReasoningLine(r));
  const firstTurn = normalizedTurns[0];
  if (firstTurn && normalizedTurns.every((t) => t.length > 20 && (t === firstTurn || t.includes(firstTurn) || firstTurn.includes(t)))) {
    return true;
  }

  // 2. Line-level overlap across turns
  const turnLines = window.map((r) =>
    r
      .split("\n")
      .map(normalizeReasoningLine)
      .filter((l) => l.length > 15)
  );

  // Find lines common to all turns in window
  if (turnLines[0] && turnLines[0].length > 0) {
    const commonLines = turnLines[0].filter((line) =>
      turnLines.every((lines) => lines.includes(line))
    );
    if (commonLines.length >= 2) {
      return true;
    }
  }

  // 3. Repeating 4-grams across all turns in window
  const turnNgrams = window.map((r) => {
    const words = normalizeReasoningLine(r).split(/\s+/).filter(Boolean);
    return extractNgrams(words, 4);
  });

  if (turnNgrams[0] && turnNgrams[0].size > 0) {
    let commonNgramCount = 0;
    for (const ng of turnNgrams[0]) {
      if (turnNgrams.every((set) => set.has(ng))) {
        commonNgramCount++;
      }
    }
    if (commonNgramCount >= 3) {
      return true;
    }
  }

  return false;
}

export const LOOP_BREAKER_DIRECTIVE =
  "[Loop Breaker: Reasoning loop detected. Take decisive action immediately]";

/**
 * Compress reasoning trace into a compact <think-summary> block.
 */
export function compressReasoningTrace(fullTrace: string, targetTokenLimit = 1024): string {
  if (!fullTrace) return "";

  const lines = fullTrace
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);

  // Filter for key deduction points (deductions, hypotheses, plans, conclusions)
  const keyLines: string[] = [];
  const deductionPattern = /^(?:therefore|because|conclusion|hypothesis|step|plan|need to|must|found|deduce|summary|note|key):/i;

  for (const line of lines) {
    if (deductionPattern.test(line) || line.startsWith("-") || line.startsWith("*")) {
      keyLines.push(line);
    }
  }

  // If no patterned lines, select head and tail lines
  let summaryBody = "";
  if (keyLines.length >= 2) {
    summaryBody = keyLines.slice(0, 10).join("\n");
  } else if (lines.length > 6) {
    summaryBody = [...lines.slice(0, 3), "... [intermediate reasoning pruned] ...", ...lines.slice(-3)].join("\n");
  } else {
    summaryBody = lines.join("\n");
  }

  const approxTokens = estimateTokens(summaryBody);
  return `<think-summary tokens="${approxTokens}">\n${summaryBody}\n</think-summary>`;
}

/**
 * Process single turn reasoning in context of prior turns.
 */
export function processTurnReasoning(
  turnInput: string,
  history: PreservedTurnContext[],
  config: Partial<ReasoningPreservationConfig> = {}
): PreservedTurnContext {
  const conf: ReasoningPreservationConfig = { ...DEFAULT_REASONING_CONFIG, ...config };
  const extracted = extractThinkingBlocks(turnInput);
  const reasoningText = extracted.thinking;
  const tokenEstimate = estimateTokens(reasoningText);

  // Check reasoning loop across recent turns without tool calls
  const recentNoToolTurns: string[] = [];
  for (let i = history.length - 1; i >= 0; i--) {
    const turn = history[i];
    if (turn && !turn.hasToolCall && turn.rawReasoningText) {
      recentNoToolTurns.unshift(turn.rawReasoningText);
    } else {
      break;
    }
  }
  if (reasoningText) {
    recentNoToolTurns.push(reasoningText);
  }

  const isLoopDetected = detectReasoningLoops(recentNoToolTurns, conf.loopDetectionWindow);

  return {
    turnId: `turn-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
    rawReasoningText: reasoningText,
    preservedText: reasoningText,
    tokenEstimate,
    isLoopDetected,
    isCompressed: false,
    hasToolCall: false,
    timestamp: Date.now(),
  };
}

/**
 * Ring buffer and context manager for multi-turn reasoning preservation.
 */
export class ReasoningPreserverRingBuffer {
  private turns: PreservedTurnContext[] = [];
  private readonly config: ReasoningPreservationConfig;

  constructor(config: Partial<ReasoningPreservationConfig> = {}) {
    this.config = { ...DEFAULT_REASONING_CONFIG, ...config };
  }

  /**
   * Record reasoning from a turn.
   */
  public recordTurn(turnContent: string, hasToolCall = false, turnId?: string): PreservedTurnContext {
    const context = processTurnReasoning(turnContent, this.turns, this.config);
    if (turnId) {
      context.turnId = turnId;
    }
    context.hasToolCall = hasToolCall;

    this.turns.push(context);
    this.compactIfNeeded();
    return context;
  }

  /**
   * Mark that the current active turn executed a tool call.
   */
  public markToolCallOnCurrentTurn(): void {
    const last = this.turns[this.turns.length - 1];
    if (last) {
      last.hasToolCall = true;
    }
  }

  /**
   * Check if accumulated tokens exceed budget and compact older turns into <think-summary>.
   */
  public compactIfNeeded(): boolean {
    const totalTokens = this.getTotalTokens();
    if (totalTokens <= this.config.maxReasoningTokens) {
      return false;
    }

    // Retain full reasoning for the most recent 1-2 turns, compact older turns
    let compactedAny = false;
    const turnsToKeep = Math.min(2, this.turns.length);
    const compactableEnd = this.turns.length - turnsToKeep;

    for (let i = 0; i < compactableEnd; i++) {
      const turn = this.turns[i];
      if (turn && !turn.isCompressed && turn.rawReasoningText) {
        const compressed = compressReasoningTrace(turn.rawReasoningText, this.config.targetSummaryTokens);
        turn.preservedText = compressed;
        turn.tokenEstimate = estimateTokens(compressed);
        turn.isCompressed = true;
        compactedAny = true;

        if (this.getTotalTokens() <= this.config.compressionThreshold) {
          break;
        }
      }
    }

    return compactedAny;
  }

  /**
   * Get total estimated tokens across all preserved turns.
   */
  public getTotalTokens(): number {
    return this.turns.reduce((sum, t) => sum + t.tokenEstimate, 0);
  }

  /**
   * Returns whether any reasoning loop is currently detected in recent turns.
   */
  public isLoopActive(): boolean {
    const last = this.turns[this.turns.length - 1];
    return Boolean(last?.isLoopDetected);
  }

  /**
   * Check if there is any preserved context available.
   */
  public hasPreservedContext(): boolean {
    return this.turns.some((t) => Boolean(t.preservedText));
  }

  /**
   * Format all preserved reasoning into an injection block for next model turn.
   */
  public formatContextForPrompt(): string {
    if (this.turns.length === 0) return "";

    const blocks: string[] = [];

    // Loop breaker warning if circular reasoning detected
    if (this.isLoopActive()) {
      blocks.push(LOOP_BREAKER_DIRECTIVE);
    }

    const preservedTraces = this.turns
      .filter((t) => Boolean(t.preservedText))
      .map((t, idx) => `[Turn ${idx + 1} Reasoning]\n${t.preservedText}`);

    if (preservedTraces.length > 0) {
      blocks.push(
        `[PRESERVED REASONING CONTEXT]\n${preservedTraces.join("\n\n")}\n[END REASONING CONTEXT]`
      );
    }

    return blocks.join("\n\n");
  }

  /**
   * Get historical turn contexts.
   */
  public getTurns(): PreservedTurnContext[] {
    return [...this.turns];
  }

  /**
   * Clear all preserved context.
   */
  public clear(): void {
    this.turns = [];
  }

  /**
   * Count of recorded turns.
   */
  public size(): number {
    return this.turns.length;
  }
}
