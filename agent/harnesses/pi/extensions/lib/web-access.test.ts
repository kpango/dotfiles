import { htmlToMarkdown, isBlockedHost, assertSafeFetchUrl } from "../web-access";

let pass = 0;
let fail = 0;

function eq<T>(name: string, actual: T, expected: T) {
  if (JSON.stringify(actual) === JSON.stringify(expected)) {
    console.log(`ok: ${name}`);
    pass++;
  } else {
    console.error(`FAIL: ${name}`);
    console.error(`  actual:   ${JSON.stringify(actual)}`);
    console.error(`  expected: ${JSON.stringify(expected)}`);
    fail++;
  }
}

function check(name: string, ok: boolean, msg?: string) {
  if (ok) {
    console.log(`ok: ${name}`);
    pass++;
  } else {
    console.error(`FAIL: ${name}: ${msg || ""}`);
    fail++;
  }
}

// 1. htmlToMarkdown basic tags
const sampleHtml = `
  <html>
    <head>
      <title>Test Page</title>
      <script>console.log("ignore me");</script>
      <style>.body { color: red; }</style>
    </head>
    <body>
      <nav><a href="/home">Home</a></nav>
      <h1>Document Title</h1>
      <p>This is a paragraph with <a href="https://example.com">a link</a> and <code>inline code</code>.</p>
      <h2>Sub section</h2>
      <pre><code>const a = 10 &lt; 20;</code></pre>
      <ul>
        <li>Item 1</li>
        <li>Item 2</li>
      </ul>
      <footer>Footer content</footer>
    </body>
  </html>
`;

const md = htmlToMarkdown(sampleHtml);

check("htmlToMarkdown strips script and style", !md.includes("ignore me") && !md.includes("color: red"));
check("htmlToMarkdown strips nav and footer", !md.includes("Home") && !md.includes("Footer content"));
check("htmlToMarkdown converts h1", md.includes("# Document Title"));
check("htmlToMarkdown converts link", md.includes("[a link](https://example.com)"));
check("htmlToMarkdown converts inline code", md.includes("`inline code`"));
check("htmlToMarkdown converts code block", md.includes("```\nconst a = 10 < 20;\n```"));
check("htmlToMarkdown unescapes entities", md.includes("10 < 20"));
check("htmlToMarkdown converts list items", md.includes("- Item 1") && md.includes("- Item 2"));

// 2. SSRF guard: blocked internal/reserved hosts
for (const h of [
  "localhost",
  "app.localhost",
  "svc.internal",
  "printer.local",
  "127.0.0.1",
  "127.5.5.5",
  "0.0.0.0",
  "10.1.2.3",
  "172.16.0.1",
  "172.31.255.255",
  "192.168.1.1",
  "169.254.169.254",
  "100.64.0.1",
  "::1",
  "fd00:ec2::254",
  "fe80::1",
  "metadata.google.internal",
]) {
  check(`isBlockedHost blocks ${h}`, isBlockedHost(h) === true);
}

// 2b. SSRF guard: non-standard numeric IP encodings of 127.0.0.1 / metadata
// (inet_aton bypass class: decimal / octal / hex / short-form).
for (const h of [
  "2130706433", // decimal 127.0.0.1
  "0x7f000001", // hex 127.0.0.1
  "0177.0.0.1", // octal first octet
  "127.1", // short form 127.0.0.1
  "127.0.1", // 3-part short form
  "0x7f.1", // mixed hex + short
  "2852039166", // decimal 169.254.169.254 (metadata)
]) {
  check(`isBlockedHost blocks numeric-bypass ${h}`, isBlockedHost(h) === true);
}

// 3. SSRF guard: allowed public hosts
for (const h of ["example.com", "1.1.1.1", "8.8.8.8", "github.com", "172.32.0.1", "11.0.0.1"]) {
  check(`isBlockedHost allows ${h}`, isBlockedHost(h) === false);
}

// 4. assertSafeFetchUrl end-to-end
check("assertSafeFetchUrl blocks metadata IP", assertSafeFetchUrl("http://169.254.169.254/latest/meta-data/").ok === false);
check("assertSafeFetchUrl blocks decimal loopback", assertSafeFetchUrl("http://2130706433/").ok === false);
check("assertSafeFetchUrl blocks decimal metadata", assertSafeFetchUrl("http://2852039166/latest/meta-data/").ok === false);
check("assertSafeFetchUrl blocks loopback", assertSafeFetchUrl("http://127.0.0.1:8080/").ok === false);
check("assertSafeFetchUrl blocks file scheme", assertSafeFetchUrl("file:///etc/passwd").ok === false);
check("assertSafeFetchUrl blocks gopher scheme", assertSafeFetchUrl("gopher://x/").ok === false);
check("assertSafeFetchUrl blocks bracketed ipv6 loopback", assertSafeFetchUrl("http://[::1]/").ok === false);
check("assertSafeFetchUrl allows https public", assertSafeFetchUrl("https://example.com/rfc").ok === true);
check("assertSafeFetchUrl rejects garbage", assertSafeFetchUrl("not a url").ok === false);

console.log(`\n${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
