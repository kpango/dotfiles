/**
 * Supermemory adapter for the Pi Coding Agent memory subsystem.
 *
 * Talks to the locally self-hosted supermemory server (default http://localhost:6767)
 * over its HTTP API (`/v3/documents` ingest, `/v4/search` retrieval). Replaces the
 * previous `~/.claude/memory` markdown dump (decide.py `memory_context` family) with
 * RAG-style semantic retrieval so sessions inject only the relevant subset instead of
 * the entire corpus.
 *
 * Design notes:
 * - Pure request/response shaping (`buildSearchRequest`, `parseSearchResults`,
 *   `buildDocumentPayload`, `formatMemoryInjection`, `resolveSupermemoryConfig`) is
 *   separated from I/O so it is unit-testable without a live server or network.
 * - The async I/O helpers accept an injectable `fetchImpl` (dependency injection) so
 *   tests never touch the network or global state.
 * - All network failures degrade gracefully to an empty result (the memory subsystem
 *   is advisory; a missing/unreachable server must never crash a session). This is
 *   error handling, not a markdown fallback — no legacy read path remains.
 * - `~/.supermemory` server prints a local API key that is "auto-applied for
 *   unauthenticated localhost requests", so from localhost the key is optional; when
 *   present (SUPERMEMORY_API_KEY env or ~/.supermemory/env) it is sent as a bearer.
 *
 * This module has no default export and imports no pi runtime-only packages, so it is
 * a plain relative-import module (never an extension discovery entry).
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

export interface SupermemoryConfig {
  endpoint: string;
  apiKey: string | null;
}

export interface SupermemoryMemory {
  id?: string;
  memory: string;
  documentId?: string;
  title?: string;
  score?: number;
  containerTag?: string;
}

export type FetchLike = (
  url: string,
  init?: {
    method?: string;
    headers?: Record<string, string>;
    body?: string;
    signal?: AbortSignal;
  },
) => Promise<{ ok: boolean; status: number; json: () => Promise<unknown>; text: () => Promise<string> }>;

const DEFAULT_ENDPOINT = "http://localhost:6767";

// Mirrors agent/scripts/hooks/supermemory.sh's sm__validate_endpoint exactly: only
// http://(localhost|127.0.0.1|[::1])(:1-65535)?/? is trusted. Rejects userinfo, path,
// query, fragment, non-loopback hosts, and any other scheme -- this client must not
// silently talk to (or leak the API key / query content to) a non-loopback endpoint,
// whether from a misconfigured env var or a tampered ~/.supermemory/env.
const LOOPBACK_ENDPOINT_RE = /^http:\/\/(localhost|127\.0\.0\.1|\[::1\])(:([0-9]+))?\/?$/;

/** Exported so tests (and any future consumer) can assert the same invariant directly. */
export function isValidLoopbackEndpoint(raw: string): boolean {
  const m = LOOPBACK_ENDPOINT_RE.exec(raw);
  if (!m) return false;
  const port = m[3];
  if (port === undefined) return true;
  const n = Number(port);
  return Number.isInteger(n) && n >= 1 && n <= 65535;
}

/**
 * Resolve the supermemory endpoint + optional API key.
 * Precedence: explicit env (SUPERMEMORY_API_URL / SUPERMEMORY_API_KEY) →
 * ~/.supermemory/env file → defaults. Never throws.
 *
 * A configured-but-invalid (non-loopback) endpoint is refused outright rather than
 * silently substituting the default -- same "fail closed, don't fall back" contract as
 * the bash sibling's `sm_endpoint`. Refusal is signaled with `endpoint: ""`; callers
 * must treat that as "no server configured" (all exported async helpers here already
 * do, via the empty-endpoint check added to each).
 */
export function resolveSupermemoryConfig(
  env: Record<string, string | undefined> = process.env,
  envFilePath: string = path.join(os.homedir(), ".supermemory", "env"),
): SupermemoryConfig {
  let endpoint = (env.SUPERMEMORY_API_URL || "").trim();
  let apiKey = (env.SUPERMEMORY_API_KEY || "").trim();

  if ((!endpoint || !apiKey) && envFilePath) {
    try {
      const raw = fs.readFileSync(envFilePath, "utf-8");
      for (const line of raw.split("\n")) {
        const idx = line.indexOf("=");
        if (idx <= 0) continue;
        const k = line.slice(0, idx).trim();
        const v = line.slice(idx + 1).trim();
        if (!endpoint && k === "SUPERMEMORY_API_URL") endpoint = v;
        if (!apiKey && k === "SUPERMEMORY_API_KEY") apiKey = v;
      }
    } catch {
      /* env file optional */
    }
  }

  const resolved = (endpoint || DEFAULT_ENDPOINT).replace(/\/+$/, "");
  return {
    endpoint: isValidLoopbackEndpoint(resolved) ? resolved : "",
    apiKey: apiKey || null,
  };
}

function authHeaders(cfg: SupermemoryConfig): Record<string, string> {
  const h: Record<string, string> = { "content-type": "application/json" };
  if (cfg.apiKey) h.authorization = `Bearer ${cfg.apiKey}`;
  return h;
}

/** Build the POST /v4/search request (pure). `tags` scope the search (containerTags). */
export function buildSearchRequest(
  cfg: SupermemoryConfig,
  query: string,
  tags: string[] = [],
  limit = 8,
): { url: string; body: string } {
  const payload: Record<string, unknown> = { q: query, limit: Math.max(1, Math.min(limit, 50)) };
  if (tags.length > 0) payload.containerTags = tags;
  return { url: `${cfg.endpoint}/v4/search`, body: JSON.stringify(payload) };
}

