/**
 * Session Stop Verification for Pi Coding Agent (advisory)
 *
 * pi 版の「クローズドループ」検証(SWARM.md §6:「完了しました」の自己申告のみでの終了禁止)。
 * claude の `agent/hooks/claude/swarm-stop-verify.sh`(Stop hook)は exit 2 でセッション完了を
 * 差し戻し修正ループへ**強制**するが、**pi の完了系イベントは全て非ブロッキング**である:
 * `session_shutdown`/`turn_end`/`agent_end`/`agent_settled` はいずれも ExtensionHandler の
 * Result 型を持たず(pi-coding-agent 0.84.4 types.d.ts で確認)、シャットダウンを veto できない。
 * injection 可能な近接イベントは `before_agent_start`(=ターン**開始**時)のみで「完了阻止」には使えない。
 *
 * よって本拡張は **助言的縮退**(D-t1.4=(a) kpango 承認 2026-09-07): `session_shutdown` 時に
 * 「このセッションで write/edit したファイル ∩ git 未コミット変更」を lint し、問題があれば
 * `ctx.ui.notify` で最終警告を出す(**ブロックはしない**)。claude の強制力は再現できないが、
 * 自己申告完了に対する可視化は提供する。
 *
 * lint は claude/agy と同じ `swarm-lint-lib.sh`(swarm_lint_dockerfile=hadolint /
 * swarm_lint_go_package=golangci-lint)を、共有 dispatcher `stop-verify-lint.sh` 経由で再利用する
 * (fable-gate の grant_consume 再利用と同型。TypeScript 再実装しない)。json は python3 -m json.tool、
 * zsh は zsh -n。各ツール欠落時は当該チェックを skip(fail-open。claude 版と同じ縮退)。
 *
 * 対象の限定(session編集 ∩ 未コミット)は claude 版と同じ意図: 無関係な dirty ファイルで
 * 警告を出さないため。session 中に編集したパスは tool_result(write/edit)で蓄積する。
 */

import { spawnSync } from "node:child_process";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { extractWrittenPath } from "./post-edit-lint";

// git status --porcelain --untracked-files=all の出力から変更ファイルの絶対パスを得る(pure)。
// 各行は "XY <path>"(先頭2列がステータス)。リネーム "R  old -> new" は new 側を採用する。
export function parseGitStatusPaths(statusOutput: string, root: string): string[] {
  const out: string[] = [];
  for (const rawLine of statusOutput.split("\n")) {
    if (!rawLine.trim()) continue;
    let p = rawLine.slice(3); // 先頭 "XY " を落とす
    const arrow = p.indexOf(" -> ");
    if (arrow >= 0) p = p.slice(arrow + 4); // rename: 新パス側
    p = p.trim();
    if (!p) continue;
    out.push(path.isAbsolute(p) ? p : path.resolve(root, p));
  }
  return out;
}

// 「session 中に編集したファイル」∩「git 未コミット変更」を検証対象にする(pure・testable)。
// 双方を絶対パスに正規化して積集合を取り、重複を除いて返す。
export function computeVerifyTargets(editedAbs: Iterable<string>, changedAbs: Iterable<string>): string[] {
  const changed = new Set<string>();
  for (const c of changedAbs) changed.add(c);
  const seen = new Set<string>();
  const targets: string[] = [];
  for (const e of editedAbs) {
    if (changed.has(e) && !seen.has(e)) {
      seen.add(e);
      targets.push(e);
    }
  }
  return targets;
}

export interface StopVerifyResult {
  errors: string; // 空文字列 = クリーン。非空 = lint 診断(複数行)
  infra: boolean; // swarm-lint-lib.sh 到達不能等のインフラ障害(助言なので警告も出さない)
}

// 共有 dispatcher stop-verify-lint.sh を呼び、targets を種別別に lint する。
// exit 0=完了(stdout=診断、空ならクリーン)/ 2=usage / 3 or spawn error=インフラ障害。
export function runStopVerify(scriptsDir: string, root: string, targets: string[]): StopVerifyResult {
  if (targets.length === 0) return { errors: "", infra: false };
  try {
    const res = spawnSync("bash", [path.join(scriptsDir, "stop-verify-lint.sh"), root, ...targets], {
      encoding: "utf-8",
    });
    if (res.error) return { errors: "", infra: true };
    if (res.status !== 0) return { errors: "", infra: true }; // usage(2)/infra(3)/予期せぬ失敗
    return { errors: (res.stdout || "").trim(), infra: false };
  } catch {
    return { errors: "", infra: true };
  }
}

function scriptsDirDefault(): string {
  return path.join(os.homedir(), ".pi", "agent", "skills", "swarm-implement", "scripts");
}

function gitStatusPaths(cwd: string): { root: string; changed: string[] } | null {
  try {
    const rootRes = spawnSync("git", ["-C", cwd, "rev-parse", "--show-toplevel"], { encoding: "utf-8" });
    if (rootRes.error || rootRes.status !== 0) return null;
    const root = (rootRes.stdout || "").trim();
    if (!root) return null;
    const st = spawnSync("git", ["-C", root, "status", "--porcelain", "--untracked-files=all"], { encoding: "utf-8" });
    if (st.error || st.status !== 0) return null;
    return { root, changed: parseGitStatusPaths(st.stdout || "", root) };
  } catch {
    return null;
  }
}

export default function (pi: ExtensionAPI) {
  // session 中に write/edit したファイル(絶対パス)を蓄積する。
  const edited = new Set<string>();

  pi.on("tool_result", async (event, ctx) => {
    if (event.toolName !== "write" && event.toolName !== "edit") return;
    if ((event as { isError?: boolean }).isError) return;
    const rawPath = extractWrittenPath(event.input as Record<string, unknown> | undefined);
    if (!rawPath) return;
    edited.add(path.isAbsolute(rawPath) ? rawPath : path.resolve(ctx.cwd, rawPath));
  });

  // 注: runStopVerify は spawnSync 同期実行で、このハンドラは dispose() 前に await される。
  // dispatcher 内の hadolint/golangci-lint は各々 `timeout 60` で頭打ちされるが、編集した Go
  // パッケージが複数あれば逐次実行で quit が数十秒遅れうる（無限ハングにはならず
  // 終了自体は妨げないが UX 上の既知トレードオフ。Checker 2026-09-07 advisory）。
  pi.on("session_shutdown", async (_event, ctx) => {
    if (edited.size === 0) return; // 編集していなければ検証不要(Q&A 等をブロック/警告しない)
    const gs = gitStatusPaths(ctx.cwd);
    if (!gs) return; // 非 git / git 失敗 → 助言不能、静かに終了
    const targets = computeVerifyTargets(edited, gs.changed);
    if (targets.length === 0) return; // 編集分は全てコミット済 → クリーン

    const res = runStopVerify(scriptsDirDefault(), gs.root, targets);
    if (res.infra) return; // インフラ障害は助言なので握り潰す(非ブロック)
    if (res.errors && ctx.hasUI) {
      const nfiles = targets.length;
      ctx.ui.notify(
        `stop-verify (advisory, non-blocking): ${nfiles} 件のセッション編集ファイルに未解決の lint 問題があります。` +
          `SWARM.md §6 クローズドループ — 「完了」の前に修正を検討してください:\n${res.errors}`,
        "warning",
      );
    }
  });
}
