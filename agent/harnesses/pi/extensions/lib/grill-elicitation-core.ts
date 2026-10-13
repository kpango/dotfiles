/**
 * Grill Elicitation Core Library for Pi Coding Agent
 *
 * Implements the interactive design-tree interview protocol to prevent
 * cognitive drift, clarify requirements, and autonomously synthesize
 * CONTEXT.md invariants.
 */

import * as fs from "node:fs";
import * as path from "node:path";

export interface OptionItem {
  label: string;
  description: string;
  recommended?: boolean;
  rationale?: string;
}

export interface DesignTreeNode {
  id: string;
  parentId?: string;
  level: 1 | 2 | 3 | 4; // 1: Architecture & Boundaries, 2: Behavior & Edge Cases, 3: Consistency & Compatibility, 4: Implementation & Tests
  category: string;
  question: string;
  background?: string;
  options: OptionItem[];
  recommendedIndex: number;
  selectedOption?: string;
  rationale?: string;
  answeredAt?: string;
}

export interface InterviewSession {
  id: string;
  topic: string;
  createdAt: string;
  updatedAt: string;
  nodes: DesignTreeNode[];
  status: "in_progress" | "completed" | "cancelled";
  currentQuestionIndex: number;
}

/**
 * Creates a new design-tree interview session.
 */
