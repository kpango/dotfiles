/**
 * Deterministic ("canonical") JSON serialization shared across the Pi extensions.
 *
 * A single implementation so idempotency-key hashing (session-journal) and stable
 * value comparison (skill-state concurrent-merge conflict detection) agree on one
 * canonical form. Keys are sorted at all depths; recursion depth is bounded and
 * ancestor-only cycle detection keeps DAG-shaped (shared but non-circular) inputs
 * serializing identically to structurally-equal distinct objects.
 */

/** Depth cap: a deeply-nested (non-cyclic) value cannot overflow the stack. The
 * sentinel is deterministic, so two equal inputs still serialize equal; only
 * pathological inputs nested beyond the cap are truncated. */
export const MAX_CANONICALIZE_DEPTH = 256;

/**
 * Recursively canonicalize any JavaScript value into a deterministic JSON string.
 * Keys in objects are sorted alphabetically at all nesting depths. Circular
 * references are safely replaced with `"[Circular]"`; depth beyond the cap with
 * `"[MaxDepth]"`.
 */
export function canonicalizeJson(obj: unknown, seen = new WeakSet(), depth = 0): string {
  if (obj === null || obj === undefined) {
    return JSON.stringify(null);
  }

  const type = typeof obj;
  if (type === "number" || type === "boolean" || type === "string") {
    return JSON.stringify(obj);
  }

  if (type !== "object") {
    return JSON.stringify(String(obj));
  }

  if (depth >= MAX_CANONICALIZE_DEPTH) {
    return '"[MaxDepth]"';
  }

  if (seen.has(obj as object)) {
    return '"[Circular]"';
  }
  // Path-based (ancestor-only) cycle detection: mark on descent, unmark on
  // ascent. A shared but NON-circular reference (a DAG-shaped input, e.g. a
  // reused options array) must serialize identically to a structurally-equal
  // distinct object, otherwise two semantically-identical inputs would serialize
  // differently. Keeping the node in `seen` after its subtree is done would
  // falsely flag such sibling shares as "[Circular]".
  seen.add(obj as object);

  if (Array.isArray(obj)) {
    const items = obj.map((item) => canonicalizeJson(item, seen, depth + 1));
    seen.delete(obj as object);
    return `[${items.join(",")}]`;
  }

  const keys = Object.keys(obj as Record<string, unknown>).sort();
  const pairs = keys.map((key) => {
    const val = (obj as Record<string, unknown>)[key];
    return `${JSON.stringify(key)}:${canonicalizeJson(val, seen, depth + 1)}`;
  });

  seen.delete(obj as object);
  return `{${pairs.join(",")}}`;
}
