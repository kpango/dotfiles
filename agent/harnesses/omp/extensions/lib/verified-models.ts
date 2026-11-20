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

export const VERIFIED_CLIS = ["omp", "agy"] as const;
export const VERIFIED_MAX_AGE_MS = 24 * 60 * 60 * 1000;

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
export function toOmpSelector(ref: string): string {
  const bare = ref.replace(EFFORT_SUFFIX, "");
  return bare.startsWith("openai/") ? `openai-codex/${bare.slice("openai/".length)}` : bare;
}

/** 有効(status=ok かつ期限内)なキャッシュに載っているモデル selector の集合。読めなければ空集合。 */
export function loadVerifiedModels(
  now: number = Date.now(),
  dir: string = verifiedModelDir(),
): Set<string> {
  const verified = new Set<string>();
  for (const cli of VERIFIED_CLIS) {
    try {
      const record = JSON.parse(fs.readFileSync(path.join(dir, `${cli}.json`), "utf-8")) as {
        status?: string;
        fetched_at?: number;
        models?: unknown;
      };
      if (record.status !== "ok" || typeof record.fetched_at !== "number") continue;
      if (now - record.fetched_at * 1000 > VERIFIED_MAX_AGE_MS) continue;
      if (!Array.isArray(record.models)) continue;
      for (const m of record.models) if (typeof m === "string") verified.add(m);
    } catch {
      // 欠落・破損は寄与なし(fail-closed)
    }
  }
  return verified;
}

/** ref を OMP selector へ正規化し、検証済み一覧に含まれる場合だけ返す。含まれなければ undefined。 */
export function pickVerified(ref: string | undefined, verified: Set<string>): string | undefined {
  if (!ref) return undefined;
  const selector = toOmpSelector(ref);
  return verified.has(selector) ? selector : undefined;
}

/** セッション開始時に CLI 一覧を取り直す。失敗しても例外は投げない(キャッシュは unavailable になる)。 */
export function refreshVerifiedModels(scriptPath: string): void {
  try {
    execFileSync("python3", [scriptPath, ...VERIFIED_CLIS], {
      stdio: ["ignore", "ignore", "ignore"],
      timeout: 60_000,
    });
  } catch {
    // fetch 失敗時は fetch-harness-models.py が unavailable を書くため、古い一覧は使われない
  }
}
