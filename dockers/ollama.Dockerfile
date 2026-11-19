# syntax = docker/dockerfile:latest
# Standalone Ollama server image with a model baked in at build time (offline-ready on
# first start, no first-run pull). Runs alongside the `dev` container (see devrun() in
# zsh/20-docker.zsh), not layered into it -- kept as its own image/container so it can
# be recreated/updated independently and isn't tied to the dev image's own build cadence.
#
# Model choice: qwen3:4b-instruct (the explicit "-instruct" tag, non-thinking) --
# validated 2026-09-12 (agent-memory-solution-reevaluation mission, supermemory's
# extraction-LLM provider switch): qwen3:8b's default thinking mode (chain-of-thought
# preamble) blew past supermemory's internal 30s workflow-step timeout under CPU-only
# inference and left documents stuck in "indexing" forever; qwen3:4b-instruct completed
# the same task cleanly in ~38s. Override via --build-arg OLLAMA_MODEL=... for other uses.
ARG OLLAMA_VERSION=0.34.0
ARG OLLAMA_MODEL=qwen3:4b-instruct

FROM ollama/ollama:${OLLAMA_VERSION} AS model-puller
ARG OLLAMA_MODEL
# `ollama pull` requires a running server (github.com/ollama/ollama#3369 -- no
# serverless "download only" mode as of this image's version). No curl/pkill in this
# minimal base image, so readiness/teardown use the ollama binary itself (`ollama list`)
# and a captured $! PID rather than external tools.
RUN set -eu; \
    ollama serve & \
    server_pid=$!; \
    ready=0; \
    for _ in $(seq 1 60); do \
        if ollama list >/dev/null 2>&1; then ready=1; break; fi; \
        sleep 1; \
    done; \
    if [ "$ready" -ne 1 ]; then echo "ollama serve did not become ready in time" >&2; exit 1; fi; \
    ollama pull "${OLLAMA_MODEL}"; \
    kill "$server_pid"; \
    wait "$server_pid" 2>/dev/null || true

FROM ollama/ollama:${OLLAMA_VERSION}
ARG EMAIL=kpango@vdaas.org
ARG OLLAMA_MODEL
LABEL maintainer="kpango <${EMAIL}>"

# Baked-in model + a larger default context (the official default is 4k unless VRAM
# implies otherwise -- irrelevant here since this runs CPU-only; 32k comfortably fits
# the kind of multi-KB documents a local extraction pipeline like supermemory's sends,
# see the mission note above for the context-overflow this was found to fix).
ENV OLLAMA_MODEL=${OLLAMA_MODEL} \
    OLLAMA_HOST=0.0.0.0:11434 \
    OLLAMA_CONTEXT_LENGTH=32768

COPY --link --from=model-puller /root/.ollama /root/.ollama

EXPOSE 11434
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=5 \
    CMD ollama list >/dev/null 2>&1 || exit 1
