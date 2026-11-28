/**
 * Time-to-Stop-and-Remind (TTSR) Rule Parser & Matcher Core
 *
 * Parses `~/.pi/agent/rules/*-ttsr.md` frontmatter (`globs`, `condition`,
 * `scope`, `interruptMode`, `repeatMode`) and evaluates tool calls / stream text.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

export interface TtsrRule {
  name: string;
  description: string;
  globs: string[];
  conditions: RegExp[];
  scopes: Array<{ tool: string; fileGlob?: string }>;
  interruptMode: "tool-only" | "stream-and-tool";
  repeatMode: "after-gap" | "once" | "always";
  body: string;
}

export interface TtsrRuntimeState {
  lastFiredTurn: Map<string, number>;
}

export function createTtsrState(): TtsrRuntimeState {
  return { lastFiredTurn: new Map() };
}

function globToRegex(glob: string): RegExp {
  let out = "^";
  for (let i = 0; i < glob.length; i++) {
    const ch = glob[i];
    if (ch === "*" && glob[i + 1] === "*") {
      if (glob[i + 2] === "/") {
        out += "(?:.*/)?";
        i += 2;
      } else {
        out += ".*";
        i += 1;
      }
    } else if (ch === "*") {
      out += "[^/]*";
    } else if (ch === "?") {
      out += ".";
    } else if (/[.+^${}()|[\]\\]/.test(ch)) {
      out += `\\${ch}`;
    } else {
      out += ch;
    }
  }
  return new RegExp(`${out}$`);
}

export function matchesGlobList(filePath: string, globs: string[]): boolean {
  if (globs.length === 0) return true;
  const norm = filePath.replace(/\\/g, "/");
  const base = path.posix.basename(norm);
  return globs.some((g) => {
    const re = globToRegex(g);
    return re.test(norm) || re.test(base) || (g.startsWith("**/") && re.test(norm.replace(/^\/+/, "")));
  });
}

function parseScopes(raw: string): Array<{ tool: string; fileGlob?: string }> {
  const out: Array<{ tool: string; fileGlob?: string }> = [];
  for (const part of raw.split(",")) {
    const trimmed = part.trim().replace(/^["']|["']$/g, "");
    const m = /^tool:([a-zA-Z0-9_-]+)(?:\(([^)]+)\))?$/.exec(trimmed);
    if (m) {
      out.push({ tool: m[1], fileGlob: m[2] });
    }
  }
  return out;
}

export function parseTtsrRuleMarkdown(markdown: string, fallbackName = "ttsr-rule"): TtsrRule | null {
  const m = /^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/.exec(markdown);
  if (!m) return null;

  const fm = m[1];
  const body = m[2].trim();
  const lines = fm.split(/\r?\n/);

  let name = fallbackName;
  let description = "";
  const globs: string[] = [];
  const conditionStrings: string[] = [];
  let scopeRaw = "";
  let interruptMode: "tool-only" | "stream-and-tool" = "tool-only";
  let repeatMode: "after-gap" | "once" | "always" = "after-gap";

  let activeList: "globs" | "condition" | null = null;
  for (const line of lines) {
    const listItem = /^\s+-\s+(.*)$/.exec(line);
    if (listItem && activeList) {
      let val = listItem[1].trim();
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1).replace(/\\\\/g, "\\").replace(/\\"/g, '"');
      }
      if (activeList === "globs") globs.push(val);
      else conditionStrings.push(val);
      continue;
    }

    activeList = null;
    const kv = /^([a-zA-Z0-9_-]+):\s*(.*)$/.exec(line);
    if (!kv) continue;
    const key = kv[1];
    const val = kv[2].trim().replace(/^["']|["']$/g, "");
    if (key === "name" && val) name = val;
    else if (key === "description") description = val;
    else if (key === "globs") activeList = val === "" ? "globs" : null;
    else if (key === "condition") activeList = val === "" ? "condition" : null;
    else if (key === "scope") scopeRaw = val;
    else if (key === "interruptMode" && (val === "tool-only" || val === "stream-and-tool")) interruptMode = val;
    else if (key === "repeatMode" && (val === "after-gap" || val === "once" || val === "always")) repeatMode = val;
  }

  const conditions: RegExp[] = [];
  for (const c of conditionStrings) {
    try {
      conditions.push(new RegExp(c));
    } catch {
      // Skip invalid regex safely.
    }
  }
  if (conditions.length === 0) return null;

  return {
    name,
    description,
    globs,
    conditions,
    scopes: parseScopes(scopeRaw),
    interruptMode,
    repeatMode,
    body,
  };
}

export function loadTtsrRules(rulesDirs: string[]): TtsrRule[] {
  const rules: TtsrRule[] = [];
  const seenNames = new Set<string>();
  for (const dir of rulesDirs) {
    if (!dir || !fs.existsSync(dir)) continue;
    let files: string[];
    try {
      files = fs.readdirSync(dir).filter((f) => f.endsWith("-ttsr.md")).sort();
    } catch {
      continue;
    }
    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(dir, file), "utf-8");
        const parsed = parseTtsrRuleMarkdown(content, file.replace(/-ttsr\.md$/, ""));
        if (parsed && !seenNames.has(parsed.name)) {
          seenNames.add(parsed.name);
          rules.push(parsed);
        }
      } catch {
        // Ignore unreadable rule file.
      }
    }
  }
  return rules;
}

export function defaultTtsrRuleDirs(cwd: string, home = os.homedir()): string[] {
  return [
    path.join(cwd, ".pi", "rules"),
    path.join(home, ".pi", "agent", "rules"),
    path.join(cwd, "agent", "rules"),
  ];
}

function canFire(rule: TtsrRule, state: TtsrRuntimeState, turnIndex: number): boolean {
  const prev = state.lastFiredTurn.get(rule.name);
  if (prev === undefined) return true;
  if (rule.repeatMode === "once") return false;
  if (rule.repeatMode === "after-gap") return turnIndex - prev >= 2;
  return true;
}

export function evaluateTtsrToolCall(
  rules: TtsrRule[],
  toolName: string,
  filePath: string,
  content: string,
  state: TtsrRuntimeState,
  turnIndex: number,
): { matched: TtsrRule; pattern: string } | null {
  if (!content) return null;
  for (const rule of rules) {
    if (!canFire(rule, state, turnIndex)) continue;
    if (rule.scopes.length > 0) {
      const scopeMatch = rule.scopes.some(
        (s) => s.tool === toolName && (!s.fileGlob || matchesGlobList(filePath, [s.fileGlob])),
      );
      if (!scopeMatch) continue;
    }
    if (!matchesGlobList(filePath, rule.globs)) continue;
    for (const re of rule.conditions) {
      if (re.test(content)) {
        state.lastFiredTurn.set(rule.name, turnIndex);
        return { matched: rule, pattern: re.source };
      }
    }
  }
  return null;
}

export function evaluateTtsrText(
  rules: TtsrRule[],
  text: string,
  state: TtsrRuntimeState,
  turnIndex: number,
): { matched: TtsrRule; pattern: string } | null {
  if (!text) return null;
  for (const rule of rules) {
    if (rule.interruptMode === "tool-only") continue;
    if (!canFire(rule, state, turnIndex)) continue;
    for (const re of rule.conditions) {
      if (re.test(text)) {
        state.lastFiredTurn.set(rule.name, turnIndex);
        return { matched: rule, pattern: re.source };
      }
    }
  }
  return null;
}
