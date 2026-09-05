/**
 * Web & RFC Access Extension for Pi Coding Agent
 *
 * Provides web documentation fetching, HTML-to-Markdown extraction,
 * and web search capabilities for fast RFC/API lookup during research tasks.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

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
