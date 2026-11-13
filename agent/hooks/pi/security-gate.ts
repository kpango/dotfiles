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
  // security_shell familyのみ、System-1 (Laya) 後段が実際に呼ばれた場合だけ存在する
  // (CONTEXT.md "ai-env-deepresearch-overhaul" I-14)。guard_advisor.apply()の戻り値。
  laya?: {
    probability: number;
    enabled_capabilities: string[];
    applied_capability: "guard_strengthen" | "guard_deny" | "guard_relax" | null;
    decision: "allow" | "ask" | "block";
  };
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
      // T9/I-14: System-1 (Laya) 後段ガードレールの opt-in。harness を明示的に渡さない限り
      // decide.py 側は System-1 後段を一切適用しない(no-op)。
      harness: "pi",
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

// Tier B 書込保護ゲート: write-scope-lib.sh の write_scope_is_protected() が定義する
// swarm自己統治ファイル(hooks/skills/SWARM.md/settings.json等)への書込を、既存の
// evaluateWritePath(機微パス)判定とは独立に追加保護する(既存ロジックには一切手を入れない)。
// **fail-openにしない**: callDecide自体が失敗(decide.py起動不能等)した場合のfallbackも、
// 他family呼び出し(evaluateWritePath等)が渡す{decision:"allow"}ではなく明示的に
// {decision:"block"}を渡す(Tier Bはfail-closed — agent/scripts/hooks/decide.pyの
// handle_write_scopeコメントと対称の方針)。
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

