#!/usr/bin/env node
const { pathToFileURL } = require('url');
const { entry } = require('./graft-resolve.cjs');

const target = entry('hooks.js');
if (target) {
  import(pathToFileURL(target).href).then((m) => m.main(process.argv[2])).catch(() => { /* graft unavailable — no-op */ });
}
