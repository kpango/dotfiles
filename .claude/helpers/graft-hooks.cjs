#!/usr/bin/env node
const { pathToFileURL } = require('url');
const { entry } = require('./graft-resolve.cjs');

const target = entry('hooks.js');
if (target) {
  // Once entry() has resolved a verified install, an import/main() failure is a real error
  // (not "graft unavailable" -- that case is already handled by the `if (target)` guard above),
  // so it goes to stderr rather than being silently swallowed. stderr, not stdout: hook stdout
  // is parsed as the hook's JSON response and must not carry diagnostic noise.
  import(pathToFileURL(target).href)
    .then((m) => m.main(process.argv[2]))
    .catch((err) => { console.error('[graft-hooks]', err && err.stack || err); });
}
