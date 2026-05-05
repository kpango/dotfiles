# syntax = docker/dockerfile:latest

# nix-base — official NixOS image with flakes + nix-command enabled.
FROM ghcr.io/nixos/nix:latest AS nix-base

ARG CURL_RETRY=3
ARG CURL_RETRY_DELAY=3

SHELL ["/bin/sh", "-o", "pipefail", "-c"]

ENV CURL_RETRY=${CURL_RETRY}
ENV CURL_RETRY_DELAY=${CURL_RETRY_DELAY}

RUN printf '%s\n' \
      'extra-experimental-features = nix-command flakes' \
      'accept-flake-config = true' \
      'substituters = https://cache.nixos.org' \
      'trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=' \
    >> /etc/nix/nix.conf

# nix-devtools — install language-server + linting/formatting tools via nixpkgs.
#   nil         : Nix Incremental Language Server (LSP)
#   nixpkgs-fmt : canonical Nix formatter
#   alejandra    : opinionated formatter (alternative)
#   statix       : Nix linter (anti-patterns + suggestions)
#   deadnix      : find unused bindings in Nix files
#   nix-tree     : interactive closure browser
#   nix-output-monitor : human-friendly build output (nom)
FROM nix-base AS nix-devtools
RUN --mount=type=cache,target=/root/.cache/nix,sharing=locked \
    nix profile install \
      nixpkgs#nil \
      nixpkgs#alejandra \
      nixpkgs#statix \
      nixpkgs#deadnix \
      nixpkgs#nix-tree \
      nixpkgs#nix-output-monitor \
    && nix-store --gc \
    && nix-store --optimise

# nix — final image: base config + devtools profile + nix store.
FROM nix-base AS nix

COPY --link --from=nix-devtools /nix /nix
COPY --link --from=nix-devtools /root/.nix-profile /root/.nix-profile

ENV NIX_PROFILE=/root/.nix-profile
ENV PATH=${NIX_PROFILE}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

CMD ["/bin/sh"]
