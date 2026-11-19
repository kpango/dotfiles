/**
 * Security Gate Extension for Oh My Pi (OMP)
 *
 * Enforces safety boundaries across shell command execution and file writes,
 * protecting credentials, sensitive files, destructive disk ops, production namespaces,
 * and repository-specific invariants (Vald Law).
 *
 * 破壊的コマンド・機微パスのルールデータは agent/security-rules.json を、Vald Law判定データは
 * agent/vald-law-rules.json を読む(いずれもclaude/agy/omp共通)。
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { callDecide, repoRoot } from "./lib/shared";

// shell_command_rules・sensitive_write_path_rules・Vald Law 1/2/3/4/5 の判定アルゴリズム
// (all_of/any_of/not_any_of の評価・force_push/git_reset_hardの特別扱い・パス候補照合・
// Vald Lawのスコープ判定/コンテンツ検査)は agent/scripts/hooks/rule_engine.py + decide.py へ
// 統合済み(2026-09-03、claude/agy/ompで独立に再実装されていたロジックを1箇所化)。本ファイルは
// OMP Extension API(ctx.ui.confirm等)への結線のみを持つ薄いシム。
// decide.py 自身が毎回最新のルールファイルを読み込むため、モジュールロード時の RULES キャッシュや
// ゲートは持たない(起動時読み込み失敗による fail-open を構造的に防止する)。
export interface DecideResult {
  decision: "allow" | "ask" | "block" | "deny";
  reason?: string;
  matched_rule_id?: string;
  resolved_path?: string;
  all_matches?: Array<{ id: string; tier: string; description: string }>;
  violations?: string[];
}

function evaluateShellCommand(root: string, cwd: string, command: string): DecideResult {
  return callDecide<DecideResult>(
    root,
    {
      family: "security_shell",
      command,
      cwd,
      rules_file: path.join(root, "agent", "security-rules.json"),
      resolve_command_target: true,
    },
    { decision: "allow" },
  );
}

function evaluateWritePath(root: string, cwd: string, home: string, rawPath: string): DecideResult {
  return callDecide<DecideResult>(
    root,
    {
      family: "security_write",
      file_path: rawPath,
      cwd,
      home,
      rules_file: path.join(root, "agent", "security-rules.json"),
    },
    { decision: "allow" },
  );
}

// Tier B 書込保護ゲート: fail-closed (callDecide失敗時も block を返す)
function evaluateWriteScope(root: string, cwd: string, home: string, rawPath: string): DecideResult {
  return callDecide<DecideResult>(
    root,
    {
      family: "write_scope",
      file_path: rawPath,
      cwd,
      home,
      rules_file: path.join(root, "agent", "write-scope-rules.json"),
    },
    { decision: "block", reason: "write-scope decide.py invocation failed; failing closed (Tier B)" },
  );
}

function extractWrittenContent(event: { toolName: string; input: Record<string, unknown> }): string {
  if (event.toolName === "write") {
    return (event.input.content as string) || "";
  }
  if (event.toolName === "edit") {
    const edits = (event.input.edits as Array<{ newText?: string }> | undefined) ?? [];
    return edits.map((e) => e.newText ?? "").join("\n");
  }
  return "";
}

function evaluateValdLaw2(root: string, valdRulesFile: string, cwd: string, command: string): DecideResult {
  return callDecide<DecideResult>(
    root,
    {
      family: "vald_law2",
      command,
      cwd,
      vald_rules_file: valdRulesFile,
      scope_mode: "cwd_and_resolved_path",
    },
    { decision: "allow" },
  );
}

function evaluateValdLaw1(root: string, valdRulesFile: string, filePath: string): DecideResult {
  return callDecide<DecideResult>(
    root,
    { family: "vald_law1", file_path: filePath, vald_rules_file: valdRulesFile },
    { decision: "allow" },
  );
}

function evaluateValdLaw345(
  root: string,
  valdRulesFile: string,
  cwd: string,
  filePath: string,
  content: string,
): DecideResult {
  return callDecide<DecideResult>(
    root,
    {
      family: "vald_law345",
      file_path: filePath,
      content,
      vald_rules_file: valdRulesFile,
      scope_mode: "cwd_and_resolved_path",
      cwd,
    },
    { decision: "allow" },
  );
}

async function confirmOrBlock(
  ctx: { hasUI?: boolean; ui?: { confirm?: (title: string, message: string) => Promise<boolean> } },
  title: string,
  confirmMessage: string,
  userDeniedReason: string,
  noUiBlockReason: string,
): Promise<{ block: true; reason: string } | undefined> {
  if (ctx?.hasUI && ctx.ui?.confirm) {
    const ok = await ctx.ui.confirm(title, confirmMessage);
    if (!ok) {
      return { block: true, reason: userDeniedReason };
    }
    return undefined;
  }
  return { block: true, reason: noUiBlockReason };
}

export async function handleShellCommandResult(
  result: DecideResult,
  command: string,
  confirmFn: (title: string, message: string) => Promise<boolean>,
  hasUI: boolean,
): Promise<{ block: true; reason: string } | undefined> {
  if (result.decision === "block" || result.decision === "deny") {
    return { block: true, reason: `Security Gate blocked command: ${result.reason ?? ""}` };
  }

  const matches = result.all_matches ?? [];
  if (matches.length > 0) {
    for (const m of matches) {
      if (hasUI) {
        const title = m.tier === "ask" ? "Confirm Destructive Operation" : "Dangerous Command Warning";
        const ok = await confirmFn(
          title,
          `The agent is trying to execute:\n\n$ ${command}\n\nReason: ${m.description}\n\nAllow execution?`,
        );
        if (!ok) {
          return { block: true, reason: `Blocked by user: ${m.description}` };
        }
        // 承認された場合はこのruleについては通過するが、複合コマンドが他のruleにも
        // 一致しうるため走査を継続する。
      } else {
        return { block: true, reason: `Security Gate blocked command: ${m.description}` };
      }
    }
    return undefined;
  }

  if (result.decision === "ask") {
    const reason = result.reason || "Operation requires confirmation";
    if (hasUI) {
      const ok = await confirmFn(
        "Confirm Destructive Operation",
        `The agent is trying to execute:\n\n$ ${command}\n\nReason: ${reason}\n\nAllow execution?`,
      );
      if (!ok) {
        return { block: true, reason: `Blocked by user: ${reason}` };
      }
    } else {
      return { block: true, reason: `Security Gate blocked command: ${reason}` };
    }
  }

  return undefined;
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    const home = os.homedir();
    const root = repoRoot(import.meta.url);

    // 1. Inspect Bash Commands
    if (event.toolName === "bash") {
      const command = (event.input.command as string) || "";

      if (root && command) {
        const result = evaluateShellCommand(root, ctx.cwd, command);
        const blocked = await handleShellCommandResult(
          result,
          command,
          (title, message) => ctx.ui.confirm(title, message),
          ctx.hasUI,
        );
        if (blocked) {
          return blocked;
        }
      }

      // Vald Law 2 Check (in vald repository)
      if (root && command) {
        const valdRulesFile = path.join(root, "agent", "vald-law-rules.json");
        if (fs.existsSync(valdRulesFile)) {
          const law2 = evaluateValdLaw2(root, valdRulesFile, ctx.cwd, command);
          if (law2.decision === "block" || law2.decision === "deny") {
            return { block: true, reason: law2.reason ?? "Vald Law 2 violation" };
          }
          if (law2.decision === "ask") {
            const reason = law2.reason || "Vald Law 2 requires confirmation";
            const res = await confirmOrBlock(
              ctx,
              "Vald Law 2 Violation",
              `The agent is trying to execute:\n\n$ ${command}\n\nReason: ${reason}\n\nAllow execution?`,
              `Blocked by user: ${reason}`,
              reason,
            );
            if (res) return res;
          }
        }
      }
    }

    // 2. Inspect File Write & Edit
    if (event.toolName === "write" || event.toolName === "edit") {
      const rawPath = (event.input.file_path || event.input.path || "") as string;
      if (!rawPath) return;

      const resolvedPath = path.isAbsolute(rawPath) ? rawPath : path.resolve(ctx.cwd, rawPath);

      if (root) {
        const writeResult = evaluateWritePath(root, ctx.cwd, home, rawPath);
        if (writeResult.decision === "deny") {
          return {
            block: true,
            reason: writeResult.reason ?? `Security Gate denied modification to sensitive path: ${resolvedPath}`,
          };
        }
        if (writeResult.decision === "block" || writeResult.decision === "ask") {
          const label = writeResult.reason ?? "";
          const res = await confirmOrBlock(
            ctx,
            "Protected File Modification",
            `The agent is trying to write to sensitive file (${label}):\n\n${resolvedPath}\n\nAllow write?`,
            `Blocked by user: Modification to protected path (${resolvedPath}) denied.`,
            `Security Gate blocked modification to sensitive path: ${resolvedPath}`,
          );
          if (res) return res;
        }
      }

      // Tier B 書込保護ゲート(write-scope)
      if (root) {
        const scopeResult = evaluateWriteScope(root, ctx.cwd, home, rawPath);
        if (scopeResult.decision === "deny") {
          return {
            block: true,
            reason: scopeResult.reason ?? `Security Gate denied write to Tier B protected path: ${resolvedPath}`,
          };
        }
        if (scopeResult.decision === "block" || scopeResult.decision === "ask") {
          const reason = scopeResult.reason ?? "Tier B protected path (write-scope)";
          const res = await confirmOrBlock(
            ctx,
            "Tier B Protected Path (write-scope gate)",
            `The agent is trying to write to a Tier B protected path (${reason}):\n\n${resolvedPath}\n\nAllow write?`,
            `Blocked by user: Tier B protected path (${resolvedPath}) denied.`,
            `Security Gate blocked write to Tier B protected path: ${resolvedPath}`,
          );
          if (res) return res;
        }
      }

      if (root) {
        const valdRulesFile = path.join(root, "agent", "vald-law-rules.json");
        if (fs.existsSync(valdRulesFile)) {
          // Vald Law 1 Check: *.pb.go, *_vtproto.pb.go, *_grpc.pb.go, *.pb.gw.go are generated
          const law1 = evaluateValdLaw1(root, valdRulesFile, resolvedPath);
          if (law1.decision === "block" || law1.decision === "deny") {
            return { block: true, reason: law1.reason ?? "Vald Law 1 violation" };
          }
          if (law1.decision === "ask") {
            const reason = law1.reason || "Vald Law 1 requires confirmation";
            const res = await confirmOrBlock(
              ctx,
              "Vald Law 1 Violation",
              `${reason}\n\n${resolvedPath}\n\nAllow write?`,
              `Blocked by user: ${reason}`,
              reason,
            );
            if (res) return res;
          }

          // Vald Laws 3/4/5
          const content = extractWrittenContent(event);
          if (content) {
            const law345 = evaluateValdLaw345(root, valdRulesFile, ctx.cwd, resolvedPath, content);
            if (law345.decision === "block" || law345.decision === "deny") {
              return { block: true, reason: law345.reason ?? "Vald Law 3/4/5 violation" };
            }
            if (law345.decision === "ask") {
              const violations = law345.violations ?? [];
              const reason =
                violations.length > 0
                  ? `Vald Law violation(s) in ${path.basename(resolvedPath)}:\n${violations.slice(0, 5).map((v) => `- ${v}`).join("\n")}`
                  : (law345.reason || `Vald Law 3/4/5 violation in ${path.basename(resolvedPath)}`);
              const res = await confirmOrBlock(
                ctx,
                "Vald Law 3/4/5 Violation",
                `${reason}\n\nAllow write?`,
                `Blocked by user: ${reason}`,
                reason,
              );
              if (res) return res;
            }
          }
        }
      }
    }
  });
}
