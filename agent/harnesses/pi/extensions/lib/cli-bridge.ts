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
  timedOut?: boolean;
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
  /** Timeout in milliseconds (default: 180,000ms / 3 minutes). 0 disables timeout. */
  timeoutMs?: number;
  /** stdoutが空の間、displayTextとして使うプレースホルダ文言(例: "(Claude Code running...)")。 */
  runningPlaceholder: string;
  /** stdoutのチャンク受信のたびに呼ばれる。呼び出し側でResultDetails形状のonUpdateを組み立てる。 */
  onUpdate?: (update: CliBridgeStreamUpdate) => void;
}

export interface CircuitBreakerState {
  status: "CLOSED" | "OPEN" | "HALF_OPEN";
  failureCount: number;
  lastFailureTime: number;
}

export const CIRCUIT_BREAKER_FAILURE_THRESHOLD = 3;
export const CIRCUIT_BREAKER_COOLDOWN_MS = 30_000;
export const CIRCUIT_BREAKER_EXIT_CODE = 111;
const circuitBreakers = new Map<string, CircuitBreakerState>();

export function getCircuitBreakerState(binary: string): CircuitBreakerState {
  const existing = circuitBreakers.get(binary);
  if (existing) return existing;
  const initial: CircuitBreakerState = {
    status: "CLOSED",
    failureCount: 0,
    lastFailureTime: 0,
  };
  circuitBreakers.set(binary, initial);
  return initial;
}

export function resetCircuitBreakers(): void {
  circuitBreakers.clear();
}

/**
 * Spawn an external CLI binary and wait for completion (or abort/timeout).
 * Includes circuit-breaker protection and process-group-safe reclamation.
 */
export function runCliBridge(opts: CliBridgeRunOptions): Promise<CliBridgeRunResult> {
  const breaker = getCircuitBreakerState(opts.binary);
  const now = Date.now();

  if (breaker.status === "OPEN") {
    if (now - breaker.lastFailureTime > CIRCUIT_BREAKER_COOLDOWN_MS) {
      breaker.status = "HALF_OPEN";
    } else {
      const remainingSec = Math.max(1, Math.round((CIRCUIT_BREAKER_COOLDOWN_MS - (now - breaker.lastFailureTime)) / 1000));
      return Promise.resolve({
        exitCode: CIRCUIT_BREAKER_EXIT_CODE,
        stdout: "",
        stderr: `Circuit breaker OPEN for binary '${opts.binary}': ${breaker.failureCount} consecutive failures. Cooldown active for ${remainingSec}s. Please use alternate fallback CLI.`,
        wasAborted: false,
        timedOut: false,
      });
    }
  }

  return new Promise((resolve) => {
    let stdout = "";
    let stderr = "";
    let wasAborted = false;
    let timedOut = false;
    let exited = false;
    let settled = false;
    let timeoutTimer: NodeJS.Timeout | null = null;
    let escalationTimers: NodeJS.Timeout[] = [];

    const timeoutLimit = opts.timeoutMs ?? 180_000;

    const proc = spawn(opts.binary, opts.args, {
      cwd: opts.cwd,
      env: opts.env ?? process.env,
      stdio: ["ignore", "pipe", "pipe"],
      detached: true,
    });

    const cleanup = () => {
      if (timeoutTimer) {
        clearTimeout(timeoutTimer);
        timeoutTimer = null;
      }
      for (const t of escalationTimers) {
        clearTimeout(t);
      }
      escalationTimers = [];
    };

    // Resolve exactly once: Node.js emits both 'error' and 'close' for spawn
    // failures (ENOENT etc.), and timeout/abort escalation must never leave the
    // caller's promise pending forever even if pipes are retained by descendants.
    const handleOutcome = (code: number | null, customError?: string) => {
      if (settled) return;
      settled = true;
      cleanup();
      // Escalation status wins over a late 'close' code: a timed-out or aborted
      // invocation must be reported as such even if the pipe eventually closes
      // with a clean exit code, so callers see the true outcome and the circuit
      // breaker records the failure.
      const finalCode = timedOut ? 124 : wasAborted ? 130 : (code ?? 0);
      if (customError) {
        stderr += `\n${customError}`;
      }

      if (finalCode === 0) {
        breaker.status = "CLOSED";
        breaker.failureCount = 0;
      } else if (!wasAborted) {
        breaker.failureCount++;
        breaker.lastFailureTime = Date.now();
        if (breaker.failureCount >= CIRCUIT_BREAKER_FAILURE_THRESHOLD) {
          breaker.status = "OPEN";
        }
      }

      resolve({ exitCode: finalCode, stdout, stderr, wasAborted, timedOut });
    };

    // Grace period after SIGKILL: if the child still refuses to release the
    // stdout/stderr pipes (e.g. detached grandchild), force-resolve so callers
    // never hang and the circuit breaker still records the failure. Fires even
    // when the parent already exited (`exited === true`) because 'close' can be
    // delayed indefinitely while a descendant holds the pipe open.
    const scheduleForceResolve = (graceMs: number) => {
      const t = setTimeout(() => {
        if (!settled) {
          handleOutcome(null);
        }
      }, graceMs);
      t.unref?.();
      escalationTimers.push(t);
    };

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
      handleOutcome(code);
    });

    proc.on("error", (err) => {
      handleOutcome(1, `Process error: ${err.message}`);
    });

    const killGroup = (sig: NodeJS.Signals) => {
      if (proc.pid) {
        try {
          process.kill(-proc.pid, sig);
          return;
        } catch {}
      }
      try {
        proc.kill(sig);
      } catch {}
    };

    const escalate = () => {
      killGroup("SIGTERM");
      const t = setTimeout(() => {
        if (!exited) killGroup("SIGKILL");
        scheduleForceResolve(1000);
      }, 3000);
      t.unref?.();
      escalationTimers.push(t);
    };

    // Timeout Protection. Mirrors the abort path: mark timedOut and escalate
    // regardless of whether the parent already exited, because 'close' can be
    // delayed indefinitely while a descendant holds the pipe open. SIGTERM/
    // SIGKILL sends are internally gated on process liveness, and the forced
    // resolution is unconditional so callers never hang.
    if (timeoutLimit > 0) {
      timeoutTimer = setTimeout(() => {
        timedOut = true;
        stderr += `\n[TIMEOUT] Process '${opts.binary}' exceeded execution deadline of ${timeoutLimit}ms. Terminated.`;
        escalate();
      }, timeoutLimit);
    }

    if (opts.signal) {
      const killProc = () => {
        wasAborted = true;
        cleanup();
        escalate();
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
