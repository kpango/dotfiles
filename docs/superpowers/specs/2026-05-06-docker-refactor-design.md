# Docker Refactor Design

Date: 2026-05-06

## Summary

Refactor `dockers/` to reduce coupling, improve cache efficiency, and fix build gaps.
Three main concerns: (1) split `env.Dockerfile` into user-setup and tool-install layers,
(2) extract cmake/vector-lib builds into a dedicated image, (3) fix Makefile and GitHub
Actions to reflect the new image graph.

## File Changes

| File                                   | Change                                                   |
| -------------------------------------- | -------------------------------------------------------- |
| `base.Dockerfile`                      | Add `# syntax = docker/dockerfile:latest` pragma         |
| `env.Dockerfile`                       | Shrink to user setup + translate-shell + bun binary only |
| `vald.Dockerfile`                      | **New** — cmake → NGT / FAISS / usearch → `FROM scratch` |
| `tools.Dockerfile`                     | **New** — bun globals + pip + protoc + vald artifacts    |
| `dev.Dockerfile`                       | Base changed from `kpango/env` to `kpango/tools`         |
| `rust.Dockerfile`                      | Remove unused `FROM kpango/rust:nightly AS old` stage    |
| `docker.Dockerfile`                    | Remove commented-out `container-diff` stage              |
| `Makefile.d/docker.mk`                 | Add zig/nix to parallel list; add tools step; fix prod   |
| `.github/workflows/docker-matrix.yaml` | Add vald to matrix; add tools job; update dev deps       |
| `.github/actions/docker/action.yaml`   | Add tools/vald to free-disk-space and GC conditions      |

## Image Dependency Graph

```
kpango/base:nightly
  ├── kpango/go:nightly
  ├── kpango/rust:nightly
  ├── kpango/docker:nightly
  ├── kpango/k8s:nightly
  ├── kpango/nim:nightly
  ├── kpango/dart:nightly
  ├── kpango/zig:nightly
  ├── kpango/nix:nightly
  ├── kpango/gcloud:nightly
  ├── kpango/vald:nightly        ← new (scratch image: headers + libs only)
  └── kpango/env:nightly         ← shrinks (user setup + bun binary only)
        └── kpango/tools:nightly ← new (bun globals + pip + protoc + vald artifacts)
              └── kpango/dev:nightly
```

## Build Order

### Makefile (docker.mk)

```
build_base
  → parallel xpanes: go docker rust dart k8s nim gcloud zig nix env vald
  → sequential: build_tools
  → [prod only]: prod_build (dev)
```

### GitHub Actions (docker-matrix.yaml)

```
base
  → images matrix: dart docker env gcloud go k8s nim nix rust vald zig  (parallel)
  → tools job (needs: base + images)
  → dev job (needs: base + images + tools)
```

## vald.Dockerfile

- Base: `FROM kpango/base:nightly`
- Stages: `cmake-base` → `ngt`, `faiss`, `usearch` (parallel from cmake-base)
- Final: `FROM scratch` exporting only headers + libs:
  - `${BIN_PATH}/ng*`
  - `${LOCAL}/include/NGT`, `${LOCAL}/lib/libngt.*`
  - `${LOCAL}/include/faiss`, `${LOCAL}/lib/libfaiss.*`
  - `${LOCAL}/include/usearch.h`, `${LOCAL}/lib/libusearch*`

## tools.Dockerfile

- Base: `FROM kpango/env:nightly`
- Internal `protoc` stage (moved from env.Dockerfile)
- `tools-stage`: bun global installs + `n latest` + pip
- Final `tools`: FROM tools-stage + COPY from vald + protoc + ldconfig + cleanup

## env.Dockerfile (after)

Retains only:

- `env-base`: user/group creation, sudo, ldconfig config, translate-shell, bun binary
- Final `env` stage: FROM env-base (no tool assembly)

## Dead Code Removed

- `rust.Dockerfile`: `FROM kpango/rust:nightly AS old` (unreferenced stage)
- `docker.Dockerfile`: commented-out `container-diff` stage (lines 141–148)

## GitHub Actions — action.yaml Changes

**free-disk-space** condition extended to include `tools` and `vald`:

```
go | rust | env | nix | tools | vald
```

**GC_FLAG** condition extended to include `tools` and `vald`:

```
go | rust | env | tools | vald
```
