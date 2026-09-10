/**
 * Bun test preload — virtual-module resolver for pi runtime-only packages.
 *
 * Several extension entrypoints (`../<name>.ts`) import `typebox` and
 * `@earendil-works/pi-tui` purely to register the pi tool schema / TUI widgets
 * at the `export default function (pi)` site. These packages are supplied by the
 * pi runtime at execution time (global node_modules), but are NOT resolvable
 * under a bare `bun test` invocation from the dotfiles tree, which caused ~12
 * `lib/*.test.ts` files to error at module-load and silently never run their
 * assertions (a silent test-coverage hole).
 *
 * The tests only exercise the *pure* functions exported from those entrypoints;
 * they never touch the schema/TUI objects. This preload registers lightweight
 * virtual modules so the imports resolve during `bun test` only. Production is
 * unaffected: `pi` loads extensions with its own resolver and never reads
 * `bunfig.toml`, so this shim is inert outside the test runner.
 *
 * Wired via `extensions/bunfig.toml` `[test].preload`.
 */

import { plugin } from "bun";

// A recursive callable proxy: any property access returns another proxy, and
// any invocation returns a proxy. This satisfies `Type.Object({...})`,
// `Type.String()`, `Type.Optional(Type.Array(...))`, TUI widget constructors,
// enum-like value access (`Key.Enter`), etc. — none of which are asserted on.
function makeDeepProxy(): any {
  const target: any = function () {
    return makeDeepProxy();
  };
  return new Proxy(target, {
    get(_t, prop) {
      if (prop === Symbol.toPrimitive) return () => "";
      if (prop === "then") return undefined; // not a thenable (avoid await traps)
      return makeDeepProxy();
    },
    apply() {
      return makeDeepProxy();
    },
    construct() {
      return makeDeepProxy();
    },
  });
}

plugin({
  name: "pi-runtime-stub-resolver",
  setup(build) {
    // typebox: `import { Type } from "typebox"`
    build.module("typebox", () => ({
      exports: { Type: makeDeepProxy() },
      loader: "object",
    }));

    // @earendil-works/pi-tui: named imports (`{ Container, Markdown, Text, Key }`)
    // require the exported names to exist statically on the exports object; an
    // opaque Proxy is insufficient for ESM named-import binding. Enumerate the
    // widgets/values imported at module-load across the extensions.
    build.module("@earendil-works/pi-tui", () => ({
      exports: {
        Container: makeDeepProxy(),
        Text: makeDeepProxy(),
        Markdown: makeDeepProxy(),
        Key: makeDeepProxy(),
        Box: makeDeepProxy(),
        Spacer: makeDeepProxy(),
      },
      loader: "object",
    }));

    // @earendil-works/pi-coding-agent is imported type-only (`import type`),
    // which bun erases; no runtime stub needed. Provide one defensively in case
    // a value import is ever added.
    build.module("@earendil-works/pi-coding-agent", () => ({
      exports: new Proxy(
        {},
        {
          get(_t, _prop) {
            return makeDeepProxy();
          },
        }
      ),
      loader: "object",
    }));
  },
});
