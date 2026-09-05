/**
 * pi/extensions/ 配下の CLI ブリッジ拡張(bridge-claude.ts・bridge-antigravity.ts・bridge-codex.ts)が
 * 共有するプロセス起動・abort処理ロジック。
 *
 * 3ファイルとも「他CLIバイナリをspawnし、stdout/stderrをストリーミング蓄積し、AbortSignal経由の
 * キャンセルをSIGTERM→3秒後SIGKILLで処理する」という同一のプロセス管理コードを持っていた
 * (2026-09-03のAI関連dotfiles横断調査で発見、各ファイル約180行中約35行が一字一句同一)。
 * この部分だけを共有し、各ツール固有のもの(paramsスキーマ・buildArgs・render関数・
 * ResultDetails型の形)は各ファイルに残す — パラメータスキーマ・CLI引数構築・表示文言は
 * ツールごとに本質的に異なり、無理に1つの型へ押し込めると可読性を損なうため。
 *
 * 注意: このファイルはPi Coding Agentの拡張機能ディスカバリの対象にしてはならない
 * (agent/hooks/pi/lib/shared.ts と同じ理由 — index.ts/index.js/package.jsonを置かなければ
 * `lib/` サブディレクトリ自体がスキャン対象から外れることを実装ソース直読で確認済み)。
 */

import { spawn } from "node:child_process";

export interface CliBridgeRunResult {
  exitCode: number;
  stdout: string;
  stderr: string;
  wasAborted: boolean;
}

export interface CliBridgeStreamUpdate {
  /** その時点までに蓄積されたstdout(まだ空の可能性がある)。 */
  stdout: string;
  /** その時点までに蓄積されたstderr。 */
  stderr: string;
  /** 画面表示用テキスト(stdoutが空ならrunningPlaceholderになる)。 */
  displayText: string;
}

export interface CliBridgeRunOptions {
  binary: string;
  args: string[];
  cwd: string;
  env?: NodeJS.ProcessEnv;
  signal?: AbortSignal;
  /** stdoutが空の間、displayTextとして使うプレースホルダ文言(例: "(Claude Code running...)")。 */
  runningPlaceholder: string;
  /** stdoutのチャンク受信のたびに呼ばれる。呼び出し側でResultDetails形状のonUpdateを組み立てる。 */
  onUpdate?: (update: CliBridgeStreamUpdate) => void;
}

/**
 * 外部CLIバイナリをspawnし、完了(またはabort)まで待つ。3ブリッジで一字一句同一だった
 * spawn/ストリーミング/abort処理をここに集約する。
 */
export function runCliBridge(opts: CliBridgeRunOptions): Promise<CliBridgeRunResult> {
  return new Promise((resolve) => {
    let stdout = "";
    let stderr = "";
    let wasAborted = false;
    // "exit"イベントを実際の終了確定フラグとして使う(security-audit指摘2026-09-03、Medium:
    // 統合前の3ブリッジに一字一句同一のまま存在していた既存バグを本統合で発見・修正。
    // ChildProcess#killedは「kill()が呼ばれたか」を示すフラグであって「実際に終了したか」
    // ではない(Node.js公式ドキュメント) — proc.kill("SIGTERM")の呼び出し成功時点で即座に
    // trueになるため、旧実装の`if (!proc.killed) proc.kill("SIGKILL")`は通常ケースで
    // 常にfalse判定となりSIGKILLへのフォールバックが実質不発だった)。
    let exited = false;

    // `detached: true` で子プロセスを新しいプロセスグループのリーダーにし、killは
    // `process.kill(-pid, sig)`(負のPID = プロセスグループ全体)で行う。単一PIDへのkillだと
    // 子プロセス自身が更に生成した孫プロセス(例: bashスクリプトが起動したsleep等)へは
    // シグナルが届かず、孫プロセスが標準出力パイプを保持し続けて"close"イベントが
    // 自然終了まで(SIGKILLしたにも関わらず)発火しない実害を実機確認した
    // (fakeバイナリ経由、SIGKILL後 close が3.5秒→10秒超に遅延することを確認・
    // プロセスグループkillへの変更で3.5秒に復帰することを確認)。detached自体はUnix限定の
    // 挙動だが、このdotfilesはArch Linux専用のため対象外プラットフォームは無い。
    const proc = spawn(opts.binary, opts.args, {
      cwd: opts.cwd,
      env: opts.env ?? process.env,
      stdio: ["ignore", "pipe", "pipe"],
      detached: true,
    });

    proc.on("exit", () => {
      exited = true;
    });

    proc.stdout.on("data", (chunk) => {
      const text = chunk.toString();
      stdout += text;
      opts.onUpdate?.({ stdout, stderr, displayText: stdout || opts.runningPlaceholder });
    });

    proc.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    proc.on("close", (code) => {
      resolve({ exitCode: code ?? 0, stdout, stderr, wasAborted });
    });

    proc.on("error", (err) => {
      stderr += `\nProcess error: ${err.message}`;
      resolve({ exitCode: 1, stdout, stderr, wasAborted });
    });

    const killGroup = (sig: NodeJS.Signals) => {
      if (proc.pid) {
        try {
          process.kill(-proc.pid, sig);
          return;
        } catch {
          // プロセスグループkillが使えない/既に空(全滅済み)の場合は単一プロセスへfallback。
        }
      }
      try {
        proc.kill(sig);
      } catch {
        // プロセスが既に終了している場合のkill失敗は無視してよい(fail-open)。
      }
    };

    if (opts.signal) {
      const killProc = () => {
        wasAborted = true;
        killGroup("SIGTERM");
        setTimeout(() => {
          if (!exited) killGroup("SIGKILL");
        }, 3000);
      };
      if (opts.signal.aborted) killProc();
      else opts.signal.addEventListener("abort", killProc, { once: true });
    }
  });
}

/**
 * exitCode/stdout/stderrから表示用テキストとisErrorを導出する共通ルール
 * (3ブリッジとも同一: stdoutがあればそれを使い、無ければexitCode!=0時はstderrかフォールバック
 * 文言、成功時は"(no output)")。
 */
export function deriveCliBridgeOutput(
  exitCode: number,
  stdout: string,
  stderr: string,
  errorFallbackText: string,
): { isError: boolean; outputText: string } {
  const isError = exitCode !== 0;
  const outputText = stdout.trim() || (isError ? stderr.trim() || errorFallbackText : "(no output)");
  return { isError, outputText };
}