/** Parse a /v4/search response body into a normalized memory list (pure, defensive). */
export function parseSearchResults(json: unknown): SupermemoryMemory[] {
  if (!json || typeof json !== "object") return [];
  const results = (json as { results?: unknown }).results;
  if (!Array.isArray(results)) return [];
  const out: SupermemoryMemory[] = [];
  for (const r of results) {
    if (!r || typeof r !== "object") continue;
    const o = r as Record<string, unknown>;
    const memory = typeof o.memory === "string" ? o.memory : typeof o.content === "string" ? o.content : "";
    if (!memory.trim()) continue;
    out.push({
      id: typeof o.id === "string" ? o.id : undefined,
      memory: memory.trim(),
      documentId: typeof o.documentId === "string" ? o.documentId : undefined,
      title: typeof o.title === "string" ? o.title : undefined,
      score: typeof o.score === "number" ? o.score : undefined,
    });
  }
  return out;
}

/** Build the POST /v3/documents ingest payload (pure). */
export function buildDocumentPayload(
  content: string,
  tags: string[],
  metadata: Record<string, unknown> = {},
  customId?: string,
): Record<string, unknown> {
  const payload: Record<string, unknown> = {
    content,
    metadata,
    containerTags: tags,
  };
  // supermemory rejects customId containing "/" or "." — sanitize to [A-Za-z0-9_-].
  if (customId) payload.customId = customId.replace(/[^A-Za-z0-9_-]/g, "-").slice(0, 120);
  return payload;
}

/** Format a retrieved memory list into a compact session-injection block (pure). */
export function formatMemoryInjection(memories: SupermemoryMemory[], header = "Relevant Memory (supermemory)"): string {
  const seen = new Set<string>();
  const lines: string[] = [];
  for (const m of memories) {
    const t = m.memory.trim();
    if (!t || seen.has(t)) continue;
    seen.add(t);
    lines.push(`- ${t}`);
  }
  if (lines.length === 0) return "";
  return `[${header}]:\n${lines.join("\n")}`;
}

async function withTimeout<T>(p: (signal: AbortSignal) => Promise<T>, ms: number, fallback: T): Promise<T> {
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), ms);
  try {
    return await p(ac.signal);
  } catch {
    return fallback;
  } finally {
    clearTimeout(timer);
  }
}

function getFetch(fetchImpl?: FetchLike): FetchLike | null {
  if (fetchImpl) return fetchImpl;
  const g = (globalThis as { fetch?: unknown }).fetch;
  return typeof g === "function" ? (g as unknown as FetchLike) : null;
}

/** Semantic search. Returns [] on any error/unavailability (advisory, never throws). */
export async function searchMemories(
  query: string,
  opts: { tags?: string[]; limit?: number; timeoutMs?: number; cfg?: SupermemoryConfig; fetchImpl?: FetchLike } = {},
): Promise<SupermemoryMemory[]> {
  const q = query.trim();
  if (!q) return [];
  const cfg = opts.cfg ?? resolveSupermemoryConfig();
  if (!cfg.endpoint) return [];
  const doFetch = getFetch(opts.fetchImpl);
  if (!doFetch) return [];
  const { url, body } = buildSearchRequest(cfg, q, opts.tags ?? [], opts.limit ?? 8);
  return withTimeout(
    async (signal) => {
      const resp = await doFetch(url, { method: "POST", headers: authHeaders(cfg), body, signal });
      if (!resp.ok) return [];
      return parseSearchResults(await resp.json());
    },
    opts.timeoutMs ?? 4000,
    [],
  );
}

/** Ingest a document. Returns the queued id or null on failure (never throws). */
export async function addMemory(
  content: string,
  tags: string[],
  opts: { metadata?: Record<string, unknown>; customId?: string; timeoutMs?: number; cfg?: SupermemoryConfig; fetchImpl?: FetchLike } = {},
): Promise<string | null> {
  if (!content.trim()) return null;
  const cfg = opts.cfg ?? resolveSupermemoryConfig();
  if (!cfg.endpoint) return null;
  const doFetch = getFetch(opts.fetchImpl);
  if (!doFetch) return null;
  const payload = buildDocumentPayload(content, tags, opts.metadata ?? {}, opts.customId);
  return withTimeout(
    async (signal) => {
      const resp = await doFetch(`${cfg.endpoint}/v3/documents`, {
        method: "POST",
        headers: authHeaders(cfg),
        body: JSON.stringify(payload),
        signal,
      });
      if (!resp.ok) return null;
      const j = (await resp.json()) as { id?: unknown };
      return typeof j.id === "string" ? j.id : null;
    },
    opts.timeoutMs ?? 30000,
    null,
  );
}

/** Cheap availability probe (GET /). Returns false on any error. */
export async function isAvailable(opts: { timeoutMs?: number; cfg?: SupermemoryConfig; fetchImpl?: FetchLike } = {}): Promise<boolean> {
  const cfg = opts.cfg ?? resolveSupermemoryConfig();
  if (!cfg.endpoint) return false;
  const doFetch = getFetch(opts.fetchImpl);
  if (!doFetch) return false;
  return withTimeout(
    async (signal) => {
      const resp = await doFetch(`${cfg.endpoint}/`, { method: "GET", signal });
      return resp.ok;
    },
    opts.timeoutMs ?? 2000,
    false,
  );
}