export function createInterviewSession(topic: string, initialNodes?: Omit<DesignTreeNode, "id">[]): InterviewSession {
  const id = `grill-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const now = new Date().toISOString();

  const session: InterviewSession = {
    id,
    topic: topic.trim() || "System Design",
    createdAt: now,
    updatedAt: now,
    nodes: [],
    status: "in_progress",
    currentQuestionIndex: 0,
  };

  if (initialNodes && initialNodes.length > 0) {
    for (const node of initialNodes) {
      addQuestionNode(session, node);
    }
  }

  return session;
}

/**
 * Adds a new question node to the interview session.
 */
export function addQuestionNode(
  session: InterviewSession,
  node: Omit<DesignTreeNode, "id">
): DesignTreeNode {
  const id = `q${session.nodes.length + 1}`;
  const fullNode: DesignTreeNode = {
    ...node,
    id,
  };

  // Ensure recommendedIndex is within bounds
  if (fullNode.options.length > 0) {
    if (fullNode.recommendedIndex < 0 || fullNode.recommendedIndex >= fullNode.options.length) {
      fullNode.recommendedIndex = 0;
    }
    // Tag the recommended option
    fullNode.options = fullNode.options.map((opt, idx) => ({
      ...opt,
      recommended: idx === fullNode.recommendedIndex,
    }));
  }

  session.nodes.push(fullNode);
  session.updatedAt = new Date().toISOString();
  return fullNode;
}

/**
 * Records an answer for a specific question node in the interview session.
 */
/**
 * Resolve which option a `selectedLabel` refers to. Exact label match wins;
 * otherwise the option whose label is the LONGEST one contained in the selected
 * label (so a short label like "A" does not shadow the actually-chosen "AB").
 * Returns -1 when nothing matches. Guarantees a single unambiguous selection.
 */
export function resolveSelectedOptionIndex(options: OptionItem[], selectedLabel: string): number {
  const exact = options.findIndex((o) => o.label === selectedLabel);
  if (exact !== -1) return exact;
  let best = -1;
  let bestLen = -1;
  options.forEach((o, i) => {
    if (o.label && selectedLabel.includes(o.label) && o.label.length > bestLen) {
      best = i;
      bestLen = o.label.length;
    }
  });
  return best;
}

export function recordAnswer(
  session: InterviewSession,
  nodeId: string,
  selectedOption: string,
  rationale?: string
): boolean {
  const node = session.nodes.find((n) => n.id === nodeId);
  if (!node) {
    return false;
  }

  node.selectedOption = selectedOption;
  const matchedIdx = resolveSelectedOptionIndex(node.options, selectedOption);
  const matchedOption = matchedIdx !== -1 ? node.options[matchedIdx] : undefined;

  node.rationale = rationale || matchedOption?.rationale || `Selected: ${selectedOption}`;
  node.answeredAt = new Date().toISOString();

  // Advance question index
  const nextUnansweredIdx = session.nodes.findIndex((n) => !n.selectedOption);
  session.currentQuestionIndex = nextUnansweredIdx >= 0 ? nextUnansweredIdx : session.nodes.length;

  // Check completion
  const allAnswered = session.nodes.length > 0 && session.nodes.every((n) => Boolean(n.selectedOption));
  if (allAnswered) {
    session.status = "completed";
  }

  session.updatedAt = new Date().toISOString();
  return true;
}

/**
 * Retrieves the next unanswered question node, or null if all are answered.
 */
export function getNextPendingQuestion(session: InterviewSession): DesignTreeNode | null {
  const node = session.nodes.find((n) => !n.selectedOption);
  return node || null;
}

/**
 * Generates default structured questions for a given topic across all 4 levels.
 */
export function generateDefaultInterviewTree(topic: string): Omit<DesignTreeNode, "id">[] {
  return [
    {
      level: 1,
      category: "Architecture & Boundaries",
      question: `What is the architectural boundary and responsibility scope for "${topic}"?`,
      background: `Clarifies module segregation, data flow, and whether this belongs to core, extension, or dedicated service.`,
      options: [
        {
          label: "In-process Native Extension",
          description: "Implement directly within the host runtime process for maximum performance and zero IPC overhead.",
          recommended: true,
          rationale: "Aligns with Ponytail stdlib-first and platform-native principles; minimizes operational complexity.",
        },
        {
          label: "Decoupled Daemon / External Service",
          description: "Run as an independent background daemon communicating via Unix socket or HTTP.",
          recommended: false,
          rationale: "Provides process isolation but introduces IPC serialization latency and lifecycle management overhead.",
        },
        {
          label: "Dynamic Plugin Hook",
          description: "Expose runtime hook points allowing custom third-party scripts to be loaded dynamically.",
          recommended: false,
          rationale: "High flexibility but potential security and stability hazards; violates YAGNI if only 1 consumer exists.",
        },
      ],
      recommendedIndex: 0,
    },
    {
      level: 2,
      category: "Behavior & Edge Cases",
      question: `How should edge cases, failures, and non-interactive environments be handled?`,
      background: `Ensures robust error propagation, timeout recovery, and headless automation safety.`,
      options: [
        {
          label: "Deterministic Fallback with Structured Error Details",
          description: "Never crash or hang indefinitely; return explicit typed fallback defaults and structured error details.",
          recommended: true,
          rationale: "Fulfills Vald Law 5 (never discard errors) and guarantees CI/headless safety without interactive prompts.",
        },
        {
          label: "Fail-fast Panic / Throw",
          description: "Immediately throw an unrecoverable exception or exit on any unexpected condition.",
          recommended: false,
          rationale: "Strict, but disrupts batch workflows and multi-agent coordination without offering self-healing.",
        },
        {
          label: "Silent Best-effort Recovery",
          description: "Catch and swallow errors, returning partial or empty results.",
          recommended: false,
          rationale: "Strictly prohibited by Vald Law 5 and Ponytail safety invariants.",
        },
      ],
      recommendedIndex: 0,
    },
    {
      level: 3,
      category: "Consistency & Compatibility",
      question: `What consistency invariants, naming conventions, and compatibility guarantees apply?`,
      background: `Guarantees backward compatibility with existing configs, single source of truth, and idiomatic naming.`,
      options: [
        {
          label: "Strict SSoT Alignment & Kebab-case Conventions",
          description: "Enforce single source of truth (agent/ hierarchy) and standard naming conventions with zero intermediate symlinks.",
          recommended: true,
          rationale: "Complies with dotfiles SSoT rules and multi-harness consistency verified by sync-verify.sh.",
        },
        {
          label: "Permissive Legacy Shim Support",
          description: "Maintain multiple legacy alias mappings and backward-compatible bridge shims indefinitely.",
          recommended: false,
          rationale: "Adds cognitive load and technical debt; violates Ponytail minimal code principle.",
        },
      ],
      recommendedIndex: 0,
    },
    {
      level: 4,
      category: "Implementation & Tests",
      question: `What is the verification strategy and test coverage requirement?`,
      background: `Defines automated test execution, deterministic assertions, and CI gating commands.`,
      options: [
        {
          label: "Standalone Bun Unit Tests + Multi-harness Suite",
          description: "Author deterministic standalone unit tests (100% pass) and verify with validate-harness.sh.",
          recommended: true,
          rationale: "Fast, isolated, reproducible execution with zero external server dependencies.",
        },
        {
          label: "End-to-end Integration Only",
          description: "Rely solely on manual interactive testing and full system E2E runs.",
          recommended: false,
          rationale: "Slow, non-deterministic, and prone to silent regressions.",
        },
      ],
      recommendedIndex: 0,
    },
  ];
}

/**
 * Formats a question node as a markdown prompt with recommended badges.
 */
export function formatQuestionPrompt(node: DesignTreeNode, index?: number): string {
  const qNum = index !== undefined ? index + 1 : node.id.replace(/^q/, "");
  const lines: string[] = [];

  lines.push(`### [Grill Q${qNum}] ${node.question}`);
  lines.push("");
  if (node.background) {
    lines.push(node.background);
    lines.push("");
  }

  node.options.forEach((opt, idx) => {
    const isRec = idx === node.recommendedIndex || opt.recommended;
    const badge = isRec ? " [Recommended]" : "";
    const box = isRec ? "[x]" : "[ ]";
    lines.push(`- ${box} **Option ${String.fromCharCode(65 + idx)}${badge}** ${opt.label}: ${opt.description}`);
  });

  lines.push("");
  const recOpt = node.options[node.recommendedIndex] || node.options[0];
  if (recOpt) {
    lines.push(`**推奨理由**: ${recOpt.rationale || "Adheres to simplicity, performance, and robustness."}`);
  }

  return lines.join("\n");
}

