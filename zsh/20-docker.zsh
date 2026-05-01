case ${OSTYPE} in
darwin*)
	if (($+commands[container])); then
		export DOCKER_BUILDKIT=${DOCKER_BUILDKIT:-1}
		export DOCKER_CLI_EXPERIMENTAL=${DOCKER_CLI_EXPERIMENTAL:-"enabled"}
		alias dls='container ps'
		alias dsh='container run -it '
	fi
	;;
linux*)
	if (($+commands[docker])); then
		export DOCKER_BUILDKIT=${DOCKER_BUILDKIT:-1}
		export DOCKER_CLI_EXPERIMENTAL=${DOCKER_CLI_EXPERIMENTAL:-"enabled"}
		alias dls='docker ps'
		alias dsh='docker run -it '
	fi
	;;
esac

rcpath="$DOTFILES_DIR"

dockerrm() {
	local containers="$(docker ps -aq)"
	if [[ -n "$containers" ]]; then
		docker container stop ${(f)containers}
		docker container rm -f ${(f)containers}
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
		"-v $docker_sock:$docker_sock"
		"-v $HOME/Documents:$container_home/Documents"
		"-v $HOME/Downloads:$container_home/Downloads"
		"-v $HOME/.claude:$container_home/.claude"
		"-v $HOME/.claude.json:$container_home/.claude.json"
		"-v $HOME/.gemini:$container_home/.gemini"
		"-v $HOME/.gnupg:$container_home/.gnupg"
		"-v $HOME/go/src:$container_goroot/src:cached"
		"-v $HOME/.kube:$container_home/.kube"
		"-v $HOME/.local/share/atuin:$container_home/.local/share/atuin:cached"
		"-v $HOME/.talos:$container_home/.talos"
		"-v $HOME/.tmux:$container_home/.tmux"
		"-v $rcpath/atuin/config.toml:$container_atuin/config.toml"
		"-v $rcpath/atuin/themes/zed_kpango.toml:$container_atuin/themes/zed_kpango.toml"
		"-v $rcpath/editorconfig:$container_home/.editorconfig"
		"-v $rcpath/gitattributes:$container_home/.gitattributes"
		"-v $rcpath/.gitignore:$container_home/.gitignore"
		"-v $rcpath/helix/config.toml:$container_helix/config.toml"
		"-v $rcpath/helix/languages.toml:$container_helix/languages.toml"
		"-v $rcpath/helix/themes/zed_kpango.toml:$container_helix/themes/zed_kpango.toml"
		"-v $rcpath/sheldon.toml:$container_config/sheldon/plugins.toml"
		"-v $rcpath/starship.toml:$container_config/starship.toml"
		"-v $rcpath/tmux.conf:$container_home/.tmux.conf"
		"-v $rcpath/tmux-kube:$container_home/.tmux-kube"
		"-v ${XDG_RUNTIME_DIR:-$HOME/.local/run}:$container_home/.local/run"
	)

	case "$OSTYPE" in
	darwin*)
		echo 'Docker on macOS start'
		local docker_daemon="$HOME/Library/Containers/com.docker.helper/Data/.docker/daemon.json"
		local docker_config="$HOME/Library/Containers/com.docker.helper/Data/.docker/config.json"
		local tz_path="/usr/share/zoneinfo/Japan"
		local font_dir="/System/Library/Fonts"

		container run \
			--name $container_name \
			--workdir $container_home \
			${=shared_vols} \
			-v $docker_config:/etc/docker/config.json \
			-v $docker_daemon:/etc/docker/daemon.json \
			-v $font_dir:/usr/share/fonts:ro \
			-v $HOME/.docker/daemon.json:$container_home/.docker/daemon.json \
			-v $HOME/.gitconfig:$container_home/.gitconfig \
			-v $HOME/.netrc:$container_home/.netrc \
			-v $HOME/.ssh:$container_home/.ssh \
			-v $HOME/.zsh_history:$container_home/.zsh_history \
			-v $rcpath/arch/limits.conf:/etc/security/limits.conf \
			-v $rcpath/network/sysctl/sysctl.conf:/etc/sysctl.conf \
			-v $rcpath/zshrc:$container_home/.zshrc \
			-v $rcpath/zshenv:$container_home/.zshenv \
			-v $tz_path:/etc/localtime:ro \
			-dit $image_name
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

		docker run \
			${=gpu_option} \
			--cap-add=ALL \
			--name $container_name \
			--privileged=$privileged \
			--restart always \
			--workdir $container_home \
			--network=host \
			--mount type=bind,source=$resolve_dnsmasq_config,destination=$resolve_config \
			--add-host=host.docker.internal:host-gateway \
			--memory=200G \
			-u "$UID:$GID" \
			${=shared_vols} \
			-v $docker_config:$docker_config:ro,cached \
			-v $docker_daemon:$docker_daemon:ro,cached \
			-v $font_dir:$font_dir \
			-v $HOME/.aws:$container_home/.aws \
			-v $XDG_CONFIG_HOME/gcloud:$container_config/gcloud \
			-v $HOME/.docker:$container_home/.docker \
			-v $HOME/.docker:$container_root/.docker \
			-v $HOME/.gnupg:$container_root/.gnupg \
			-v $HOME/.netrc:$container_home/.netrc:ro \
			-v $HOME/.password-store:$container_home/.password-store \
			-v $HOME/.password-store:$container_root/.password-store \
			-v $HOME/.ssh:$container_home/.ssh:ro \
			-v $HOME/.tig_history:$container_home/.tig_history \
			-v $HOME/.zsh_history:$container_home/.zsh_history:cached \
			-v $rcpath/arch/limits.conf:/etc/security/limits.conf:ro,cached \
			-v $rcpath/gitconfig:$container_home/.gitconfig \
			-v $rcpath/go.env:$container_goroot/go.env:ro \
			-v $rcpath/go.env:$goroot/go.env:ro \
			-v $rcpath/network/sysctl/sysctl.conf:/etc/sysctl.conf:ro,cached \
			-v $rcpath/zshrc:$container_home/.zshrc:ro,cached \
			-v $rcpath/zshenv:$container_home/.zshenv:ro,cached \
			-v $tz_path:/etc/localtime:ro,cached \
			-v /etc/group:/etc/group:ro \
			-v /etc/passwd:/etc/passwd:ro \
			-v /etc/shadow:/etc/shadow:ro \
			-v /mnt:/mnt \
			-v /usr/lib/modules:/lib/modules:ro \
			-dt $image_name
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
		if (($+commands[zsh-patina])); then
			zsh-patina restart
		fi
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
	docker update --restart=no $container_name 2>/dev/null || true
	local containers="$(docker ps -aq)"
	if [[ -n "$containers" ]]; then
		docker container stop ${(f)containers} 2>/dev/null || true
		docker container rm -f ${(f)containers} 2>/dev/null || true
	fi
	docker container prune -f
	if [[ "$OSTYPE" == "linux"* ]]; then
		sudo systemctl restart docker || true
	fi
}

alias devres="devkill && devrun"

alias devref="devkill && dockerrm && sudo systemctl restart docker;devrun"
