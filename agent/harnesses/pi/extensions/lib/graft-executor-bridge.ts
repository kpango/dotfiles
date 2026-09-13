/**
 * graft (via executor gateway) bridge for Pi Coding Agent — ADR-0001 decision 2.
 *
 * `graft` has no official Pi Coding Agent target (`graft init --list-agents` does not list
 * pi/primeagent — confirmed by reading graft's installed `dist/hosts/registry.js` /
 * `dist/hosts/mcp-config.js`, see this mission's T4/@fix_plan.md and ADR-0001's Context section).
 * Instead, `executor` (already registered as an MCP server for both Pi and Claude Code) has
 * `graft` registered in its own catalog as integration slug `graft-dotfiles`, reachable at
 * `graft-dotfiles.user.graftDotfiles.<toolName>` via `executor call <path> '<json args>'`
 * (verified end-to-end 2026-09-13, ADR-0001 §Decisions/1). This module shells out to that CLI
 * via the shared `runCliBridge` helper (agent/harnesses/pi/extensions/lib/cli-bridge.ts) —
 * reused rather than duplicated, per this same helper's own header comment about
 * bridge-claude.ts/bridge-antigravity.ts/bridge-codex.ts sharing it.
 *
 * A real `executor call graft-dotfiles.user.graftDotfiles.graft_find_code '{"query":"...","limit":2}'`
 * response looks like (captured live, 2026-09-13):
 *   {"ok":true,"data":{"content":[{"type":"text","text":"<prose with file:line citations>"}],"isError":false}}
 * A failed lookup (unknown tool path, or any other executor-side error) returns exit code 0 from
 * the `executor` CLI itself but `{"ok":false,"error":{"code":"...","message":"..."}}` in stdout —
 * confirmed live by calling a nonexistent tool path and by passing non-JSON args. So exit code
 * alone is NOT sufficient to detect failure; `parsed.ok` must be checked explicitly.
 *
 * 注意: このファイルは lib/ 配下のため Pi の拡張ディスカバリ対象にはならない
 * (`./cli-bridge.ts` 冒頭コメントで確認済みの規約と同じ)。
 */

import { runCliBridge } from "./cli-bridge";

export interface CallGraftToolOptions {
  /** Timeout in milliseconds for the underlying `executor call` process. Default: 10_000ms.
   *  Deliberately much shorter than cli-bridge's own 180_000ms default: this bridge is used from
   *  `before_agent_start`/`session_start` hooks where a hung `executor` must not stall the start
   *  of every turn/session — graft's own context injection here is advisory, not required. */
  timeoutMs?: number;
  /** Override for the `executor` binary name. Test-only hook to simulate "executor not
   *  installed" (ENOENT) without touching PATH; production callers should leave this unset. */
  binary?: string;
  /** Working directory to spawn `executor` from. Note this is NOT the repo graft itself indexes
   *  — that cwd is fixed at executor.mcp.addServer registration time (ADR-0001's "Known
   *  limitation, accepted deliberately"). This is only where the `executor` CLI process itself
   *  is spawned from, which does not affect which repo graft queries. Defaults to process.cwd(). */
  cwd?: string;
}

/**
 * Call one of graft's 6 tools (graft_find_code, graft_trace_calls, graft_find_all,
 * graft_file_api, graft_repo_map, graft_check_freshness) through the executor gateway.
 *
 * Never throws. Returns the extracted `data.content[0].text` string on success, or `null` when:
 * the `executor` binary is missing, the call times out or is otherwise unavailable, the response
 * is not parseable JSON, the response reports `ok:false`, or (this bridge's own design choice,
 * not an executor/graft contract) `data.isError` is `true` — meaning the underlying graft tool
 * call itself failed even though the executor RPC succeeded; surfacing that failure text as if it
 * were legitimate graft context/orientation content would be misleading, so it is treated the
 * same as "unavailable" and dropped silently, mirroring graft's own Claude-Code philosophy of
 * silent no-op when a tool isn't usable.
 */
export async function callGraftTool(
  toolName: string,
  args: Record<string, unknown>,
  opts: CallGraftToolOptions = {},
): Promise<string | null> {
  const binary = opts.binary ?? "executor";
  const cwd = opts.cwd ?? process.cwd();
  const toolPath = `graft-dotfiles.user.graftDotfiles.${toolName}`;

  let result;
  try {
    // args is passed as ["call", toolPath, <one JSON string>] — an argv array, not a shell
    // string — so runCliBridge's underlying node:child_process.spawn (no `shell: true`) delivers
    // the JSON blob to `executor` as a single literal argument regardless of any shell
    // metacharacters it contains. This is the same safety property graphify-bridge.ts's
    // tryGraphifyCli documents and regression-tests for spawnSync; see
    // lib/graft-executor-bridge.test.ts's L1 case for this bridge's own verification.
    result = await runCliBridge({
      binary,
      args: ["call", toolPath, JSON.stringify(args)],
      cwd,
      timeoutMs: opts.timeoutMs ?? 10_000,
      runningPlaceholder: "(graft via executor running...)",
    });
  } catch {
    // runCliBridge's own contract is to resolve, never reject, but guard defensively anyway
    // since this function's own contract ("never throws") is stronger than its callee's.
    return null;
  }

  if (result.wasAborted || result.timedOut || result.exitCode !== 0) return null;

  let parsed: unknown;
  try {
    parsed = JSON.parse(result.stdout);
  } catch {
    return null;
  }

  if (typeof parsed !== "object" || parsed === null || (parsed as { ok?: unknown }).ok !== true) {
    return null;
  }

  const data = (parsed as { data?: unknown }).data;
  if (typeof data !== "object" || data === null) return null;
  if ((data as { isError?: unknown }).isError === true) return null;

  const content = (data as { content?: unknown }).content;
  if (!Array.isArray(content) || content.length === 0) return null;
  const first = content[0];
  if (
    typeof first !== "object" ||
    first === null ||
    (first as { type?: unknown }).type !== "text" ||
    typeof (first as { text?: unknown }).text !== "string"
  ) {
    return null;
  }

  return (first as { text: string }).text;
}
