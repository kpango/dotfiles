# Migrate Aliases into Zsh Scripts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize docker and dev-related shell aliases by moving the contents of `alias` into `zsh/20-docker.zsh` and removing the legacy `alias` file.

**Architecture:** We will copy the complete contents of `alias` into the end of `zsh/20-docker.zsh`. Then we will remove the conditional `source $HOME/.aliases` logic from `zsh/20-docker.zsh` since it's no longer needed. Finally, we'll delete the original `alias` file.

**Tech Stack:** Bash, Zsh, Git.

---

### Task 1: Migrate alias contents into `zsh/20-docker.zsh`

**Files:**

- Modify: `zsh/20-docker.zsh`
- Read: `alias`

- [ ] **Step 1: Write a conceptual test**
      Run: `grep -q 'alias dockerrm="dockerrm"' zsh/20-docker.zsh || echo "Not found"`
      Expected: Output `Not found`.

- [ ] **Step 2: Remove lazy-loading logic from `zsh/20-docker.zsh`**
      In `zsh/20-docker.zsh`, remove these blocks:

```zsh
        [ -z "$_lazy_docker_aliases" ] && {
            [ -f $HOME/.aliases ] && source $HOME/.aliases
            _lazy_docker_aliases=1
        }
```

There are two occurrences (one in `darwin*)` and one in `linux*)`). Remove both.

- [ ] **Step 3: Append `alias` contents to `zsh/20-docker.zsh`**
      Read the contents of `alias` and append them to the end of `zsh/20-docker.zsh` (excluding the `#!/usr/bin/zsh` header).

- [ ] **Step 4: Verify migration**
      Run: `grep -q 'alias dockerrm="dockerrm"' zsh/20-docker.zsh && echo "Found"`
      Expected: Output `Found`.

- [ ] **Step 5: Commit changes**

```bash
git add zsh/20-docker.zsh
git commit -m "refactor(zsh): migrate aliases into docker script and remove lazy loading"
```

---

### Task 2: Remove the legacy `alias` file

**Files:**

- Delete: `alias`

- [ ] **Step 1: Verify the file exists**
      Run: `ls alias`
      Expected: Output `alias`

- [ ] **Step 2: Delete the file**
      Run: `git rm alias`

- [ ] **Step 3: Commit changes**

```bash
git commit -m "chore: remove legacy alias file"
```
