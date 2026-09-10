// Local header-injecting proxy: adds x-opencode-session (required by opencode.ai/zen "go")
// and forwards to the OpenCode Zen OpenAI-compatible gateway. Local-only.
//
// Upstream is allowlisted to opencode.ai (or a *.opencode.ai subdomain): callers may supply
// their own Authorization header for that provider, and this proxy must never silently
// relay it (or the injected session header) to an unrelated host if OPENCODE_UPSTREAM is
// ever misconfigured or tampered with.
const UP = process.env.OPENCODE_UPSTREAM || "https://opencode.ai/zen/go/v1";
const UP_HOST = new URL(UP).hostname;
if (UP_HOST !== "opencode.ai" && !UP_HOST.endsWith(".opencode.ai")) {
  console.error(`opencode-proxy: refusing to start, OPENCODE_UPSTREAM host "${UP_HOST}" is not opencode.ai or a subdomain of it`);
  process.exit(1);
}
const PORT = Number(process.env.OPENCODE_PROXY_PORT || 8788);
const SID = "ses_" + crypto.randomUUID().replace(/-/g, "");
Bun.serve({
  port: PORT, hostname: "127.0.0.1", idleTimeout: 240,
  async fetch(req) {
    const url = new URL(req.url);
    const path = url.pathname.replace(/^\/v1/, "");
    const target = UP + path + url.search;
    const h = new Headers(req.headers);
    h.set("x-opencode-session", SID);
    h.delete("host"); h.delete("content-length");
    const init = { method: req.method, headers: h };
    if (!["GET", "HEAD"].includes(req.method)) { init.body = req.body; init.duplex = "half"; }
    let resp;
    try { resp = await fetch(target, init); }
    catch (e) { return new Response(JSON.stringify({ error: { message: "proxy fetch failed: " + e }}), { status: 502, headers: { "content-type": "application/json" }}); }
    const rh = new Headers(resp.headers); rh.delete("content-encoding"); rh.delete("content-length");
    return new Response(resp.body, { status: resp.status, headers: rh });
  },
});
console.log(`opencode-proxy listening http://127.0.0.1:${PORT}/v1 -> ${UP} (session ${SID.slice(0,12)}...)`);
