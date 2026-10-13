#!/usr/bin/env node
const { pathToFileURL } = require('url');
const { entry } = require('./graft-resolve.cjs');

const target = entry('statusline.js');
if (target) {
  // See graft-hooks.cjs for why this goes to stderr rather than a blanket no-op: once entry()
  // has resolved a verified install, a thrown error here is a real failure, not "graft
  // unavailable" (that case is already handled by the `if (target)` guard above).
  import(pathToFileURL(target).href)
    .then((m) => m.main())
    .catch((err) => { console.error('[graft-statusline]', err && err.stack || err); });
}
