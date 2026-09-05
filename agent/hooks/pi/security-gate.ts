/**
 * Security Gate Extension for Pi Coding Agent
 *
 * Enforces safety boundaries across shell command execution and file writes,
 * protecting credentials, sensitive files, destructive disk ops, production namespaces,
 * and repository-specific invariants (Vald Law).
 *
 * 破壊的コマンド・機微パスのルールデータは agent/security-rules.json を、Vald Law判定データは
 * agent/vald-law-rules.json を読む(いずれもclaude/agy/pi共通)。
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { callDecide, repoRoot } from "./lib/shared";

interface ShellCommandRule {
  id: string;
  description: string;
  tier: "block" | "ask";
  all_of?: string[];
  any_of?: string[];
  not_any_of?: string[];
  protected_branches?: string[];
  any_of_with_branches?: string[];
  target_branch_pattern?: string;
  cd_target_pattern?: string;
  dash_c_target_pattern?: string;
}

interface SensitiveWritePathRule {
  id: string;
  label: string;
  pattern: string;
}

interface SecurityRules {
  shell_command_rules: ShellCommandRule[];
  sensitive_write_path_rules: SensitiveWritePathRule[];
}

function loadJson<T>(relPath: string): T | null {
  try {
    const root = repoRoot(import.meta.url);
    if (!root) return null;
    const raw = fs.readFileSync(path.join(root, relPath), "utf-8");
    return JSON.parse(raw) as T;
  } catch {
    // ルールデータ欠落・破損時は fail-open(致命的にしない、claude/agyと同じ方針)
    return null;
  }
}

const RULES = loadJson<SecurityRules>("agent/security-rules.json");

// shell_command_rules・sensitive_write_path_rules・Vald Law 1/2/3/4/5 の判定アルゴリズム
// (all_of/any_of/not_any_of の評価・force_push/git_reset_hardの特別扱い・パス候補照合・
// Vald Lawのスコープ判定/コンテンツ検査)は agent/scripts/hooks/rule_engine.py + decide.py へ
// 統合済み(2026-09-03、claude/agy/piで3回独立に再実装されていたロジックを1箇所化)。本ファイルは
// Pi Extension API(ctx.ui.confirm等)への結線のみを持つ薄いシム。
interface DecideResult {
  decision: "allow" | "ask" | "block";
  reason?: string;
  matched_rule_id?: string;
  resolved_path?: string;
  // security_shell familyのみ: JSON宣言順の全一致ルール。tier/descriptionはdecide.pyが応答に
  // 直接埋め込む値をそのまま使う(security-audit指摘2026-09-03: ローカルのRULESキャッシュへ
  // idで逆引きすると、decide.pyがフレッシュに読んだルールファイルとこのプロセス寿命中の
  // キャッシュがズレた場合に該当マッチが未確認のまま握り潰される穴になるため、キャッシュ
  // 経由の逆引きはしない)。
  all_matches?: Array<{ id: string; tier: string; description: string }>;
  // vald_law345 familyのみ: 一致したルールのメッセージ一覧。
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
      // pi は global extension として全リポジトリ横断で発火するため、旧実装どおり
      // path.resolve(ctx.cwd, targetDir) で明示的に絶対化する(claudeはproject-scoped配線で
      // 足りるため絶対化しない、既存の意図的な差異をresolve_command_targetで保持する)。
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

// write tool の input は { path, content }、edit tool は { path, edits: [{oldText, newText}] }
// (pi-coding-agent 0.84.4 の型定義 dist/core/tools/{write,edit}.d.ts で実測確認済み。
// old_string/new_string ではなく edits[].oldText/newText の配列形式である点に注意)。
// Law3/4/5はこの変更が新たに持ち込む内容(write=content全体、edit=各edits[].newText)だけを
// 検査する対象に絞る設計(claude実装と同じ判断、agent/README.md参照)。
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

// Vald Law 2 は pi の global extension として全リポジトリ横断で発火するため、claude(vald
// project-scoped hookのため無条件チェックで足りる)と違い、ctx.cwd だけでなくコマンド自身が
// `cd <dir> && ...` / `-C <dir>` で切り替える対象ディレクトリも解決して判定する必要がある
// (security-audit指摘2026-09-03: `cd /other-repo && go build` のようなコマンドが、セッションの
// cwdがvald外であれば丸ごとすり抜けていた)。scope_mode="cwd_and_resolved_path" が
// rule_engine.vald_command_targets 内で同型のロジック(cwd判定→cd/-Cターゲット解決→絶対化して
// 判定)を再現する。
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

// Vald Laws 3/4/5: no panic/log.Fatal, no discarded errors, no stdlib log/errors/sync/strings
// imports in production (non-test) Go code. claude/agy実装との強制力の食い違い(pi は元々
// Law3/4/5チェック自体が存在しなかった)を解消するため本統合で追加した。scope_mode=
// "cwd_and_resolved_path" は元実装の `pattern.test(ctx.cwd) || pattern.test(resolvedPath)` と
// 同じ判定を rule_engine 側(candidates = [cwd, file_path])で再現する。
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

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    const home = os.homedir();

    // 1. Inspect Bash Commands
    if (event.toolName === "bash") {
      const command = (event.input.command as string) || "";
      const root = repoRoot(import.meta.url);

      if (RULES && root && command) {
        const result = evaluateShellCommand(root, ctx.cwd, command);
        // all_matches をJSON宣言順のまま走査し、旧実装の「マッチ毎にhasUI時confirm・
        // 承認後も継続・非UI時は即hard block」というUXをそのまま再現する。tier/descriptionは
        // decide.pyが応答に直接埋め込む値をそのまま使う(security-audit指摘2026-09-03:
        // モジュールロード時に読み込んだローカルのRULESキャッシュへidで逆引きすると、
        // decide.pyがフレッシュに読んだルールファイルとこのプロセス寿命中のキャッシュが
        // ズレた場合に該当マッチが未確認のまま握り潰される穴になっていた — RULESは
        // 「decide.py呼び出し前のnullチェック」以外の用途に使わない)。
        for (const m of result.all_matches ?? []) {
          if (ctx.hasUI) {
            const title = m.tier === "ask" ? "Confirm Destructive Operation" : "Dangerous Command Warning";
            const ok = await ctx.ui.confirm(
              title,
              `The agent is trying to execute:\n\n$ ${command}\n\nReason: ${m.description}\n\nAllow execution?`,
            );
            if (!ok) {
              return { block: true, reason: `Blocked by user: ${m.description}` };
            }
            // 承認された場合はこのruleについては通過するが、複合コマンドが他のruleにも
            // 一致しうるため走査を継続する(claude実装のask/block順序バグと同じ罠への対策 —
            // ここで早期returnすると後続のより深刻なruleを見逃す)。
          } else {
            return { block: true, reason: `Security Gate blocked command: ${m.description}` };
          }
        }
      }

      // Vald Law 2 Check (in vald repository)
      if (root && command) {
        const valdRulesFile = path.join(root, "agent", "vald-law-rules.json");
        if (fs.existsSync(valdRulesFile)) {
          const law2 = evaluateValdLaw2(root, valdRulesFile, ctx.cwd, command);
          if (law2.decision === "block") {
            return { block: true, reason: law2.reason ?? "Vald Law 2 violation" };
          }
        }
      }
    }

    // 2. Inspect File Write & Edit
    if (event.toolName === "write" || event.toolName === "edit") {
      const rawPath = (event.input.file_path || event.input.path || "") as string;
      if (!rawPath) return;

      const root = repoRoot(import.meta.url);
      const resolvedPath = path.isAbsolute(rawPath) ? rawPath : path.resolve(ctx.cwd, rawPath);

      if (RULES && root) {
        const writeResult = evaluateWritePath(root, ctx.cwd, home, rawPath);
        if (writeResult.decision === "block") {
          const label = writeResult.reason ?? "";
          if (ctx.hasUI) {
            const ok = await ctx.ui.confirm(
              "Protected File Modification",
              `The agent is trying to write to sensitive file (${label}):\n\n${resolvedPath}\n\nAllow write?`,
            );
            if (!ok) {
              return { block: true, reason: `Blocked by user: Modification to protected path (${resolvedPath}) denied.` };
            }
          } else {
            return { block: true, reason: `Security Gate blocked modification to sensitive path: ${resolvedPath}` };
          }
        }
      }
      if (root) {
        const valdRulesFile = path.join(root, "agent", "vald-law-rules.json");
        if (fs.existsSync(valdRulesFile)) {
          // Vald Law 1 Check: *.pb.go, *_vtproto.pb.go, *_grpc.pb.go, *.pb.gw.go are generated
          const law1 = evaluateValdLaw1(root, valdRulesFile, resolvedPath);
          if (law1.decision === "block") {
            return { block: true, reason: law1.reason ?? "Vald Law 1 violation" };
          }

          // Vald Laws 3/4/5: no panic/log.Fatal, no discarded errors, no stdlib log/errors/
          // sync/strings imports in production (non-test) Go code. claude/agy実装との強制力の
          // 食い違い(pi は元々Law3/4/5チェック自体が存在しなかった)を解消するため本統合で追加した。
          const content = extractWrittenContent(event);
          if (content) {
            const law345 = evaluateValdLaw345(root, valdRulesFile, ctx.cwd, resolvedPath, content);
            if (law345.decision === "ask") {
              const violations = law345.violations ?? [];
              if (violations.length > 0) {
                // 旧実装どおり先頭5件までに切り詰める(claudeは無制限、agy/piは元々5件上限
                // だった書式上の差異を保持する — decisionそのものへの影響は無い)。
                const reason = `Vald Law violation(s) in ${path.basename(resolvedPath)}:\n${violations.slice(0, 5).map((v) => `- ${v}`).join("\n")}`;
                if (ctx.hasUI) {
                  const ok = await ctx.ui.confirm("Vald Law 3/4/5 Violation", `${reason}\n\nAllow write?`);
                  if (!ok) {
                    return { block: true, reason: `Blocked by user: ${reason}` };
                  }
                } else {
                  return { block: true, reason };
                }
              }
            }
          }
        }
      }
    }
  });
}
