if [[ -f /etc/NIXOS || -f /etc/nixos/configuration.nix ]]; then
	nixup() {
		kpangoup
		local host="${NIX_HOST_NAME:-$(hostname)}"
		local dotfiles="${DOTFILES_DIR:-$HOME/dotfiles}"
		echo "==> Rebuilding NixOS for host: $host"
		sudo nixos-rebuild switch --flake "${dotfiles}/nix#${host}" --show-trace
	}
	alias up=nixup

	nixtest() {
		local host="${NIX_HOST_NAME:-$(hostname)}"
		local dotfiles="${DOTFILES_DIR:-$HOME/dotfiles}"
		echo "==> Dry-run build for host: $host"
		sudo nixos-rebuild dry-activate --flake "${dotfiles}/nix#${host}" --show-trace
	}

	nixclean() {
		echo "==> Collecting Nix garbage..."
		nix-collect-garbage -d
		sudo nix-collect-garbage -d
		sudo nix store optimise 2>/dev/null || true
	}
	alias ncg=nixclean

	if (($+commands[home-manager])); then
		hmup() {
			local host="${NIX_HOST_NAME:-$(hostname)}"
			local dotfiles="${DOTFILES_DIR:-$HOME/dotfiles}"
			echo "==> Switching home-manager for host: $host"
			home-manager switch --flake "${dotfiles}/nix#${host}"
		}
	fi

	if (($+commands[reboot])); then
		reboot() {
			nixup
			nixclean
			sudo reboot && exit
		}
	fi

	if (($+commands[shutdown])); then
		shutdown() {
			nixup
			nixclean
			sudo shutdown now && exit
		}
	fi
fi
