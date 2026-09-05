{
  dotfilesPath,
  homeDirectory,
  lib,
  ...
}:

# Home-manager translation of Makefile.d/install.mk's claude/install, pi/install,
# agy/install, and codex/install targets (plus the claude/pi/agy/codex-relevant
# lines of DOTFILES_MAP).
# Every `source` below points at the same canonical, non-symlinked repo paths those
# Makefile targets themselves link from (agent/rules, agent/agents, agent/skills,
# agent/RTK.md, agent/SWARM.md, agent/SWARM_REFERENCES.md, and each tool's own
# settings/hooks/prompts/extensions directory) — never through a repo-internal
# symlink (claude/rules, agy/agents, etc.), matching the ongoing removal of those
# symlinks elsewhere in this repo.
#
# force = true on every directory entry: see dotfiles/shared.nix's ghostty/shaders
# comment. On any host where Makefile.d/install.mk's claude/install, pi/install, or
# agy/install already ran (mac/install always runs them before nix/setup), these
# destinations are pre-existing directory symlinks pointing at the identical
# dotfiles-repo source, which home.file's checkLinkTargets can't diff and so
# refuses as "would be clobbered" without force.
#
# NOT translated here (intentionally out of scope for this per-user home-manager
# module):
#   - ~/.claude/projects, ~/.claude/history.jsonl (claude/install): symlinks into
#     a separate, external kpango/pass secrets repo, not sourced from dotfilesPath.
#   - Root-session sharing (claude/install's $(ROOT_HOME)/.claude mountpoint/
#     symlink dance, and the $(ROOT_HOME)/.gitconfig, $(ROOT_HOME)/.agy/* lines
#     alongside it; pi/install's and agy/install's equivalent $(ROOT_HOME)/.pi,
#     $(ROOT_HOME)/.agy, $(ROOT_HOME)/.gemini mountpoint/symlink dance): system-
#     level (root home directory), not user-scoped state — out of place in a
#     home-manager module. NixOS/nix-darwin system modules would be the correct
#     layer if this is ever wanted, but nothing here currently manages it.
#   - .agy/settings.json and .agy/policies/rules.toml: already defined in
#     dotfiles/shared.nix (added before this module existed) — redefining the
#     same home.file key from two modules is a module-system conflict, so this
#     module covers every other claude/pi/agy destination and leaves those two
#     alone.
let
  # <targetSubpath> 直下を、複数の物理ディレクトリ(srcDirs)からのper-file symlinkで構成する
  # home.file エントリ群を生成する。通常の home.file."<path>".source = <dir> はディレクトリ丸ごと
  # 1本のsymlinkにするため単一の物理ソースしか表現できないが、hooksスクリプトの一部が
  # agent/hooks/ へ実体移動した後(agent-hooks-and-pi-agents-unificationミッション)
  # claude/hooks・agy/hooks・pi/extensions(および pi/extensions/lib)の各ターゲットディレクトリは
  # 複数の物理ソースを合成する必要が生じた。Makefile.d/install.mkの対応するターゲットが
  # `find <dir> -maxdepth 1 -type f -exec ln -sfvn {} <target>/ \;` を複数回実行するのと同型の
  # per-file symlink方式。`builtins.readDir` はディレクトリ内容を評価時に読み取るため、新規
  # ファイル追加・削除時もNix側の変更は不要(ソースディレクトリの実ファイルに追随)。
  # .gitkeep等のplaceholderファイルはper-file symlinkの対象から除外する(2026-09-04、
  # claude-hooks-full-agent-consolidationミッション Phase 4.5で発見: claude/hooks/が実体移動で
  # 空になったことに伴い.gitkeepを追加したが、Makefile.d/install.mk側は`-name "*.sh"`フィルタで
  # 除外する一方、本ヘルパーは拡張子を問わず"regular"な全ファイルを対象にするため.gitkeepも
  # ~/.claude/hooks/.gitkeepとしてsymlinkされてしまっていた。5箇所の呼び出し全てに影響する
  # 共有ヘルパーのため、`.sh`拡張子限定のallowlist化ではなく〈.agy/hooksターゲットは
  # hooks.jsonという非.shファイルも正当に含むため拡張子allowlistは使えない〉、placeholder
  # ファイル名のblocklist化で対処する)。
  mergedDirPlaceholders = [ ".gitkeep" ];
  mergedDirFiles =
    targetSubpath: srcDirs:
    lib.foldl' (
      acc: srcDir:
      acc
      // (lib.mapAttrs'
        (name: _: {
          name = "${targetSubpath}/${name}";
          value = {
            source = "${srcDir}/${name}";
            force = true;
          };
        })
        (
          lib.filterAttrs (n: v: v == "regular" && !(lib.elem n mergedDirPlaceholders)) (
            builtins.readDir srcDir
          )
        )
      )
    ) { } srcDirs;
