# Dockers Refactoring Design

## Overview

The `dockers/` directory contains numerous Dockerfiles that share a common foundation (`kpango/base:nightly`). However, there is significant boilerplate duplication across these files, specifically concerning `ENV` and `ARG` declarations for system architecture and common download paths. This design aims to apply the DRY (Don't Repeat Yourself) principle by strictly relying on Docker's image inheritance capabilities.

## Architecture & Implementation

### 1. `base.Dockerfile` (Single Source of Truth)

The `base.Dockerfile` will be expanded to serve as the definitive source for common environment variables used across all downstream images.

**Additions to `base.Dockerfile`:**

- **OS/Arch Flags**: Confirm `OS`, `ARCH`, `XARCH`, `AARCH` are set.
- **Common Paths**: Introduce `LOCAL=/usr/local` and `BIN_PATH=${LOCAL}/bin`.
- **Download Helpers**: Introduce standard variables used for downloading binaries, which are currently duplicated in files like `k8s.Dockerfile`.
  - `GITHUBCOM=github.com`
  - `GITHUB=https://${GITHUBCOM}`
  - `API_GITHUB=https://api.github.com/repos`
  - `RAWGITHUB=https://raw.githubusercontent.com`
  - `GOOGLE=https://storage.googleapis.com`
  - `RELEASE_DL=releases/download`
  - `RELEASE_LATEST=releases/latest`

### 2. Stripping Downstream Dockerfiles

With the base image providing the necessary context, we will strip redundant blocks from the downstream Dockerfiles to make them purely functional.

**Targets for Cleanup:**

- **`dockers/go.Dockerfile`**: Remove re-declarations of `TARGETOS`, `TARGETARCH`, `OS`, `ARCH`, `AARCH`, `XARCH`, `DEBIAN_FRONTEND`, `LANG`.
- **`dockers/k8s.Dockerfile`**: Remove re-declarations of `TARGETOS`, `TARGETARCH`, `OS`, `ARCH`, `AARCH`, `XARCH`, and the `GITHUB` / `BIN_PATH` URL block (now provided by base).
- **`dockers/docker.Dockerfile`**: Remove `TARGETOS`, `TARGETARCH`, `OS`, `ARCH`, `AARCH`, `XARCH`.
- **`dockers/env.Dockerfile`**: Remove `OS`, `ARCH`, `AARCHS`, `AARCH`, `XARCH`.
- **`dockers/rust.Dockerfile`**: Remove manual `BIN_PATH` mapping that overlaps with the new base logic, if possible.

## Testing Strategy

- Validation will be performed by ensuring the Dockerfiles still parse correctly.
- If possible in the environment, a `docker build` dry-run or linting step will be executed to confirm layers inherit variables as expected.
