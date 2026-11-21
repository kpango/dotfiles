# Harness² tree validation and Compose ported into harness2-offline.py

## Decided
- The upstream `harness2/core/tree.py` surface is now a first-class stage of the offline pipeline:
  `SurfaceSpec` (flat surface, no caps), `read_tree`, `validate_tree`, `tree_diversity` (a reduced
  `diversity`) and `census`, exposed as `tree` in the JSON report. Upstream's `diff_summary` is NOT ported
  (`kept_base` has no local equivalent). Only errors a candidate *introduces* (compared to a baseline
  validation) become `tree_invalid`, and Compose subtracts the same baseline errors, so a pre-existing
  defect cannot block an edit or fall back every batch.
- Compose is a real stage: accepted candidates are applied to the base tree, the merged tree is validated
  as a whole, and one `composed.diff` is written (`--compose-out`, never `--dry-run`). Same-path
  candidates fall back (current harness kept), mirroring upstream's invalid→inherit.
- The tree check runs *after* the stage-3 policy checks, so a C6 target keeps reporting
  `skill_lines` / `skill_frontmatter` / `skill_description` instead of a redundant `tree_invalid`.
- `--check-tree` is the tree-only mode: rc 0 valid, rc 1 invalid, rc 2 input error. `--traces` became
  optional only in that mode.

## Tried and ruled out
- Charging C6 on the advertised (name + description) projection: upstream hard-caps the always-on text
  and never charges a skill body, while the repo's Net Token Budget law is encoded by 15 existing tests as
  the local, stricter policy
  (whole-file delta). The advertised delta is reported as `advertised_delta_tokens` only; the docstring and
  `agent/skills/swarm-evolve/SKILL.md` state the divergence instead of pretending parity.
- Making `tree_ctx` a required `evaluate()` parameter: the canonical test calls `evaluate()` directly and
  died with a `TypeError` (empty output, silently read as a failed check). Default `None` skips tree
  validation for programmatic callers.
- A recursive `agent/scripts` scan: the surface stays flat (`agent/scripts/*.sh|*.py`, plus skill and
  subagent dirs), matching the upstream flat tree; `agent/scripts/hooks/*.py` are covered by the harness
  gates instead.

## Watch out
- `@dataclass(frozen=True)` breaks when the module is loaded through `importlib.util.module_from_spec`
  without registering it in `sys.modules` (`AttributeError: 'NoneType' object has no attribute '__dict__'`,
  read by the test as "empty output"). `typing.NamedTuple` has no such import-time assumption; keep it.
- Any new `evaluate()` reason must respect the documented order
  (`net_token_budget` → `skill_lines` → `skill_frontmatter` → `skill_description` → `tree_invalid` → probes →
  `security_gate*`); the tests assert single-reason strings such as `skill_description`.
- A test fixture that redirects one `cand()` object into a `.json` file fails with
  `must be a JSON array` — always pipe through `jq -s .`.
- `write_atomic` takes a `label`; the proposal path's message (`cannot write proposal <dest>`) is asserted
  verbatim by the suite.

## Follow-up: fail-closed gaps found by two adversarial reviews
- `--compose-out` now goes through the same repo-containment guard as `--out-dir` (it could overwrite a
  harness file inside the repo); Compose subtracts `base_errors` like stage 3.5 does, so a pre-existing
  defect cannot fall back every batch; a fallback reports `applied: []` (nothing was applied).
- The surface walk is recursive (`agent/scripts/**`, `extensions/**`) because `on_surface()` is
  prefix-based: a flat walk left 9 nested scripts and 66 nested `.ts` files validated only when a
  candidate happened to touch them. `census` counts by prefix too.
- The shared sources (`agent/AGENTS.md`, `agent/SYSTEM.md` and their omp supplements) are on the surface
  as `source_files`: they are not injected, so they are not in `always_on` (no budget), but a candidate
  on them must be validated inside the tree. `on_surface` alone used to reject `agent/AGENTS.md`.
- A target outside the surface is rejected as `off_surface_target` (classify() only looks at the file
  name, so `docs/agents/x.md` used to be accepted untested), and `--check-tree` fails closed: a
  non-directory `--repo-root` is rc 2, a tree without any always-on file is rc 1 (upstream `is_tree`).
- `always_on_text` joins with `"\n\n"` (upstream parity; the old `"\n"` made `always_on_chars` one char
  short) and `diversity` ignores blank lines, counts distinct trees and rounds to 4 digits (upstream).