/**
 * Synthesizes domain glossary and system invariants into CONTEXT.md format.
 */
export function synthesizeContext(
  session: InterviewSession,
  existingContext?: string
): string {
  const glossaryItems: { term: string; definition: string }[] = [];
  const invariants: string[] = [];
  const boundaries: string[] = [];
  const constraints: string[] = [];

  glossaryItems.push({
    term: session.topic,
    definition: `Domain component scoped during Grilling elicitation session ${session.id}.`,
  });

  for (const node of session.nodes) {
    const chosen = node.selectedOption || (node.options[node.recommendedIndex]?.label ?? "Standard");
    glossaryItems.push({
      term: `${node.category} Design Choice`,
      definition: `${chosen} — selected for ${node.question}`,
    });

    if (node.level === 1) {
      boundaries.push(`Allowed dependency direction: ${session.topic} operates within ${chosen} without circular dependencies.`);
    } else if (node.level === 2) {
      invariants.push(`Invariant-1 (Behavior & Error Handling): ${chosen} — ${node.rationale || "Deterministic error propagation."}`);
    } else if (node.level === 3) {
      invariants.push(`Invariant-2 (Consistency): ${chosen} — adheres to SSoT naming and configuration contracts.`);
    } else if (node.level === 4) {
      invariants.push(`Invariant-3 (Verification): Tests must pass with 100% success rate.`);
      constraints.push(`Test constraint: ${chosen}`);
    }
  }

  if (boundaries.length === 0) {
    boundaries.push(`Allowed dependency direction: Caller -> ${session.topic} (Strict unidirectional dependency).`);
    boundaries.push(`Error handling protocol: Structured error returns without silent swallowing.`);
  }

  if (invariants.length === 0) {
    invariants.push(`Invariant-1 (Precondition): Valid configuration and parameters must be supplied.`);
    invariants.push(`Invariant-2 (State Transition): Session status moves monotonically from in_progress to completed.`);
    invariants.push(`Invariant-3 (Postcondition): Output artifacts adhere strictly to standardized schemas.`);
  }

  if (constraints.length === 0) {
    constraints.push(`Constraints: Zero external runtime overhead; POSIX and Bun compatible.`);
    constraints.push(`Non-Goals: Out-of-scope speculative generality or unnecessary third-party dependencies.`);
  }

  // If existingContext is provided, parse and supplement
  if (existingContext && existingContext.trim().length > 0) {
    let result = existingContext.trim();

    // Check if sections exist; if so, append new items under their respective headings
    const sectionsToAppend = [
      { header: "## 1. ドメイン用語集 (Domain Glossary)", items: glossaryItems.map((g) => `- **${g.term}**: ${g.definition}`) },
      { header: "## 2. システム不変条件 (System Invariants)", items: invariants.map((i) => `- ${i}`) },
      { header: "## 3. 責務境界と入出力規約 (Boundary & Contracts)", items: boundaries.map((b) => `- ${b}`) },
      { header: "## 4. 既知の制約と非目標 (Constraints & Non-Goals)", items: constraints.map((c) => `- ${c}`) },
    ];

    let updated = result;
    for (const sec of sectionsToAppend) {
      if (updated.includes(sec.header)) {
        const insertIdx = updated.indexOf(sec.header) + sec.header.length;
        const addition = "\n" + sec.items.join("\n");
        updated = updated.slice(0, insertIdx) + addition + updated.slice(insertIdx);
      }
    }
    return updated + "\n";
  }

  const lines: string[] = [
    `# CONTEXT — ${session.topic}`,
    "",
    `## 1. ドメイン用語集 (Domain Glossary)`,
  ];
  for (const g of glossaryItems) {
    lines.push(`- **${g.term}**: ${g.definition}`);
  }

  lines.push("");
  lines.push(`## 2. システム不変条件 (System Invariants)`);
  for (const inv of invariants) {
    lines.push(`- ${inv}`);
  }

  lines.push("");
  lines.push(`## 3. 責務境界と入出力規約 (Boundary & Contracts)`);
  for (const b of boundaries) {
    lines.push(`- ${b}`);
  }

  lines.push("");
  lines.push(`## 4. 既知の制約と非目標 (Constraints & Non-Goals)`);
  for (const c of constraints) {
    lines.push(`- ${c}`);
  }
  lines.push("");

  return lines.join("\n");
}

