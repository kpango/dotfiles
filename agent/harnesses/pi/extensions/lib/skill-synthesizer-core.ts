/**
 * Hermes-Style Closed-Loop Skill Synthesizer Core
 *
 * Distills task execution trajectories (bash commands, git diffs, test evidence)
 * into canonical SKILL.md specs with strict YAML frontmatter, deduplication against
 * existing skills, and sanitized naming.
 */

import * as fs from "node:fs";
import * as path from "node:path";

export interface CommandExecutionRecord {
  command: string;
  exitCode: number;
  stdout: string;
  stderr: string;
}

export interface ToolExecutionRecord {
  tool: string;
  params: unknown;
  result: unknown;
  isError?: boolean;
}

export interface VerificationEvidence {
  description: string;
  passed: boolean;
  command?: string;
  exitCode?: number;
}

export interface TaskExecutionTrace {
  sessionId?: string;
  cwd?: string;
  objective?: string;
  commands: CommandExecutionRecord[];
  tools: ToolExecutionRecord[];
  gitDiff?: string;
  verificationEvidence?: VerificationEvidence[];
}

export interface SkillFrontmatter {
  name: string;
  description: string;
  allowedTools?: string[];
  "allowed-tools"?: string[];
  userInvocable?: boolean;
  disableModelInvocation?: boolean;
}

export interface SkillProcedureStep {
  step: number;
  name: string;
  instruction: string;
  command?: string;
}

export interface SkillSpec {
  frontmatter: SkillFrontmatter;
  overview?: string;
  trigger?: string;
  procedure?: SkillProcedureStep[];
  boundaryConditions?: string[];
  verificationMethod?: string;
  body?: string;
}

export interface SkillSynthesisResult {
  skillName: string;
  markdownContent: string;
  canonicalPath: string;
  persisted: boolean;
  warnings?: string[];
  error?: string;
}

export interface SaveSkillOptions {
  skillsDir?: string;
  overwrite?: boolean;
}

/**
 * Sanitizes arbitrary raw skill names to strictly lowercase kebab-case.
 */
export function sanitizeSkillName(rawName: string): string {
  if (!rawName || typeof rawName !== "string") {
    return "synthesized-skill";
  }
  const sanitized = rawName
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return sanitized || "synthesized-skill";
}

/**
 * Strips volatile/ephemeral paths (such as /tmp/...) to make skills portable.
 */
export function stripEphemeralPaths(text: string): string {
  if (!text) return "";
  return text
    .replace(/\/tmp\/[a-zA-Z0-9._-]+/g, "<temp-path>")
    .replace(/\/var\/tmp\/[a-zA-Z0-9._-]+/g, "<temp-path>");
}

/**
 * Helper to determine if a command is a verification/testing operation.
 */
function isTestOrVerificationCommand(cmd: string): boolean {
  const norm = cmd.toLowerCase();
  return (
    norm.includes("test") ||
    norm.includes("verify") ||
    norm.includes("validate") ||
    norm.includes("check") ||
    norm.includes("lint")
  );
}

/**
 * Extracts a structured execution trajectory from raw session events/entries.
 */
export function extractTrace(events: any[]): TaskExecutionTrace {
  const commands: CommandExecutionRecord[] = [];
  const tools: ToolExecutionRecord[] = [];
  const verificationEvidence: VerificationEvidence[] = [];
  let gitDiff: string | undefined;
  let objective: string | undefined;
  let cwd: string | undefined;

  if (!Array.isArray(events)) {
    return { commands, tools, verificationEvidence };
  }

  for (const ev of events) {
    if (!ev) continue;

    if (ev.commands && Array.isArray(ev.commands)) {
      commands.push(...ev.commands);
    }
    if (ev.tools && Array.isArray(ev.tools)) {
      tools.push(...ev.tools);
    }
    if (ev.verificationEvidence && Array.isArray(ev.verificationEvidence)) {
      verificationEvidence.push(...ev.verificationEvidence);
    }
    if (ev.gitDiff) gitDiff = ev.gitDiff;
    if (ev.objective) objective = ev.objective;
    if (ev.cwd) cwd = ev.cwd;

    if ((ev.role === "user" || ev.type === "user") && typeof ev.content === "string" && !objective) {
      objective = ev.content.trim();
    }

    const toolName = ev.toolName || ev.tool;
    if (toolName) {
      const params = ev.input || ev.params || {};
      const result = ev.result !== undefined ? ev.result : ev.output;
      const isError = Boolean(ev.isError || ev.error);

      tools.push({
        tool: String(toolName),
        params,
        result,
        isError,
      });

      if (toolName === "bash") {
        const cmd =
          typeof params === "object" && params !== null && "command" in params
            ? String(params.command)
            : typeof params === "string"
            ? params
            : "";

        let stdout = "";
        let stderr = "";
        let exitCode = 0;

        if (typeof result === "string") {
          stdout = result;
        } else if (result && typeof result === "object") {
          stdout = String(result.stdout || result.output || "");
          stderr = String(result.stderr || "");
          if (typeof result.exitCode === "number") {
            exitCode = result.exitCode;
          }
        }
        if (isError && exitCode === 0) exitCode = 1;

        const cmdRecord: CommandExecutionRecord = {
          command: cmd,
          exitCode,
          stdout: stripEphemeralPaths(stdout),
          stderr: stripEphemeralPaths(stderr),
        };
        commands.push(cmdRecord);

        if (cmd.includes("git diff")) {
          gitDiff = stdout;
        }

        if (isTestOrVerificationCommand(cmd)) {
          verificationEvidence.push({
            description: `Command: ${cmd}`,
            command: cmd,
            passed: exitCode === 0,
            exitCode,
          });
        }
      }
    }
  }

  return {
    objective,
    cwd,
    commands,
    tools,
    gitDiff,
    verificationEvidence,
  };
}

