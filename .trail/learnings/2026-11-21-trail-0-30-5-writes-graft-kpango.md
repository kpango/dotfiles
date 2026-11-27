---
title: trail 0.30.5 writes graft-hooks.cjs and defaults to ./graft
author: Kpango
date: 2026-11-21
branch: main
id: l-adeb181c
scope: repo
status: active
src: agent
touches:
  - agent/harnesses/claude/settings.json
  - agent/skills/trail/SKILL.md
---

## Decided

- trail 0.30.5 installs its Claude Code helper as ~/.claude/helpers/graft-hooks.cjs (byte-identical to the repo's .trail/hook.cjs). agent/harnesses/claude/settings.json now points at it, and claude/docker/install copies .trail/hook.cjs there so the dev image's hook commands resolve.
- Keep the graph in .trail/cache for this repo via `trail --dir <repo>/.trail/cache build`, because 0.30.5 otherwise creates ./graft.

## Tried and ruled out

- `trail build --deep` with the Anthropic and OpenAI keys in `pass ai/anthropic|open_ai`: both return 400 "no credits".
- OpenCode Zen (/zen/v1) is pay-as-you-go; only /zen/go/v1 works with the oc*sk* subscription key, and it rejects requests without an x-opencode-session header. A 40-line local Bun shim adding that header is enough for trail's OpenAI provider.
- `trail build --deep` via Groq free tier: the deep prompt is ~28k tokens and the 8k TPM cap rejects it (429), so the run cannot finish.
- `trail build --deep` via the Zen shim with `glm-5.3`: rc=0 but the model ignored the forced tool_choice and the concept pass produced 0 nodes/links; do not trust the exit code.
- The same shim with `deepseek-v4.1-flash` for both `GRAFT_MODEL` and `GRAFT_SYNTH_MODEL`: 136 concepts / 243 links from 350 files, `--check` OK. Trail does not read the shim's `OPENCODE_API_KEY`; set `GRAFT_API_KEY` (any value) and `GRAFT_PROVIDER=openai` or it silently falls back to the structural build.

## Watch out

- Bun's fetch decompresses the upstream body but keeps content-encoding; a pass-through proxy must delete content-encoding/content-length or clients abort with "terminated".
- `trail init` rewrites agent/skills/trail/SKILL.md (description length) and settings.json. ~/.local/bin/trail is now a guard that re-runs the real binary and restores only SKILL.md afterwards; `claude/docker/install` installs the same guard inside the dev container.
- A deep run that exits 0 can still produce zero concept nodes when the synthesis model ignores tool_choice; check the per-stage counts, not only the exit code.
