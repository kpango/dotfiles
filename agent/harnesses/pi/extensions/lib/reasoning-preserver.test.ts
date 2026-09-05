/**
 * Unit Tests for Reasoning Preserver Core
 *
 * Tests <think> block extraction, unclosed tag handling, token budget
 * compaction into <think-summary>, and circular overthinking loop detection.
 */

import {
  extractThinkingBlocks,
  extractReasoningBlocks,
  estimateTokens,
  detectReasoningLoops,
  compressReasoningTrace,
  processTurnReasoning,
  ReasoningPreserverRingBuffer,
  LOOP_BREAKER_DIRECTIVE,
} from "./reasoning-preserver-core";

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

function eq<T>(name: string, actual: T, expected: T, msg?: string) {
  const ok = actual === expected;
  check(name, ok, msg || `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

// 1. Basic <think> extraction
const standardInput = "<think>We need to check the filesystem first.</think>Here is the directory listing.";
const extracted1 = extractThinkingBlocks(standardInput);
eq("Standard <think> extraction thinking text", extracted1.thinking, "We need to check the filesystem first.");
eq("Standard <think> extraction visible text", extracted1.visibleText, "Here is the directory listing.");
eq("Standard <think> hasUnclosedTag is false", extracted1.hasUnclosedTag, false);

// 2. Spec-compatible alias extractReasoningBlocks
const specExtracted = extractReasoningBlocks(standardInput);
eq("extractReasoningBlocks returns thinking", specExtracted.thinking, "We need to check the filesystem first.");
eq("extractReasoningBlocks returns answer", specExtracted.answer, "Here is the directory listing.");

// 3. Multiple <think> blocks
const multiInput = "<think>Step 1: check git status.</think>Running git status...\n<think>Step 2: inspect diff.</think>Here is the diff.";
const extracted2 = extractThinkingBlocks(multiInput);
check(
  "Multiple think blocks joined",
  extracted2.thinking.includes("Step 1: check git status.") && extracted2.thinking.includes("Step 2: inspect diff.")
);
check(
  "Multiple visible segments preserved",
  extracted2.visibleText.includes("Running git status...") && extracted2.visibleText.includes("Here is the diff.")
);

// 4. Text without <think> tags
const noThinkInput = "Just a direct response to the user with no internal monologue.";
const extracted3 = extractThinkingBlocks(noThinkInput);
eq("No think tag yields empty thinking", extracted3.thinking, "");
eq("No think tag preserves full visible text", extracted3.visibleText, noThinkInput);
eq("No think tag hasUnclosedTag is false", extracted3.hasUnclosedTag, false);

// 5. Unclosed <think> tag handling
const unclosedInput = "<think>I am pondering the meaning of life and never closed this tag";
const extracted4 = extractThinkingBlocks(unclosedInput);
eq(
  "Unclosed tag captures thinking text up to EOF",
  extracted4.thinking,
  "I am pondering the meaning of life and never closed this tag"
);
eq("Unclosed tag flags hasUnclosedTag true", extracted4.hasUnclosedTag, true);

// 6. Token estimation
const shortText = "Hello world";
const tokens = estimateTokens(shortText);
check("estimateTokens produces reasonable token count (~3)", tokens >= 2 && tokens <= 4);

// 7. Compacting reasoning trace into <think-summary>
const verboseTrace = `
Need to investigate the memory leak.
Step 1: Run heap profiler on port 6060.
Found memory retention in cache map.
Therefore: We should implement an LRU eviction policy with TTL.
Conclusion: Replace Map with LRUCache to resolve leak.
`;
const compressed = compressReasoningTrace(verboseTrace, 50);
check("compressReasoningTrace outputs <think-summary>", compressed.startsWith("<think-summary tokens="));
check("compressReasoningTrace preserves conclusion", compressed.includes("Conclusion: Replace Map with LRUCache"));

// 8. Loop detection across >3 turns without tool calls
const loopTurn1 = "Let me analyze the log again. The server returned 502 bad gateway.";
const loopTurn2 = "Let me analyze the log again. The server returned 502 bad gateway.";
const loopTurn3 = "Let me analyze the log again. The server returned 502 bad gateway.";
const isLoop = detectReasoningLoops([loopTurn1, loopTurn2, loopTurn3], 3);
check("detectReasoningLoops detects identical reasoning across 3 turns", isLoop === true);

const diverseTurn1 = "Investigating connection timeouts in gateway.";
const diverseTurn2 = "Found packet drop at firewall ruleset.";
const diverseTurn3 = "Applying network rule to allow port 443 traffic.";
const isNotLoop = detectReasoningLoops([diverseTurn1, diverseTurn2, diverseTurn3], 3);
check("detectReasoningLoops returns false for progressive reasoning", isNotLoop === false);

// 9. ReasoningPreserverRingBuffer: multi-turn tracking and loop detection
const buffer = new ReasoningPreserverRingBuffer({
  maxReasoningTokens: 100, // low threshold to test compaction
  loopDetectionWindow: 3,
  compressionThreshold: 60,
  targetSummaryTokens: 20,
});

// Turn 1: Normal
buffer.recordTurn("<think>Step 1: Reading file A.</think>Done reading.", false);
check("Turn 1 recorded", buffer.size() === 1);
check("No loop on turn 1", buffer.isLoopActive() === false);

// Turn 2: Repetitive
buffer.recordTurn("<think>Checking the same file again and pondering.</think>", false);
check("Turn 2 recorded", buffer.size() === 2);
check("No loop on turn 2", buffer.isLoopActive() === false);

// Turn 3: Repetitive
buffer.recordTurn("<think>Checking the same file again and pondering.</think>", false);
check("Turn 3 recorded", buffer.size() === 3);

// Turn 4: Repetitive without tool calls
buffer.recordTurn("<think>Checking the same file again and pondering.</think>", false);
check("Loop detected on turn 4 (3 consecutive identical turns without tool calls)", buffer.isLoopActive() === true);

const promptContext = buffer.formatContextForPrompt();
check("Prompt context contains loop breaker directive", promptContext.includes(LOOP_BREAKER_DIRECTIVE));

// 10. Intervening tool call breaks the loop
const bufferWithTools = new ReasoningPreserverRingBuffer({ loopDetectionWindow: 3 });
bufferWithTools.recordTurn("<think>Checking system state.</think>", false);
bufferWithTools.recordTurn("<think>Checking system state.</think>", true); // tool called here
bufferWithTools.recordTurn("<think>Checking system state.</think>", false);
check("Intervening tool call prevents loop false positive", bufferWithTools.isLoopActive() === false);

// 11. Token budget compaction in ring buffer
const budgetBuffer = new ReasoningPreserverRingBuffer({
  maxReasoningTokens: 100,
  compressionThreshold: 80,
  targetSummaryTokens: 30,
});

const longReasoning1 = `<think>
${"Very detailed long analysis line. ".repeat(20)}
Therefore: First deduction made.
</think>Done 1`;

const longReasoning2 = `<think>
${"Another extensive explanation line. ".repeat(20)}
Therefore: Second deduction made.
</think>Done 2`;

const longReasoning3 = `<think>
${"Third extensive reasoning line. ".repeat(20)}
Therefore: Third deduction made.
</think>Done 3`;

budgetBuffer.recordTurn(longReasoning1, true);
budgetBuffer.recordTurn(longReasoning2, true);
budgetBuffer.recordTurn(longReasoning3, true);

const turns = budgetBuffer.getTurns();
check("Older turn was compressed when budget exceeded", turns[0].isCompressed === true);
check("Older turn has <think-summary>", turns[0].preservedText.includes("<think-summary"));
check("Recent turn remains uncompressed", turns[2].isCompressed === false);

console.log(`\nreasoning-preserver.test: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