export const extractOperationalTrace = extractTrace;


/**
 * Validates strict YAML frontmatter schema.
 */
export function validateSkillFrontmatter(fm: SkillFrontmatter): { valid: boolean; errors: string[] } {
  const errors: string[] = [];
  if (!fm || typeof fm !== "object") {
    return { valid: false, errors: ["Frontmatter must be an object"] };
  }
  if (!fm.name || typeof fm.name !== "string" || !fm.name.trim()) {
    errors.push("Missing or empty 'name' in frontmatter");
  } else {
    const sanitized = sanitizeSkillName(fm.name);
    if (sanitized !== fm.name) {
      errors.push(`Invalid skill name '${fm.name}'. Must be kebab-case (e.g. '${sanitized}')`);
    }
  }
  if (!fm.description || typeof fm.description !== "string" || !fm.description.trim()) {
    errors.push("Missing or empty 'description' in frontmatter");
  }
  return {
    valid: errors.length === 0,
    errors,
  };
}

/**
 * Formats a SkillSpec into a canonical SKILL.md Markdown file with YAML frontmatter.
 */
export function formatSkillMarkdown(spec: SkillSpec): string {
  if (!spec || !spec.frontmatter) {
    throw new Error("Cannot format skill markdown: missing spec or frontmatter");
  }
  const { name, description } = spec.frontmatter;
  const allowed = spec.frontmatter["allowed-tools"] || spec.frontmatter.allowedTools;

  let fm = `---\nname: ${name}\ndescription: ${description}\n`;
  if (Array.isArray(allowed) && allowed.length > 0) {
    fm += `allowed-tools:\n${allowed.map((t) => `  - ${t}`).join("\n")}\n`;
  } else if (typeof allowed === "string" && allowed.trim()) {
    fm += `allowed-tools: ${allowed.trim()}\n`;
  }
  if (spec.frontmatter.userInvocable !== undefined) {
    fm += `user-invocable: ${spec.frontmatter.userInvocable}\n`;
  }
  if (spec.frontmatter.disableModelInvocation !== undefined) {
    fm += `disable-model-invocation: ${spec.frontmatter.disableModelInvocation}\n`;
  }
  fm += `---\n\n`;

  if (spec.body && spec.body.trim()) {
    return fm + spec.body.trim() + "\n";
  }

  const titleWords = name.split("-").map((w) => w.charAt(0).toUpperCase() + w.slice(1));
  const title = titleWords.join(" ");

  let content = `# ${title}\n\n`;

  if (spec.overview) {
    content += `## Overview\n\n${spec.overview.trim()}\n\n`;
  }

  if (spec.trigger) {
    content += `## When to Use\n\n${spec.trigger.trim()}\n\n`;
  }

  if (spec.procedure && spec.procedure.length > 0) {
    content += `## Procedure\n\n`;
    for (const step of spec.procedure) {
      content += `### Step ${step.step}: ${step.name}\n\n${step.instruction}\n\n`;
      if (step.command) {
        content += "```bash\n" + step.command.trim() + "\n```\n\n";
      }
    }
  }

  if (spec.boundaryConditions && spec.boundaryConditions.length > 0) {
    content += `## Boundary Conditions\n\n`;
    for (const b of spec.boundaryConditions) {
      content += `- ${b}\n`;
    }
    content += `\n`;
  }

  if (spec.verificationMethod) {
    content += `## Verification Method\n\n${spec.verificationMethod.trim()}\n`;
  }

  return fm + content.trim() + "\n";
}

/**
 * Resolves the canonical skills directory.
 */
export function getSkillsDirectory(customDir?: string): string {
  if (customDir && fs.existsSync(customDir)) {
    return path.resolve(customDir);
  }
  let cur = __dirname;
  for (let i = 0; i < 6; i++) {
    const candidate = path.join(cur, "agent", "skills");
    if (fs.existsSync(candidate) && fs.statSync(candidate).isDirectory()) {
      return candidate;
    }
    const parentCandidate = path.join(cur, "skills");
    if (fs.existsSync(parentCandidate) && fs.statSync(parentCandidate).isDirectory()) {
      return parentCandidate;
    }
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  const homeSkills = path.join(process.env.HOME || "", ".pi", "agent", "skills");
  if (fs.existsSync(homeSkills)) return homeSkills;
  return path.resolve(process.cwd(), "agent", "skills");
}

/**
 * Discovers existing skills in the target skills directory.
 */
export function discoverExistingSkills(skillsDir?: string): Set<string> {
  const dir = getSkillsDirectory(skillsDir);
  const skills = new Set<string>();
  if (!fs.existsSync(dir)) return skills;

  try {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const ent of entries) {
      if (ent.isDirectory()) {
        skills.add(ent.name);
      }
    }
  } catch {
    // Return partial set
  }
  return skills;
}

