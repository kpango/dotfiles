/**
 * Web & RFC Access Extension for Pi Coding Agent
 *
 * Provides web documentation fetching, HTML-to-Markdown extraction,
 * and web search capabilities for fast RFC/API lookup during research tasks.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

// --- SSRF guard for outbound fetches -----------------------------------------
// `web_fetch` accepts an arbitrary URL. Without validation an attacker (via a
// poisoned page/tool argument) could target the loopback interface, the
// link-local cloud metadata endpoint (169.254.169.254), or RFC1918 hosts to
// reach internal services. This blocks obvious internal/reserved targets by
// literal host/IP inspection. (DNS-rebinding is out of scope for a hostname
// check; the intent is to stop the trivial and most damaging cases.)

// Parse a single inet_aton-style numeric part: decimal, octal (0-prefixed), or
// hex (0x-prefixed). Returns null if not a valid numeric literal.
function parseIpPart(s: string): number | null {
  if (s === "") return null;
  let val: number;
  if (/^0[xX][0-9a-fA-F]+$/.test(s)) {
    val = parseInt(s.slice(2), 16);
  } else if (/^0[0-7]+$/.test(s)) {
    val = parseInt(s, 8);
  } else if (/^(0|[1-9]\d*)$/.test(s)) {
    val = parseInt(s, 10);
  } else {
    return null;
  }
  return Number.isFinite(val) ? val : null;
}

// Full inet_aton emulation: accepts "a", "a.b", "a.b.c", "a.b.c.d" with each
// part in decimal/octal/hex. This is required because getaddrinfo() (used by the
// fetch DNS layer) treats e.g. "2130706433", "0177.0.0.1", "0x7f.1", "127.1" as
// 127.0.0.1 — a classic SSRF bypass a naive dotted-quad regex misses.
function ipv4ToInt(host: string): number | null {
  const parts = host.split(".");
  if (parts.length < 1 || parts.length > 4) return null;
  const nums: number[] = [];
  for (const p of parts) {
    const n = parseIpPart(p);
    if (n === null) return null;
    nums.push(n);
  }
  // inet_aton: the last part absorbs the remaining bytes.
  let ip: number;
  switch (nums.length) {
    case 1:
      if (nums[0] > 0xffffffff) return null;
      ip = nums[0];
      break;
    case 2:
      if (nums[0] > 0xff || nums[1] > 0xffffff) return null;
      ip = (nums[0] << 24) + nums[1];
      break;
    case 3:
      if (nums[0] > 0xff || nums[1] > 0xff || nums[2] > 0xffff) return null;
      ip = (nums[0] << 24) + (nums[1] << 16) + nums[2];
      break;
    default:
      if (nums.some((n) => n > 0xff)) return null;
      ip = (nums[0] << 24) + (nums[1] << 16) + (nums[2] << 8) + nums[3];
      break;
  }
  return ip >>> 0;
}

function ipv4InCidr(ip: number, base: string, bits: number): boolean {
  const b = ipv4ToInt(base);
  if (b === null) return false;
  const mask = bits === 0 ? 0 : (0xffffffff << (32 - bits)) >>> 0;
  return (ip & mask) === (b & mask);
}

export function isBlockedHost(rawHost: string): boolean {
  let host = (rawHost || "").trim().toLowerCase();
  if (!host) return true;
  // strip IPv6 brackets
  const v6 = host.startsWith("[") && host.endsWith("]");
  if (v6) host = host.slice(1, -1);

  // Hostname suffixes / literals that always resolve internally.
  if (
    host === "localhost" ||
    host.endsWith(".localhost") ||
    host.endsWith(".internal") ||
    host.endsWith(".local") ||
    host === "metadata.google.internal"
  ) {
    return true;
  }

  // IPv4 literal ranges.
  const ip = ipv4ToInt(host);
  if (ip !== null) {
    return (
      ipv4InCidr(ip, "0.0.0.0", 8) ||
      ipv4InCidr(ip, "10.0.0.0", 8) ||
      ipv4InCidr(ip, "100.64.0.0", 10) ||
      ipv4InCidr(ip, "127.0.0.0", 8) ||
      ipv4InCidr(ip, "169.254.0.0", 16) || // link-local incl. 169.254.169.254 metadata
      ipv4InCidr(ip, "172.16.0.0", 12) ||
      ipv4InCidr(ip, "192.0.0.0", 24) ||
      ipv4InCidr(ip, "192.168.0.0", 16) ||
      ipv4InCidr(ip, "198.18.0.0", 15) ||
      ip === 0xffffffff
    );
  }

  // IPv6 literal ranges (loopback / unspecified / ULA fc00::/7 / link-local fe80::/10
  // / IPv4-mapped loopback).
  if (host.includes(":")) {
    if (host === "::1" || host === "::") return true;
    if (/^f[cd][0-9a-f]{2}:/.test(host)) return true; // fc00::/7 ULA
    if (/^fe[89ab][0-9a-f]:/.test(host)) return true; // fe80::/10 link-local
    const mapped = host.match(/::ffff:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/);
    if (mapped) return isBlockedHost(mapped[1]);
    return true; // unknown/other IPv6 literal -> block conservatively
  }

  return false;
}

export function assertSafeFetchUrl(url: string): { ok: true } | { ok: false; reason: string } {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return { ok: false, reason: `Invalid URL: ${url}` };
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    return { ok: false, reason: `Blocked non-HTTP(S) scheme: ${parsed.protocol}` };
  }
  if (isBlockedHost(parsed.hostname)) {
    return { ok: false, reason: `Blocked internal/reserved host: ${parsed.hostname}` };
  }
  return { ok: true };
}

export function htmlToMarkdown(html: string): string {
  let text = html;

  // 1. Strip script, style, svg, noscript, nav, header, footer
  text = text.replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, "");
  text = text.replace(/<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>/gi, "");
  text = text.replace(/<svg\b[^<]*(?:(?!<\/svg>)<[^<]*)*<\/svg>/gi, "");
  text = text.replace(/<noscript\b[^<]*(?:(?!<\/noscript>)<[^<]*)*<\/noscript>/gi, "");
  text = text.replace(/<nav\b[^<]*(?:(?!<\/nav>)<[^<]*)*<\/nav>/gi, "");
  text = text.replace(/<footer\b[^<]*(?:(?!<\/footer>)<[^<]*)*<\/footer>/gi, "");

  // 2. Headings
  text = text.replace(/<h1[^>]*>([\s\S]*?)<\/h1>/gi, "\n# $1\n");
  text = text.replace(/<h2[^>]*>([\s\S]*?)<\/h2>/gi, "\n## $1\n");
  text = text.replace(/<h3[^>]*>([\s\S]*?)<\/h3>/gi, "\n### $1\n");
  text = text.replace(/<h[4-6][^>]*>([\s\S]*?)<\/h[4-6]>/gi, "\n#### $1\n");

  // 3. Code blocks & inline code
  text = text.replace(/<pre[^>]*><code[^>]*>([\s\S]*?)<\/code><\/pre>/gi, "\n```\n$1\n```\n");
  text = text.replace(/<code[^>]*>([\s\S]*?)<\/code>/gi, "`$1`");

  // 4. Links & images
  text = text.replace(/<a\s+(?:[^>]*?\s+)?href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi, "[$2]($1)");
  text = text.replace(/<img\s+(?:[^>]*?\s+)?src="([^"]*)"(?:\s+alt="([^"]*)")?[^>]*>/gi, "![$2]($1)");

  // 5. Lists & items
  text = text.replace(/<li[^>]*>([\s\S]*?)<\/li>/gi, "\n- $1");

  // 6. Paragraphs, blockquotes, divs, breaks
  text = text.replace(/<blockquote[^>]*>([\s\S]*?)<\/blockquote>/gi, "\n> $1\n");
  text = text.replace(/<br\s*\/?>/gi, "\n");
  text = text.replace(/<p[^>]*>([\s\S]*?)<\/p>/gi, "\n\n$1\n\n");
  text = text.replace(/<div[^>]*>/gi, "\n");
  text = text.replace(/<\/div>/gi, "\n");

  // 7. Strip remaining HTML tags
  text = text.replace(/<[^>]+>/g, "");

  // 8. Unescape common HTML entities
  text = text
    .replace(/&nbsp;/g, " ")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x27;/g, "'");

  // 9. Normalize whitespace
  text = text.replace(/[ \t]+/g, " ");
  text = text.replace(/\n{3,}/g, "\n\n");
  return text.trim();
}

export async function fetchUrl(url: string, maxChars: number = 32000): Promise<{ title: string; markdown: string; status: number }> {
  const safe = assertSafeFetchUrl(url);
  if (!safe.ok) {
    return { title: "", markdown: `Blocked (SSRF guard): ${safe.reason}`, status: 0 };
  }
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 15000);

  try {
    const res = await fetch(url, {
      signal: controller.signal,
      headers: {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0",
        Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,text/plain;q=0.8,*/*;q=0.5",
      },
    });

    clearTimeout(timeoutId);

    const status = res.status;
    if (!res.ok) {
      return { title: "", markdown: `HTTP Error: ${res.status} ${res.statusText}`, status };
    }

    const html = await res.text();
    const titleMatch = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
    const title = titleMatch ? titleMatch[1].trim() : url;

    let markdown = htmlToMarkdown(html);
    if (markdown.length > maxChars) {
      markdown = markdown.slice(0, maxChars) + `\n\n... [Content truncated at ${maxChars} characters]`;
    }

    return { title, markdown, status };
  } catch (err: any) {
    clearTimeout(timeoutId);
    return { title: "", markdown: `Fetch Error: ${err.message}`, status: 0 };
  }
}

