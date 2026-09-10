/**
 * pi向けdecide.py委譲shim(agent/hooks/pi/配下)が共有するヘルパー関数。
 *
 * 注意: このファイルはPi Coding Agentの拡張機能ディスカバリの対象にしてはならない。
 * `pi/extensions/lib/` サブディレクトリ(本ファイルの旧配置場所。現在は
 * `~/.pi/agent/extensions/lib` へper-file symlinkされるagent/hooks/pi/lib/が実体)に
 * `index.ts`/`index.js`/`package.json`(`pi.extensions`宣言付き)を置くと、そのサブディレクトリ
 * 自体が独立した拡張機能エントリとして扱われてしまう(`@earendil-works/pi-coding-agent` の
 * `discoverExtensionsInDir`/`resolveExtensionEntries` 実装を直読して確認済み、2026-09-03)。
 * このファイルは他の拡張機能ファイルから相対importされる通常のモジュールとしてのみ機能し、
 * default exportを持たない(意図的)。
 */

import { execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

/**
 * 呼び出し元の拡張機能ファイルから見たdotfilesリポジトリのrootを解決する。
 *
 * 呼び出し元(security-gate.ts・graphify-hint.ts・auto-memory.ts)は `~/.pi/agent/extensions/*.ts`
 * (通常インストール経路、agent/hooks/pi/*.tsへのper-file symlink、2026-09-03以降は
 * claude/agy側と同型のmerged directory — ディレクトリ自体は実体でファイル単位のsymlinkのみ)
 * として実行されるため、realpath でsymlinkを物理解決してから遡る必要がある(2026-09-03以前は
 * 3ファイルに一字一句同一のこの関数が独立にコピーされていたものを統合、
 * agent-hooks-and-pi-agents-unificationミッションで`pi/extensions/*.ts`から
 * `agent/hooks/pi/*.ts`へ実体移動したため階層が1段深くなった: 旧配置
 * `pi/extensions/<file>.ts`(repo rootまで2階層)→ 新配置`agent/hooks/pi/<file>.ts`
 * (repo rootまで3階層)。
 *
 * **realpathSyncを`dirname`より先に、ファイルパス自身へ適用する**(bash側のCRITICAL修正
 * 〈`readlink -f`をfile自身へ先に適用してから`dirname`する〉と同じ理由・同じ順序)。
 * `import.meta.url`(=callerUrl)がbun/nodeの実装により既にsymlink解決済みのパスを返す場合は
 * このrealpathSyncは冪等な no-op だが、将来のbun/nodeバージョンでこの挙動が変わり
 * callerUrlが未解決のmerged directory側パスを返すようになった場合でも、ここで
 * ファイル自身のsymlinkを解決してから`dirname`するため正しいrepo rootへ到達できる
 * (2026-09-03 Phase 4.5 Round 2レビューで指摘: 現行bun/node実装での実機確認のみに依拠せず、
 * bashと同じ「dirnameより先にファイル自身のsymlinkを解決する」順序へ揃えることでバージョン
 * 依存の前提を除去する)。
 *
 * `callerUrl` には呼び出し元で `import.meta.url` を渡すこと — このファイル自身の
 * `import.meta.url` を使うと `lib/` という1階層分ずれた場所を起点に解決してしまう。
 */
export function repoRoot(callerUrl: string): string | null {
  try {
    const filePath = fs.realpathSync(fileURLToPath(callerUrl));
    const here = path.dirname(filePath);
    return path.resolve(here, "..", "..", "..");
  } catch {
    return null;
  }
}

/**
 * `agent/scripts/hooks/decide.py` を呼び出し、標準入力にJSONで渡した `request` の判定結果を
 * 標準出力からJSON.parseして返す共有ヘルパー。
 *
 * 2026-09-03以前、security-gate.ts・auto-memory.ts・graphify-hint.ts に execFileSync + JSON.parse +
 * try/catch fail-open という同型のパターン(decide.pyのパスもpath.join(root, "agent", "scripts",
 * "hooks", "decide.py")で同一)が戻り値の型だけを変えてそれぞれ独立に実装されていたものを統合した。
 *
 * decide.py 自体が見つからない/起動できない/クラッシュした場合は fail-open し、呼び出し元が
 * 渡した `fallback` をそのまま返す(致命的にしない、claude/agyシムと同じ方針)。
 */
interface CacheEntry<T> {
  value: T;
  timestamp: number;
}

const DECIDE_CACHE = new Map<string, CacheEntry<any>>();
const CACHE_TTL_MS = 60_000; // 60s TTL
const MAX_CACHE_SIZE = 500;

export function clearDecideCache(): void {
  DECIDE_CACHE.clear();
}

export function getDecideCacheSize(): number {
  return DECIDE_CACHE.size;
}

/**
 * `agent/scripts/hooks/decide.py` を呼び出し、標準入力にJSONで渡した `request` の判定結果を
 * 標準出力からJSON.parseして返す共有ヘルパー。
 *
 * 高頻度な tool_call での Python 起動コストを排除するため、LRU / TTL 付きインメモリキャッシュを
 * 備え、同一判定リクエストはサブミリ秒（<0.1ms）で高速返却する。
 */
export function callDecide<T>(root: string, request: Record<string, unknown>, fallback: T): T {
  const cacheKey = JSON.stringify({ root, request });
  const now = Date.now();

  const cached = DECIDE_CACHE.get(cacheKey);
  if (cached && now - cached.timestamp < CACHE_TTL_MS) {
    return cached.value as T;
  }

  try {
    const decidePy = path.join(root, "agent", "scripts", "hooks", "decide.py");
    const out = execFileSync("python3", [decidePy], {
      input: JSON.stringify(request),
      encoding: "utf-8",
      timeout: 10000,
    });
    const parsed = JSON.parse(out) as T;

    // Maintain cache size
    if (DECIDE_CACHE.size >= MAX_CACHE_SIZE) {
      const oldestKey = DECIDE_CACHE.keys().next().value;
      if (oldestKey) DECIDE_CACHE.delete(oldestKey);
    }
    DECIDE_CACHE.set(cacheKey, { value: parsed, timestamp: now });

    return parsed;
  } catch {
    return fallback;
  }
}
