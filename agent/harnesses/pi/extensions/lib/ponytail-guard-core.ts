/**
 * Ponytail Guard Core Library for Pi Coding Agent
 *
 * Implements the 7-step anti-overengineering logic ladder and safety guard
 * to eliminate speculative abstractions, dependency bloat, and gratuitous churn
 * while strictly enforcing error propagation, bounds checks, and security invariants.
 */

export interface LadderStep {
  step: number;
  name: string;
  question: string;
  rule: string;
}

export interface BloatFinding {
  step: number;
  ruleName: string;
  severity: "info" | "warning" | "error";
  message: string;
  location?: { line?: number; file?: string };
  suggestion: string;
}

export interface SafetyFinding {
  type: "error_suppression" | "missing_bounds_check" | "security_violation" | "type_safety";
  severity: "warning" | "error";
  message: string;
  location?: { line?: number; file?: string };
  remedy: string;
}

export interface AuditResult {
  passed: boolean;
  bloatScore: number; // 0 to 100 (0 = pure minimal, >20 = flagged bloat)
  bloatFindings: BloatFinding[];
  safetyFindings: SafetyFinding[];
  suggestions: string[];
  metrics: {
    linesOfCode: number;
    cyclomaticComplexityEstimate?: number;
    dependencyCount?: number;
  };
}

/**
 * Returns the canonical 7-step Ponytail anti-overengineering logic ladder.
 */
export function getLadderSteps(): LadderStep[] {
  return [
    {
      step: 1,
      name: "YAGNI",
      question: "Is this abstraction, interface, parameter, or future hook strictly necessary right now?",
      rule: "Delete speculative features, premature abstractions, and unused config parameters. Solve only the concrete case at hand.",
    },
    {
      step: 2,
      name: "Codebase reuse",
      question: "Is there already a helper, utility, type, or regex in the codebase that does this?",
      rule: "Reuse existing, tested repository components before authoring new ones. Avoid wheel reinvention.",
    },
    {
      step: 3,
      name: "Stdlib first",
      question: "Can the language standard library solve this without third-party dependencies?",
      rule: "Prefer Go stdlib, Rust std, Python standard library, Node/Bun built-ins over external packages.",
    },
    {
      step: 4,
      name: "Platform native",
      question: "Can the host platform (Linux / POSIX / Bun) handle this natively?",
      rule: "Leverage native filesystem primitives, pipes, environment variables, coreutils rather than reinventing in app layer.",
    },
    {
      step: 5,
      name: "Minimal dependency",
      question: "If an external dependency is indispensable, is it minimal without heavy transitive trees?",
      rule: "Evaluate transitive dependency trees, binary size impact, and maintenance health strictly.",
    },
    {
      step: 6,
      name: "Minimal expression",
      question: "Can this be written in 1-5 direct, idiomatic lines instead of a complex pattern?",
      rule: "Write linear, readable code with minimal cognitive jumps; reject 50-line design patterns for trivial tasks.",
    },
    {
      step: 7,
      name: "Surgical minimal diff",
      question: "Does the diff contain only minimal changes with zero gratuitous churn?",
      rule: "Zero unsolicited refactoring, zero gratuitous renaming, zero whitespace churn. Keep diffs reviewable and focused.",
    },
  ];
}

/**
 * Normalizes language name from explicit parameter or filename extension.
 */
function detectLanguage(language?: string, filename?: string): string {
  if (language && language.trim().length > 0) {
    const l = language.toLowerCase().trim();
    if (["go", "golang"].includes(l)) return "go";
    if (["ts", "typescript", "tsx"].includes(l)) return "typescript";
    if (["js", "javascript", "jsx"].includes(l)) return "javascript";
    if (["py", "python"].includes(l)) return "python";
    if (["rs", "rust"].includes(l)) return "rust";
    if (["sh", "bash", "zsh", "shell"].includes(l)) return "shell";
    if (["c", "cpp", "c++", "h", "hpp"].includes(l)) return "cpp";
    return l;
  }

  if (filename) {
    const ext = filename.split(".").pop()?.toLowerCase();
    switch (ext) {
      case "go": return "go";
      case "ts":
      case "tsx": return "typescript";
      case "js":
      case "jsx": return "javascript";
      case "py": return "python";
      case "rs": return "rust";
      case "sh":
      case "zsh": return "shell";
      case "c":
      case "cpp":
      case "cc":
      case "h":
      case "hpp": return "cpp";
    }
  }

  return "typescript";
}

