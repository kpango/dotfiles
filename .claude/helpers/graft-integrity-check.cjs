#!/usr/bin/env node
// Detects AND ACTIVELY REPAIRS `.claude/helpers/graft-{resolve,hooks,statusline}.cjs` and
// `.claude/settings.json` whenever @nanonets/graft's own `session-start`-hook upkeep mechanism
// silently reverts them to its vendor template, reintroducing the vulnerabilities fixed here:
//
//   1. `entry()` treating the project tree (CLAUDE_PROJECT_DIR/cwd) as a "verified" search
//      candidate for the module it's about to `import()`.
//   2. `.claude/settings.json` carrying an unanchored `Bash(node dist/cli.js:*)` permission, or
//      an unscoped `Bash(npx graft:*)` (vs. the scoped `Bash(npx @nanonets/graft:*)`).
//
// HISTORY / WHY THIS IS ACTIVE-REPAIR, NOT JUST A WARNING (2026-09-13):
// - Round 3 (Phase 4.5, architecture-adversarial-reviewer) added this file as a WARN-ONLY,
//   Stop-only check, written after the reversion was observed live once with no known mechanism.
// - It then recurred in a freshly created task worktree (t5-pi-graft-parity) with nobody having
//   run `graft init`/`graft build` by hand, which led to actually reading @nanonets/graft's own
//   installed source (dist/upkeep.js, dist/claude/hooks.js) rather than continuing to guess:
//   graft's `session-start` hook unconditionally calls `runUpkeep()` -> `reconcileWiring()`,
//   which reads a version "stamp" at `graft/.cache/wiring-stamp.json` and -- per that function's
//   own doc-comment -- treats a MISSING stamp as license to silently re-run its own `init` and
//   overwrite the very files this script protects. That stamp lives under `graft/`, which this
//   repo's own .gitignore (added in this same mission, T4) excludes from git -- so it is
//   necessarily ABSENT in every freshly created `git worktree add` checkout (mission and task
//   worktrees alike, i.e. this repo's normal swarm-loop workflow), making the revert-on-first-
//   session-start not a rare accident but a structural certainty for any new worktree.
// - A warning alone has no enforcement power against a mechanism that fires automatically at
//   SessionStart, before a human ever sees the Stop-time message, and that repeats on every
//   fresh worktree. Hence this version restores automatically, wired into BOTH SessionStart
//   (closes the window as early as possible in a given session) and Stop (a second backstop).
//
// Still deliberately non-blocking (prints to stderr, always exits 0) -- repairing silently and
// promptly is the goal, not halting the session. And still only a literal-marker check, not a
// full behavioral verification -- a sufficiently different rewrite of any of these files could
// still evade detection; this narrows the specific, already-seen recurrence, it does not replace
// keeping the underlying logic correct.
//
// This file itself is NOT part of @nanonets/graft's own template (grep dist/claude/init.js's
// write list against this filename to confirm), so graft's own upkeep has no reason to touch it
// -- unlike graft-hooks.cjs/graft-statusline.cjs/graft-resolve.cjs/.claude/settings.json, which
// graft's installer (and its upkeep re-run of that same installer) does write.
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const root = path.join(__dirname, '..', '..');
const actions = []; // human-readable log of repairs actually made, printed at the end

function readOrNull(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch { return null; }
}

// Write `content` to `fullPath` via a same-directory temp file + atomic rename, rather than a
// direct fs.writeFileSync -- defense-in-depth (security-adversarial-reviewer, follow-up pass on
// this file, 2026-09-13, MEDIUM) against the case where a concurrent hook process (e.g. graft's
// own session-start upkeep, if Claude Code ever runs multiple hooks for one event concurrently
// rather than sequentially -- not confirmed either way from available docs/source) writes the
// same file at the same time: a direct write can interleave with another writer's, producing a
// file that is neither version; a rename is a single filesystem operation that can only land one
// writer's full content or the other's, never a splice of both.
function writeFileAtomic(fullPath, content) {
  const tmp = `${fullPath}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(tmp, content);
  fs.renameSync(tmp, fullPath);
}

// The only files this script is ever allowed to restore from git HEAD -- see restoreFromGitHead.
const RESTORABLE_REL_PATHS = new Set([
  path.join('.claude', 'helpers', 'graft-resolve.cjs'),
  path.join('.claude', 'helpers', 'graft-hooks.cjs'),
  path.join('.claude', 'helpers', 'graft-statusline.cjs'),
]);

// Restore `relPath` (repo-root-relative) to its content at git HEAD. Returns true on success.
// Fails soft (returns false) on any error -- a failed repair attempt must never throw and block
// the hook; the next SessionStart/Stop will simply try again.
//
// `relPath` today only ever comes from the three hardcoded literals below (never from file
// content, argv, or any other externally-influenceable input) -- the RESTORABLE_REL_PATHS
// allowlist check is defense-in-depth for a future edit to this file, not a response to a
// currently-reachable path (security-adversarial-reviewer, follow-up pass, 2026-09-13, MEDIUM:
// this function's own safety previously depended entirely on caller discipline, not on anything
// the function itself enforced).
function restoreFromGitHead(relPath) {
  if (!RESTORABLE_REL_PATHS.has(relPath)) {
    actions.push(`FAILED to restore ${relPath}: not in this script's restorable-file allowlist (refusing as a precaution)`);
    return false;
  }
  try {
    const content = execFileSync('git', ['show', `HEAD:${relPath}`], { cwd: root, encoding: 'utf8' });
    writeFileAtomic(path.join(root, relPath), content);
    return true;
  } catch (err) {
    actions.push(`FAILED to restore ${relPath} from git HEAD: ${err && err.message || err}`);
    return false;
  }
}