in
{
  home.file =
    (mergedDirFiles ".claude/hooks" [
      "${dotfilesPath}/agent/harnesses/claude/hooks"
      "${dotfilesPath}/agent/hooks/claude"
    ])
    // (mergedDirFiles ".pi/agent/extensions" [
      "${dotfilesPath}/agent/harnesses/pi/extensions"
      "${dotfilesPath}/agent/hooks/pi"
    ])
    // (mergedDirFiles ".pi/agent/extensions/lib" [
      "${dotfilesPath}/agent/harnesses/pi/extensions/lib"
      "${dotfilesPath}/agent/hooks/pi/lib"
    ])
    // (mergedDirFiles ".agy/hooks" [
      "${dotfilesPath}/agent/harnesses/agy/hooks"
      "${dotfilesPath}/agent/hooks/agy"
    ])
    // (mergedDirFiles ".gemini/hooks" [
      "${dotfilesPath}/agent/harnesses/agy/hooks"
      "${dotfilesPath}/agent/hooks/agy"
    ])
    // (mergedDirFiles ".prime/agent/extensions" [
      "${dotfilesPath}/agent/harnesses/pi/extensions"
      "${dotfilesPath}/agent/hooks/pi"
    ])
    // (mergedDirFiles ".prime/agent/extensions/lib" [
      "${dotfilesPath}/agent/harnesses/pi/extensions/lib"
      "${dotfilesPath}/agent/hooks/pi/lib"
    ])
    // {
      # ── Claude Code (~/.claude/) ──────────────────────────────────────────────
      ".claude/CLAUDE.md".source = "${dotfilesPath}/agent/harnesses/claude/CLAUDE.md";
      # AGENTS.md unification (2026-09-03): claude/CLAUDE.md's first two lines are
      # `@AGENTS.md` / `@AGENTS-supplement.md` (Claude Code's own @import syntax), so
      # both siblings must exist under ~/.claude/ for the import to resolve.
      ".claude/AGENTS.md".source = "${dotfilesPath}/agent/AGENTS.md";
      ".claude/AGENTS-supplement.md".source = "${dotfilesPath}/agent/AGENTS-claude-supplement.md";
      ".claude/SWARM.md".source = "${dotfilesPath}/agent/SWARM.md";
      ".claude/SWARM_REFERENCES.md".source = "${dotfilesPath}/agent/SWARM_REFERENCES.md";
      ".claude/keybindings.json".source = "${dotfilesPath}/agent/harnesses/claude/keybindings.json";
      ".claude/settings.json".source = "${dotfilesPath}/agent/harnesses/claude/settings.json";
      ".claude/settings.local.json".source = "${dotfilesPath}/agent/harnesses/claude/settings.local.json";
      ".claude/statusline-command.sh".source =
        "${dotfilesPath}/agent/harnesses/claude/statusline-command.sh";
      ".claude/model-routing.json".source = "${dotfilesPath}/agent/harnesses/claude/model-routing.json";
      ".claude/RTK.md".source = "${dotfilesPath}/agent/RTK.md";
      # installed_plugins.json is envsubst'd by claude/install (only $HOME appears
      # in it — see the template). homeDirectory is known statically here, so a
      # plain string substitution reproduces envsubst's effect without a runtime
      # activation step. Mirrors dotfiles/darwin.nix's gpg-agent.conf pinentry-path
      # substitution.
      ".claude/plugins/installed_plugins.json".text =
        builtins.replaceStrings
          [ "$HOME" ]
          [
            homeDirectory
          ]
          (builtins.readFile "${dotfilesPath}/agent/harnesses/claude/installed_plugins.json");

      ".claude/agents" = {
        source = "${dotfilesPath}/agent/agents";
        force = true;
      };
      ".claude/skills" = {
        source = "${dotfilesPath}/agent/skills";
        force = true;
      };
      ".claude/rules" = {
        source = "${dotfilesPath}/agent/rules";
        force = true;
      };

      # ── Pi Coding Agent (~/.pi/agent/) ────────────────────────────────────────
      ".pi/agent/AGENTS.md".source = "${dotfilesPath}/agent/harnesses/pi/AGENTS.md";
      ".pi/agent/SYSTEM.md".source = "${dotfilesPath}/agent/harnesses/pi/SYSTEM.md";
      ".pi/agent/SWARM.md".source = "${dotfilesPath}/agent/SWARM.md";
      ".pi/agent/SWARM_REFERENCES.md".source = "${dotfilesPath}/agent/SWARM_REFERENCES.md";
      ".pi/agent/RTK.md".source = "${dotfilesPath}/agent/RTK.md";
      ".pi/agent/settings.json".source = "${dotfilesPath}/agent/harnesses/pi/settings.json";
      ".pi/agent/models.json".source = "${dotfilesPath}/agent/harnesses/pi/models.json";
      ".pi/agent/keybindings.json".source = "${dotfilesPath}/agent/harnesses/pi/keybindings.json";
      ".pi/agent/mcp.json".source = "${dotfilesPath}/agent/harnesses/pi/mcp.json";
      ".pi/agent/model-routing.json".source = "${dotfilesPath}/agent/harnesses/pi/model-routing.json";

      # 2026-09-03以前はpi/agentsが生成物の実ディレクトリだったが、agent/scripts/gen-pi-agents.shが
      # 行っていたtools:frontmatter変換(PascalCase→pi-coding-agentのlowercase語彙)をpi/extensions/
      # subagents.tsの実行時変換(mapToolNames)へ移植したため、claude/agyと同型でagent/agentsへ直接
      # symlinkできるようになった(agent-hooks-and-pi-agents-unificationミッション)。
      ".pi/agent/agents" = {
        source = "${dotfilesPath}/agent/agents";
        force = true;
      };
      ".pi/agent/skills" = {
        source = "${dotfilesPath}/agent/skills";
        force = true;
      };
      ".pi/agent/rules" = {
        source = "${dotfilesPath}/agent/rules";
        force = true;
      };
      ".pi/agent/prompts" = {
        source = "${dotfilesPath}/agent/harnesses/pi/prompts";
        force = true;
      };
      ".pi/agent/themes" = {
        source = "${dotfilesPath}/agent/harnesses/pi/themes";
        force = true;
      };

      # ── Antigravity (~/.agy/ and ~/.gemini/) ──────────────────────────────────
      # .agy/settings.json and .agy/policies/rules.toml are already in
      # dotfiles/shared.nix — see the module-level comment above.
      ".agy/AGENTS.md".source = "${dotfilesPath}/agent/harnesses/agy/AGENTS.md";
      ".agy/SYSTEM.md".source = "${dotfilesPath}/agent/harnesses/agy/SYSTEM.md";
      ".agy/SWARM.md".source = "${dotfilesPath}/agent/SWARM.md";
      ".agy/SWARM_REFERENCES.md".source = "${dotfilesPath}/agent/SWARM_REFERENCES.md";
      ".agy/RTK.md".source = "${dotfilesPath}/agent/RTK.md";
      ".agy/mcp_config.json".source = "${dotfilesPath}/agent/harnesses/agy/mcp_config.json";
      ".agy/model-routing.json".source = "${dotfilesPath}/agent/harnesses/agy/model-routing.json";
      # agy/install links agy/policies/policy.toml to *both* .agy/policies/rules.toml
      # (already in shared.nix) *and* .agy/policies/policy.toml (this one).
      ".agy/policies/policy.toml".source = "${dotfilesPath}/agent/harnesses/agy/policies/policy.toml";

      ".agy/agents" = {
        source = "${dotfilesPath}/agent/agents";
        force = true;
      };
      ".agy/skills" = {
        source = "${dotfilesPath}/agent/skills";
        force = true;
      };
      ".agy/rules" = {
        source = "${dotfilesPath}/agent/rules";
        force = true;
      };

      ".gemini/AGENTS.md".source = "${dotfilesPath}/agent/harnesses/agy/AGENTS.md";
      ".gemini/SYSTEM.md".source = "${dotfilesPath}/agent/harnesses/agy/SYSTEM.md";
      ".gemini/SWARM.md".source = "${dotfilesPath}/agent/SWARM.md";
      ".gemini/SWARM_REFERENCES.md".source = "${dotfilesPath}/agent/SWARM_REFERENCES.md";
      ".gemini/RTK.md".source = "${dotfilesPath}/agent/RTK.md";
      ".gemini/settings.json".source = "${dotfilesPath}/agent/harnesses/agy/settings.json";
      ".gemini/antigravity-cli/settings.json".source =
        "${dotfilesPath}/agent/harnesses/agy/settings.json";
      ".gemini/policies/rules.toml".source = "${dotfilesPath}/agent/harnesses/agy/policies/policy.toml";
      ".gemini/policies/policy.toml".source = "${dotfilesPath}/agent/harnesses/agy/policies/policy.toml";
      ".gemini/config/mcp_config.json".source = "${dotfilesPath}/agent/harnesses/agy/mcp_config.json";
      ".gemini/config/hooks.json".source = "${dotfilesPath}/agent/harnesses/agy/hooks/hooks.json";
      ".gemini/model-routing.json".source = "${dotfilesPath}/agent/harnesses/agy/model-routing.json";
      ".gemini/config/model-routing.json".source =
        "${dotfilesPath}/agent/harnesses/agy/model-routing.json";

      ".gemini/config/skills" = {
        source = "${dotfilesPath}/agent/skills";
        force = true;
      };
      ".gemini/config/rules" = {
        source = "${dotfilesPath}/agent/rules";
        force = true;
      };
      ".gemini/config/agents" = {
        source = "${dotfilesPath}/agent/agents";
        force = true;
      };
      ".gemini/skills" = {
        source = "${dotfilesPath}/agent/skills";
        force = true;
      };
      ".gemini/rules" = {
        source = "${dotfilesPath}/agent/rules";
        force = true;
      };
      ".gemini/agents" = {
        source = "${dotfilesPath}/agent/agents";
        force = true;
      };

      # ── OpenAI Codex CLI (~/.codex/) ──────────────────────────────────────────
      ".codex/AGENTS.md".source = "${dotfilesPath}/agent/AGENTS.md";
      ".codex/config.toml".source = "${dotfilesPath}/agent/harnesses/codex/config.toml";
      ".codex/model-routing.json".source = "${dotfilesPath}/agent/harnesses/codex/model-routing.json";
      ".codex/skills" = {
        source = "${dotfilesPath}/agent/skills";
        force = true;
      };

      # ── PrimeAgent (~/.prime/agent/) ──────────────────────────────────────────
      # PrimeAgent is Pi-based, reusing Pi configuration & extensions
      ".prime/agent/AGENTS.md".source = "${dotfilesPath}/agent/harnesses/pi/AGENTS.md";
      ".prime/agent/SYSTEM.md".source = "${dotfilesPath}/agent/harnesses/pi/SYSTEM.md";
      ".prime/agent/SWARM.md".source = "${dotfilesPath}/agent/SWARM.md";
      ".prime/agent/SWARM_REFERENCES.md".source = "${dotfilesPath}/agent/SWARM_REFERENCES.md";
      ".prime/agent/RTK.md".source = "${dotfilesPath}/agent/RTK.md";
      ".prime/agent/settings.json".source = "${dotfilesPath}/agent/harnesses/primeagent/settings.json";
      ".prime/agent/models.json".source = "${dotfilesPath}/agent/harnesses/primeagent/models.json";
      ".prime/agent/keybindings.json".source = "${dotfilesPath}/agent/harnesses/pi/keybindings.json";
      ".prime/agent/mcp.json".source = "${dotfilesPath}/agent/harnesses/pi/mcp.json";
      ".prime/agent/model-routing.json".source =
        "${dotfilesPath}/agent/harnesses/primeagent/model-routing.json";
      ".prime/agent/agents" = {
        source = "${dotfilesPath}/agent/agents";
        force = true;
      };
      ".prime/agent/skills" = {
        source = "${dotfilesPath}/agent/skills";
        force = true;
      };
      ".prime/agent/rules" = {
        source = "${dotfilesPath}/agent/rules";
        force = true;
      };
      ".prime/agent/prompts" = {
        source = "${dotfilesPath}/agent/harnesses/pi/prompts";
        force = true;
      };
      ".prime/agent/themes" = {
        source = "${dotfilesPath}/agent/harnesses/pi/themes";
        force = true;
      };
    };

  # Directories claude/install, pi/install, and agy/install `mkdir -p` but never
  # populate from repo content (runtime-written state: plugin cache, memory,
  # session logs/transcripts) — home.file has nothing to source for these, so
  # they're created directly, mirroring the Makefile's plain `mkdir -p` lines.
  home.activation.ensureAgentToolDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p \
      "$HOME/.claude/plugins" \
      "$HOME/.claude/memory" \
      "$HOME/.claude/session-data" \
      "$HOME/.pi/agent/sessions" \
      "$HOME/.prime/agent/sessions"
  '';
}