/**
 * Audits source code against the Ponytail 7-step ladder and safety invariants.
 */
export function auditCode(code: string, language?: string, filename?: string): AuditResult {
  const lang = detectLanguage(language, filename);
  const bloatFindings: BloatFinding[] = [];
  const safetyFindings: SafetyFinding[] = [];
  const suggestions: string[] = [];

  const lines = code.split("\n");
  const nonBlankLines = lines.filter((l) => l.trim().length > 0 && !l.trim().startsWith("//") && !l.trim().startsWith("#"));
  const loc = nonBlankLines.length;

  let anyCount = 0;

  // Global multiline error suppression checks
  if (lang === "typescript" || lang === "javascript") {
    const emptyCatchRegex = /catch\s*(?:\([^)]*\))?\s*\{\s*\}/g;
    let match;
    while ((match = emptyCatchRegex.exec(code)) !== null) {
      const lineNum = code.slice(0, match.index).split("\n").length;
      safetyFindings.push({
        type: "error_suppression",
        severity: "error",
        message: `Empty catch block silently suppresses exceptions without logging or propagation.`,
        location: { line: lineNum, file: filename },
        remedy: `Log the caught error or rethrow with structured context. Never swallow errors silently.`,
      });
    }
  }

  if (lang === "python") {
    const pyPassRegex = /except(?:\s+[^:]+)?:\s*(?:#[^\n]*\n\s*|\n\s*|\s+)pass\b/g;
    let matchPy;
    while ((matchPy = pyPassRegex.exec(code)) !== null) {
      const lineNum = code.slice(0, matchPy.index).split("\n").length;
      safetyFindings.push({
        type: "error_suppression",
        severity: "error",
        message: `Silent exception suppression ('except: pass') masks critical failures.`,
        location: { line: lineNum, file: filename },
        remedy: `Catch specific exceptions and log or re-raise. Never pass silently.`,
      });
    }
  }

  // Scan lines for bloat patterns and safety invariants
  for (let i = 0; i < lines.length; i++) {
    const lineNum = i + 1;
    const line = lines[i];
    const trimmed = line.trim();

    // ------------------------------------------------------------------------
    // Safety Invariant 1: Error Discarding / Suppression (Never Ignore Errors)
    // ------------------------------------------------------------------------
    // Go: _ = err or _, _ = ... err
    if (lang === "go") {
      if (/\b_\s*=\s*err\b/.test(trimmed) || (/\b_,\s*err\s*:=/.test(trimmed) && /_\s*=\s*err/.test(code))) {
        safetyFindings.push({
          type: "error_suppression",
          severity: "error",
          message: `Discarded error with '_ = err' violates Vald Law 5 and Ponytail Safety Invariants.`,
          location: { line: lineNum, file: filename },
          remedy: `Explicitly propagate the error ('if err != nil { return ..., err }') or handle it with appropriate context.`,
        });
      }
    }

    if (lang === "typescript" || lang === "javascript") {
      // Check for excessive 'any'
      const matchesAny = trimmed.match(/:\s*any\b/g);
      if (matchesAny) {
        anyCount += matchesAny.length;
      }
    }

    // ------------------------------------------------------------------------
    // Safety Invariant 2: Security Violations (Shell Injection / Path Traversal)
    // ------------------------------------------------------------------------
    // Shell execution with string concatenation
    if (lang === "typescript" || lang === "javascript") {
      if (/(?:exec|execSync)\s*\(\s*`[^`]*\$\{/.test(line) || /(?:exec|execSync)\s*\([^)]*\+\s*\w+/.test(line)) {
        safetyFindings.push({
          type: "security_violation",
          severity: "error",
          message: `Command execution using dynamic string interpolation risks shell injection vulnerabilities.`,
          location: { line: lineNum, file: filename },
          remedy: `Use 'execFile', 'spawn', or array-argument execution primitives without shell interpolation.`,
        });
      }
    }

    if (lang === "python") {
      if (/os\.system\s*\(\s*f?["'].*\{/.test(line) || /subprocess\.Popen\s*\([^)]*shell\s*=\s*True/.test(line)) {
        safetyFindings.push({
          type: "security_violation",
          severity: "error",
          message: `Shell execution with shell=True or os.system string formatting invites command injection.`,
          location: { line: lineNum, file: filename },
          remedy: `Use subprocess.run(['cmd', arg1, arg2], shell=False).`,
        });
      }
    }

    // ------------------------------------------------------------------------
    // Step 3: Stdlib First (Non-stdlib imports when stdlib suffices)
    // ------------------------------------------------------------------------
    if (lang === "typescript" || lang === "javascript") {
      // Lodash when Array methods / Object methods suffice
      if (/(?:import|from|require\s*\()\s*["']lodash(?:\/.*)?["']/.test(trimmed)) {
        bloatFindings.push({
          step: 3,
          ruleName: "Stdlib First (JS/TS)",
          severity: "warning",
          message: `Importing 'lodash' introduces dependency bloat when built-in Array and Object methods suffice.`,
          location: { line: lineNum, file: filename },
          suggestion: `Replace lodash utilities with native Array.prototype (map, filter, reduce, some) and Object.entries/fromEntries.`,
        });
      }

      // Moment when Date / Intl suffices
      if (/(?:import|from|require\s*\()\s*["']moment["']/.test(trimmed)) {
        bloatFindings.push({
          step: 3,
          ruleName: "Stdlib First (JS/TS)",
          severity: "warning",
          message: `Importing 'moment' adds a heavy legacy dependency.`,
          location: { line: lineNum, file: filename },
          suggestion: `Use standard JavaScript 'Date', 'Intl.DateTimeFormat', or lightweight native time calculations.`,
        });
      }

      // Axios or request when web-standard fetch suffices
      if (/(?:import|from|require\s*\()\s*["'](?:axios|request)["']/.test(trimmed)) {
        bloatFindings.push({
          step: 3,
          ruleName: "Stdlib First (JS/TS)",
          severity: "warning",
          message: `External HTTP client ('axios'/'request') is redundant with web-standard 'fetch' available natively in Node 18+ and Bun.`,
          location: { line: lineNum, file: filename },
          suggestion: `Use built-in global 'fetch()' with standard Request/Response APIs.`,
        });
      }
    }

    // ------------------------------------------------------------------------
    // Step 1: YAGNI (Speculative Abstractions & Builder / Factory Patterns)
    // ------------------------------------------------------------------------
    if (/(?:class|interface)\s+\w+Builder\b/.test(trimmed)) {
      bloatFindings.push({
        step: 1,
        ruleName: "YAGNI / Anti-Overengineering",
        severity: "warning",
        message: `Builder pattern detected. In TypeScript/modern languages, typed object options replace builder classes.`,
        location: { line: lineNum, file: filename },
        suggestion: `Use a plain TypeScript interface/type with default parameter values instead of a multi-method Builder class.`,
      });
    }

    if (/(?:class|interface)\s+\w+Factory\b/.test(trimmed)) {
      bloatFindings.push({
        step: 1,
        ruleName: "YAGNI / Anti-Overengineering",
        severity: "warning",
        message: `Factory class detected. Plain functions or direct constructor calls eliminate unnecessary cognitive jumps.`,
        location: { line: lineNum, file: filename },
        suggestion: `Export a simple factory function 'createX()' or instantiate directly rather than creating a Factory class.`,
      });
    }

    // ------------------------------------------------------------------------
    // Step 6: Minimal Expression (Unnecessary static-only wrapper classes)
    // ------------------------------------------------------------------------
    if (/(?:public\s+|private\s+)?static\s+\w+\s*\(/.test(trimmed) && trimmed.includes("static")) {
      // Check if file consists mostly of static methods inside a class
      if (/class\s+\w+Utils\b|class\s+\w+Helper\b/.test(code)) {
        bloatFindings.push({
          step: 6,
          ruleName: "Minimal Expression",
          severity: "info",
          message: `Static utility class container detected ('Utils'/'Helper').`,
          location: { line: lineNum, file: filename },
          suggestion: `In modern TS/JS and Python, prefer standalone exported pure functions over static utility classes.`,
        });
        // Only report once per class
        break;
      }
    }
  }

  // Check type safety: excessive any
  if (anyCount >= 5) {
    safetyFindings.push({
      type: "type_safety",
      severity: "warning",
      message: `Excessive usage of ': any' (${anyCount} occurrences) degrades type safety.`,
      location: { file: filename },
      remedy: `Replace 'any' with 'unknown', generic type parameters, or explicit interfaces.`,
    });
  }

  // Calculate Bloat Score (0 = pure minimal, 100 = extreme bloat)
  let score = 0;
  for (const b of bloatFindings) {
    if (b.severity === "error") score += 30;
    else if (b.severity === "warning") score += 15;
    else score += 5;
  }
  for (const s of safetyFindings) {
    if (s.severity === "error") score += 25;
    else score += 10;
  }

  const bloatScore = Math.min(100, score);
  const errorSafetyCount = safetyFindings.filter((s) => s.severity === "error").length;
  const passed = bloatScore <= 20 && errorSafetyCount === 0;

  // Synthesize actionable suggestions
  if (bloatFindings.length > 0) {
    for (const b of bloatFindings) {
      if (!suggestions.includes(b.suggestion)) {
        suggestions.push(b.suggestion);
      }
    }
  }
  if (safetyFindings.length > 0) {
    for (const s of safetyFindings) {
      if (!suggestions.includes(s.remedy)) {
        suggestions.push(s.remedy);
      }
    }
  }

  if (suggestions.length === 0) {
    suggestions.push("Code adheres to Ponytail 7-step logic ladder and safe minimal code standards.");
  }

  return {
    passed,
    bloatScore,
    bloatFindings,
    safetyFindings,
    suggestions,
    metrics: {
      linesOfCode: loc,
      dependencyCount: bloatFindings.filter((b) => b.step === 3 || b.step === 5).length,
    },
  };
}

/**
 * Audits a unified git diff against Step 7: Surgical Minimal Diff and safety rules.
 */
export function auditDiff(diffText: string): AuditResult {
  const bloatFindings: BloatFinding[] = [];
  const safetyFindings: SafetyFinding[] = [];
  const suggestions: string[] = [];

  const lines = diffText.split("\n");
  let addedLines = 0;
  let deletedLines = 0;
  let whitespaceOnlyCount = 0;
  let modifiedFiles: string[] = [];
  let currentFile = "";

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    if (line.startsWith("diff --git")) {
      const parts = line.split(/\s+/);
      currentFile = parts[parts.length - 1]?.replace(/^b\//, "") || "";
      if (currentFile && !modifiedFiles.includes(currentFile)) {
        modifiedFiles.push(currentFile);
      }
      continue;
    }

    if (line.startsWith("+++") || line.startsWith("---") || line.startsWith("@@")) {
      continue;
    }

    if (line.startsWith("+")) {
      addedLines++;
      const content = line.slice(1);
      const trimmed = content.trim();

      // Check for error suppression introduced in diff
      if (/\b_\s*=\s*err\b/.test(trimmed)) {
        safetyFindings.push({
          type: "error_suppression",
          severity: "error",
          message: `Introduced '_ = err' in diff. Violates Vald Law 5.`,
          location: { file: currentFile, line: i + 1 },
          remedy: `Handle or return the error explicitly in the diff.`,
        });
      }

      if (/catch\s*(\([^)]*\))?\s*\{\s*\}/.test(trimmed) || /catch\s*(?:\([^)]*\))?\s*\{/.test(trimmed)) {
        // Also check if next line or this line is empty catch
        const nextLine = lines[i + 1]?.trim();
        if (/catch\s*(\([^)]*\))?\s*\{\s*\}/.test(trimmed) || (nextLine && nextLine.startsWith("}"))) {
          safetyFindings.push({
            type: "error_suppression",
            severity: "error",
            message: `Introduced empty catch block in diff.`,
            location: { file: currentFile, line: i + 1 },
            remedy: `Log or rethrow the exception.`,
          });
        }
      }

      // Check for bloated dependency imports introduced in diff
      if (/(?:import|from|require)\s*["'](?:lodash|moment|axios)["']/.test(trimmed)) {
        bloatFindings.push({
          step: 3,
          ruleName: "Stdlib First",
          severity: "warning",
          message: `Introduced external dependency import in diff.`,
          location: { file: currentFile, line: i + 1 },
          suggestion: `Use language standard library or native runtime APIs instead.`,
        });
      }

      // Trivial whitespace change detection
      if (trimmed.length === 0) {
        whitespaceOnlyCount++;
      }
    } else if (line.startsWith("-")) {
      deletedLines++;
      const content = line.slice(1);
      if (content.trim().length === 0) {
        whitespaceOnlyCount++;
      }
    }
  }

  // Gratuitous whitespace churn check
  const totalChurn = addedLines + deletedLines;
  if (totalChurn > 30 && whitespaceOnlyCount / totalChurn > 0.4) {
    bloatFindings.push({
      step: 7,
      ruleName: "Surgical Minimal Diff",
      severity: "warning",
      message: `Diff contains excessive whitespace or formatting churn (${whitespaceOnlyCount} blank line changes).`,
      suggestion: `Revert formatting-only changes and keep only functional edits in the pull request.`,
    });
  }

  // Broad file count check (scope creep)
  if (modifiedFiles.length > 8) {
    bloatFindings.push({
      step: 7,
      ruleName: "Surgical Minimal Diff",
      severity: "info",
      message: `Diff modifies ${modifiedFiles.length} files. Verify that this does not constitute scope creep.`,
      suggestion: `Decompose into smaller surgical commits if multiple independent concerns are being touched.`,
    });
  }

  let score = 0;
  for (const b of bloatFindings) {
    if (b.severity === "error") score += 30;
    else if (b.severity === "warning") score += 15;
    else score += 5;
  }
  for (const s of safetyFindings) {
    if (s.severity === "error") score += 25;
    else score += 10;
  }

  const bloatScore = Math.min(100, score);
  const errorSafetyCount = safetyFindings.filter((s) => s.severity === "error").length;
  const passed = bloatScore <= 20 && errorSafetyCount === 0;

  if (bloatFindings.length > 0) {
    for (const b of bloatFindings) {
      if (!suggestions.includes(b.suggestion)) suggestions.push(b.suggestion);
    }
  }
  if (safetyFindings.length > 0) {
    for (const s of safetyFindings) {
      if (!suggestions.includes(s.remedy)) suggestions.push(s.remedy);
    }
  }
  if (suggestions.length === 0) {
    suggestions.push("Diff is surgical, focused, and satisfies Ponytail minimal diff principles.");
  }

  return {
    passed,
    bloatScore,
    bloatFindings,
    safetyFindings,
    suggestions,
    metrics: {
      linesOfCode: totalChurn,
    },
  };
}

/**
 * Formats a comprehensive Markdown audit report.
 */
export function formatAuditReport(result: AuditResult, targetLabel?: string): string {
  const statusBadge = result.passed ? "✅ PASSED (Safe Minimal Code)" : "❌ FAILED (Bloat / Invariant Violation)";
  const label = targetLabel ? ` for "${targetLabel}"` : "";

  const lines: string[] = [
    `# ✂️ Ponytail Code Audit Report${label}`,
    "",
    `**Status**: ${statusBadge}`,
    `**Bloat Score**: **${result.bloatScore} / 100** ${result.bloatScore <= 20 ? "(Clean)" : result.bloatScore <= 50 ? "(Moderate Bloat)" : "(Severe Bloat)"}`,
    `**Analyzed Lines**: ${result.metrics.linesOfCode}`,
    "",
  ];

  // Safety Findings Section
  if (result.safetyFindings.length > 0) {
    lines.push("## 🚨 Safety & Invariant Violations (Non-Negotiable)");
    for (const sf of result.safetyFindings) {
      const icon = sf.severity === "error" ? "🛑" : "⚠️";
      const loc = sf.location?.line ? ` (line ${sf.location.line})` : "";
      lines.push(`${icon} **[${sf.type.toUpperCase()}]**${loc}: ${sf.message}`);
      lines.push(`   *Remedy*: ${sf.remedy}`);
    }
    lines.push("");
  }

  // Bloat Findings Section
  if (result.bloatFindings.length > 0) {
    lines.push("## 📦 Overengineering & Bloat Findings");
    for (const bf of result.bloatFindings) {
      const icon = bf.severity === "error" ? "🛑" : bf.severity === "warning" ? "⚠️" : "ℹ️";
      const loc = bf.location?.line ? ` (line ${bf.location.line})` : "";
      lines.push(`${icon} **Step ${bf.step}: ${bf.ruleName}**${loc}: ${bf.message}`);
      lines.push(`   *Suggestion*: ${bf.suggestion}`);
    }
    lines.push("");
  }

  // Actionable Suggestions
  lines.push("## 💡 Actionable Ponytail Suggestions");
  for (const sug of result.suggestions) {
    lines.push(`- ${sug}`);
  }
  lines.push("");

  return lines.join("\n");
}
