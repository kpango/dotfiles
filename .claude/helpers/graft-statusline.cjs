#!/usr/bin/env node
const { pathToFileURL } = require('url');
const { entry } = require('./graft-resolve.cjs');

const target = entry('statusline.js');
if (target) {
  import(pathToFileURL(target).href).then((m) => m.main()).catch(() => { /* graft unavailable — no-op */ });
}
