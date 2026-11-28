# Pi + Google AI Ultra / Antigravity Auth Tracking Note

- **Decision Date**: 2026-11-28
- **Current Bridge**: `@estebanforge/pi-antigravity-bridge@1.16.0` (declared in `agent/harnesses/pi/settings.json` `packages`) via official `agy acp` / `stream-json`, paired with `agent/harnesses/pi/extensions/bridge-antigravity.ts` (`antigravity` tool / `/agy-cli`).
- **ToS Boundary (Google Antigravity Section 6)**:
  - Interactive usage via official `agy acp` (`@estebanforge/pi-antigravity-bridge`) or explicit `antigravity` CLI delegation is scoped to human interactive sessions.
  - Automated background/SWARM loops (`swarm-loop`, `swarm-graph`, `daemon_spawn`, `--every`/`--until`) MUST keep primary routing on direct API / OAuth-supported providers (`anthropic`, `openai`, `opencode-go`, `ollama`, `google`, `google-vertex`) rather than wrapping consumer Antigravity OAuth in unattended loops.
- **Upstream Tracking Reminder**:
  - An open upstream issue in `earendil-works/pi` tracks **official native Google AI Ultra authentication support** in Pi.
  - Once that upstream PR/release merges into `@earendil-works/pi-coding-agent`:
    1. Upgrade `@earendil-works/pi-coding-agent` in `dockers/tools.Dockerfile` and host global Bun/npm.
    2. Remove `npm:@estebanforge/pi-antigravity-bridge@1.16.0` from `agent/harnesses/pi/settings.json` `packages`.
    3. Migrate `antigravity-cli/*` fallback/sub-route targets in `agent/models/catalog.json` and `agent/harnesses/pi/model-routing.json` to the official Pi provider ID and re-run `make pi/models/sync`.
    4. Authenticate via `pi auth login <official-google-provider>`.
