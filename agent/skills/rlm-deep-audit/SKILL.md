---
name: rlm-deep-audit
description: Depth-1 bounded chunked analysis of 200K+ token logs or multi-repo dumps via rlm-bounded.py. Not for small inputs.
---

# RLM Deep Audit — bounded fan-out over very large inputs

Use this only when the input is too large to read directly: a log, trace or concatenated multi-repo dump of roughly
**200K tokens or more** (~800 KB). Below that, read the file (or `grep`) yourself; fanning out costs more than it saves,
and the script refuses to run below the threshold.

## Procedure

1. Put the input in ONE regular file (no FIFO / symlink / binary). Keep the query to ONE line.
2. Run the analyzer with the gate on, so a too-small input exits 3 without spending anything:

   ```bash
   RLM_BACKEND=exec RLM_BACKEND_CMD='["claude","-p","--model","{model}"]' \
   RLM_BACKEND_PASS_ENV=ANTHROPIC_API_KEY \
   python3 -I -B agent/scripts/rlm/rlm-bounded.py \
     --query "which requests failed with a timeout, and why?" \
     --context-file /tmp/big.log \
     --require-min-tokens 200000 --chunk-bytes 262144 --max-chunks 64 \
     --max-workers 4 --cell-timeout 120 --sandbox --json
   ```

3. Read `answers` (one short evidence block per relevant chunk, at most 16) and `answered_chunks` / `chunks`.
   Chunks that answered NONE are dropped. `truncated: true` means more answers existed than were reported.
4. Verify every claim you act on against the original file (`grep -n`); the answers are leads, not proof.

## Hard limits (do not work around them)

- Depth is 1. `--max-depth` above 1 is rejected; the analyzer never calls itself.
- `--max-workers` 1..16 (default 8; use 4 for a metered API), `--cell-timeout` 1..3600 s per chunk, `--max-chunks` <= 4096.
- Nothing is truncated silently: input over the limits is rejected, not read.
- `--sandbox` runs the backend command through pa-sandbox and fails closed when it is missing. pa-sandbox keeps the
  network on; a backend that needs the network (a hosted LLM) works, one that must not have it needs `unshare -rn`.
- The backend gets only PATH / HOME / LANG / LC_ALL / TMPDIR plus the names in `RLM_BACKEND_PASS_ENV`. Name the one
  credential it needs and nothing else.

## Evidence

Every run appends one JSON line to `<ledger-dir>/rlm-trace.jsonl` (default `/tmp/rlm-ledger`): timestamp, chunks, model,
backend, workers, timeout, sandbox, query hash. It records that a run passed its checks, not that its output was delivered.

## Don't

- Don't use it for inputs under the threshold, for code review, or when a `grep` answers the question.
- Don't put secrets or private data in the query or the context file; chunks are sent to whatever backend you configured.
- Don't wrap it in a loop that feeds answers back in as a new context (that is depth 2 by another name).
