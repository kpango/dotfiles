#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
readonly image=dotfiles-hermes-agent:v0.23.4
readonly name=dotfiles-hermes-agent
readonly data=dotfiles-hermes-agent-data
readonly label=io.github.kpango.dotfiles.hermes
readonly mountpoint=/home/kpango/go/src
readonly published=127.0.0.1:19120:19120
# The only repository paths the image build may read. validate-harness.sh checks
# that this list covers every input of hermes/docker/install and hermes.Dockerfile.
readonly -a context_paths=(
    Makefile Makefile.d agent/harnesses/hermes agent/skills agent/scripts/sandbox/pa-sandbox
    agent/scripts/bot/hermes-container-entrypoint.py dockers/hermes.Dockerfile
)

# Use only the local engine, with an empty client configuration so Docker
# cannot inject host proxy variables or use the host's registry credentials.
scratch=$(mktemp -d)
readonly -a docker=(env -i "PATH=$PATH" "HOME=$scratch" docker --config "$scratch" --host unix:///var/run/docker.sock)
readonly invocation_label="$label.invocation=${scratch##*/}"
readonly gateway_label="$label.role=gateway"

# Output must never change control flow: a closed pipe raises SIGPIPE, which is not
# an error status, so write inside a subshell that ignores it. Only the write's own
# error text is discarded (the order `>&2 2>/dev/null` keeps the message on stderr).
warn() { ( trap '' PIPE; printf '%s\n' "$*" >&2 2>/dev/null ) || :; }
say() { ( trap '' PIPE; printf '%s\n' "$*" 2>/dev/null ) || :; }
# --foreground keeps the child in the terminal's process group, so Ctrl-C reaches
# it immediately instead of waiting for the timeout to expire.
bounded() { local seconds=$1; shift; timeout --foreground --kill-after=1 "$seconds" "$@"; }
dk() { bounded 15 "${docker[@]}" "$@"; }

creating_container=0
pending_container=
# Under set -e a failing command in this trap would skip the rest of it, so every
# step is best effort and the original exit status is preserved.
cleanup() {
    local status=$? containers= container
    trap '' INT TERM
    if (( creating_container )); then
        if [[ "$pending_container" =~ ^[0-9a-f]{64}$ ]]; then
            containers=$pending_container
        else
            # Create may have completed on the daemon without returning its ID.
            if ! containers=$(bounded 5 "${docker[@]}" container ls --all --quiet --no-trunc \
                --filter "label=$invocation_label"); then
                warn "Hermes rollback unconfirmed for label $invocation_label; inspect the local Docker engine"
                containers=
            fi
        fi
        while IFS= read -r container; do
            if [[ "$container" =~ ^[0-9a-f]{64}$ ]]; then
                if bounded 10 "${docker[@]}" container rm -f "$container" >/dev/null; then
                    warn "Hermes rolled back container $container; its state volume was retained"
                else
                    warn "Hermes rollback unconfirmed for container $container; inspect the local Docker engine"
                fi
            fi
        done <<< "$containers"
    fi
    rm -r -- "$scratch" || :
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() { warn "Hermes container: $*"; exit 1; }

build() {
    local context="$scratch/context" iidfile="$scratch/image-id" tree id
    mkdir -- "$context"
    # Build from one indexed snapshot, never from an untracked HOME or a worktree.
    # (git write-tree records tree objects in the repository.)
    tree=$(git -C "$root" write-tree)
    warn "Building from Git tree $tree"
    git -C "$root" archive "$tree" "${context_paths[@]}" | tar -xf - -C "$context"
    # Constant mtimes keep Docker's layer cache valid across rebuilds of the same content.
    find "$context" -exec touch -h -d @0 {} +
    "${docker[@]}" buildx build --builder default --platform linux/amd64 --network none \
        --load --iidfile "$iidfile" --tag "$image" -f "$context/dockers/hermes.Dockerfile" "$context" >&2
    # Read through EOF, rejecting NULs and allowing only one trailing newline.
    [[ -f "$iidfile" ]] || fail 'Buildx did not write an image ID'
    if IFS= read -r -d '' id < "$iidfile"; then fail 'Buildx wrote an invalid image ID'; fi
    id=${id%$'\n'}
    [[ "$id" =~ ^sha256:[0-9a-f]{64}$ ]] || fail 'Buildx wrote an invalid image ID'
    loaded_image_id "$id"
}

loaded_image_id() {
    local id=$1 loaded
    loaded=$(dk image inspect --format '{{.Id}}' "$id") ||
        fail "image $id is not loaded locally"
    [[ "$loaded" == "$id" ]] || fail "local image inspection did not return $id"
    say "$id"
}

# Any locally loaded image ID is accepted; the launcher cannot tell that it came
# from this recipe, or that password and start use the same one.
image_id() {
    local id=${HERMES_CONTAINER_IMAGE_ID:-}
    [[ "$id" =~ ^sha256:[0-9a-f]{64}$ ]] ||
        fail 'set HERMES_CONTAINER_IMAGE_ID to the image ID printed by make hermes/container/build'
    loaded_image_id "$id"
}

workspace_source() {
    local gopath=${GOPATH:-} src sockets
    if [[ -z "$gopath" ]]; then gopath=$(go env GOPATH) || fail 'cannot determine GOPATH'; fi
    case "$gopath" in /*) ;; *) fail 'GOPATH must be a single absolute directory';; esac
    case "$gopath" in *:*) fail 'set GOPATH to one directory, not a list';; esac
    # realpath -z avoids losing newlines with command substitution.
    IFS= read -r -d '' gopath < <(realpath -ze -- "$gopath") || fail 'GOPATH does not exist'
    [[ "$gopath" != / ]] || fail 'GOPATH must not be the filesystem root'
    src="$gopath/src"
    [[ -d "$src" && ! -L "$src" ]] || fail 'GOPATH/src must be a real directory'
    case "$src" in *','*|*'"'*|*$'\n'*|*$'\r'*) fail 'GOPATH/src contains an unsupported Docker mount delimiter';; esac
    # A read-only mount does not prevent connecting to an existing Unix socket.
    sockets=$(bounded 30 find "$src" -xdev -type s -printf yes -quit) ||
        fail 'could not check GOPATH/src for Unix sockets (timed out or unreadable)'
    [[ -z "$sockets" ]] || fail 'GOPATH/src contains a Unix socket; remove it or choose a different GOPATH'
    say "$src"
}

# Check ownership on an existing resource. Never reuse an unrelated volume or network.
owned() {
    local kind=$1 resource=$2 template=$3 expected=$4 value
    value=$(dk "$kind" inspect --format "{{index .Labels \"$label\"}} $template" "$resource") ||
        fail "could not inspect $kind $resource"
    [[ "$value" == "1 $expected" ]] || fail "$kind $resource has unexpected ownership or settings"
}

state() {
    if ! dk volume inspect "$data" >/dev/null 2>&1; then
        dk volume create --driver local --label "$label=1" "$data" >/dev/null
    fi
    owned volume "$data" '{{.Driver}} {{len .Options}}' 'local 0'
}

bridge() {
    local version
    version=$(dk version --format '{{.Server.Version}}')
    if [[ ! "$version" =~ ^([0-9]+)\. ]] || (( BASH_REMATCH[1] < 28 )); then
        fail 'Docker Engine 28 or later is required for safe loopback publishing'
    fi
    if ! dk network inspect "$name" >/dev/null 2>&1; then
        dk network create --driver bridge --ipv6=false --label "$label=1" \
            --opt com.docker.network.bridge.gateway_mode_ipv4=nat \
            --opt com.docker.network.bridge.enable_icc=false "$name" >/dev/null
    fi
    owned network "$name" \
        '{{.Driver}} {{.Internal}} {{.EnableIPv6}} {{len .Containers}} {{index .Options "com.docker.network.bridge.gateway_mode_ipv4"}} {{index .Options "com.docker.network.bridge.enable_icc"}} {{index .Options "com.docker.network.bridge.trusted_host_interfaces"}}' \
        'bridge false false 0 nat false '
}

# One-shot containers are unnamed and unlabelled as gateways, so stop can never target them.
readonly -a common=(--pull never --label "$label=1" --user 1000:1000
    --cap-drop ALL --security-opt no-new-privileges --read-only --pids-limit 256 --memory 2g --memory-swap 2g --ipc private
    --tmpfs /tmp:rw,nosuid,nodev,mode=1777,size=256m
    --mount "type=volume,source=$data,target=/home/kpango/.hermes")

# The entrypoint limits itself to 30 s: PID 1 ignores TERM, so a client-side timeout
# alone would leave the container behind.
check_auth() {
    bounded 90 "${docker[@]}" run --rm --network none "${common[@]}" "$1" --check-webapp
}

before_deadline() {
    local remaining=$(( $1 - SECONDS ))
    shift
    (( remaining > 0 )) || return 124
    timeout --foreground --kill-after=1 "${remaining}s" "$@"
}

wait_ready() {
    local container=$1 deadline=$2 response host_response internal_api host_api
    local status='unknown'
    local status_format='{{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}}'
    local -a probe=(--disable --noproxy '*' --silent --max-time 1 --output /dev/null
        --write-out '%{http_code} %{redirect_url}' http://127.0.0.1:19120/)
    local -a api_probe=(--disable --noproxy '*' --silent --max-time 1 --output /dev/null
        --write-out '%{http_code}' http://127.0.0.1:19120/api/profiles)
    while (( SECONDS < deadline )); do
        status=$(before_deadline "$deadline" "${docker[@]}" container inspect \
            --format "$status_format" "$container") || break
        case "$status" in
            exited\ *|dead\ *|removing\ *|restarting\ *) break ;;
        esac
        response=$(before_deadline "$deadline" "${docker[@]}" exec "$container" /usr/bin/curl "${probe[@]}") ||
            response=
        case "$response" in
            '302 http://127.0.0.1:19120/login'|'302 http://127.0.0.1:19120/login?'*)
                if host_response=$(before_deadline "$deadline" curl "${probe[@]}") &&
                    [[ "$host_response" == "$response" ]] &&
                    internal_api=$(before_deadline "$deadline" "${docker[@]}" exec "$container" /usr/bin/curl "${api_probe[@]}") &&
                    [[ "$internal_api" == 401 ]] &&
                    host_api=$(before_deadline "$deadline" curl "${api_probe[@]}") &&
                    [[ "$host_api" == 401 ]] &&
                    status=$(before_deadline "$deadline" "${docker[@]}" container inspect \
                        --format "$status_format" "$container") &&
                    [[ "$status" == running\ * ]]; then
                    return 0
                fi
                ;;
        esac
        (( SECONDS < deadline )) && sleep 1
    done
    warn "Hermes readiness failed (last container state: ${status:-unknown}; startup deadline: 45s)"
    return 1
}

case ${1:-} in
    build) build ;;
    password)
        [[ -t 0 ]] || fail 'set the Webapp password in a local terminal'
        id=$(image_id)
        state
        if dk container inspect "$name" >/dev/null 2>&1; then
            fail 'stop the Hermes gateway before changing its password'
        fi
        # Fail now, not at the first start, if this kernel cannot isolate workspace sockets.
        bounded 90 "${docker[@]}" run --rm --network none "${common[@]}" "$id" --check-landlock
        # The password prompt reads the terminal; only its hash and signing key persist.
        "${docker[@]}" run --rm -it --network none "${common[@]}" "$id" dashboard password --username hermes
        ;;
    start)
        command -v curl >/dev/null || fail 'curl is required for the Webapp readiness check'
        command -v timeout >/dev/null || fail 'timeout is required for bounded startup and rollback'
        if dk container inspect "$name" >/dev/null 2>&1; then
            fail 'a Hermes container already exists; run make hermes/container/stop first (to update, stop, then start the new image ID)'
        fi
        id=$(image_id)
        src=$(workspace_source)
        state
        check_auth "$id"
        bridge
        warn "Mounting $src read-only at $mountpoint (agent tools can read, but not modify, its files)"
        creating_container=1
        pending_container=$(bounded 45 "${docker[@]}" create "${common[@]}" --name "$name" \
            --label "$invocation_label" --label "$gateway_label" \
            --log-driver local --log-opt max-size=10m --log-opt max-file=3 \
            --network "$name" --publish "$published" \
            --mount "type=bind,source=$src,target=$mountpoint,readonly,bind-recursive=disabled" \
            "$id")
        [[ "$pending_container" =~ ^[0-9a-f]{64}$ ]] || fail 'Docker create did not return a valid container ID'
        deadline=$((SECONDS + 45))
        if ! before_deadline "$deadline" "${docker[@]}" start "$pending_container" >/dev/null ||
            ! wait_ready "$pending_container" "$deadline"; then
            fail 'authenticated Webapp did not become ready; rolling back the new container and retaining its state volume'
        fi
        # Failed startups must not leave a restart-enabled gateway behind.
        if ! bounded 10 "${docker[@]}" update --restart unless-stopped "$pending_container" >/dev/null; then
            fail 'could not enable the restart policy; rolling back the new container'
        fi
        # A fresh short budget: the startup deadline may already be spent by readiness.
        if ! status=$(bounded 10 "${docker[@]}" container inspect --format '{{.State.Status}}' "$pending_container"); then
            fail 'could not confirm the container state after enabling its restart policy; rolling back the new container'
        fi
        [[ "$status" == running ]] || fail "Hermes is $status after enabling its restart policy; rolling back the new container"
        creating_container=0
        say 'Hermes Desktop Webapp: http://127.0.0.1:19120/ - sign in as hermes and open Bots (login and Bot Chat are not verified by start).'
        ;;
    stop)
        if ! value=$(dk container inspect \
            --format "{{.Id}} {{index .Config.Labels \"$label\"}} {{index .Config.Labels \"$label.role\"}}" "$name" 2>/dev/null); then
            listed=$(dk container ls --all --quiet --filter "name=^$name\$") || fail 'could not query the local Docker engine'
            [[ -z "$listed" ]] || fail "could not inspect container $name"
            warn "No Hermes container named $name; nothing to stop"
            exit 0
        fi
        container=${value%% *}
        [[ "$value" == "$container 1 gateway" && "$container" =~ ^[0-9a-f]{64}$ ]] ||
            fail "container $name is not a gateway owned by this launcher"
        bounded 30 "${docker[@]}" stop "$container" >/dev/null
        bounded 10 "${docker[@]}" container rm "$container" >/dev/null
        warn "Stopped and removed container $container; its state volume and bridge were retained"
        ;;
    *) fail 'usage: hermes-container.sh {build|password|start|stop}' ;;
esac
