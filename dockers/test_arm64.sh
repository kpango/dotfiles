#!/bin/bash
OS=linux
ARCH=arm64
XARCH=x86_64
AARCH=aarch64

GITHUB=https://github.com
API_GITHUB=https://api.github.com/repos

check_url() {
    local name=$1
    local url=$2
    local code=$(curl -IsL -o /dev/null -w "%{http_code}" "$url")
    echo "$name: $code - $url"
}

# 4. slim
VERSION=$(curl -fsSL ${API_GITHUB}/slimtoolkit/slim/releases/latest | jq -r .tag_name | sed 's/^v//')
case "${ARCH}" in amd64) SLIM_ARCH="" ;; arm64|aarch64) SLIM_ARCH="_arm64" ;; *) SLIM_ARCH="" ;; esac
check_url "slim" "https://github.com/slimtoolkit/slim/releases/download/${VERSION}/dist_${OS}${SLIM_ARCH}.tar.gz"

# 5. docker-credential-pass
VERSION=$(curl -fsSL ${API_GITHUB}/docker/docker-credential-helpers/releases/latest | jq -r .tag_name | sed 's/^v//')
check_url "docker-credential-pass" "${GITHUB}/docker/docker-credential-helpers/releases/download/v${VERSION}/docker-credential-pass-v${VERSION}.${OS}-${ARCH}"

# 6. docker-credential-secretservice
check_url "docker-credential-secretservice" "${GITHUB}/docker/docker-credential-helpers/releases/download/v${VERSION}/docker-credential-secretservice-v${VERSION}.${OS}-${ARCH}"

# 7. buildx
VERSION=$(curl -fsSL ${API_GITHUB}/docker/buildx/releases/latest | jq -r .tag_name | sed 's/^v//')
check_url "buildx" "${GITHUB}/docker/buildx/releases/download/v${VERSION}/buildx-v${VERSION}.${OS}-${ARCH}"

# 8. dockfmt
VERSION=$(curl -fsSL ${API_GITHUB}/jessfraz/dockfmt/releases/latest | jq -r .tag_name | sed 's/^v//')
check_url "dockfmt" "${GITHUB}/jessfraz/dockfmt/releases/download/v${VERSION}/dockfmt-${OS}-${ARCH}"

# 9. compose
VERSION=$(curl -fsSL ${API_GITHUB}/docker/compose/releases/latest | jq -r .tag_name | sed 's/^v//')
C_ARCH=${ARCH}
case "${C_ARCH}" in amd64) C_ARCH=${XARCH} ;; arm64) C_ARCH=${AARCH} ;; esac
check_url "compose" "${GITHUB}/docker/compose/releases/download/v${VERSION}/docker-compose-${OS}-${C_ARCH}"

# 10. containerd
VERSION=$(curl -fsSL ${API_GITHUB}/containerd/containerd/releases/latest | jq -r .tag_name | sed 's/^v//')
check_url "containerd" "${GITHUB}/containerd/containerd/releases/download/v${VERSION}/containerd-${VERSION}-${OS}-${ARCH}.tar.gz"