/**
 * Formats a status report for the interview session.
 */
export function formatStatusReport(session: InterviewSession): string {
  const total = session.nodes.length;
  const answered = session.nodes.filter((n) => Boolean(n.selectedOption)).length;
  const percent = total > 0 ? Math.round((answered / total) * 100) : 0;

  const lines: string[] = [
    `📊 **Grill Interview Status Report: ${session.topic}**`,
    `• Session ID: \`${session.id}\``,
    `• Status: **${session.status.toUpperCase()}** (${answered}/${total} answered, ${percent}%)`,
    "",
  ];

  if (session.nodes.length > 0) {
    lines.push("### Design Tree Decisions:");
    session.nodes.forEach((node, idx) => {
      const isAnswered = Boolean(node.selectedOption);
      const icon = isAnswered ? "✅" : "⏳";
      lines.push(`${icon} **Q${idx + 1} (${node.category})**: ${node.question}`);
      if (isAnswered) {
        lines.push(`   └ Selected: **${node.selectedOption}**`);
        if (node.rationale) {
          lines.push(`     Rationale: ${node.rationale}`);
        }
      } else {
        const rec = node.options[node.recommendedIndex]?.label || "Option A";
        lines.push(`   └ [Pending] Recommended: **${rec}**`);
      }
    });
  } else {
    lines.push("No questions registered yet. Use \`addQuestionNode\` or start with default tree.");
  }

  const nextQ = getNextPendingQuestion(session);
  if (nextQ) {
    lines.push("");
    lines.push("---");
    lines.push("**Next Question To Answer:**");
    lines.push(formatQuestionPrompt(nextQ));
  }

  return lines.join("\n");
}