export interface SearchResult {
  title: string;
  url: string;
  snippet: string;
}

export async function searchWeb(query: string, limit: number = 5): Promise<SearchResult[]> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 15000);

  try {
    const searchUrl = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`;
    const res = await fetch(searchUrl, {
      signal: controller.signal,
      headers: {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0",
      },
    });

    clearTimeout(timeoutId);
    if (!res.ok) return [];

    const html = await res.text();
    const results: SearchResult[] = [];

    // Parse DuckDuckGo html search results
    const blockRegex = /<div class="result__body">([\s\S]*?)<\/div>/gi;
    let blockMatch: RegExpExecArray | null;

    while ((blockMatch = blockRegex.exec(html)) !== null && results.length < limit) {
      const block = blockMatch[1];
      const titleMatch = block.match(/<a class="result__url"[^>]*href="([^"]*)"[^>]*>[\s\S]*?<\/a>[\s\S]*?<a class="result__snippet[^"]*"[^>]*href="[^"]*"[^>]*>([\s\S]*?)<\/a>/i) ||
                         block.match(/<a class="result__snippet"[^>]*>([\s\S]*?)<\/a>/i);
      const urlMatch = block.match(/<a class="result__url"[^>]*href="([^"]*)"/i);
      const headlineMatch = block.match(/<h2 class="result__title">[\s\S]*?<a[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/i);

      if (headlineMatch) {
        const rawUrl = headlineMatch[1];
        let cleanUrl = rawUrl;
        if (rawUrl.includes("uddg=")) {
          const match = rawUrl.match(/uddg=([^&]+)/);
          if (match) cleanUrl = decodeURIComponent(match[1]);
        }
        const title = htmlToMarkdown(headlineMatch[2]);
        const snippet = titleMatch ? htmlToMarkdown(titleMatch[titleMatch.length - 1]) : "";
        results.push({ title, url: cleanUrl, snippet });
      }
    }

    return results;
  } catch {
    clearTimeout(timeoutId);
    return [];
  }
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "web_fetch",
    label: "Web Fetch",
    description: "Fetch web documentation, RFC specifications, or articles and extract clean Markdown content.",
    parameters: Type.Object({
      url: Type.String({ description: "URL to fetch" }),
      maxChars: Type.Optional(Type.Integer({ description: "Maximum character length of content (default: 32000)" })),
    }),
    async execute(_id, params) {
      const res = await fetchUrl(params.url, params.maxChars);
      return {
        content: [{ type: "text", text: `# ${res.title}\n\n${res.markdown}` }],
        details: { status: res.status, title: res.title },
      };
    },
  });

  pi.registerTool({
    name: "web_search",
    label: "Web Search",
    description: "Search the web for programming documentation, error solutions, RFCs, and API references.",
    parameters: Type.Object({
      query: Type.String({ description: "Search query" }),
      limit: Type.Optional(Type.Integer({ description: "Maximum results to return (default: 5)" })),
    }),
    async execute(_id, params) {
      const results = await searchWeb(params.query, params.limit || 5);
      if (results.length === 0) {
        return {
          content: [{ type: "text", text: `No search results found for: "${params.query}"` }],
          details: { count: 0 },
        };
      }

      const formatted = results
        .map((r, i) => `${i + 1}. [${r.title}](${r.url})\n   ${r.snippet}`)
        .join("\n\n");

      return {
        content: [{ type: "text", text: `Search results for "${params.query}":\n\n${formatted}` }],
        details: { count: results.length, results },
      };
    },
  });
}
