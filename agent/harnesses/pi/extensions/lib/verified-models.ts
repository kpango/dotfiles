/**
 * CLI 由来の検証済みモデル一覧(agent/scripts/fetch-harness-models.py のキャッシュ)を読む。
 *
 * OMP のモデル選択は、直前の実行で CLI が返した一覧に含まれるものだけに限定する。
 * キャッシュが無い・古い・status!=ok のときは何も許可しない(fail-closed)。
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { execFileSync } from "node:child_process";

export const VERIFIED_CLIS = ["pi", "agy"] as const;
export const VERIFIED_MAX_AGE_MS = 24 * 60 * 60 * 1000;
/**
 * session_start で一覧を取り直す最小間隔。これより新しいキャッシュは再利用する。
 * fetch は `omp models` を子プロセスで起動するため、毎セッション実行すると
 * session_start が実測 ~5.7s ブロックする(ui.loop-blocked / execFileSync)。
 */
export const VERIFIED_REFRESH_INTERVAL_MS = 6 * 60 * 60 * 1000;
/**
 * status!=ok(未ログイン等)のキャッシュを再試行する最小間隔。
 * 失敗を毎セッション取り直すと session_start が実測 5.7〜13.2s ブロックし続けるため、
 * 失敗は成功(6h)より短い 1h で再試行し、回復はその範囲で拾う。
 */
export const VERIFIED_FAILURE_RETRY_MS = 60 * 60 * 1000;

const EFFORT_SUFFIX = /:(minimal|low|medium|high|xhigh|max)$/;

export function verifiedModelDir(env: NodeJS.ProcessEnv = process.env, home: string = os.homedir()): string {
  if (env.AGENT_MODEL_LIST_DIR) return env.AGENT_MODEL_LIST_DIR;
  return path.join(env.XDG_CACHE_HOME || path.join(home, ".cache"), "agent-model-lists");
}

/**
 * SSoT の provider 名を OMP の selector provider へ読み替える。
 * OMP では OpenAI モデルは openai-codex provider(Codex ログイン)経由で提供される。
 * 思考レベル suffix(":high" 等)は選択判定の対象外なので除く。
 */
export function toPiSelector(ref: string): string {
  const bare = ref.replace(EFFORT_SUFFIX, "");
  return bare.startsWith("openai/") ? `openai-codex/${bare.slice("openai/".length)}` : bare;
}

interface VerifiedRecord {
  status?: string;
  fetched_at?: number;
  models?: unknown;
}

function readVerifiedRecord(dir: string, cli: string): VerifiedRecord | undefined {
  try {
    return JSON.parse(fs.readFileSync(path.join(dir, `${cli}.json`), "utf-8")) as VerifiedRecord;
  } catch {
    return undefined; // 欠落・破損は寄与なし(fail-closed)
  }
}

/** 有効(status=ok かつ期限内)なキャッシュに載っているモデル selector の集合。読めなければ空集合。 */
export function loadVerifiedModels(
  now: number = Date.now(),
  dir: string = verifiedModelDir(),
): Set<string> {
  const verified = new Set<string>();
  for (const cli of VERIFIED_CLIS) {
    const record = readVerifiedRecord(dir, cli);
    if (!record || record.status !== "ok" || typeof record.fetched_at !== "number") continue;
    if (now - record.fetched_at * 1000 > VERIFIED_MAX_AGE_MS) continue;
    if (!Array.isArray(record.models)) continue;
    for (const m of record.models) if (typeof m === "string") verified.add(m);
  }
  return verified;
}

/** ref を OMP selector へ正規化し、検証済み一覧に含まれる場合だけ返す。含まれなければ undefined。 */
export function pickVerified(ref: string | undefined, verified: Set<string>): string | undefined {
  if (!ref) return undefined;
  const selector = toPiSelector(ref);
  return verified.has(selector) ? selector : undefined;
}

/** 全 CLI のキャッシュが `intervalMs` 以内に status=ok で取得済みか。 */
export function isVerifiedCacheFresh(
  now: number = Date.now(),
  dir: string = verifiedModelDir(),
  intervalMs: number = VERIFIED_REFRESH_INTERVAL_MS,
): boolean {
  for (const cli of VERIFIED_CLIS) {
    try {
      const record = JSON.parse(fs.readFileSync(path.join(dir, `${cli}.json`), "utf-8")) as {
        status?: string;
        fetched_at?: number;
      };
      if (record.status !== "ok" || typeof record.fetched_at !== "number") return false;
      if (now - record.fetched_at * 1000 > intervalMs) return false;
    } catch {
      return false;
    }
  }
  return true;
}

/**
 * 再取得が必要な CLI 一覧。成功済みは `okIntervalMs`、未取得・失敗は
 * `failureRetryMs` を超えたら対象になる。失敗した CLI だけを fetch するため、
 * 片方が未ログインでも他方の再取得コストは増えない。
 */
export function verifiedRefetchTargets(
  now: number = Date.now(),
  dir: string = verifiedModelDir(),
  okIntervalMs: number = VERIFIED_REFRESH_INTERVAL_MS,
  failureRetryMs: number = VERIFIED_FAILURE_RETRY_MS,
): string[] {
  const due: string[] = [];
  for (const cli of VERIFIED_CLIS) {
    const record = readVerifiedRecord(dir, cli);
    if (!record || typeof record.fetched_at !== "number") {
      due.push(cli);
      continue;
    }
    const ageMs = now - record.fetched_at * 1000;
    const limit = record.status === "ok" ? okIntervalMs : failureRetryMs;
    if (ageMs > limit) due.push(cli);
  }
  return due;
}

export interface RefreshVerifiedModelsOptions {
  now?: number;
  dir?: string;
  intervalMs?: number;
  failureRetryMs?: number;
  /** テスト用フック。既定は python3 fetch-harness-models.py の同期実行。 */
  run?: (scriptPath: string, clis: string[]) => void;
}

/**
 * セッション開始時に CLI 一覧を取り直す。失敗しても例外は投げない(キャッシュは unavailable になる)。
 * 再取得対象が無ければ何もしない: fetch 自体が `omp models` を起動するため、
 * 毎セッションの同期実行は起動を数秒ブロックする。
 */
export function refreshVerifiedModels(
  scriptPath: string,
  options: RefreshVerifiedModelsOptions = {},
): void {
  const dir = options.dir ?? verifiedModelDir();
  const targets = verifiedRefetchTargets(options.now, dir, options.intervalMs, options.failureRetryMs);
  if (targets.length === 0) return;
  const run =
    options.run ??
    ((p: string, clis: string[]) => {
      execFileSync("python3", [p, ...clis], {
        stdio: ["ignore", "ignore", "ignore"],
        timeout: 60_000,
      });
    });
  try {
    run(scriptPath, targets);
  } catch {
    // fetch 失敗時は fetch-harness-models.py が unavailable を書くため、古い一覧は使われない
  }
}