/**
 * Synthesizes a structured SkillSpec from an execution trajectory.
 */
export function synthesizeSkillFromTrace(trace: TaskExecutionTrace, suggestedName?: string): SkillSpec {
  let name = suggestedName ? sanitizeSkillName(suggestedName) : "";
  if (!name && trace.objective) {
    const words = trace.objective
      .toLowerCase()
      .replace(/[^a-z0-9\n\s]/g, "")
      .split(/\s+/)
      .filter((w) => w.length > 2 && !["the", "for", "and", "with", "this", "that"].includes(w))
      .slice(0, 3);
    if (words.length > 0) {
      name = words.join("-");
    }
  }
  if (!name) name = "synthesized-task-skill";

  const description = trace.objective
    ? `Autonomous skill for: ${trace.objective}`
    : `Synthesized skill covering ${trace.commands.length} operations and verified procedures.`;

  const procedure: SkillProcedureStep[] = [];
  let stepIdx = 1;

  const uniqueCmds = new Set<string>();
  for (const c of trace.commands) {
    if (!c.command || uniqueCmds.has(c.command)) continue;
    uniqueCmds.add(c.command);

    procedure.push({
      step: stepIdx++,
      name: `Execute ${c.command.split(/\s+/)[0] || "Command"}`,
      instruction: "Run the required operation and ensure success.",
      command: c.command,
    });
  }

  const boundaryConditions: string[] = [
    "Verify target directories and file permissions before modification.",
    "Do not execute destructive operations without validation.",
    "Ensure all tests pass before completing.",
  ];

  let verificationMethod = "Run the project test command to confirm behavior.";
  if (trace.verificationEvidence && trace.verificationEvidence.length > 0) {
    const passedEv = trace.verificationEvidence.filter((e) => e.passed);
    if (passedEv.length > 0) {
      verificationMethod =
        "Execute verification commands and ensure exit code 0:\n" +
        passedEv.map((e) => `- \`${e.command || e.description}\``).join("\n");
    }
  }

  return {
    frontmatter: {
      name,
      description,
      "allowed-tools": Array.from(new Set(trace.tools.map((t) => t.tool))),
    },
    overview: trace.objective || "Standard operational procedure distilled from execution trace.",
    trigger: "Use this skill whenever repeating similar tasks or procedures.",
    procedure,
    boundaryConditions,
    verificationMethod,
  };
}

/**
 * Persists a synthesized skill to agent/skills/<name>/SKILL.md, enforcing deduplication.
 */
export function saveSkill(spec: SkillSpec, options?: SaveSkillOptions): SkillSynthesisResult {
  const targetDir = getSkillsDirectory(options?.skillsDir);
  const rawName = spec.frontmatter.name;
  const sanitizedName = sanitizeSkillName(rawName);
  spec.frontmatter.name = sanitizedName;

  const validation = validateSkillFrontmatter(spec.frontmatter);
  if (!validation.valid) {
    return {
      skillName: sanitizedName,
      markdownContent: "",
      canonicalPath: "",
      persisted: false,
      error: `Validation failed: ${validation.errors.join("; ")}`,
      warnings: validation.errors,
    };
  }

  const existingSkills = discoverExistingSkills(targetDir);
  const exists = existingSkills.has(sanitizedName);
  const overwrite = options?.overwrite ?? false;

  if (exists && !overwrite) {
    return {
      skillName: sanitizedName,
      markdownContent: "",
      canonicalPath: "",
      persisted: false,
      error: `Skill '${sanitizedName}' already exists in ${targetDir}. Pass overwrite=true to replace.`,
    };
  }

  const markdownContent = formatSkillMarkdown(spec);
  const skillFolderPath = path.join(targetDir, sanitizedName);
  const canonicalPath = path.join(skillFolderPath, "SKILL.md");

  try {
    if (!fs.existsSync(skillFolderPath)) {
      fs.mkdirSync(skillFolderPath, { recursive: true });
    }
    fs.writeFileSync(canonicalPath, markdownContent, "utf-8");
    return {
      skillName: sanitizedName,
      markdownContent,
      canonicalPath,
      persisted: true,
      warnings: [],
    };
  } catch (err: any) {
    return {
      skillName: sanitizedName,
      markdownContent,
      canonicalPath,
      persisted: false,
      error: `Failed to persist skill: ${err.message}`,
    };
  }
}

export function persistSkill(skillsDir: string, spec: SkillSpec, overwrite = false): SkillSynthesisResult {
  return saveSkill(spec, { skillsDir, overwrite });
}
