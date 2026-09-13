// Shared @nanonets/graft dist/claude resolution logic for graft-hooks.cjs and
// graft-statusline.cjs (previously duplicated verbatim in both -- factored out here per
// architecture-adversarial-reviewer's Phase 4.5 finding, 2026-09-13).
'use strict';
const path = require('path');
const fs = require('fs');
const { execFileSync } = require('child_process');

const BAKED = "/home/kpango/.bun/install/global/node_modules/@nanonets/graft/dist/claude";

// The dist/claude dir of @nanonets/graft resolved from a base whose node_modules is searched.
// `base` must never be (or be derived from) the project tree itself -- see the SECURITY note
// on entry() below for why.
function fromPkg(base) {
  try {
    const pkg = require.resolve('@nanonets/graft/package.json', { paths: [base] });
    return path.join(path.dirname(pkg), 'dist', 'claude');
  } catch { return null; }
}

// The global node_modules dir per npm (handles Homebrew/Windows/volta). Queried on demand.
function globalRoot() {
  try {
    const root = execFileSync('npm', ['root', '-g'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], shell: process.platform === 'win32' }).trim();
    return root || null;
  } catch { return null; /* npm unavailable */ }
}

// The {name, version} of the package a dist/claude dir belongs to, or null if unreadable.
// Reading `name` (not just `version`) lets best() reject a candidate that isn't actually
// @nanonets/graft, rather than trusting directory shape alone.
function pkgInfoOf(distClaude) {
  try {
    const pkg = JSON.parse(fs.readFileSync(path.join(distClaude, '..', '..', 'package.json'), 'utf8'));
    return { name: pkg.name || null, version: pkg.version || null };
  } catch { return null; }
}

// Numeric-dotted compare of the release part; an unreadable version loses to any known one.
function newer(a, b) {
  if (!a) return false;
  if (!b) return true;
  const p = (v) => String(v).split('-')[0].split('.').map((n) => Number(n) || 0);
  const pa = p(a), pb = p(b);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] || 0) - (pb[i] || 0);
    if (d !== 0) return d > 0;
  }
  return false;
}

// The highest-versioned dir in `dirs` that actually contains `name` AND whose package.json
// name field is genuinely "@nanonets/graft" (not just directory shape), or null.
function best(dirs, name) {
  let bestDir = null, bestVer = null;
  for (const d of dirs) {
    if (!d || !fs.existsSync(path.join(d, name))) continue;
    const info = pkgInfoOf(d);
    // Strict opt-in: an unreadable package.json, or one whose name isn't literally
    // "@nanonets/graft", is rejected outright -- never treated as an unknown-but-acceptable
    // version. (A prior version of this check only rejected an explicit name mismatch, which
    // let a candidate with no readable package.json at all slip through as "unknown version".)
    if (!info || info.name !== '@nanonets/graft') continue;
    if (bestDir === null || newer(info.version, bestVer)) { bestDir = d; bestVer = info.version; }
  }
  return bestDir;
}

// Resolve the on-disk path to `name` (e.g. "hooks.js"/"statusline.js") inside a *verified*
// @nanonets/graft install, or null if none is found.
//
// SECURITY (security-adversarial-reviewer, Phase 4.5, 2026-09-13, 2 rounds): the original
// version of this resolver ended in an unverified last-ditch guess -- `path.join(dir, 'dist',
// 'claude', name)` where `dir` is the project root -- and imported whatever was there with no
// check it belonged to the real package (round 1 finding). The round-1 fix still searched
// `fromPkg(dir)` (the project root) as a "verified" candidate, but `require.resolve` against
// an attacker-writable directory only proves *a directory shaped like the package* exists
// there, not that it's genuine -- round 2's review planted a fake
// `<project>/node_modules/@nanonets/graft/{package.json (forged high version),
// dist/claude/hooks.js}` and showed it silently won over the real global install, because
// `best()` picked highest-*claimed*-version with no name check.
// This version fixes both: (a) `dir` (the project tree) is never included in the search
// candidates at all -- only BAKED (a fixed, non-project absolute path), Node's own install
// tree, and `npm root -g` are searched, none of which a project-tree PR/file can influence;
// (b) `best()`/`pkgInfoOf()` additionally verify the candidate's package.json `name` field is
// literally "@nanonets/graft" before trusting its claimed version, so a forged package.json
// can no longer outrank a genuine install even if it does end up on one of the searched paths.
function entry(name) {
  // Cheap candidates first, and only shell out to npm when every one of them misses. Deliberately
  // excludes the project directory (CLAUDE_PROJECT_DIR/cwd) -- see SECURITY note above.
  const nodeLib = fromPkg(path.join(path.dirname(process.execPath), '..', 'lib'));
  const hit = best([BAKED, nodeLib], name);
  if (hit) return path.join(hit, name);
  const gr = globalRoot();
  const global = gr && path.join(gr, '@nanonets', 'graft', 'dist', 'claude');
  if (global) {
    const verified = best([global], name);
    if (verified) return path.join(verified, name);
  }
  return null; // no verified install found anywhere searched -- caller no-ops
}

module.exports = { entry };