// --- graft-resolve.cjs: full restore from git HEAD if it looks reverted ---
const resolveRel = path.join('.claude', 'helpers', 'graft-resolve.cjs');
const resolvePath = path.join(root, resolveRel);
const resolveSrc = readOrNull(resolvePath);
if (resolveSrc === null) {
  if (restoreFromGitHead(resolveRel)) actions.push(`restored missing ${resolveRel} from git HEAD`);
} else {
  // Strip full-line `//` comments before matching -- this file's own SECURITY comment quotes the
  // vulnerable snippets it replaced (`fromPkg(dir)`, `CLAUDE_PROJECT_DIR`) as prose, which would
  // otherwise false-positive against the checks that follow.
  const codeOnly = resolveSrc.split('\n').filter((l) => !l.trim().startsWith('//')).join('\n');
  const looksReverted =
    /\bfromPkg\(dir\)/.test(codeOnly) ||
    /^const dir = process\.env\.CLAUDE_PROJECT_DIR/m.test(codeOnly) ||
    !codeOnly.includes("!== '@nanonets/graft'");
  if (looksReverted && restoreFromGitHead(resolveRel)) {
    actions.push(`restored ${resolveRel} from git HEAD (looked reverted to vendor template)`);
  }
}

// --- graft-hooks.cjs / graft-statusline.cjs: full restore from git HEAD if reverted ---
for (const consumer of ['graft-hooks.cjs', 'graft-statusline.cjs']) {
  const rel = path.join('.claude', 'helpers', consumer);
  const p = path.join(root, rel);
  const src = readOrNull(p);
  const looksReverted = src === null || !src.includes("require('./graft-resolve.cjs')");
  if (looksReverted && restoreFromGitHead(rel)) {
    actions.push(`restored ${rel} from git HEAD (${src === null ? 'was missing' : 'looked reverted to vendor template'})`);
  }
}

// --- .claude/settings.json: surgical repair of permissions.allow only ---
// A full-file restore-from-HEAD would also discard any *legitimate* unrelated local edit a human
// made to this shared, general-purpose file (other plugins/permissions) -- narrower than the two
// helper files above, which have no legitimate reason to diverge from this repo's own fix.
const settingsRel = path.join('.claude', 'settings.json');
const settingsPath = path.join(root, settingsRel);
const settingsSrc = readOrNull(settingsPath);
if (settingsSrc !== null) {
  let settings = null;
  try {
    settings = JSON.parse(settingsSrc);
  } catch (err) {
    // Visible on purpose (security-adversarial-reviewer, follow-up pass, 2026-09-13, MEDIUM):
    // this used to fail silently, asymmetric with restoreFromGitHead's failures (which always
    // push to `actions`) -- and this is this script's own hook wiring file, the least acceptable
    // one to go silently unrepaired.
    actions.push(`FAILED to parse ${settingsRel} as JSON, cannot check/repair its permissions.allow: ${err && err.message || err}`);
  }
  if (settings && settings.permissions && Array.isArray(settings.permissions.allow)) {
    const before = settings.permissions.allow;
    let after = before.filter((entry) => entry !== 'Bash(node dist/cli.js:*)' && entry !== 'Bash(npx graft:*)');
    if (!after.includes('Bash(npx @nanonets/graft:*)')) after = [...after, 'Bash(npx @nanonets/graft:*)'];
    const changed = after.length !== before.length || after.some((v, i) => v !== before[i]);
    if (changed) {
      settings.permissions.allow = after;
      try {
        writeFileAtomic(settingsPath, JSON.stringify(settings, null, 2) + '\n');
        actions.push(`repaired ${settingsRel}'s permissions.allow in place (removed reverted entries, kept the rest of the file as-is)`);
      } catch (err) {
        actions.push(`FAILED to repair ${settingsRel}: ${err && err.message || err}`);
      }
    }
  }
}

if (actions.length > 0) {
  console.error('[graft-integrity-check] graft integration files looked reverted to an unpatched state -- repaired:');
  for (const a of actions) console.error(`  - ${a}`);
  console.error('[graft-integrity-check] Likely cause: @nanonets/graft\'s own session-start upkeep (see this file\'s header comment). Repair is automatic; no action needed unless a FAILED line appears above.');
}
process.exit(0); // always non-blocking -- see file header
