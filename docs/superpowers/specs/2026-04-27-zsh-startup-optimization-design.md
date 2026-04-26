# Zsh Startup Optimization Design

## Overview

This document outlines the design for optimizing the startup speed of Zsh in the dotfiles repository.

## Architecture & Components

- **Target Files**: All `.zsh` configuration files located in the `zsh/` directory (`00-tmux.zsh`, `10-editor.zsh`, `20-dev.zsh`, `20-docker.zsh`, `20-git.zsh`, `20-k8s.zsh`, `20-network.zsh`, `20-os.zsh`, `20-ssh-gpg.zsh`) as well as the main `zshrc` file if applicable.
- **Optimization Strategy**: The primary bottleneck identified is the frequent use of subprocess forks for command availability checks (e.g., `if type <cmd> >/dev/null 2>&1`). These will be systematically replaced with the Zsh-native hash table check `if (( $+commands[<cmd>] ))`.

## Data Flow & Execution Logic

The execution flow of the Zsh initialization scripts remains fundamentally the same. The conditional logic testing for command existence will behave identically:

- `$+commands[<cmd>]` evaluates to `1` if the command is found in Zsh's internal command hash table.
- It evaluates to `0` if the command is absent.
  This provides a 1:1 functional replacement for the `type` checks but with zero subshell or fork overhead.

## Error Handling

- The replacement is syntax-safe within standard Zsh `if` statements.
- Edge cases where `type` was used to check aliases or functions (instead of external commands) need to be considered. However, an analysis shows that the `type <cmd>` checks in this context are exclusively for external binaries (e.g., `tmux`, `docker`, `kubectl`, `helm`, `rg`). In these cases, `$+commands` is perfectly accurate and safe.

## Testing Strategy

- **Syntax Validation**: Run `zsh -n <file>` or evaluate `zsh -c exit` to ensure no syntax errors are introduced across the modified scripts.
- **Performance Verification**: Measure startup time before and after using the existing `zstime` alias (`time (zsh -i -c exit)`) or similar profiling techniques to confirm the performance gain.
