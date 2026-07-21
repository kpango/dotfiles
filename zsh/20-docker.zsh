case ${OSTYPE} in
darwin*)
	if (($+commands[container])); then
		alias dls='container ps'
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
	local -a containers=($(docker ps -aq))
	if [[ ${#containers[@]} -gt 0 ]]; then
		docker container stop "${containers[@]}"
		docker container rm -f "${containers[@]}"
	fi
	docker system prune -a -f --volumes
}

zsh_path="/usr/bin/zsh"
user_name="kpango"
container_name="dev"
container_version="nightly"
image_name="$user_name/$container_name:$container_version"

alias kpmove="cd $rcpath"

alias kpbuild="kpmove&&docker build --pull=true --file=$rcpath/Dockerfile -t $image_name $rcpath"

devrun() {
	port_range="8000-9300"
	privileged=true
	container_home="/home/kpango"
	container_root="/root"
	container_goroot="$container_home/go"
	container_config="$container_home/.config"
	container_atuin="$container_config/atuin"
	container_helix="$container_config/helix"
	goroot="/usr/local/go"
	docker_sock="/var/run/docker.sock"

	# Define base shared volumes applicable to both environments
	local -a shared_vols=(
		-v "/tmp:/tmp"
		-v "$docker_sock:$docker_sock"
		-v "$HOME/Documents:$container_home/Documents"
		-v "$HOME/Downloads:$container_home/Downloads"
		-v "$HOME/.claude:$container_home/.claude"
		-v "$HOME/.claude.json:$container_home/.claude.json"
		-v "$HOME/.gemini:$container_home/.gemini"
		-v "$HOME/.gnupg:$container_home/.gnupg"
		-v "$HOME/go/src:$container_goroot/src:cached"
		-v "$HOME/.kube:$container_home/.kube"
		# rw, no consistency flag (= :consistent): atuin's search/TUI and `atuin status` open
		# history.db read-write directly (not via the daemon socket), so :ro caused SQLITE_CANTOPEN
		# and broke Ctrl-R. Real-time host<->container sync: container `atuin history end` reaches the
		# HOST daemon over the shared socket (XDG_RUNTIME_DIR mount below) — single writer — while both
		# sides read the same WAL-mode db (same inode), so search sees the daemon's writes at once.
		# Do NOT use :cached/:delegated here: on macOS they relax cache coherence and risk corrupting
		# a concurrently-written db. (Daemon must run on the host; container has no systemd user bus.)
		-v "${XDG_DATA_HOME:-$HOME/.data}/atuin:$container_home/.data/atuin"
		-v "${XDG_DATA_HOME:-$HOME/.data}/sheldon:$container_home/.data/sheldon:cached"
		-v "$HOME/.local/share/sheldon:$container_home/.local/share/sheldon:cached"
		-v "$HOME/.talos:$container_home/.talos"
		-v "$HOME/.tmux:$container_home/.tmux"
		-v "$rcpath/atuin/config.toml:$container_atuin/config.toml:ro"
		-v "$rcpath/atuin/themes/zed_kpango.toml:$container_atuin/themes/zed_kpango.toml"
		-v "$rcpath/editorconfig:$container_home/.editorconfig"
		-v "$rcpath/gitattributes:$container_home/.gitattributes"
		-v "$rcpath/.gitignore:$container_home/.gitignore"
		-v "$rcpath/gitui/key_bindings.ron:$container_config/gitui/key_bindings.ron"
		-v "$rcpath/gitui/theme.ron:$container_config/gitui/theme.ron"
		-v "$rcpath/herdr/config.toml:$container_config/herdr/config.toml:ro"
		# Mount herdr session sockets so Docker-side herdr CLI can reach the host server.
		-v "$HOME/.config/herdr/sessions:$container_home/.config/herdr/sessions"
		-v "$rcpath/lumen.json:$container_config/lumen/lumen.config.json"
		-v "$rcpath/helix/config.toml:$container_helix/config.toml"
		-v "$rcpath/helix/languages.toml:$container_helix/languages.toml"
		-v "$rcpath/helix/themes/zed_kpango.toml:$container_helix/themes/zed_kpango.toml"
		-v "$rcpath/sheldon.toml:$container_config/sheldon/plugins.toml"
		-v "$rcpath/tmux.conf:$container_home/.tmux.conf"
		-v "$rcpath/tmux.conf.d:$container_home/.tmux.conf.d"
		-v "$HOME/.zcache:$container_home/.zcache"
		-v "${XDG_RUNTIME_DIR:-/run/user/$UID}:/run/user/$UID"
	)

	case "$OSTYPE" in
	darwin*)
		echo 'Docker on macOS start'
		local docker_daemon="$HOME/Library/Containers/com.docker.helper/Data/.docker/daemon.json"
		local docker_config="$HOME/Library/Containers/com.docker.helper/Data/.docker/config.json"
		local tz_path="/usr/share/zoneinfo/Japan"
		local font_dir="/System/Library/Fonts"

		local -a mac_cmd=(
			container run
			--name $container_name
			--workdir $container_home
			-e XDG_RUNTIME_DIR=/run/user/$UID
			-e XDG_DATA_HOME=$container_home/.data
			"${shared_vols[@]}"
			-v $docker_config:/etc/docker/config.json
			-v $docker_daemon:/etc/docker/daemon.json
			-v $font_dir:/usr/share/fonts:ro
			-v $HOME/.docker/daemon.json:$container_home/.docker/daemon.json
			-v $HOME/.gitconfig:$container_home/.gitconfig
			-v $HOME/.netrc:$container_home/.netrc
			-v $HOME/.ssh:$container_home/.ssh
			-v $HOME/.zsh_history:$container_home/.zsh_history
			-v $rcpath/arch/limits.conf:/etc/security/limits.conf
			-v $rcpath/network/sysctl/sysctl.conf:/etc/sysctl.conf
			-v $tz_path:/etc/localtime:ro
			-dit $image_name
		)
		echo "Pulling image: $image_name"
		docker pull "$image_name"
		echo "Running:"
		local -a _dargs=("${mac_cmd[@]:2}")
		local _di _dw=0
		for ((_di = 1; _di <= $#_dargs; _di += 2)); do
			((${#_dargs[$_di]} > _dw)) && _dw=${#_dargs[$_di]}
		done
		((_dw += 3))
		((_dw > 55)) && _dw=55
		printf '  %s %s' "${mac_cmd[1]}" "${mac_cmd[2]}"
		for ((_di = 1; _di <= $#_dargs; _di += 2)); do
			if ((_di < $#_dargs)); then
				printf ' \\\n    %-*s %s' "$_dw" "${_dargs[$_di]}" "${_dargs[$((_di+1))]}"
			else
				printf ' \\\n    %s' "${_dargs[$_di]}"
			fi
		done
		printf '\n'
		"${mac_cmd[@]}"
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

		if (($+commands[nvidia-smi])) && nvidia-smi &>/dev/null; then
			gpu_option="--gpus=all"
		fi

		local -a run_cmd=(
			docker run
			$gpu_option
			--cap-add=ALL
			--name $container_name
			--privileged=$privileged
			--security-opt no-new-privileges=false
			--restart always
			--workdir $container_home
			--network=host
			--pull=never
			--mount type=bind,source=$resolve_dnsmasq_config,destination=$resolve_config
			--add-host=host.docker.internal:host-gateway
			--memory=200G
			-e XDG_RUNTIME_DIR=/run/user/$UID
			-e XDG_DATA_HOME=$container_home/.data
			-u "$UID:$GID"
			"${shared_vols[@]}"
			-v $docker_config:$docker_config:ro,cached
			-v $docker_daemon:$docker_daemon:ro,cached
			-v $font_dir:$font_dir
			-v $HOME/.aws:$container_home/.aws
			-v ${XDG_CONFIG_HOME:-$HOME/.config}/gcloud:$container_config/gcloud
			-v $HOME/.docker:$container_home/.docker
			-v $HOME/.docker:$container_root/.docker
			-v $HOME/.gnupg:$container_root/.gnupg
			-v $HOME/.netrc:$container_home/.netrc:ro
			-v $HOME/.password-store:$container_home/.password-store
			-v $HOME/.password-store:$container_root/.password-store
			-v $HOME/.ssh:$container_home/.ssh:ro
			-v $HOME/.tig_history:$container_home/.tig_history
			-v $HOME/.zsh_history:$container_home/.zsh_history
			-v $rcpath/arch/limits.conf:/etc/security/limits.conf:ro,cached
			-v $rcpath/gitconfig:$container_home/.gitconfig
			-v $rcpath/go.env:$container_goroot/go.env:ro
			-v $rcpath/go.env:$goroot/go.env:ro
			-v $rcpath/network/sysctl/sysctl.conf:/etc/sysctl.conf:ro,cached
			-v $tz_path:/etc/localtime:ro,cached
			-v /etc/group:/etc/group:ro
			-v /etc/passwd:/etc/passwd:ro
			-v /mnt:/mnt
			-v /usr/lib/modules:/lib/modules:ro
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
			return 1
		fi
		docker exec -u 0 $container_name bash -c \
			"ln -sfvn $container_goroot/src/github.com/kpango/dotfiles/zshrc $container_home/.zshrc && \
			 ln -sfvn $container_goroot/src/github.com/kpango/dotfiles/zshenv $container_home/.zshenv" &&
			docker exec -u 0 $container_name \
				chown "$UID:$GID" \
				"$container_home" \
				"$container_home/.bun" \
				"$container_home/.cache" \
				"$container_home/.config" \
				"$container_home/.config/atuin" \
				"$container_home/.config/gitui" \
				"$container_home/.config/helix" \
				"$container_home/.config/herdr" \
				"$container_home/.config/lumen" \
				"$container_home/.config/sheldon" \
				"$container_home/.local" \
				"$container_home/.local/share" \
				"$container_home/.npm" 2>/dev/null || true
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
		_ts_ssh tr
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
		docker exec -it ${TMUX:+-e TMUX="$TMUX"} $container_name $zsh_path
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
}

alias devres="devkill && devrun"

alias devref="devkill && dockerrm && sudo systemctl restart docker;devrun"
