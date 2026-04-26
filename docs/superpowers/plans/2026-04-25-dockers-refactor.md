# Dockers Refactoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove redundant `ENV` and `ARG` definitions across child Dockerfiles by centralizing them into the foundational `base.Dockerfile`.

**Architecture:** The `base.Dockerfile` acts as the single source of truth for OS-level and repository-level download paths, allowing downstream Dockerfiles (like `k8s.Dockerfile` and `go.Dockerfile`) to be completely DRY.

**Tech Stack:** Docker.

---

### Task 1: Update base.Dockerfile

**Files:**

- Modify: `dockers/base.Dockerfile`

- [ ] **Step 1: Add new standard variables to base**
      We need to insert the GitHub/Path standard variables after the existing `ENV` declarations (around line 18, after `ENV LD_LIBRARY_PATH=...`).

```bash
sed -i '/ENV LD_LIBRARY_PATH=/a \
ENV GITHUBCOM=github.com\nENV GITHUB=https://${GITHUBCOM}\nENV API_GITHUB=https://api.github.com/repos\nENV RAWGITHUB=https://raw.githubusercontent.com\nENV GOOGLE=https://storage.googleapis.com\nENV RELEASE_DL=releases/download\nENV RELEASE_LATEST=releases/latest\nENV LOCAL=/usr/local\nENV BIN_PATH=${LOCAL}/bin\n' dockers/base.Dockerfile
```

- [ ] **Step 2: Verify the modification**
      Run: `grep -E 'ENV GITHUB|ENV LOCAL' dockers/base.Dockerfile`
      Expected: Output showing the newly added `ENV` lines.

- [ ] **Step 3: Commit**

```bash
git add dockers/base.Dockerfile
git commit -m "refactor(dockers): add centralized paths and constants to base.Dockerfile"
```

---

### Task 2: Strip redundancies from k8s.Dockerfile

**Files:**

- Modify: `dockers/k8s.Dockerfile`

- [ ] **Step 1: Remove redundant ENV blocks**
      Remove the block of standard OS and Path variables from `k8s.Dockerfile`.

```bash
sed -i -e '/ENV OS=${TARGETOS}/d' \
       -e '/ENV ARCH=${TARGETARCH}/d' \
       -e '/ENV AARCH=aarch64/d' \
       -e '/ENV XARCH=x86_64/d' \
       -e '/ENV GITHUBCOM=github.com/d' \
       -e '/ENV GITHUB=https:\/\/${GITHUBCOM}/d' \
       -e '/ENV API_GITHUB=https:\/\/api.github.com\/repos/d' \
       -e '/ENV RAWGITHUB=https:\/\/raw.githubusercontent.com/d' \
       -e '/ENV GOOGLE=https:\/\/storage.googleapis.com/d' \
       -e '/ENV RELEASE_DL=releases\/download/d' \
       -e '/ENV RELEASE_LATEST=releases\/latest/d' \
       -e '/ENV LOCAL=\/usr\/local/d' \
       -e '/ENV BIN_PATH=${LOCAL}\/bin/d' dockers/k8s.Dockerfile
```

- [ ] **Step 2: Verify removal**
      Run: `grep -E 'ENV GITHUB' dockers/k8s.Dockerfile`
      Expected: No output.

- [ ] **Step 3: Commit**

```bash
git add dockers/k8s.Dockerfile
git commit -m "refactor(dockers): strip redundant ENV variables from k8s.Dockerfile"
```

---

### Task 3: Strip redundancies from go.Dockerfile

**Files:**

- Modify: `dockers/go.Dockerfile`

- [ ] **Step 1: Remove redundant ENV blocks**
      Remove the standard OS variables and duplicate APT config from `go.Dockerfile`.

```bash
sed -i -e '/ENV OS=${TARGETOS}/d' \
       -e '/ENV ARCH=${TARGETARCH}/d' \
       -e '/ENV AARCH=aarch_64/d' \
       -e '/ENV XARCH=x86_64/d' \
       -e '/ENV DEBIAN_FRONTEND=noninteractive/d' \
       -e '/ENV INITRD=No/d' \
       -e '/ENV LANG=en_US.UTF-8/d' dockers/go.Dockerfile
```

- [ ] **Step 2: Verify removal**
      Run: `grep -E 'ENV DEBIAN_FRONTEND' dockers/go.Dockerfile`
      Expected: No output.

- [ ] **Step 3: Commit**

```bash
git add dockers/go.Dockerfile
git commit -m "refactor(dockers): strip redundant ENV variables from go.Dockerfile"
```

---

### Task 4: Strip redundancies from docker.Dockerfile

**Files:**

- Modify: `dockers/docker.Dockerfile`

- [ ] **Step 1: Remove redundant ENV blocks**

```bash
sed -i -e '/ENV OS=${TARGETOS}/d' \
       -e '/ENV ARCH=${TARGETARCH}/d' \
       -e '/ENV AARCH=aarch64/d' \
       -e '/ENV XARCH=x86_64/d' dockers/docker.Dockerfile
```

- [ ] **Step 2: Verify removal**
      Run: `grep -E 'ENV XARCH' dockers/docker.Dockerfile`
      Expected: No output.

- [ ] **Step 3: Commit**

```bash
git add dockers/docker.Dockerfile
git commit -m "refactor(dockers): strip redundant ENV variables from docker.Dockerfile"
```

---

### Task 5: Strip redundancies from env.Dockerfile

**Files:**

- Modify: `dockers/env.Dockerfile`

- [ ] **Step 1: Remove redundant ENV blocks**

```bash
sed -i -e '/ENV OS=${TARGETOS}/d' \
       -e '/ENV ARCH=${TARGETARCH}/d' \
       -e '/ENV AARCHS=aarch_64/d' \
       -e '/ENV AARCH=aarch64/d' \
       -e '/ENV XARCH=x86_64/d' dockers/env.Dockerfile
```

- [ ] **Step 2: Verify removal**
      Run: `grep -E 'ENV AARCH' dockers/env.Dockerfile`
      Expected: No output.

- [ ] **Step 3: Commit**

```bash
git add dockers/env.Dockerfile
git commit -m "refactor(dockers): strip redundant ENV variables from env.Dockerfile"
```

---

### Task 6: Check rust.Dockerfile

**Files:**

- Modify: `dockers/rust.Dockerfile`

- [ ] **Step 1: Remove redundant BIN_PATH ENV**
      `rust.Dockerfile` uses `BIN_PATH=${CARGO_HOME}/bin`, which conflicts with the new base `BIN_PATH=${LOCAL}/bin`. However, Cargo specifically uses `CARGO_HOME/bin`. We will retain `BIN_PATH=${CARGO_HOME}/bin` in `rust.Dockerfile` because it purposefully overwrites the base variable for the Rust context. We just need to remove any other redundant OS ones if they exist.

```bash
sed -i -e '/ENV OS=${TARGETOS}/d' \
       -e '/ENV ARCH=${TARGETARCH}/d' \
       -e '/ENV AARCH=aarch64/d' \
       -e '/ENV XARCH=x86_64/d' dockers/rust.Dockerfile
```

- [ ] **Step 2: Verify removal**
      Run: `grep -E 'ENV OS=' dockers/rust.Dockerfile || true`
      Expected: No output (if they existed, they are removed).

- [ ] **Step 3: Commit**

```bash
git add dockers/rust.Dockerfile
git commit -m "refactor(dockers): strip redundant OS variables from rust.Dockerfile if any"
```
