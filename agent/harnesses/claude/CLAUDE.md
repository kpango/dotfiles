@AGENTS.md

@AGENTS-supplement.md

## Claude Code

- Periodically run `/doctor` to catch CLAUDE.md bloat (content Claude could already derive from the codebase)
- `/init` and `/import` can pull `AGENTS.md`/other agent configs into a project-level `CLAUDE.md` — this file already imports the shared `agent/AGENTS.md` (dotfiles), so re-running `/import` at the user scope is not needed