// T9/I-14: reflect decide.py's TOP-LEVEL `decision` (which may have been adjusted
// by the System-1/Laya post-stage layer, guard_advisor.apply()) into pi's
// confirm/block UX, on top of the pre-existing per-match `all_matches` walk
// below (that walk predates T9 and is unchanged in its own semantics).
//
// Extracted as a standalone, exported, pure-ish function (its only side effect
// is calling the injected `confirmFn`) specifically so it can be unit-tested
// against constructed DecideResult fixtures without the full Pi Extension API
// runtime -- see agent/scripts/jev/test_security_gate_pi.ts.
//
// Three cases (CONTEXT.md I-14's own decision table):
//   - guard_deny (-> "block"): hard block, unconditionally (no confirm even with
//     hasUI) -- Laya's own strengthening judgment is treated the same way a
//     deterministic "block" is treated in the no-UI branch below, not given the
//     hasUI-shows-a-confirm treatment `all_matches`-driven block/ask entries get
//     (that existing UX is about a *deterministically matched rule*; a
//     guard_deny escalation from "allow" has, by construction, no matched rule
//     backing it at all, since decide.py's own `_GUARD_CAPABILITIES` order checks
//     guard_deny before guard_strengthen and only ever escalates a non-block
//     decision that survived every deterministic rule check unmatched).
//   - guard_strengthen (allow -> "ask"): show ONE confirm for this Laya-driven
//     strengthening (not tied to any all_matches entry, since none exists for
//     it); no UI -> hard block, matching the existing all_matches no-UI branch's
//     own convention.
//   - guard_relax (ask -> "allow"): the ORIGINAL deterministic decision was
//     "ask", sourced from exactly one all_matches entry (`result.matched_rule_id`)
//     -- the confirm the loop below would otherwise show for that one entry is
//     skipped, since decide.py's own top-level decision already reflects the
//     relaxed outcome and asking about it would contradict that outcome and
//     needlessly interrupt the user for something already resolved. Any OTHER
//     matched entry (a different rule matching the same compound command) is
//     processed normally.
export async function handleShellCommandResult(
  result: DecideResult,
  command: string,
  confirmFn: (title: string, message: string) => Promise<boolean>,
  hasUI: boolean,
): Promise<{ block: true; reason: string } | undefined> {
  // I-2 hard floor, checked FIRST and unconditionally, before any all_matches
  // walk (Checker-reported defect, revision 2 review, reproduced and fixed):
  // decide.py's own top-level "block" must never be reachable via a confirm
  // dialog that the user can approve their way past. The previous version of
  // this function only reached this check AFTER walking `all_matches`, gated
  // on `all_matches.length === 0` -- but guard_deny can escalate a
  // deterministic "ask" (which DOES have a matching all_matches entry, e.g.
  // `git_checkout_discard`) straight to "block", so that gate was false and
  // the loop below handled the entry as an ordinary ask-tier confirm instead:
  // approving it returned `undefined` (allow), executing the command despite
  // decide.py's own decision being "block". Reproduced: guard_deny enabled,
  // mock noul=0.95, harness=pi, command "git checkout ." ->
  // decision="block", all_matches=[git_checkout_discard] -- approving the
  // resulting confirm let the command through.
  //
  // This also applies to an ordinary DETERMINISTIC block-tier match (no Laya
  // involved at all): decide.py's own block_rules-before-ask_rules ordering
  // guarantees that whenever any all_matches entry has tier "block", decision
  // is already "block" (guard_advisor.apply() never touches an existing
  // "block" either -- I-2's hard floor). The PRE-EXISTING pi implementation
  // (before this task) showed a confirm dialog for such a match whenever
  // hasUI was true, letting a user override what claude/agy both already
  // treat as an unconditional deny -- an independent inconsistency with I-2
  // this fix also closes, not only the guard_deny-escalation case above.
  if (result.decision === "block") {
    return { block: true, reason: `Security Gate blocked command: ${result.reason ?? ""}` };
  }

  const laya = result.laya;
  const relaxedMatchId = laya?.applied_capability === "guard_relax" ? result.matched_rule_id : undefined;

  for (const m of result.all_matches ?? []) {
    if (m.id === relaxedMatchId) {
      continue;
    }
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
      // 一致しうるため走査を継続する(claude実装のask/block順序バグと同じ罠への対策 —
      // ここで早期returnすると後続のより深刻なruleを見逃す)。
    } else {
      return { block: true, reason: `Security Gate blocked command: ${m.description}` };
    }
  }

  // guard_strengthen (allow -> "ask") is the only remaining case that can
  // reach here with `laya` set: guard_deny is handled by the unconditional
  // "block" check above (decide.py's own _GUARD_CAPABILITIES order checks
  // guard_deny before guard_strengthen, and both only ever fire on a decision
  // that survived every deterministic rule check unmatched, so
  // `result.all_matches` is empty whenever either actually applied -- kept as
  // an explicit condition below anyway, for defense in depth / self-
  // documentation, not because it can currently be false when reached).
  const noDeterministicMatch = (result.all_matches ?? []).length === 0;
  if (laya?.applied_capability === "guard_strengthen" && result.decision === "ask" && noDeterministicMatch) {
    if (hasUI) {
      const ok = await confirmFn(
        "Confirm Destructive Operation (System-1)",
        `The agent is trying to execute:\n\n$ ${command}\n\nReason: ${result.reason ?? ""}\n\nAllow execution?`,
      );
      if (!ok) {
        return { block: true, reason: `Blocked by user: ${result.reason ?? ""}` };
      }
    } else {
      return { block: true, reason: `Security Gate blocked command (System-1): ${result.reason ?? ""}` };
    }
  }
  return undefined;
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
        // all_matches をJSON宣言順のまま走査する既存UX(旧実装の「マッチ毎にhasUI時confirm・
        // 承認後も継続・非UI時は即hard block」)に加え、T9/I-14: decide.pyのトップレベル
        // decision(System-1/Layaによる調整を含みうる)も反映する
        // (handleShellCommandResultの内部doc参照)。
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

      // Tier B 書込保護ゲート(write-scope): security-rules.jsonの機微パス判定とは独立に、
      // swarm自体の行動規範ファイル(hooks/skills/SWARM.md/settings.json等)への書込を追加保護
      // する。RULES(security-rules.json)のロードに失敗していてもこちらは独立に評価する
      // (root さえ解決できればよい)。
      if (root) {
        const scopeResult = evaluateWriteScope(root, ctx.cwd, home, rawPath);
        if (scopeResult.decision === "block") {
          const reason = scopeResult.reason ?? "Tier B protected path (write-scope)";
          if (ctx.hasUI) {
            const ok = await ctx.ui.confirm(
              "Tier B Protected Path (write-scope gate)",
              `The agent is trying to write to a Tier B protected path (${reason}):\n\n${resolvedPath}\n\nAllow write?`,
            );
            if (!ok) {
              return { block: true, reason: `Blocked by user: Tier B protected path (${resolvedPath}) denied.` };
            }
          } else {
            return { block: true, reason: `Security Gate blocked write to Tier B protected path: ${resolvedPath}` };
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
