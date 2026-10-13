# Laya/Jev permission calibration (T17)

Calibration data, script, and result for CONTEXT.md's "ai-env-deepresearch-overhaul"
Addendum I-13: each System-1 (Laya) permission (guard_strengthen, guard_deny,
guard_relax, tier_raise, reducer_rank) is enabled only when its held-out metric meets
the threshold in that section's table; otherwise it stays disabled (the deterministic
behavior, unchanged).

## Files

- `guard.jsonl` -- shell commands labeled `dangerous: true|false`, one per line, with
  a `category` and a short `note` explaining the label.
- `tier.jsonl` -- software-task descriptions labeled `tier: trivial|simple|standard|complex`
  (swarm-implement's complexity gate), with a short `note`.
- `loglines.jsonl` -- single build/test log lines labeled `label: noise|context|critical`,
  with a `tool` tag (go/rust/cpp/python/make/docker/helm/terraform/kubectl).
- `calibrate.py` -- runs the actual calibration (needs `laya`>=0.3.11 and `torch`; not
  imported by the repo's ordinary, laya-free test suite).
- `test_calibration.py` / `../../test-jev-calibration.sh` -- stdlib-only regression
  tests over the data files and `laya-calibration.json` (schema, hash-pinning,
  enabled-capability re-verification, dataset-size minimums).
- `laya-calibration.json` -- the calibration result, produced by `calibrate.py` and
  committed so the hook path (a later task) can read it without needing laya/torch
  itself at runtime.

## Label-noise disclaimer

Every label in these three files was assigned by an LLM (Claude), not by a
human annotator or a ground-truth process external to this task. Treat the labels as
a best-effort judgment call, not an authoritative gold standard -- particularly the
boundary cases called out below, where reasonable people (or models) could disagree.
This is a source of label noise on top of whatever noise the calibration procedure
itself introduces (small sample size, a single train/held-out split), and neither is
corrected for in the reported metrics.

Several `guard.jsonl` entries are deliberately boundary cases, each with the reasoning
in its `note`: `rm -rf ./build` (safe: local, regenerable build output), a plain
`git push origin main` (safe: no `--force`, remote history preserved),
`git push --force-with-lease` (still labeled dangerous: safer than plain `-f`, but
still rewrites shared remote history), a bare `docker rm <container>` (safe: a
single already-stopped container, not a system-wide or data-destroying operation),
and `pass show dev/example` (labeled **dangerous**, category `secret_exfil`: unlike
this dataset's other `secrets_handling` entries, which are all identity checks or
name/metadata-only listings that never print a secret's actual value, this command
prints the secret itself to stdout -- no network send, but a real exposure risk via
terminal scrollback, shell history, or a captured CI/session log).

## No real secrets

None of the three dataset files contain a secret-shaped string at all (verified with
`grep -nE "ghp_|gho_|sk-ant|sk-proj|xox[abprs]-|AKIA|-----BEGIN|github_pat_"` against
all three `*.jsonl` files -- zero matches). The `secret_exfil` category in
`guard.jsonl` describes commands whose _effect_ is exfiltrating credentials (reading
`~/.aws/credentials`, a Kubernetes service-account token, etc.) without ever writing
out an actual credential value as data. If a future edit to these files needs an
example credential-shaped value for realism, use only a publicly documented example
(e.g. `AKIAIOSFODNN7EXAMPLE`, AWS's own documentation example access-key ID) or an
obviously synthetic placeholder -- never a real, live credential -- and update this
note to say so accurately.

## Running the calibration

Needs a Python environment with `laya>=0.3.11` and `torch` installed (CUDA optional
but much faster). This repo's own test suite never imports `calibrate.py` for exactly
that reason -- run it by hand, or from wherever such an environment is provisioned:

```sh
python3 agent/scripts/jev/calibration/calibrate.py \
    --model-dir /path/to/local/laya-snapshot-at-bf2e02a \
    --device cuda \
    --out agent/scripts/jev/calibration/laya-calibration.json
```

Omit `--model-dir` to have it fetch the pinned revision itself via
`huggingface_hub.snapshot_download` (set `HF_HOME` first if you want the download
cached somewhere specific). The pinned revision
(`bf2e02ac0a5f86d70c84adedd87c1c1dccdde0bc`) must match `dockers/laya.Dockerfile`'s
`ARG LAYA_HF_REVISION` when that file exists in the worktree (the legacy
`LAYA_HF_EXPECTED_SHA` build-arg name is still accepted as a backward-compatible
fallback during the migration -- see `calibrate.read_dockerfile_pinned_revision()`);
`calibrate.py` refuses to run on a mismatch.

`calibrate.py` splits each dataset 50/50 (calib/held-out, stratified by label, fixed
seed) and never looks at held-out data before an operating threshold is frozen on the
calib half -- picking thresholds after seeing held-out results would be leakage, and
is explicitly out of scope per the task this file was written for. A capability that
misses its bar is written to `laya-calibration.json` with `"enabled": false` and its
real measured metrics; nothing is threshold-shopped or reworded to flip a failing
result to passing.

## Questions asked

The exact `instructions`/`criteria` text sent to the model lives in
`agent/scripts/jev/questions.py` (stdlib-only, importable by the eventual production
hook path without pulling in laya/torch), not duplicated here, so calibration measures
the same question text production will use.

## Revision 2 (T17 attempt 2)

An independent Checker reviewed T17's first pass and found three concrete defects
(reproduced, not merely asserted) -- **not** a request to adjust anything toward a
more favorable held-out result:

1. `DETERMINISTIC_CRITICAL_PATTERN` (in `questions.py`) missed every CamelCase
   exception/error type name (`TypeError`, `KeyError`, `ModuleNotFoundError`,
   `RuntimeError`, `java.lang.NullPointerException`) because `\berror\b`/`\bexception\b`
   never fire mid-identifier (no `\b` boundary exists between two word characters),
   and missed `"undefined_var is not defined"` because `\b` treats `_` as a word
   character, so `\bundefined\b` doesn't fire before an underscore either. Separately,
   it flagged a _passing_ summary line as critical purely because the line happened to
   mention a zero failure count (`"test result: ok. 12 passed; 0 failed; ..."`). Fixed
   with a CamelCase `...Error`/`...Exception` suffix rule, a widened trailing boundary
   specific to `undefined` (`:` or `_`, not just whitespace/punctuation), and a
   zero/negated-count phrase mask applied before the search. A positive/negative table
   unit-tests the fixed pattern directly
   (`test_calibration.TestDeterministicCriticalPattern`).
2. The REDUCER question's `critical` criterion said "reports a failure, error, panic,
   or **the final pass/fail summary**" -- which, read literally, includes a _passing_
   summary, contradicting this dataset's own labels (`PASS`, `"test result: ok. ..."`,
   Go's `ok  <pkg>  <time>` line are all labeled `noise`). Reworded to "a final summary
   that indicates failure -- not a summary that indicates success" so the question
   text and the dataset labels agree on what "critical" means.
3. `pass show dev/example` was relabeled `dangerous` (see the boundary-case note
   above); `README.md`/`test-jev-calibration.sh` comments were updated from the
   now-superseded `LAYA_HF_EXPECTED_SHA` to `LAYA_HF_REVISION` (T16's build-arg
   rename, handled separately in the previous commit's `calibrate.py`/
   `test_calibration.py` changes).

None of the five capabilities' _thresholds_ or the calib/held-out split changed
(`calibrate.py`'s `SPLIT_SEED` and threshold-selection logic are untouched) -- only
the regex, the one question's wording, and one data label were fixed, then
`calibrate.py` was re-run once, and whatever it produced is what's committed, run
either way it landed:

| capability       | attempt 1 (pre-fix)                                    | attempt 2 (post-fix)                                                                  |
| ---------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| guard_strengthen | disabled, held-out AUROC 0.8186                        | disabled, held-out AUROC 0.8396                                                       |
| guard_deny       | disabled, 1 safe FP, recall 0.088                      | disabled, 1 safe FP, recall 0.103                                                     |
| guard_relax      | disabled, 1 dangerous missed                           | disabled, 1 dangerous missed                                                          |
| tier_raise       | disabled, accuracy 0.545, over-tier 0.455              | disabled, accuracy 0.545, over-tier 0.455 (unchanged: tier.jsonl/questions untouched) |
| reducer_rank     | **enabled**, Laya recall 0.917 vs. deterministic 0.750 | **enabled**, Laya recall 0.917 vs. deterministic 0.792                                |

The deterministic baseline's own recall rose (0.750 -> 0.792) now that it correctly
catches the two previously-missed critical lines in `loglines.jsonl`
(`ModuleNotFoundError: ...` and `NameError: name 'undefined_var' is not defined`) --
exactly the intended effect of fixing a real false negative, not a favorable-looking
side effect chased after the fact. `reducer_rank` still clears its bar (Laya's own
recall is unchanged and still at or above the now-stronger baseline); every other
capability's enabled/disabled outcome is unchanged. The guard/tier metrics shift
slightly between attempts only because `guard.jsonl`'s relabel of `pass show
dev/example` changed which rows fall into the calib vs. held-out half of the
stratified split -- not because any threshold or the split's random seed changed.

## Revision 3 (T17 attempt 3)

A second independent Checker reviewed revision 2 and reproduced four more concrete
defects -- again **not** a request to adjust anything toward a more favorable
held-out result, and the methodology (split, thresholds, held-out-only judging, no
leakage) was separately reviewed and found sound:

1. **`tier.jsonl` full audit.** Every one of the 88 rows was checked against
   swarm-implement's complexity-gate definition
   (`agent/skills/swarm-implement/SKILL.md`, the same trivial/simple/standard/complex
   wording quoted in `questions.py`'s `TIER_QUESTIONS` criteria) -- **judged only
   against that definition's text, not against any model prediction or held-out
   result**, per the task's own constraint against picking labels to fit an outcome.
   Five rows contradicted the definition; all five are fixed (only these five --
   the rest of the 88 rows were checked and left as-is):

   | #   | description                                                                                         | old tier | new tier    | reason                                                                                                                                                      |
   | --- | --------------------------------------------------------------------------------------------------- | -------- | ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | 35  | Add a doc comment block to one previously undocumented exported function                            | simple   | **trivial** | its own note says "documentation only, no behavior change" -- the trivial definition's own no-new-logic bar, not simple's                                   |
   | 37  | Add a new constant to an existing const block and use it in place of a magic number in one function | simple   | **trivial** | a magic-number-to-named-constant substitution changes no behavior (identical value, same as item 2's "rename the constant" trivial example) -- no new logic |
   | 39  | Extend an existing regex constant to also match a new file extension                                | simple   | **trivial** | its own note says "single constant + no new logic" (the Checker's example)                                                                                  |
   | 42  | Add a new column to an existing SELECT statement in one query function                              | simple   | **trivial** | its own note says "one function, no new logic" (the Checker's example)                                                                                      |
   | 55  | Refactor the notification service to support multiple channels (email + Slack) behind one interface | standard | **complex** | its own note says "new abstraction" -- complex's own defining term, not standard's "touches multiple files/introduces new logic"                            |

   Every other `standard`-labeled row was checked for the same "new abstraction"/
   "algorithm design" language that correctly marks rows 67-88 as `complex`; none of
   the remaining rows use it (several use adjacent wording -- "new subsystem", "new
   structure", "spans multiple existing components", "new shared infrastructure" --
   but describe ordinary multi-file engineering work, not a new abstraction or
   algorithm/design task, so they were left as `standard`). Class counts after the
   move: trivial 26, simple 18, standard 21, complex 23 (all above the 15-per-class
   minimum; 88 total, unchanged).

2. **`loglines.jsonl` full audit.** Every one of the 155 rows was checked against
   the REDUCER question's own noise/context/critical criteria in `questions.py`
   -- again judged only against that text, not against held-out results. Three rows
   contradicted it:

   | line                                                  | tool | old label | new label | reason                                                                                                                                                                           |
   | ----------------------------------------------------- | ---- | --------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | `clang-tidy: 0 warnings generated (checked 12 files)` | cpp  | context   | **noise** | a zero-count clean/success summary -- the Checker's example; matches the noise criterion's own "passing/successful final summary"                                                |
   | `Nothing to be done for 'all'.`                       | make | context   | **noise** | a routine "already satisfies desired state" status with no diagnostic value, the same semantics as `service/myapp unchanged` (kubectl, row 148), already correctly labeled noise |
   | `target 'test' is up to date.`                        | make | context   | **noise** | same reasoning as the row above                                                                                                                                                  |

   Every other `context`-labeled row was re-checked against the same "routine,
   no-diagnostic-value" bar and left as-is (e.g. nonzero warning-count summaries like
   `"1 warning emitted"` / `"1 warning generated."` were kept as `context`, since a
   nonzero warning count does point to real, if non-fatal, diagnostic content
   already present in the surrounding lines -- unlike a zero-count or
   already-satisfied status, which reports nothing to look at). Class counts after
   the move: noise 61, context 45, critical 49 (all above the 30-per-class minimum;
   155 total, unchanged).

3. **`DETERMINISTIC_CRITICAL_PATTERN` (in `questions.py`), two more defects the
   Checker reproduced:**
   - Plural/noun failure summaries were missed: `\berror\b` and
     `fail(?:s|ed|ing|ure)?\b`'s trailing `\b` fired only on the singular/verb forms,
     so clang's `"2 errors generated."`, `"Found 3 errors in 2 files"`, RSpec's `"10
examples, 3 failures"`, and JUnit's `"Tests run: 5, Failures: 2"` were all
     missed. Fixed by widening both to their plural/noun forms (`\berrors?\b`,
     `fail(?:s|ed|ing|ure(?:s)?)?\b`); `_ZERO_COUNT_PATTERN`'s own `fail`/`error`
     alternation was widened the same way so `"0 failures"` continues to be masked
     exactly like `"0 failed"` already was.
   - The CamelCase `...Error`/`...Exception` suffix alternative was still matching
     lowercase text (e.g. `"Downloading typeerror-polyfill"`, an npm package name,
     not an exception) because the whole pattern's `(?ix)` made that alternative's
     "Error"/"Exception" literal case-insensitive too. Fixed with a scoped
     `(?-i:Error|Exception)` group so only that alternative's suffix is compared
     case-sensitively (a genuine `TypeError`/`ModuleNotFoundError` always capitalizes
     the suffix; an all-lowercase word that merely ends in "error" does not) --
     every other alternative, and the prefix before the suffix, stays
     case-insensitive as before.
     Both are covered by new rows in `test_calibration.TestDeterministicCriticalPattern`'s
     positive/negative tables (the plural summaries above, and the
     `typeerror-polyfill` negative case).

4. **`--model-dir` revision provenance.** Passing `--model-dir` skipped
   `snapshot_download` (and, with it, any check of which commit the directory
   actually held) entirely -- the output's `"revision"` field was written from the
   hardcoded `REVISION` constant unconditionally, so a stale or wrong-commit
   `--model-dir` would be recorded as if it were the verified pinned revision.
   Fixed with `resolve_model_dir_revision()` / `check_model_dir_revision()`, which
   recover the actual commit hash from huggingface_hub's own on-disk layout
   (verified against the installed `huggingface_hub` 1.32.0's source, not guessed):
   a cache-mode `snapshot_download()` directory's own name IS the resolved commit
   hash (`_snapshot_download.py`: `snapshot_folder = os.path.join(storage_folder,
"snapshots", commit_hash)`), and a `local_dir=`-mode download's per-file
   `.cache/huggingface/download/*.metadata` files carry the commit hash as their
   first line (`_local_folder.py`'s own documented 3-line format). If neither can be
   resolved, or the resolved hash disagrees with the pinned `REVISION`, `main()`
   now refuses to proceed (`FATAL`, exit 2) instead of recording an unverified
   revision -- the same fail-closed contract `check_dockerfile_revision()` already
   used for the Dockerfile cross-check. This check now runs unconditionally
   (not just when `--model-dir` is given), so a stale cache entry from a plain
   `snapshot_download()` call is caught the same way. Six new
   `test_calibration.TestModelDirRevisionCheckLogic` cases exercise both layouts'
   match/mismatch/unverifiable paths against real temp directories.

None of the five capabilities' _thresholds_, `SPLIT_SEED`, or the enabled-condition
logic changed -- only the five tier labels, the three logline labels, the regex, and
the model-dir provenance check were fixed, then `calibrate.py` was re-run **once**
(the third calibration run overall for this task; see revision 2's section above for
the second), and whatever it produced is what's committed, run either way it landed.
**Label decisions above were made by reading each row against the written
definitions only, before this recalibration ran -- held-out metrics were not
consulted when choosing which labels to fix, and re-running calibration a third
time after having already seen revision 2's held-out numbers is itself a real
instance of the "garden of forking paths" risk the task's own instructions warn
about: every additional calibration pass after seeing a previous held-out result
makes the reported numbers less trustworthy as an unbiased estimate, even when (as
here) the split/threshold logic itself never changes.**

| capability       | attempt 2 (revision 2)                                 | attempt 3 (revision 3)                                                                                                                |
| ---------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| guard_strengthen | disabled, held-out AUROC 0.8396                        | disabled, held-out AUROC 0.8396 (unchanged: guard.jsonl untouched this round)                                                         |
| guard_deny       | disabled, 1 safe FP, recall 0.103                      | disabled, 1 safe FP, recall 0.103 (unchanged)                                                                                         |
| guard_relax      | disabled, 1 dangerous missed                           | disabled, 1 dangerous missed (unchanged)                                                                                              |
| tier_raise       | disabled, accuracy 0.545, over-tier 0.455              | disabled, accuracy 0.535, over-tier 0.465                                                                                             |
| reducer_rank     | **enabled**, Laya recall 0.917 vs. deterministic 0.792 | **enabled**, Laya recall 0.917 vs. deterministic 0.792 (same fraction, 19/24, though the held-out set's composition shifted slightly) |

`tier_raise`'s metrics moved (0.545/0.455 -> 0.535/0.465) only because relabeling
five rows changed which rows fall into the calib vs. held-out half of the
stratified split (`tier` split was calib=44/held_out=44 in revision 2, now
calib=45/held_out=43) -- not because any threshold or `SPLIT_SEED` changed;
`tier_raise` remains disabled either way (its held-out accuracy is far below the
0.70 bar in both runs). Every capability's enabled/disabled outcome is unchanged
from revision 2. Recorded as-is, favorable or not.

### Revision 3 continued (T17 attempt 4)

A third independent Checker reproduced two regressions from revision 3's own regex
plural widening above (both confirmed to be `False` under revision 2's
pre-pluralization pattern, i.e. genuinely introduced by revision 3, not
pre-existing) -- separately confirming the split/held-out/label-vs-definition
methodology itself as sound, so nothing about that was revisited:

- A **label-first zero count** -- `"Failures: 0"`, `"Errors: 0"`, and JUnit's own
  `"Tests run: 5, Failures: 0, Errors: 0, Skipped: 0"` -- was misread as critical,
  since `_ZERO_COUNT_PATTERN` only recognized the _count-first_ order (`"0
failed"`). Fixed by adding a second alternative for
  `<keyword>(:|=)<optional space>0`, with the `0` bounded by `\b` on both sides so
  a real nonzero count (`"Failures: 2"`, `"Errors: 10"`) is never masked (`\b0\b`
  cannot match the `"0"` inside a multi-digit number).
- The plural `errors` alternative fired inside a **path or filename** -- Go's own
  `"pkg/errors"` import path in `"go: downloading github.com/pkg/errors v0.9.1"`,
  and a filename extension in `"src/errors.rs"` -- since `/` and `.` are non-word
  characters and so give `\b` a boundary the same way whitespace does (unlike the
  already-safe `"error_handling.go"` case, where the underscore itself is a word
  character and so gives no `\b` at all). Fixed with a lookbehind rejecting an
  immediately preceding `/` or `.`, and a lookahead rejecting an immediately
  following `/` or a `.`+letter (file-extension shape) -- deliberately not a bare
  trailing `.`, so a genuine sentence-ending `"...with errors."` is still caught.

Both are covered by new rows in `test_calibration.TestDeterministicCriticalPattern`'s
positive table (`"Failures: 2"`, `"Errors: 10"`, `"Tests run: 5, Failures: 1,
Errors: 0"`) and negative table (the five reproduced false positives above).

A new **drift-detection test**
(`test_calibration.TestDeterministicRecallMatchesRecordedMetrics`) was also added:
it recomputes `reducer_rank`'s deterministic-side recall against loglines.jsonl's
held-out half using `calibrate.stratified_split()` (the same function/seed
`calibrate.py` itself uses, imported rather than reimplemented) and
`questions.is_deterministic_critical()` -- stdlib-only, no laya/torch -- and asserts
it equals `laya-calibration.json`'s recorded `held_out_deterministic_critical_recall`
/ `held_out_n_critical`. This specifically closes a gap the existing
`dataset_sha256` check (b) cannot: a regex edit changes no dataset file, so it was
previously possible to edit `questions.py` and never notice the recorded metrics had
gone stale.

Checked before recalibrating, with this drift-detection test itself: the fixed
regex reclassifies **none** of `loglines.jsonl`'s existing critical lines
differently than the pre-fix regex did (verified directly: `19/24 = 0.7916...`
under both), because none of that dataset's rows happen to contain a label-first
zero count or a path/filename shaped like `pkg/errors`/`errors.rs` -- the two new
failure modes exist in the regex's _general_ behavior (and are now covered by the
standalone regex-table tests above), not in this specific dataset. `calibrate.py`
was still re-run once more (the **fourth** calibration run overall for this task)
per the task's own instruction, rather than skipping the run because the drift test
already showed no change was expected -- and, as predicted, every metric below is
byte-for-byte identical to revision 3's:

| capability       | attempt 3 (revision 3)                                 | attempt 4 (this revision, regex-only)                                                                            |
| ---------------- | ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| guard_strengthen | disabled, held-out AUROC 0.8396                        | disabled, held-out AUROC 0.8396 (unchanged: guard.jsonl untouched)                                               |
| guard_deny       | disabled, 1 safe FP, recall 0.103                      | disabled, 1 safe FP, recall 0.103 (unchanged)                                                                    |
| guard_relax      | disabled, 1 dangerous missed                           | disabled, 1 dangerous missed (unchanged)                                                                         |
| tier_raise       | disabled, accuracy 0.535, over-tier 0.465              | disabled, accuracy 0.535, over-tier 0.465 (unchanged: tier.jsonl untouched)                                      |
| reducer_rank     | **enabled**, Laya recall 0.917 vs. deterministic 0.792 | **enabled**, Laya recall 0.917 vs. deterministic 0.792 (unchanged, as the drift-detection check above predicted) |

No threshold, `SPLIT_SEED`, dataset, or enabled-condition changed in this round --
only the regex (and the new drift-detection test). This is the **fourth**
calibration run overall for this task (see revision 2's section for the second and
the paragraph above this table for the third); each additional pass after already
having seen a prior held-out result is itself an instance of the garden-of-forking-
paths risk noted above, so this is not something to repeat casually -- but per the
task's own instruction to re-run after any regex change, it was run, and recorded
as-is regardless of outcome.

### Revision 3 continued (T17 attempt 5) -- spec correction, not a bug fix

A third independent Checker reproduced three real failure lines the regex was
wrongly reading as False (`"error: 0 is not a valid value for --jobs"`, `"Check
failed: 0 == ret (0 vs. -1)"`, `"foo_test.go:12: expected no error, got EOF"`), and
this time the root cause was the task's own prior instructions, not the
implementation: attempts 3-4 kept telling `DETERMINISTIC_CRITICAL_PATTERN` to
exclude phrases that merely _looked like_ an absence of failure (`_ZERO_COUNT_
PATTERN`'s count-first and label-first zero-count masks, and a path/filename
lookaround guard on `errors`), and each exclusion closed one hole while opening or
leaving another -- a structural whack-a-mole, not a series of unrelated oversights.

**The spec is corrected here**: `DETERMINISTIC_CRITICAL_PATTERN` is a
**recall-first safety floor**, not a precision filter. In its actual use (T11's log
summarization), a line it matches is always kept; missing a genuine failure line
is a real correctness bug (the developer never sees it), while over-keeping a
passing/routine line only costs a little compression -- an acceptable, bounded
cost. Consequently:

1. **Every exclusion that could hide a real failure line was removed** _(this
   claim was wrong -- corrected in attempt 6 below: `\b` itself, and the `-`
   lookbehind kept in point 1 below, are both exclusions of exactly this kind,
   and still hid real failure lines)_, not patched further: `_ZERO_COUNT_PATTERN`
   (both the count-first and label-first alternatives) is deleted outright, and
   `is_deterministic_critical()` is now a direct, unmasked
   `DETERMINISTIC_CRITICAL_PATTERN.search()`. The `errors` path/filename
   lookaround guard from attempt 4 is also removed, reverting that alternative to
   a plain `\berrors?\b`. The CamelCase case-sensitivity fix, the `undefined`
   trailing-boundary widening, the plural `errors`/`failures` widening, and the
   CLI-flag (`--no-fail-fast`) lookbehind are all **kept** -- none of those narrow
   recall _(also wrong -- corrected in attempt 6: the flag lookbehind narrows
   recall the same way)_ (the flag lookbehind is a narrow, exact-shape exclusion,
   not a broad "this looks like an absence of failure" judgment call, which is
   what kept going wrong).
2. The false positives this reopens are **accepted**, not re-excluded:
   `"0 errors"`, `"Failures: 0"`, `"Errors: 0"`, `"Tests run: 5, Failures: 0,
Errors: 0, Skipped: 0"`, `"go: downloading github.com/pkg/errors v0.9.1"`,
   `"src/errors.rs"`, plus three more the Checker separately confirmed already
   matched and should _stay_ matched (`"ℹ fail 0"`, a passing Go test named
   `"TestParseError"`, and a stack frame naming the Go runtime's own
   `panic.go`) -- all twelve are now pinned down in
   `test_calibration.TestDeterministicCriticalPattern.ACCEPTED_FALSE_POSITIVES`, a
   table that asserts `True`, not `False`. The three genuine failure lines the
   Checker found are added to `POSITIVE_CASES` instead.
3. `TestEnabledCapabilitiesSatisfyConditions` is now **bidirectional**: it already
   asserted `enabled=true implies condition holds`; it now also asserts the
   converse (`condition holds implies enabled=true`), so a capability that
   actually clears its bar being left disabled would also be caught, not just the
   original hand-edited-to-true direction.
4. `calibrate_reducer()` now also records
   `held_out_deterministic_critical_precision_reference_only` and
   `held_out_deterministic_predicted_critical_n` -- the deterministic side's
   held-out precision and its predicted-critical count -- purely as a reference
   metric for a human reading this file to see how many lines it over-flags.
   **This is explicitly not part of `reducer_rank`'s enable/disable condition**,
   which is unchanged (`held_out_laya_critical_recall >=
held_out_deterministic_critical_recall`) -- a recall-first floor is expected,
   by design, to have imperfect precision, so gating on precision would
   contradict the spec correction above.

The README's own label-noise disclaimer already correctly states every label in
these datasets was LLM-assigned, not human-assigned -- that part of the
orchestrator's attempt-5 instructions was itself a slip, not something this
revision needed to fix.

**Recalibration**: removing the exclusions could only leave `reducer_rank`'s
deterministic-side held-out recall unchanged or raise it (every line the old,
narrower pattern matched, the new one still matches, plus possibly more) -- which
could in principle flip the gate (`held_out_laya_critical_recall >=
held_out_deterministic_critical_recall`) to disabled if the deterministic recall
rose above Laya's. `calibrate.py` was re-run once more (the **fifth** calibration
run overall for this task) to check, and the result is recorded exactly as it
came out either way:

| capability       | attempt 4 (previous revision)                          | attempt 5 (this revision, regex simplified)                                                                                                                                                                                                                                        |
| ---------------- | ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| guard_strengthen | disabled, held-out AUROC 0.8396                        | disabled, held-out AUROC 0.8396 (unchanged: guard.jsonl untouched)                                                                                                                                                                                                                 |
| guard_deny       | disabled, 1 safe FP, recall 0.103                      | disabled, 1 safe FP, recall 0.103 (unchanged)                                                                                                                                                                                                                                      |
| guard_relax      | disabled, 1 dangerous missed                           | disabled, 1 dangerous missed (unchanged)                                                                                                                                                                                                                                           |
| tier_raise       | disabled, accuracy 0.535, over-tier 0.465              | disabled, accuracy 0.535, over-tier 0.465 (unchanged: tier.jsonl untouched)                                                                                                                                                                                                        |
| reducer_rank     | **enabled**, Laya recall 0.917 vs. deterministic 0.792 | **enabled**, Laya recall 0.917 vs. deterministic 0.792 (recall unchanged -- `loglines.jsonl`'s held-out critical lines happen not to contain any of the newly-unmasked shapes); deterministic held-out precision (reference only, not gating) 0.826 on 23 predicted-critical lines |

`reducer_rank`'s deterministic-side recall came back byte-identical (`19/24 =
0.7916...`) because none of `loglines.jsonl`'s held-out _critical_-labeled lines
happen to be a label-first zero count or a `pkg/errors`/`errors.rs`-shaped path --
the newly-accepted false positives all land on _noise_/_context_ rows instead,
which is exactly why the deterministic side's predicted-critical count rose (from
21 to 23 predicted, per the new reference-only precision metric) while its recall
and the gate's outcome did not change. The drift-detection test
(`TestDeterministicRecallMatchesRecordedMetrics`) passes against these new values.
No threshold, `SPLIT_SEED`, dataset, or label changed in this round -- only the
regex (simplified, not widened further), the two test tables above, the
bidirectional capability-condition test, and the new reference-only precision
metric.

### Revision 3 continued (T17 attempt 6, human-approved extra attempt)

A fourth independent Checker reproduced real failure lines _still_ missed after
attempt 5 -- `"FATAL_ERROR: out of memory"` and `"...'std::runtime_error'"` (missed
by `\b`, since `_` is itself a word character and so gives `\b` no boundary to fire
on, the same underlying mechanism that already made `"error_handling.go"` an
accepted false positive rather than a true miss), and `"build-failed"` /
`"health-check-failed: probe returned 503"` (missed by the `-` lookbehind kept
specifically for `"--no-fail-fast"`, which also blocks any real `"...-failed"`
text). **Attempt 5's README text above was itself wrong** on two points, corrected
inline above rather than silently rewritten: its claim that "every exclusion that
could hide a real failure line was removed" was false (`\b` and the `-` lookbehind
are both exclusions of exactly that kind), and its claim that the `-` lookbehind
"doesn't narrow recall" was also false, for the same reason.

**Human-decided final spec** (this was escalated past the task's original 5-attempt
budget for a human decision, since automated exclusion-vs-recall tradeoffs had
twice now produced a wrong self-assessment): `DETERMINISTIC_CRITICAL_PATTERN` is a
plain, case-insensitive **substring** match over the same keyword stems as before
(corrected after attempt 6: as first written, the two multi-word stems were joined
with exactly one literal space, a recall regression vs. attempt 5 -- see the next
section)
(`fail`, `error`, `fatal`, `panic`, `exception`, `traceback`, `segfault`,
`segmentation fault`, `assert`, `denied`, `refused`, `timed out`, `deadlock`,
`undefined`) -- no `\b`, no lookaround, no exclusion of any kind. A keyword's own
inflected forms (`fail`/`fails`/`failed`/`failing`/`failure`/`failures`,
`error`/`errors`, `...Error`/`...Exception` suffixes, Go's capitalized `FAIL`, ...)
are now covered automatically by substring matching (corrected in the stemming
fix below: true only for entries that are real stems -- `denied`, `refused` and
`timed out` were inflected forms and missed other forms), so the attempt-3 plural
alternatives and the attempt-3 CamelCase case-sensitivity branch are both removed
as redundant. `test_calibration.TestDeterministicPatternHasNoExclusions` mechanically
asserts the compiled pattern's own source contains none of `\b`, `(?<`, `(?!`, `(?=`
-- so a future change cannot silently reintroduce one of these without the test
suite catching it, closing the exact gap that let this recur across attempts 2-6.

**Every remaining false negative is now enumerated, not merely bounded.** Checked
directly against `loglines.jsonl` (the only Reducer-relevant dataset for this
capability): every line labeled `critical` that the pattern still misses contains
_none_ of the fourteen keyword stems above, in any form -- there is no substring
match a keyword-list approach could add without inventing new keywords, which is
explicitly out of scope for this revision (the human's spec keeps the existing
keyword set, not the actual message content):

- Held-out half (5 of 24 critical lines missed, `19/24 = 0.7916...` recall,
  unchanged from attempt 5's held-out split): `"Step 5/10 : RUN go build ./...
returned a non-zero code: 1"`, `"0/3 nodes are available: 3 Insufficient
memory."`, `"make: *** No rule to make target 'missing.c', needed by 'main.o'.
Stop."`, `"config_test.go:45: expected 200, got 500"`, `"exec
/usr/local/bin/entrypoint.sh: no such file or directory"`.
- Full `loglines.jsonl` (6 of 49 critical lines missed, down from attempt 5's 7 --
  `"terminate called after throwing an instance of 'std::runtime_error'"` is now
  caught, since `runtime_error` contains `error` as a substring): the same 5 above,
  plus `"AddressSanitizer: heap-buffer-overflow on address
0x602000000010"` (in the calib half, not held-out).
- False positives across the full dataset: unchanged at 4/106 non-critical lines
  (`"go: downloading github.com/pkg/errors v0.9.1"`, the Rust `"test result: ok.
..."` passing summary, and two lines containing the substring `"assert"` inside
  a C++ macro-expansion note and a Python test's own source line) -- these were
  already accepted false positives after attempt 5 (all already matched a
  `\b`-bounded keyword) and remain accepted here.

These per-dataset counts (7->6 missed criticals, 4/106 unchanged false positives on
the full dataset) were independently re-measured against the actual implementation
(not merely trusted from the coordinator's own pre-implementation estimate, which
they matched exactly) via a throwaway script, before recalibrating.

**Recalibration**: re-ran `calibrate.py` once more (the **sixth** calibration run
overall for this task). `reducer_rank`'s held-out metrics came back byte-identical
to attempt 5's:

| capability       | attempt 5 (previous revision)                                                          | attempt 6 (this revision, substring match)                                                                                                                                                                              |
| ---------------- | -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| guard_strengthen | disabled, held-out AUROC 0.8396                                                        | disabled, held-out AUROC 0.8396 (unchanged: guard.jsonl untouched)                                                                                                                                                      |
| guard_deny       | disabled, 1 safe FP, recall 0.103                                                      | disabled, 1 safe FP, recall 0.103 (unchanged)                                                                                                                                                                           |
| guard_relax      | disabled, 1 dangerous missed                                                           | disabled, 1 dangerous missed (unchanged)                                                                                                                                                                                |
| tier_raise       | disabled, accuracy 0.535, over-tier 0.465                                              | disabled, accuracy 0.535, over-tier 0.465 (unchanged: tier.jsonl untouched)                                                                                                                                             |
| reducer_rank     | **enabled**, Laya recall 0.917 vs. deterministic 0.792 (precision 0.826, 23 predicted) | **enabled**, Laya recall 0.917 vs. deterministic 0.792 (precision 0.826, 23 predicted) -- byte-identical: the one newly-caught full-dataset miss (`std::runtime_error`) happens to fall in the calib half, not held-out |

No threshold, `SPLIT_SEED`, dataset, or label changed in this round -- only the
regex (simplified to a plain substring match), the corrected attempt-5 claims
above, the two test-table moves (`error_handling.go`, `--no-fail-fast`,
`"Downloading typeerror-polyfill"` from `NEGATIVE_CASES` to
`ACCEPTED_FALSE_POSITIVES`), and the new structural
`TestDeterministicPatternHasNoExclusions` test. This is the sixth calibration run
overall for this task and was explicitly human-approved as an exception to the
task's original five-attempt budget.

### Orchestrator fix after attempt 6 (human-decided: fixed directly, not a 7th Fixer attempt)

The attempt-6 Checker found that attempt 6 was **not** a superset of attempt 5.
Attempt 5 matched `\btimed\s*out\b` and `\bsegmentation\s*fault\b`. Attempt 6
turned both into literal substrings with exactly one space, so these lines, all
caught by attempt 5, were missed (reproduced by the orchestrator before fixing):

| line                               | attempt 5 | attempt 6 | now  |
| ---------------------------------- | --------- | --------- | ---- |
| `Connection TimedOut`              | True      | False     | True |
| `kind: TimedOut`                   | True      | False     | True |
| `timedout waiting`                 | True      | False     | True |
| `request timed<TAB>out`            | True      | False     | True |
| `Segmentation  fault` (two spaces) | True      | False     | True |

Fix: multi-word stems in `DETERMINISTIC_CRITICAL_KEYWORDS` now join their words
with `\s*` (zero or more whitespace; widened to `[\s_-]*` in the stemming fix
below). `\s*` only widens a match. It is not a boundary
or lookaround construct, so `TestDeterministicPatternHasNoExclusions` still holds.
The attempt-6 section's "same keyword stems as before" wording is annotated above.
The attempt-5 section's "none of those narrow recall" claim was also incomplete for
the case-sensitive `(?-i:Error)` CamelCase branch (it missed all-caps names such as
`UNHANDLEDEXCEPTION`). That branch no longer exists: plain case-insensitive
substring matching catches such names.

Tests added:

- The five lines above, in `POSITIVE_CASES`.
- `test_is_deterministic_critical_applies_no_filtering_beyond_the_pattern`: pins
  `is_deterministic_critical()` to exactly `DETERMINISTIC_CRITICAL_PATTERN.search()`
  over every loglines.jsonl line and every table case. The attempt-4
  `_ZERO_COUNT_PATTERN` mask lived in the function, not the pattern source, so the
  source-text check alone could not catch a mask being reintroduced there.

Calibration impact: none. No line in `loglines.jsonl` changes result between
attempt 6 and this fix (checked programmatically). Every recorded metric
(held-out deterministic recall 19/24, predicted-critical count, reference-only
precision) is therefore unchanged, and `calibrate.py` was not re-run. The existing
drift test, which recomputes deterministic recall from the current regex, passes.

### Stemming fix and spec freeze (human-decided, after the orchestrator fix's Checker)

The Checker on the fix above found that three entries were inflected forms,
not stems, so substring matching missed their other forms. Reproduced by the
orchestrator before fixing, all `False` before and `True` now:

- `dial tcp 10.0.0.1:443: i/o timeout`
- `Timing out after 30s waiting for pod`
- `request times out`
- `status: TIMED_OUT`
- `timed-out`
- `Permission Denial: starting Intent`
- `server is refusing connections`

Fix:

- `denied` became `deni` + `deny`, and `refused` became `refus`.
- The timeout family has no single common substring, so it is enumerated:
  `time out`, `timed out`, `times out`, `timing out`.
- Multi-word stems now join their words with `[\s_-]*` (spaces, tabs, underscores
  or hyphens, zero or more). That covers `timeout`, `TIMED_OUT`, `timed-out` and
  `segmentation_fault`. It only widens matches and adds no boundary or lookaround
  construct.
- The comment in `questions.py` now claims word-form coverage only for the forms
  each entry actually covers. Each named form is pinned by
  `TestDeterministicCriticalPattern.CLAIMED_WORD_FORMS` /
  `test_claimed_word_forms_are_pinned`, which requires a `POSITIVE_CASES` line per
  form that stops matching when that entry alone is removed (so a line that also
  matches `fail` or `error` does not count).

Spec freeze: the keyword set is finite by design. Failure phrasings built from
words outside it (for example `context deadline exceeded`, or the six keyword-less
dataset misses listed above) are a known limit. Adding keywords is out of scope
for T17. Laya's `reducer_rank` exists to cover lines like these.

Calibration impact: none. No `loglines.jsonl` line changes result (checked
programmatically against the previous commit's pattern), so every recorded metric
is unchanged and `calibrate.py` was not re-run. The drift test passes.
