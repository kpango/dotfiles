if (($+commands[compton])); then
	comprestart() {
		sudo pkill compton
		compton --config $HOME/.config/compton/compton.conf --xrender-sync-fence -cb
	}
	alias comprestart=comprestart
fi
if (($+commands[fwupdmgr])); then
	fup() {
		sudo systemctl reload dbus.service
		sudo systemctl restart fwupd.service
		sudo lsusb
		sudo fwupdtool get-devices
		sudo fwupdtool clear-history
		sudo fwupdtool clear-offline
		sudo fwupdtool refresh --force
		sudo fwupdtool get-updates --force
		sudo fwupdtool get-upgrades --force
		sudo fwupdtool update
	}
	alias fup=fup
fi
update_git_repo() {
	local repo_dir=$1
	if [ -d "$repo_dir" ]; then
		pushd "$repo_dir" >/dev/null || return
		#if git diff-index --quiet HEAD -- && [ -z "$(git status --porcelain | grep '^[^ ]')" ]; then
		if git diff-index --quiet HEAD -- && [ -z "$(git diff --ignore-space-change --ignore-blank-lines --diff-filter=MARC)" ]; then
			echo "No local changes in $repo_dir, pulling latest changes from origin..."
			gfrs
		else
			echo "Local changes detected in $repo_dir, not pulling from origin. Here are the changes:"
			git status
			git diff --name-only
			echo "Detailed changes:"
			git diff
		fi
		popd >/dev/null || return
	else
		echo "Directory $repo_dir does not exist." >&2
	fi
}

update_multiple_git_repos() {
	local repos=("$@")
	for repo in "${repos[@]}"; do
		update_git_repo "$repo"
	done
}

