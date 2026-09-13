#!/usr/bin/env node
// Detects whether `graft-resolve.cjs`/`.claude/settings.json` have been silently reverted to
// @nanonets/graft's vendor template by an (accidental or intentional) `graft init`/`graft build`
// re-run against this actual worktree, reintroducing the two vulnerabilities fixed here:
//
//   1. `entry()` treating the project tree (CLAUDE_PROJECT_DIR/cwd) as a "verified" search
//      candidate for the module it's about to `import()`.
//   2. `.claude/settings.json` carrying an unanchored `Bash(node dist/cli.js:*)` permission, or
//      an unscoped `Bash(npx graft:*)` (vs. the scoped `Bash(npx @nanonets/graft:*)`).
//
// Written after this exact reversion happened live during Phase 4.5 round 3
// (architecture-adversarial-reviewer, 2026-09-13): a comment alone ("diff these files after any
// future `graft init` re-run") proved to have zero enforcement power when the re-run itself went
// unnoticed. This script is a substitute for that manual diff, not a replacement for keeping
// `graft-resolve.cjs`'s actual logic correct -- it only checks for the presence/absence of a few
// literal markers, so a sufficiently different rewrite of either file could still evade it. It is
// deliberately non-blocking (prints to stderr, always exits 0) rather than blocking Stop -- see
// the Stop hook entry in .claude/settings.json that invokes it.
//
// This file itself is NOT part of @nanonets/graft's own template (grep dist/claude/init.js's
// PATCH_TARGETS-equivalent list against this filename to confirm), so a `graft init` re-run has
// no reason to touch it -- unlike graft-hooks.cjs/graft-statusline.cjs/graft-resolve.cjs, which
// graft's own installer does write.
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', '..');
const problems = [];

function readOrNull(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch { return null; }
}

const resolvePath = path.join(root, '.claude', 'helpers', 'graft-resolve.cjs');
const resolveSrc = readOrNull(resolvePath);
if (resolveSrc === null) {
  problems.push(`${resolvePath}: file missing entirely (expected the fixed graft-resolve.cjs)`);
} else {
  // Strip full-line `//` comments before matching code patterns below -- this file's own
  // SECURITY comment quotes the vulnerable snippets it replaced (`fromPkg(dir)`,
  // `CLAUDE_PROJECT_DIR`) as prose, which would otherwise false-positive against the checks
  // that follow.
  const codeOnly = resolveSrc
    .split('\n')
    .filter((line) => !line.trim().startsWith('//'))
    .join('\n');
  // Vulnerable vendor template's `entry()` builds its candidate list with `fromPkg(dir)` where
  // `dir` is the project tree -- the fixed version never references `dir` at all.
  if (/\bfromPkg\(dir\)/.test(codeOnly) || /^const dir = process\.env\.CLAUDE_PROJECT_DIR/m.test(codeOnly)) {
    problems.push(`${resolvePath}: contains the vulnerable project-tree candidate pattern (fromPkg(dir)/CLAUDE_PROJECT_DIR fallback) -- looks reverted to the vendor template`);
  }
  if (!codeOnly.includes("!== '@nanonets/graft'")) {
    problems.push(`${resolvePath}: missing the package.json \`name\` verification (best()/pkgInfoOf()) -- looks reverted to the vendor template`);
  }
}

for (const consumer of ['graft-hooks.cjs', 'graft-statusline.cjs']) {
  const p = path.join(root, '.claude', 'helpers', consumer);
  const src = readOrNull(p);
  if (src === null) {
    problems.push(`${p}: file missing entirely`);
  } else if (!src.includes("require('./graft-resolve.cjs')")) {
    problems.push(`${p}: no longer delegates to graft-resolve.cjs -- looks reverted to the vendor template (which duplicates resolution logic inline instead)`);
  }
}

const settingsPath = path.join(root, '.claude', 'settings.json');
const settingsSrc = readOrNull(settingsPath);
if (settingsSrc === null) {
  problems.push(`${settingsPath}: file missing entirely`);
} else {
  let settings;
  try { settings = JSON.parse(settingsSrc); } catch { settings = null; }
  const allow = settings && settings.permissions && Array.isArray(settings.permissions.allow)
    ? settings.permissions.allow : [];
  if (allow.includes('Bash(node dist/cli.js:*)')) {
    problems.push(`${settingsPath}: permissions.allow contains the unanchored "Bash(node dist/cli.js:*)" entry removed in the round-1 security fix`);
  }
  if (allow.includes('Bash(npx graft:*)')) {
    problems.push(`${settingsPath}: permissions.allow contains the unscoped "Bash(npx graft:*)" entry (should be narrowed to "Bash(npx @nanonets/graft:*)")`);
  }
}

if (problems.length > 0) {
  console.error('[graft-integrity-check] WARNING: graft integration files look reverted to an unpatched state:');
  for (const p of problems) console.error(`  - ${p}`);
  console.error('[graft-integrity-check] If this followed a `graft init`/`graft build` re-run, restore via `git checkout -- <file>` and re-apply the security fix (see git log for graft-resolve.cjs).');
}
process.exit(0); // always non-blocking -- see file header
