case ${OSTYPE} in
darwin*)
	if (($+commands[container])); then
		# `container ps`/`container images` (docker-style names) are NOT recognized by the
		# CLI and hang instead of erroring (confirmed against container CLI 1.2.2) — the
		# real subcommands are `list`/`image`.
		alias dls='container list'
		alias dsh='container run -it '
	fi
	;;
linux*)
	if (($+commands[docker])); then
		alias dls='docker ps'
		alias dsh='docker run -it '
	fi
	;;
esac

rcpath="$DOTFILES_DIR"

dockerrm() {
	case "$OSTYPE" in
	darwin*)
		container stop --all 2>/dev/null
		container delete --all 2>/dev/null
		container image prune --all 2>/dev/null
		container volume prune 2>/dev/null
		;;
	*)
		local -a containers=($(docker ps -aq))
		if [[ ${#containers[@]} -gt 0 ]]; then
			docker container stop "${containers[@]}"
			docker container rm -f "${containers[@]}"
		fi
		docker system prune -a -f --volumes
		;;
	esac
}

zsh_path="/usr/bin/zsh"
user_name="kpango"
container_name="dev"
container_version="nightly"
image_name="$user_name/$container_name:$container_version"

# Standalone Ollama server (model baked in, dockers/ollama.Dockerfile) — runs alongside
# $container_name, not layered into it, so it can be recreated independently. devrun()
# starts all three (dev, ollama, and the laya sidecar defined further below); devkill()
# stops all three. On Linux all three containers use --network=host, so ollama is
# always reachable at 127.0.0.1:11434 from the dev container (and the real host) with no
# extra network setup. On macOS (apple/container) there's no host-network equivalent —
# it lands on apple/container's `default` network instead, reachable from other
# containers on that same network via `ollama.test:11434` (embedded DNS,
# apple/container/docs/networking.md — requires macOS 26+ for container-to-container
# DNS; on macOS 15 use `container inspect ollama` for its IP instead).
ollama_container_name="ollama"
ollama_image_name="$user_name/$ollama_container_name:$container_version"

# Laya sidecar (System-1 judgment backend, model baked in, dockers/laya.Dockerfile) --
# same "runs alongside, not layered into, $container_name" precedent as ollama above.
# LAYA_HOST=127.0.0.1 is baked into the image (laya-serve's own default bind is
# 0.0.0.0, which this deliberately narrows -- CONTEXT.md "ai-env-deepresearch-overhaul"
# addendum I-12), so on Linux (--network=host, same as $container_name) it's reachable
# at 127.0.0.1:$laya_port from both the dev container and the real host. The
# authoritative TYPESAFE_API_URL export now lives in zfunc/_gen_env (baked into
# $ZCACHE_DIR/env.zsh, sourced synchronously before anything deferred runs) --
# this file's own export below is a deliberately harmless, idempotent (`:-`)
# fallback, not the primary source: this file is only reached via combined.zsh,
# which zshrc sources deferred (ZLE-idle) for interactive shells, so anything
# reading TYPESAFE_API_URL early in shell startup would otherwise see it unset.
# Loopback endpoints are exempt from needing TYPESAFE_API_KEY (`agent/scripts/jev/jev_client.py`'s
# own allow-list: an http:// endpoint on 127.0.0.1/localhost/[::1] is sent to without a key --
# see its `evaluate()`, `if not key and not loopback: return None`), so this is safe to export
# unconditionally even when the sidecar isn't currently running (that same client fails closed to
# None on connection refused or any other transport failure, per CONTEXT.md I-3).
laya_container_name="laya"
laya_image_name="$user_name/$laya_container_name:$container_version"
laya_port="${LAYA_PORT:-18765}"
export TYPESAFE_API_URL="${TYPESAFE_API_URL:-http://127.0.0.1:${laya_port}/v1/systemone}"

alias kpmove="cd $rcpath"

# `container build` reads Dockerfile/Containerfile syntax the same way `docker build` does
# (BuildKit-backed, see `container builder start`) — only the binary name changed.
alias kpbuild="kpmove&&container build --pull --file=$rcpath/Dockerfile -t $image_name $rcpath"

# macOS: apple/container's per-invocation `container run`/`container exec` — deliberately
# NOT `container machine` (its persistent-VM sibling). `container machine create` only takes
# --home-mount (the whole $HOME, all-or-nothing) with no per-path mount option at all, so it
# can't reproduce the granular, Linux-parity mount list below; `container run`/`exec` support
# the same `-v`/`--mount`/`-u`/`-w` flags docker does, so this mirrors the Linux branch path
# for path, translating container_home="/home/kpango" the same way instead of syncing the
# entire macOS $HOME in. Same fix as the Linux branch for the pre-existing bug this replaced:
# the old darwin devrun assembled a `container run` command but pulled the image via
# `docker pull` — separate, incompatible local image caches, so the pull never actually fed
# the run. Registry auth also differs from docker (`container` has no credsStore/credHelpers
# support at all, github.com/apple/container#820 — use `container registry login` instead).

# Shared macOS sidecar start/reuse step for the ollama and laya sidecars in the darwin
# branch of devrun() below: running-check -> stale-container removal -> image pull ->
# `container run -d`, with a WARNING (not a hard failure) if the run itself fails. The two
# sidecars differ only in name/image and the parenthesized note on the "Starting ..." line,
# which the caller passes in as <start_note> so each sidecar's echo output stays byte-identical
# to what it was before this was factored out.
_devrun_mac_sidecar() {
	local name="$1" image="$2" start_note="$3"
	if container list --format json 2>/dev/null | grep -q "\"id\"[[:space:]]*:[[:space:]]*\"$name\""; then
		echo "Container '$name' is already running."
		return 0
	fi
	if container inspect "$name" >/dev/null 2>&1; then
		echo "Removing stale container '$name'"
		container delete -f "$name" &>/dev/null || true
	fi
	echo "Pulling image: $image"
	container image pull "$image"
	echo "Starting $name ($start_note)"
	if ! container run -d --name "$name" "$image"; then
		echo "WARNING: failed to start '$name' — continuing without it" >&2
	fi
}

# Shared Linux sidecar prepare step for the ollama and laya sidecars in the linux branch of
# devrun() below: docker-inspect status check -> stale-container removal (with a "(status: X)"
# echo) -> "Pulling image" echo, then `docker pull`. Returns 0 when the caller still needs to run
# `docker run` for the sidecar, 1 when it's already running (nothing left to do). The actual
# `docker run` invocation (GPU flags, env vars, CDI-vs-CPU retry) stays at each call site since
# those differ per sidecar.
_devrun_docker_sidecar_prepare() {
	local name="$1" image="$2"
	# NOT `status` — that's zsh's own read-only special parameter (holds the last command's
	# exit code), so a `local status` here would fail with "read-only variable: status".
	local _status
	_status=$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null)
	if [[ "$_status" == "running" ]]; then
		echo "Container '$name' is already running."
		return 1
	fi
	if [[ -n "$_status" ]]; then
		echo "Removing stale container '$name' (status: $_status)"
		docker container rm -f "$name" &>/dev/null || true
	fi
	echo "Pulling image: $image"
	docker pull "$image"
	return 0
}

devrun() {
	local -a _no_gpu
	zparseopts -D -- -no-gpu=_no_gpu || {
		echo "Usage: devrun [--no-gpu]" >&2
		return 1
	}

	case "$OSTYPE" in
	darwin*)
		if ! (($+commands[container])); then
			echo "ERROR: 'container' not found — is apple/container installed? (nix-darwin: services.containerization)" >&2
			return 1
		fi

		local container_home="/home/kpango"
		local container_goroot="$container_home/go"
		# The image's own baked-in "kpango" user (dockers/env.Dockerfile's `useradd --uid
		# ${USER_ID}`, default 1000) — NOT the macOS host's own $UID:$GID (this Mac's account
		# is 501:20, unrelated to the container's user namespace). Confirmed 2026-08-19: running
		# as the host's 501:20 leaves image-baked rootfs paths owned by uid 1000 (.zcache,
		# likely .cache/.bun/.local/.npm too) unwritable ("permission denied") even though
		# bind-mounted *host* paths remain accessible either way (apple/container's virtiofs
		# share doesn't appear to enforce per-uid checks on those). Matches the Linux branch's
		# *intent* (its host convention already is uid/gid 1000, so "$UID:$GID" there
		# incidentally equals this) without inheriting the macOS host's unrelated numeric ids.
		local container_uid=1000
		local container_gid=1000

		# Start (or confirm) the ollama sidecar before the dev container itself, so it's
		# already reachable by the time devin's shell comes up. Same stale/running check
		# idiom as the dev container below (`container list` running-only, `inspect` any).
		_devrun_mac_sidecar "$ollama_container_name" "$ollama_image_name" \
			"default network — reachable from '$container_name' at ollama.test:11434"

		# Laya sidecar, same stale/running check idiom as ollama above. Known gap: unlike
		# ollama (which binds 0.0.0.0 and is reachable via apple/container's embedded DNS at
		# ollama.test:11434), this image bakes in LAYA_HOST=127.0.0.1 for the security reason
		# documented next to laya_container_name's definition above -- apple/container has no
		# --network=host equivalent, so on macOS the sidecar only answers its own loopback and
		# is NOT reachable from '$container_name'. Left as a known macOS limitation rather than
		# silently weakened, since the task this sidecar was added for treats Linux
		# (--network=host with CDI GPU, below) as the primary target.
		_devrun_mac_sidecar "$laya_container_name" "$laya_image_name" \
			"default network — loopback-only, see comment above"

		# Mirrors the Linux branch's stale-container handling below: `container list`
		# (no --all) only shows running containers, `inspect` succeeds for any state.
		if container list --format json 2>/dev/null | grep -q "\"id\"[[:space:]]*:[[:space:]]*\"$container_name\""; then
			echo "Container '$container_name' is already running. Use 'devin' to enter it."
			return 0
		elif container inspect "$container_name" >/dev/null 2>&1; then
			echo "Removing stale container '$container_name'"
			container delete -f "$container_name" &>/dev/null || true
		fi

		echo "Pulling image: $image_name"
		container image pull "$image_name"

		# Unlike `docker run -v`, `container run -v` does NOT create a missing host-side
		# path — it hard-errors ("path '...' does not exist") and aborts the whole run.
		# Several of these are optional/per-machine (.talos, .aws, .kube, gcloud config,
		# shell histories, ...), so build the -v list defensively: only mount paths that
		# actually exist on this host instead of listing every path unconditionally.
		local -a mount_specs=(
			"/tmp:/tmp"
			"$HOME/Documents:$container_home/Documents"
			"$HOME/Downloads:$container_home/Downloads"
			"$HOME/.claude:$container_home/.claude"
			"$HOME/.claude.json:$container_home/.claude.json"
			"$HOME/.pi:$container_home/.pi"
			# .agy/.gemini/.antigravity/.config/Antigravity/.cache/antigravity/.gnupg (and .password-store below):
			# mounted read-write deliberately, unlike .ssh/:ro/.netrc/:ro further down. Per kpango
			# (repo owner), the devrun container is actually used to run
			# write-side gpg/pass operations, not just read them -- :ro would
			# break that interactive workflow. (This isn't something the
			# scripted code in this repo does itself, so it can't be confirmed
			# by reading this file; it's recorded here as the documented reason
			# for the asymmetry with .ssh/.netrc, not an inferred one.)
			"$HOME/.agy:$container_home/.agy"
			"$HOME/.gemini:$container_home/.gemini"
			"$HOME/.antigravity:$container_home/.antigravity"
			"$HOME/.config/Antigravity:$container_home/.config/Antigravity"
			"$HOME/.cache/antigravity:$container_home/.cache/antigravity"
			"$HOME/.gnupg:$container_home/.gnupg"
			"$HOME/go/src:$container_goroot/src"
			"$HOME/.kube:$container_home/.kube"
			"${XDG_DATA_HOME:-$HOME/.data}/atuin:$container_home/.data/atuin"
			"${XDG_DATA_HOME:-$HOME/.data}/sheldon:$container_home/.data/sheldon"
			"$HOME/.local/share/sheldon:$container_home/.local/share/sheldon"
			"$HOME/.local/share/cipher:$container_home/.local/share/cipher"
			"$HOME/.serena:$container_home/.serena"
			"$HOME/.talos:$container_home/.talos"
			# NOT $HOME/.tmux, unlike the Linux branch below. Confirmed 2026-08-19: this
			# directory holds a *live* tmux-main.sock from the host's own tmux session (same
			# AF_UNIX/virtiofs limitation as the XDG_RUNTIME_DIR mount removed above).
			# zsh/01-tmux.zsh's `[[ -S "$TMUX_SOCK" ]]` check only confirms the path is a
			# socket-type file, not that it's actually connectable — so it skips creating a
			# fresh, working socket and its final `exec tmux ... new-session -A` fails
			# ("Operation not supported"), which — because it's an `exec`, not a plain call —
			# takes the whole login shell (and thus the container's PID 1) down with it.
			# Leaving this unmounted gives the container its own $HOME/.tmux from scratch;
			# the tpm self-install check just below already handles a missing plugins dir.
			"$rcpath/atuin/config.toml:$container_home/.config/atuin/config.toml:ro"
			"$rcpath/atuin/themes/zed_kpango.toml:$container_home/.config/atuin/themes/zed_kpango.toml"
			"$rcpath/editorconfig:$container_home/.editorconfig"
			"$rcpath/gitattributes:$container_home/.gitattributes"
			"$rcpath/.gitignore:$container_home/.gitignore"
			"$rcpath/gitui/key_bindings.ron:$container_home/.config/gitui/key_bindings.ron"
			"$rcpath/gitui/theme.ron:$container_home/.config/gitui/theme.ron"
			"$rcpath/herdr/config.toml:$container_home/.config/herdr/config.toml:ro"
			"$HOME/.config/herdr/sessions:$container_home/.config/herdr/sessions"
			"$rcpath/lumen.json:$container_home/.config/lumen/lumen.config.json"
			"$rcpath/helix/config.toml:$container_home/.config/helix/config.toml"
			"$rcpath/helix/languages.toml:$container_home/.config/helix/languages.toml"
			"$rcpath/helix/themes/zed_kpango.toml:$container_home/.config/helix/themes/zed_kpango.toml"
			"$rcpath/sheldon.toml:$container_home/.config/sheldon/plugins.toml"
			"$rcpath/tmux.conf:$container_home/.tmux.conf"
			"$rcpath/tmux.conf.d:$container_home/.tmux.conf.d"
			# NOT $HOME/.zcache, unlike the Linux branch below: _zcache_eval (zfunc/_zcache_eval)
			# caches *absolute source paths* into $ZCACHE_DIR/*.zsh (e.g. "source
			# $DOTFILES_DIR/zsh/01-tmux.zsh"). On Linux this repo's own host path already equals
			# container_home ($HOME is /home/kpango on both sides), so sharing the cache is a
			# harmless no-op cache hit. On macOS the host path is /Users/<user>/... while
			# container_home is /home/kpango — bind-mounting the host's cache verbatim confirmed
			# (2026-08-19) to fail every _zcache_eval'd source line at container shell startup
			# ("no such file or directory: /Users/yusukekato/...zsh/01-tmux.zsh"). Leaving this
			# unmounted lets the container regenerate its own, container-path-correct cache on
			# first login instead (_zcache_eval already self-heals on a missing cache file).
			# NOT the host's XDG_RUNTIME_DIR (unlike the Linux branch below, which shares it for
			# genuine same-kernel sockets — ssh-agent, gpg-agent, wayland, ...). Confirmed
			# 2026-08-19: this Mac's runtime dir holds a *live* tmux-main.sock from the host's own
			# tmux session; zsh/01-tmux.zsh's `[[ -d "/run/user/$_TMUX_UID" ]]` (docker-detection
			# there checks only /.dockerenv, which apple/container doesn't create) picks that same
			# path and tries to connect through it — but AF_UNIX sockets don't work across the
			# virtiofs share backing this bind mount, failing with "Operation not supported" and
			# taking the whole container down with it (the failed connect wasn't guarded). Leaving
			# this unmounted makes 01-tmux.zsh's own `-d` check see no dir and fall back to
			# $HOME/.tmux/tmux-main.sock — a socket purely inside the container's own filesystem,
			# not shared across the VM boundary, which is unaffected by this limitation.
			"$HOME/.aws:$container_home/.aws"
			"${XDG_CONFIG_HOME:-$HOME/.config}/gcloud:$container_home/.config/gcloud"
			"$HOME/.netrc:$container_home/.netrc:ro"
			"$HOME/.password-store:$container_home/.password-store"
			"$HOME/.ssh:$container_home/.ssh:ro"
			"$HOME/.tig_history:$container_home/.tig_history"
			"$HOME/.zsh_history:$container_home/.zsh_history"
			"$rcpath/gitconfig:$container_home/.gitconfig"
			"$rcpath/go.env:$container_goroot/go.env:ro"
		)
		local -a vol_args=()
		local _spec _host
		for _spec in "${mount_specs[@]}"; do
			_host="${_spec%%:*}"
			if [[ -e "$_host" ]]; then
				vol_args+=(-v "$_spec")
			else
				echo "  skipping mount (host path missing): $_host" >&2
			fi
		done

		local -a run_cmd=(
			container run
			--cap-add=ALL
			--name $container_name
			--workdir $container_home
			-u "$container_uid:$container_gid"
			# $container_home/.local/run, NOT /run/user/$container_uid like the Linux branch
			# below: zshenv's own OS-conditional default *also* picks /run/user/$UID for any
			# linux-classified shell (this VM's guest OS genuinely is linux, regardless of the
			# macOS host underneath) — since real Linux hosts have systemd-logind create+own
			# that path, but this minimal VM doesn't run one, and /run itself is root-owned.
			# Confirmed 2026-08-19: leaving XDG_RUNTIME_DIR unset here doesn't help (zshenv's own
			# fallback still lands on the same unwritable /run/user/1000) — it has to be pinned
			# explicitly to a path the container_uid actually owns, same as zshenv's *darwin*
			# default would give a real Mac ($HOME/.local/run, here under container_home).
			-e XDG_RUNTIME_DIR=$container_home/.local/run
			-e XDG_DATA_HOME=$container_home/.data
			"${vol_args[@]}"
			-dit $image_name
		)

		echo "Running:"
		echo "  ${run_cmd[*]}"
		if ! "${run_cmd[@]}"; then
			echo "ERROR: failed to start container $container_name" >&2
			echo "  hint: 'container system start' must succeed first (run it from a real Terminal —" >&2
			echo "        it needs an interactive macOS session, not a headless/CI-style shell)." >&2
			return 1
		fi
		# Best-effort: devin below still runs either way (a partially-configured
		# container is more useful than none), but surface the failure instead
		# of silently leaving symlinks/ownership unset.
		if ! container exec -u 0 $container_name sh -c \
			"ln -sfvn $container_goroot/src/github.com/kpango/dotfiles/zshrc $container_home/.zshrc && \
			 ln -sfvn $container_goroot/src/github.com/kpango/dotfiles/zshenv $container_home/.zshenv"; then
			echo "WARNING: failed to symlink zshrc/zshenv into container" >&2
		elif ! container exec -u 0 $container_name \
			chown "$container_uid:$container_gid" \
			"$container_home" \
			"$container_home/.antigravity" \
			"$container_home/.config" \
			"$container_home/.config/Antigravity" \
			"$container_home/.config/atuin" \
			"$container_home/.config/gitui" \
			"$container_home/.config/helix" \
			"$container_home/.config/herdr" \
			"$container_home/.config/lumen" \
			"$container_home/.config/sheldon" \
			"$container_home/.pi" 2>/dev/null; then
			echo "WARNING: failed to chown container config dirs" >&2
		fi
		devin
		;;

	linux*)
		echo 'Docker on Linux start'
		local docker_daemon="/etc/docker/daemon.json"
		local docker_config="/etc/docker/config.json"
		local tz_path="/etc/localtime"
		local font_dir="/usr/share/fonts"
		local resolve_config="/etc/resolv.conf"
		local resolve_dnsmasq_config="/etc/resolv.dnsmasq.conf"
		local gpu_option=""
		local container_home="/home/kpango"
		local container_goroot="$container_home/go"

		if [[ ${#_no_gpu} -eq 0 ]] && (($+commands[nvidia-smi])) && nvidia-smi &>/dev/null; then
			gpu_option="--gpus=all"
		fi

		# Start (or confirm) the ollama sidecar before the dev container's own stale-check/
		# early-return below, so it comes up (or is reconfirmed) every devrun call regardless
		# of whether the dev container itself was already running. --network=host (same as
		# the dev container's run_cmd further down) means no extra network wiring is needed —
		# it's reachable at 127.0.0.1:11434 from inside the dev container and the real host.
		if _devrun_docker_sidecar_prepare "$ollama_container_name" "$ollama_image_name"; then
			echo "Starting $ollama_container_name (network=host)"
			if ! docker run -d \
				$gpu_option \
				--name "$ollama_container_name" \
				--restart always \
				--network=host \
				"$ollama_image_name"; then
				echo "WARNING: failed to start '$ollama_container_name' — continuing without it" >&2
			fi
		fi

		# Start (or confirm) the laya sidecar (System-1 judgment backend, dockers/laya.Dockerfile),
		# same stale/running-check idiom as ollama above. --network=host makes it reachable at
		# 127.0.0.1:$laya_port (baked-in LAYA_HOST=127.0.0.1) from both the dev container and the
		# real host, same as ollama. GPU is passed via CDI (`--device nvidia.com/gpu=all`), not
		# `--gpus=all` (ollama's mechanism) — this host's CDI device is confirmed present via
		# `docker info` as `nvidia.com/gpu=all`/`nvidia.com/gpu=0`. Reuses the same $gpu_option
		# nvidia-smi probe above (and --no-gpu) rather than a second detection pass; a non-empty
		# $gpu_option means a GPU was found, so CDI is attempted, with a CPU retry if the CDI
		# device turns out not to be registered (e.g. nvidia-smi present but the CDI spec wasn't
		# generated) so a GPU-detection false positive never blocks the sidecar from starting.
		local -a laya_gpu_opt=()
		local laya_device="cpu"
		if [[ -n "$gpu_option" ]]; then
			laya_gpu_opt=(--device nvidia.com/gpu=all)
			laya_device="cuda"
		fi
		if _devrun_docker_sidecar_prepare "$laya_container_name" "$laya_image_name"; then
			echo "Starting $laya_container_name (network=host, device=$laya_device)"
			if ! docker run -d \
				"${laya_gpu_opt[@]}" \
				--name "$laya_container_name" \
				--restart always \
				--network=host \
				-e LAYA_DEVICE="$laya_device" \
				-e LAYA_PORT="$laya_port" \
				"$laya_image_name"; then
				if [[ ${#laya_gpu_opt[@]} -gt 0 ]]; then
					echo "WARNING: failed to start '$laya_container_name' with CDI GPU (nvidia.com/gpu=all) — retrying on CPU" >&2
					docker container rm -f "$laya_container_name" &>/dev/null || true
					if ! docker run -d \
						--name "$laya_container_name" \
						--restart always \
						--network=host \
						-e LAYA_DEVICE=cpu \
						-e LAYA_PORT="$laya_port" \
						"$laya_image_name"; then
						echo "WARNING: failed to start '$laya_container_name' — continuing without it" >&2
					fi
				else
					echo "WARNING: failed to start '$laya_container_name' — continuing without it" >&2
				fi
			fi
		fi

		# Remove any stale container (created/exited/dead) to avoid "name already in use" on retry.
		# Happens after: driver update mid-session, failed GPU mount, or interrupted devrun.
		local _existing_status
		_existing_status=$(docker inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null)
		if [[ "$_existing_status" == "running" ]]; then
			echo "Container '$container_name' is already running. Use 'devin' to enter it."
			return 0
		elif [[ -n "$_existing_status" ]]; then
			echo "Removing stale container '$container_name' (status: $_existing_status)"
			docker container rm -f "$container_name" &>/dev/null || true
		fi

		# Build mount list defensively: mount optional host paths only if they exist on the host,
		# avoiding docker creating missing paths as root:root on the host filesystem.
		local -a mount_specs=(
			"/tmp:/tmp"
			"/var/run/docker.sock:/var/run/docker.sock"
			"$HOME/Documents:$container_home/Documents"
			"$HOME/Downloads:$container_home/Downloads"
			"$HOME/.claude:$container_home/.claude"
			"$HOME/.claude.json:$container_home/.claude.json"
			"$HOME/.pi:$container_home/.pi"
			# .agy/.gemini/.antigravity/.config/Antigravity/.cache/antigravity/.gnupg/.password-store:
			# deliberately read-write, see the matching comment in the macOS mount_specs above.
			"$HOME/.agy:$container_home/.agy"
			"$HOME/.gemini:$container_home/.gemini"
			"$HOME/.antigravity:$container_home/.antigravity"
			"$HOME/.config/Antigravity:$container_home/.config/Antigravity"
			"$HOME/.cache/antigravity:$container_home/.cache/antigravity"
			"$HOME/.gnupg:$container_home/.gnupg"
			"$HOME/go/src:$container_goroot/src:cached"
			"$HOME/.kube:$container_home/.kube"
			"${XDG_DATA_HOME:-$HOME/.data}/atuin:$container_home/.data/atuin"
			"${XDG_DATA_HOME:-$HOME/.data}/sheldon:$container_home/.data/sheldon:cached"
			"$HOME/.local/share/sheldon:$container_home/.local/share/sheldon:cached"
			"$HOME/.local/share/cipher:$container_home/.local/share/cipher"
			"$HOME/.serena:$container_home/.serena"
			"$HOME/.talos:$container_home/.talos"
			"$HOME/.tmux:$container_home/.tmux"
			"$rcpath/atuin/config.toml:$container_home/.config/atuin/config.toml:ro"
			"$rcpath/atuin/themes/zed_kpango.toml:$container_home/.config/atuin/themes/zed_kpango.toml"
			"$rcpath/editorconfig:$container_home/.editorconfig"
			"$rcpath/gitattributes:$container_home/.gitattributes"
			"$rcpath/.gitignore:$container_home/.gitignore"
			"$rcpath/gitui/key_bindings.ron:$container_home/.config/gitui/key_bindings.ron"
			"$rcpath/gitui/theme.ron:$container_home/.config/gitui/theme.ron"
			"$rcpath/herdr/config.toml:$container_home/.config/herdr/config.toml:ro"
			"$HOME/.config/herdr/sessions:$container_home/.config/herdr/sessions"
			"$rcpath/lumen.json:$container_home/.config/lumen/lumen.config.json"
			"$rcpath/helix/config.toml:$container_home/.config/helix/config.toml"
			"$rcpath/helix/languages.toml:$container_home/.config/helix/languages.toml"
			"$rcpath/helix/themes/zed_kpango.toml:$container_home/.config/helix/themes/zed_kpango.toml"
			"$rcpath/sheldon.toml:$container_home/.config/sheldon/plugins.toml"
			"$rcpath/tmux.conf:$container_home/.tmux.conf"
			"$rcpath/tmux.conf.d:$container_home/.tmux.conf.d"
			"$HOME/.zcache:$container_home/.zcache"
			"${XDG_RUNTIME_DIR:-/run/user/$UID}:/run/user/$UID"
			"$docker_config:$docker_config:ro,cached"
			"$docker_daemon:$docker_daemon:ro,cached"
			"$font_dir:$font_dir"
			"$HOME/.aws:$container_home/.aws"
			"${XDG_CONFIG_HOME:-$HOME/.config}/gcloud:$container_home/.config/gcloud"
			"$HOME/.docker:$container_home/.docker"
			"$HOME/.docker:/root/.docker"
			"$HOME/.gnupg:/root/.gnupg"
			"$HOME/.netrc:$container_home/.netrc:ro"
			"$HOME/.password-store:$container_home/.password-store"
			"$HOME/.password-store:/root/.password-store"
			"$HOME/.agy:/root/.agy"
			"$HOME/.gemini:/root/.gemini"
			"$HOME/.antigravity:/root/.antigravity"
			"$HOME/.claude:/root/.claude"
			"$HOME/.pi:/root/.pi"
			"$HOME/.ssh:$container_home/.ssh:ro"
			"$HOME/.tig_history:$container_home/.tig_history"
			"$HOME/.zsh_history:$container_home/.zsh_history"
			"$rcpath/arch/limits.conf:/etc/security/limits.conf:ro,cached"
			"$rcpath/gitconfig:$container_home/.gitconfig"
			"$rcpath/go.env:$container_goroot/go.env:ro"
			"$rcpath/go.env:/usr/local/go/go.env:ro"
			"$rcpath/network/sysctl/sysctl.conf:/etc/sysctl.conf:ro,cached"
			"$tz_path:/etc/localtime:ro,cached"
			"/etc/group:/etc/group:ro"
			"/etc/passwd:/etc/passwd:ro"
			"/mnt:/mnt"
			"/usr/lib/modules:/lib/modules:ro"
		)
		local -a vol_args=()
		local _spec _host
		for _spec in "${mount_specs[@]}"; do
			_host="${_spec%%:*}"
			if [[ -e "$_host" ]]; then
				vol_args+=(-v "$_spec")
			fi
		done

		local -a run_cmd=(
			docker run
			$gpu_option
			--cap-add=ALL
			--name $container_name
			--privileged=true
			--security-opt no-new-privileges=false
			--restart always
			--workdir $container_home
			--network=host
			--pull=never
			--mount type=bind,source=$resolve_dnsmasq_config,destination=$resolve_config
			--add-host=host.docker.internal:host-gateway
			--memory=200G
			-e XDG_RUNTIME_DIR=/run/user/$UID
			-e DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID/bus
			-e XDG_DATA_HOME=$container_home/.data
			-u "$UID:$GID"
			"${vol_args[@]}"
			-dt $image_name
		)

		echo "Pulling image: $image_name"
		docker pull "$image_name"
		echo "Running:"
		local -a _dargs=("${run_cmd[@]:2}")
		local _di _dw=0
		for ((_di = 1; _di <= $#_dargs; _di += 2)); do
			((${#_dargs[$_di]} > _dw)) && _dw=${#_dargs[$_di]}
		done
		((_dw += 3))
		((_dw > 55)) && _dw=55
		printf '  %s %s' "${run_cmd[1]}" "${run_cmd[2]}"
		for ((_di = 1; _di <= $#_dargs; _di += 2)); do
			if ((_di < $#_dargs)); then
				printf ' \\\n    %-*s %s' "$_dw" "${_dargs[$_di]}" "${_dargs[$((_di+1))]}"
			else
				printf ' \\\n    %s' "${_dargs[$_di]}"
			fi
		done
		printf '\n'
		if ! "${run_cmd[@]}"; then
			echo "ERROR: failed to start container $container_name" >&2
			echo "  docker version: $(docker version --format '{{.Server.Version}}' 2>/dev/null)" >&2
			echo "  containerd version: $(docker version --format '{{.Server.Components}}' 2>/dev/null | rg -o 'containerd [0-9.]*' || true)" >&2
			echo "  hint: if 'unsupported protocol: Yunix' appears in journalctl -u docker," >&2
			echo "        ensure /etc/containerd/config.toml sets socket_dir under [plugins.'io.containerd.shim.v1.manager']" >&2
			echo "        run: sudo make dotfiles/install && sudo systemctl restart containerd docker" >&2
			if (($+commands[nvidia-smi])) && ! nvidia-smi &>/dev/null; then
				echo "  hint: nvidia-smi failed — GPU driver/kernel version mismatch detected." >&2
				echo "        reboot to reload the kernel module, then run 'devrun' again for full GPU support." >&2
			fi
			return 1
		fi
		docker exec -u 0 $container_name bash -c \
			"ln -sfvn $container_goroot/src/github.com/kpango/dotfiles/zshrc $container_home/.zshrc && \
			 ln -sfvn $container_goroot/src/github.com/kpango/dotfiles/zshenv $container_home/.zshenv" &&
			docker exec -u 0 $container_name \
				chown "$UID:$GID" \
				"$container_home" \
				"$container_home/.antigravity" \
				"$container_home/.bun" \
				"$container_home/.cache" \
				"$container_home/.config" \
				"$container_home/.config/Antigravity" \
				"$container_home/.config/atuin" \
				"$container_home/.config/gitui" \
				"$container_home/.config/helix" \
				"$container_home/.config/herdr" \
				"$container_home/.config/lumen" \
				"$container_home/.config/sheldon" \
				"$container_home/.local" \
				"$container_home/.local/share" \
				"$container_home/.npm" \
				"$container_home/.pi" 2>/dev/null || true
		docker exec -u "$UID" $container_name \
			sh -c 'atuin daemon status 2>/dev/null \
				&& echo "atuin: daemon reachable from container (real-time history sync active)" \
				|| echo "WARNING: atuin daemon socket not reachable — container history will not sync in real-time" >&2' || true
		;;

	CYGWIN* | MINGW32* | MSYS*)
		echo 'MS Windows is not ready for this environment'
		;;

	*)
		echo 'other OS'
		;;
	esac
}

_ts_ssh() {
	tailscale down
	tailscale up --reset --accept-routes
	ssh "$1" -v
}

devin() {
	if [[ -f /.dockerenv ]] || [[ "$(cat /proc/1/cgroup 2>/dev/null)" == *"docker"* ]] || [[ "$(cat /proc/1/cgroup 2>/dev/null)" == *"containerd"* ]]; then
		cd "${GOPATH:-$HOME/go}/src/github.com/vdaas/vald" || return 1
		return 0
	fi

	case "$OSTYPE" in
	darwin*)
		local _status
		_status=$( (($+commands[container])) && container inspect "$container_name" 2>/dev/null | grep -o '"state"[^,}]*' | head -1)
		if [[ "$_status" == *running* ]]; then
			container exec -it $container_name $zsh_path
		else
			echo "ERROR: container '$container_name' is not running (status: ${_status:-not found})" >&2
			echo "  run 'devres' to recreate, or 'devrun' if it was never created." >&2
			return 1
		fi
		;;
	linux*)
		if command -v zsh-patina &>/dev/null; then
			zsh-patina restart
		fi
		local _status
		_status=$(docker inspect --format '{{.State.Status}}' $container_name 2>/dev/null)
		if [[ "$_status" != "running" ]]; then
			echo "ERROR: container '$container_name' is not running (status: ${_status:-not found})" >&2
			echo "  run 'devres' to recreate, or check: journalctl -u docker -n 20" >&2
			return 1
		fi
		# No -e TMUX: each exec starts its own tmux nested in the host's (zsh/01-tmux.zsh).
		docker exec -it $container_name $zsh_path
		;;
	CYGWIN* | MINGW32* | MSYS*)
		echo 'MS Windows Dev Environment is not ready for this environment'
		;;
	*)
		echo 'other OS'
		;;
	esac
}

udmin() {
	_ts_ssh udmpro
}

udrin() {
	_ts_ssh udr
}

alias udr=udrin

devkill() {
	case "$OSTYPE" in
	darwin*)
		if (($+commands[container])); then
			container stop "$container_name" 2>/dev/null || true
			container delete -f "$container_name" 2>/dev/null || true
			container stop "$ollama_container_name" 2>/dev/null || true
			container delete -f "$ollama_container_name" 2>/dev/null || true
			container stop "$laya_container_name" 2>/dev/null || true
			container delete -f "$laya_container_name" 2>/dev/null || true
		fi
		;;
	*)
		docker update --restart=no $container_name 2>/dev/null || true
		local -a containers=($(docker ps -aq))
		if [[ ${#containers[@]} -gt 0 ]]; then
			docker container stop "${containers[@]}" 2>/dev/null || true
			docker container rm -f "${containers[@]}" 2>/dev/null || true
		fi
		docker container prune -f
		if [[ "$OSTYPE" == "linux"* ]]; then
			sudo systemctl restart docker || true
		fi
		;;
	esac
}

alias devres="devkill && devrun"

alias devref="devkill && dockerrm && [[ \$OSTYPE == linux* ]] && sudo systemctl restart docker;devrun"
