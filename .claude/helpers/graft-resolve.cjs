// Shared @nanonets/graft dist/claude resolution logic for graft-hooks.cjs and
// graft-statusline.cjs (previously duplicated verbatim in both -- factored out here per
// architecture-adversarial-reviewer's Phase 4.5 finding, 2026-09-13).
'use strict';
const path = require('path');
const fs = require('fs');
const { execFileSync } = require('child_process');

const dir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const BAKED = "/home/kpango/.bun/install/global/node_modules/@nanonets/graft/dist/claude";

// The dist/claude dir of @nanonets/graft resolved from a base whose node_modules is searched.
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

// The version of the package a dist/claude dir belongs to, or null if unreadable.
function versionOf(distClaude) {
  try {
    return JSON.parse(fs.readFileSync(path.join(distClaude, '..', '..', 'package.json'), 'utf8')).version || null;
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

// The highest-versioned dir in `dirs` that actually contains `name`, or null.
function best(dirs, name) {
  let bestDir = null, bestVer = null;
  for (const d of dirs) {
    if (!d || !fs.existsSync(path.join(d, name))) continue;
    const v = versionOf(d);
    if (bestDir === null || newer(v, bestVer)) { bestDir = d; bestVer = v; }
  }
  return bestDir;
}

// Resolve the on-disk path to `name` (e.g. "hooks.js"/"statusline.js") inside a *verified*
// @nanonets/graft install, or null if none is found.
//
// SECURITY (security-adversarial-reviewer, Phase 4.5, 2026-09-13): the original version of
// this resolver ended in an unverified last-ditch guess -- `path.join(dir, 'dist', 'claude',
// name)` -- and imported whatever was there with no check that it actually belonged to the
// real @nanonets/graft package. Since these hooks fire on nearly every agent action with no
// user confirmation (unlike Bash-tool calls, which go through the permission system), that
// guess would have silently imported and executed any file an attacker (a malicious PR, a
// compromised dependency, an unrelated tool) managed to place at `<project>/dist/claude/*.js`.
// This version never falls back to a bare guess: every candidate below is verified to belong
// to an actual installed @nanonets/graft package (via `fromPkg`'s `require.resolve` against a
// real node_modules, or `globalRoot`'s `npm root -g`) before its dist/claude dir is trusted.
function entry(name) {
  // Cheap candidates first, and only shell out to npm when every one of them misses.
  const cheap = [BAKED, fromPkg(dir), fromPkg(path.join(path.dirname(process.execPath), '..', 'lib'))];
  const hit = best(cheap, name);
  if (hit) return path.join(hit, name);
  const gr = globalRoot();
  const global = gr && path.join(gr, '@nanonets', 'graft', 'dist', 'claude');
  if (global && fs.existsSync(path.join(global, name))) return path.join(global, name);
  return null; // no verified install found anywhere searched -- caller no-ops
}

module.exports = { entry };
