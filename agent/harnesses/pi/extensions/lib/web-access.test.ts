import { htmlToMarkdown } from "../web-access";

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

console.log(`\n${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