kpangoup() {
	update_multiple_git_repos \
		"$GOPATH/src/github.com/kpango/dotfiles" \
		"$GOPATH/src/github.com/kpango/pass" \
		"$GOPATH/src/github.com/kpango/wallpapers" \
		"$GOPATH/src/github.com/vdaas/vald" \
		"$GOPATH/src/github.com/vdaas/vald-client-go"
}
alias kpangoup=kpangoup
if (($+commands[brew])); then
	brewup() {
		kpangoup
		cd $(brew --prefix)/Homebrew
		gfr
		git config --local pull.ff only
		git fetch origin
		git reset --hard origin/master
		cd -
		brew cleanup
		brew update
		brew upgrade
		brew cleanup
		brew doctor
		softwareupdate --all --install --force
		sudo pmset -a hibernatemode 0
		sudo rm -rf /private/var/vm/sleepimage
		sudo touch /private/var/vm/sleepimage
		sudo chmod 000 /private/var/vm/sleepimage
		# sudo pmset -a hibernatemode 3
		# sudo rm /private/var/vm/sleepimage
		sudo rm -rf /System/Library/Speech/Voices/*
		sudo rm -rf /private/var/log/*
		sudo rm -rf /private/var/folders/
		sudo rm -rf /usr/share/emacs/
		sudo rm -rf /private/var/tmp/TM*
		sudo rm -rf $HOME/Library/Caches/*
		sudo rm -rf /private/tmp/junk
		purge
	}
	alias brewup=brewup
	alias up=brewup
elif (($+commands[pacman])); then
	GCC=${commands[gcc]}
	GXX=${commands[g++]}
	GCPP="$GCC -E"
	run_command() {
		local desc="$1"
		shift

		echo "==> $desc"
		if ! "$@"; then
			echo "ERROR: $desc failed (exit code $?)"
			return 1
		fi
		return 0
	}

	try_package_manager() {
		local manager=$1
		shift
		if (($+commands[$manager])); then
			echo "Trying with $manager..."
			if run_command "executing $manager" $manager "$@"; then
				return 0
			fi
			echo "$manager failed, trying to ignore unnecessary packages."
			if run_command "executing $manager (ignore mozc)" $manager "$@" --ignore mozc-ut-full-common --ignore fcitx5-mozc-ut-full; then
				return 0
			fi
			echo "$manager with ignoreing unnecessary package failed, trying with gcc/g++ environment variables set."
			if CC=$GCC CXX=$GXX CPP=$GCPP run_command "executing $manager (with gcc env)" $manager "$@"; then
				return 0
			fi
			echo "$manager with gcc/g++ environment variables failed, trying to ignore unnecessary packages with gcc/g++ environment."
			if CC=$GCC CXX=$GXX CPP=$GCPP run_command "executing $manager (with gcc env + ignore mozc)" $manager "$@" --ignore mozc-ut-full-common --ignore fcitx5-mozc-ut-full; then
				return 0
			fi
			echo "$manager failed."
		else
			echo "$manager is not installed."
		fi
		return 1
	}

	kacman() {
		if try_package_manager paru "$@"; then return 0; fi
		if try_package_manager pakku "$@"; then return 0; fi
		if try_package_manager yay "$@"; then return 0; fi
		if try_package_manager "sudo pacman" "$@"; then return 0; fi
		echo "Failed to execute the command with option '$@' with all package managers."
		return 1
	}
	kacclean() {
		sudo chmod -R 777 $HOME/.config/gcloud
		sudo chown -R $USER $HOME/.config/gcloud
		sudo rm -rf $HOME/.cache/* \
			$HOME/.config/gcloud/config_sentinel \
			$HOME/.config/gcloud/logs/* \
			/tmp/makepkg/* \
			/var/lib/pacman/db.l* \
			/usr/share/man/man5/gemfile* \
			/var/cache/pacman/pkg \
			/var/lib/pacman/sync/*
		sudo mkdir -p /var/cache/pacman/pkg
		kacman -Scc --noconfirm
		sudo pacman -Qtdq | xargs -r kacman -Rsucnd --noconfirm
		sudo rm -rf /var/lib/pacman/db.lck
		sudo paccache -ruk0
	}
	archback() {
		family_name=$(cat /sys/devices/virtual/dmi/id/product_family)
		echo $family_name
		kacman -Sy
		if [[ $family_name =~ "P1" ]]; then
			echo "backup ThinkPad P1 Gen 2 packages"
			sudo chmod -R 777 $DOTFILES_DIR/arch/pkg_p1.list
			sudo chmod -R 777 $DOTFILES_DIR/arch/aur_p1.list
			pacman -Qqen | sort -n >$DOTFILES_DIR/arch/pkg_p1.list
			pacman -Qqem | sort -n >$DOTFILES_DIR/arch/aur_p1.list
		elif [[ $family_name =~ "5th" ]]; then
			echo "backup ThinkPad X1 Carbon Gen 5 packages"
			sudo chmod -R 777 $DOTFILES_DIR/arch/pkg_nc.list
			sudo chmod -R 777 $DOTFILES_DIR/arch/aur_nc.list
			pacman -Qqen | sort -n >$DOTFILES_DIR/arch/pkg_nc.list
			pacman -Qqem | sort -n >$DOTFILES_DIR/arch/aur_nc.list
		elif [[ $family_name =~ "X1" ]]; then
			echo "backup ThinkPad X1 Carbon Gen 9 packages"
			sudo chmod -R 777 $DOTFILES_DIR/arch/pkg.list
			sudo chmod -R 777 $DOTFILES_DIR/arch/aur.list
			pacman -Qqen | sort -n >$DOTFILES_DIR/arch/pkg.list
			pacman -Qqem | sort -n >$DOTFILES_DIR/arch/aur.list
		else
			echo "backup packages"
			sudo chmod -R 777 $DOTFILES_DIR/arch/pkg_desk.list
			sudo chmod -R 777 $DOTFILES_DIR/arch/aur_desk.list
			pacman -Qqen | sort -n >$DOTFILES_DIR/arch/pkg_desk.list
			pacman -Qqem | sort -n >$DOTFILES_DIR/arch/aur_desk.list
		fi
		kacclean
	}
	alias archback=archback

	test_pacman_mirror() {
		local log_file
		log_file="$(mktemp)" || return 1
		trap '[[ -n "$log_file" && -e "$log_file" ]] && rm -f "$log_file"' RETURN

		if (($+commands[milcheck])); then
			run_command "milcheck" sudo milcheck || true
		fi

		if kacman -Syy >"$log_file" 2>&1; then
			return 0
		fi

		# DNS-related errors: attempt one quick retry
		if grep -qE "Temporary failure in name resolution|could not resolve host|Name or service not known" "$log_file"; then
			echo "DNS resolution error detected; retrying once after a short delay..."
			sleep 3
			if kacman -Syy; then
				return 0
			fi
		fi

		echo "pacman -Syy failed; see log:"
		cat "$log_file"
		return 1
	}

	arch_update_mirrors() {
		local mirror="/etc/pacman.d/mirrorlist"
		local backup="/etc/pacman.d/mirrorlist.backup"
		local tmpfile

		tmpfile="$(mktemp)" || return 1
		trap '[[ -n "$tmpfile" && -e "$tmpfile" ]] && rm -f "$tmpfile"'

		# if there is no mirrorlist yet, handle gracefully
		if [[ -f "$mirror" ]]; then
			sudo cp "$mirror" "$backup"
		fi

		# Call reflector
		if ! reflector \
			--country "Australia,Austria,Bulgaria,Canada,Czechia,France,Germany,India,Japan,New Zealand,Singapore,South Korea,Sweden,Taiwan,Thailand,United Kingdom,United States" \
			--protocol https \
			--fastest 60 \
			--sort score \
			--threads 64 \
			--age 24 \
			--isos \
			--ipv6 \
			--delay 0.2 \
			--completion-percent 100 \
			--save "$tmpfile"; then
			echo "Reflector failed; keeping existing mirrorlist"
			return 1
		fi

		# Minimal sanity check
		if [[ ! -s "$tmpfile" || $(wc -l <"$tmpfile") -lt 5 ]]; then
			echo "Reflector produced an unexpectedly small mirrorlist; aborting."
			return 1
		fi

		# Apply new mirrorlist (but keep backup until tested)
		sudo mv "$tmpfile" "$mirror"
		sudo chown root:root "$mirror"
		sudo chmod 0644 "$mirror"

		# Test the new mirrorlist
		if ! test_pacman_mirror; then
			echo "New mirrorlist seems broken; restoring backup"

			if [[ -f "$backup" ]]; then
				sudo mv "$backup" "$mirror"
				sudo chown root:root "$mirror"
				sudo chmod 0644 "$mirror"
			fi

			return 1
		fi

		echo "New mirrorlist validated successfully; removing backup"
		sudo rm -f "$backup"
		return 0
	}

	arch_update_packages() {
		# Pre-update maintenance (moved from start of old archup)
		sudo chown 0 /etc/sudoers.d/$USER
		sudo chmod -R 700 $HOME/.gnupg
		sudo chmod -R 600 $HOME/.gnupg/*

		run_command "sync and clear cache" sh -c "sync && sudo sysctl -w vm.drop_caches=3 && sudo swapoff -a && sudo swapon -a" &&
			printf '\n%s\n' 'RAM-cache and Swap were cleared.' &&
			free

		sudo su -c "chown 0 /etc/sudoers.d/$USER"

		run_command "cleaning package cache (pre-update)" kacclean

		if (($+commands[gpgconf])); then
			sudo gpgconf --kill all
		fi

		# Handling keys
		if [ $# -eq 1 ]; then
			sudo chown -R $USER $HOME/.gnupg
			touch $HOME/.gnupg/dirmngr_ldapservers.conf
			sudo chmod 700 $HOME/.gnupg/crls.d/
			if (($+commands[dirmgr])); then
				sudo dirmngr </dev/null
			fi
			if (($+commands["pacman-key"])); then
				run_command "init pacman keys" sudo pacman-key --init
				run_command "populate archlinux keys" sudo pacman-key --populate archlinux
				run_command "refresh keys" sudo pacman-key --refresh-keys
			fi
		elif (($+commands["pacman-key"])); then
			run_command "populate archlinux keys" sudo pacman-key --populate archlinux
		fi

		run_command "cleaning package cache (pre-update 2)" kacclean

		# Now the main event
		run_command "pacman full upgrade" kacman -Syyu --noconfirm || return $?
		# run_command "pacman full upgrade" kacman -Syyu --noconfirm --skipreview --removemake --cleanafter --useask --combinedupgrade --batchinstall --sudoloop || return $?
	}

	alias archpkgs=arch_update_packages

	arch_maintenance() {
		run_command "pacman db upgrade" sudo pacman-db-upgrade || return $?
		run_command "cleaning package cache (post-update)" kacclean

		run_command "update bootloader" sudo bootctl update || return $?
		run_command "regenerate initramfs" sudo mkinitcpio -p linux-zen || return $?
		run_command "vacuum journal" sudo journalctl --vacuum-time=2weeks

		run_command "final sync and maintenance" sh -c "sync && sudo sysctl -w vm.drop_caches=3 && sudo swapoff -a && sudo swapon -a" &&
			printf '\n%s\n' 'RAM-cache and Swap were cleared.' &&
			sudo fsck -AR -a &&
			sudo journalctl --vacuum-time=2weeks &&
			systemd-analyze &&
			sensors &&
			free
	}

	alias archmain=arch_maintenance

	archup() {
		kpangoup

		# arch_update_mirrors || return $?
		arch_update_mirrors
		arch_update_packages "$@" || return $?
		arch_maintenance || return $?
	}
	alias archup=archup
	alias up=archup

	if (($+commands[reboot])); then
		reboot() {
			if [ $# -eq 1 ]; then
				archup keyref
			else
				archup
			fi
			fup
			archback
			sudo reboot && exit
		}
		alias reboot=reboot
	fi

	if (($+commands[shutdown])); then
		shutdown() {
			if [ $# -eq 1 ]; then
				archup keyref
			else
				archup
			fi
			fup
			archback
			sudo shutdown now && exit
		}
		alias shutdown=shutdown
	fi
elif (($+commands["apt-get"])); then
	aptup() {
		kpangoup
		sudo du -sh /var/cache/apt/archives
		sudo rm -rf /var/cache/apt /var/lib/apt/lists/*
		sudo mkdir -p /var/cache/apt/archives/partial
		sudo apt-key adv --refresh-keys --keyserver keyserver.ubuntu.com
		sudo apt-key list | awk -F"/" '/expired:/{print $2}' | xargs -I {} sudo apt-key del {}
		echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' >/etc/apt/apt.conf.d/keep-cache
		echo 'APT::Install-Recommends "false";' >/etc/apt/apt.conf.d/no-install-recommends
		sudo DEBIAN_FRONTEND=noninteractive apt-get -y clean
		sudo DEBIAN_FRONTEND=noninteractive apt-get -y autoremove
		sudo DEBIAN_FRONTEND=noninteractive apt-get -y update
		sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
		sudo DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
		sudo DEBIAN_FRONTEND=noninteractive apt-get -y clean
		sudo dpkg-reconfigure -f noninteractive tzdata
		sudo DEBIAN_FRONTEND=noninteractive apt-get -y autoremove --purge
		sudo DEBIAN_FRONTEND=noninteractive apt-get -y autoclean --purge
		sudo du -sh /var/cache/apt/archives
		sudo rm -rf /var/cache/apt /var/lib/apt/lists/*
		sudo mkdir -p /var/cache/apt/archives/partial
		sudo update-alternatives --set cc $CC
		sudo update-alternatives --set c++ $CXX
		sudo systemctl daemon-reload
	}
	alias aptup=aptup
	alias up=aptup
fi
if (($+commands[bumblebeed])); then
	discrete() {
		killall Xorg
		modprobe nvidia_drm
		modprobe nvidia_modeset
		modprobe nvidia
		tee /proc/acpi/bbswitch <<<ON
		cp /etc/X11/xorg.conf.nvidia /etc/X11/xorg.conf
	}
	alias discrete=discrete
	integrated() {
		killall Xorg
		rmmod nvidia_drm
		rmmod nvidia_modeset
		rmmod nvidia
		tee /proc/acpi/bbswitch <<<OFF
		cp /etc/X11/xorg.conf.intel /etc/X11/xorg.conf
	}
	alias integrated=integrated
fi

if (($+commands[systemctl])); then
	alias checkkm="sudo systemctl status systemd-modules-load.service"
fi

if (($+commands[sway])); then
	set_swaysock() {
		export SWAYSOCK=/run/user/$UID/sway-ipc.$UID.$(pgrep -x sway).sock
	}
fi

if (($+commands[chrome])); then
	alias chrome="chrome --audio-buffer-size=4096"
fi
