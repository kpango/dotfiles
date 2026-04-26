# Zsh Startup Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce Zsh startup time by replacing slow subprocess `type` checks with Zsh-native `$+commands` hash lookups.

**Architecture:** We will systematically modify `zshrc` and all `.zsh` files in the `zsh/` directory.

**Tech Stack:** Bash, Zsh, Perl/Sed

---

### Task 1: Replace subprocess type checks with Zsh native hash checks

**Files:**

- Modify: `zshrc`
- Modify: `zsh/00-tmux.zsh`
- Modify: `zsh/01-core.zsh`
- Modify: `zsh/10-editor.zsh`
- Modify: `zsh/20-dev.zsh`
- Modify: `zsh/20-docker.zsh`
- Modify: `zsh/20-git.zsh`
- Modify: `zsh/20-k8s.zsh`
- Modify: `zsh/20-network.zsh`
- Modify: `zsh/20-os.zsh`
- Modify: `zsh/20-ssh-gpg.zsh`

- [ ] **Step 1: Execute replacement script**

Run the following perl one-liner to safely replace all occurrences of `type <cmd> >/dev/null 2>&1` with `(( $+commands[<cmd>] ))` in the target files.

```bash
perl -pi -e 's/type\s+([A-Za-z0-9_.\$-]+)\s*>\/dev\/null\s*2>&1/\(\( \$+commands[$1] \)\)/g' zshrc zsh/*.zsh
```

- [ ] **Step 2: Verify the replacements**

Run a grep to ensure no old `type` checks remain in the relevant files.

```bash
grep -E "type .*>/dev/null 2>&1" zshrc zsh/*.zsh || true
```

Expected: No output.

- [ ] **Step 3: Test Zsh syntax validation**

Run a syntax check on the modified files to ensure the replacements didn't break anything.

```bash
zsh -n zshrc
for file in zsh/*.zsh; do zsh -n "$file"; done
```

Expected: No output (which means syntax is valid).

- [ ] **Step 4: Verify Zsh can start successfully**

Run Zsh interactively and immediately exit to ensure it loads without runtime errors.

```bash
zsh -i -c exit
```

Expected: Successful execution with no error messages.

- [ ] **Step 5: Commit changes**

```bash
git add zshrc zsh/*.zsh
git commit -m "perf(zsh): optimize startup by replacing type with Zsh native hash checks"
```
