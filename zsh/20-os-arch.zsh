if (($+commands[pacman])); then
	GCC=${commands[gcc]}
	GXX=${commands[g++]}
	GCPP="$GCC -E"
	run_command() {
		local desc="$1"
		shift
		local rc
		echo "==> $desc"
		"$@"
		rc=$?
		if [[ $rc -ne 0 ]]; then
			echo "ERROR: $desc failed (exit code $rc)"
			return $rc
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
		[[ -n "${XDG_CONFIG_HOME:-}" ]] && sudo chmod -R 777 "$XDG_CONFIG_HOME/gcloud" 2>/dev/null || true
		[[ -n "${XDG_CONFIG_HOME:-}" ]] && sudo chown -R "$USER" "$XDG_CONFIG_HOME/gcloud" 2>/dev/null || true
		[[ -n "${HOME:-}" ]] && sudo rm -rf "$HOME/.cache"/* 2>/dev/null || true
		[[ -n "${XDG_CONFIG_HOME:-}" ]] && sudo rm -rf \
			"$XDG_CONFIG_HOME/gcloud/config_sentinel" \
			"$XDG_CONFIG_HOME/gcloud/logs"/* 2>/dev/null || true
		sudo rm -rf \
			/tmp/makepkg/* \
			/usr/share/man/man5/gemfile* \
			/var/cache/pacman/pkg \
			/var/lib/pacman/sync/*
		sudo rm -f /var/lib/pacman/db.lck
		sudo mkdir -p /var/cache/pacman/pkg
		kacman -Scc --noconfirm
		local _orphans
		_orphans=$(sudo pacman -Qtdq 2>/dev/null)
		[[ -n "$_orphans" ]] && echo "$_orphans" | xargs -r kacman -Rsucnd --noconfirm || true
		(($+commands[paccache])) && sudo paccache -ruk0 || true
	}
	_backup_packages() {
		local suffix=$1
		local pkg_list="$DOTFILES_DIR/arch/pkg${suffix}.list"
		local aur_list="$DOTFILES_DIR/arch/aur${suffix}.list"
		sudo chmod -R 777 "$pkg_list" 2>/dev/null || true
		sudo chmod -R 777 "$aur_list" 2>/dev/null || true
		pacman -Qqen | sort -n >"$pkg_list"
		pacman -Qqem | sort -n >"$aur_list"
	}

	archback() {
		local family_name
		family_name=$(cat /sys/devices/virtual/dmi/id/product_family 2>/dev/null || echo "unknown")
		echo "$family_name"
		kacman -Sy

		local list_suffix
		if [[ $family_name =~ "P1" ]]; then
			echo "backup ThinkPad P1 Gen 2 packages"
			list_suffix="_p1"
		elif [[ $family_name =~ "5th" ]]; then
			echo "backup ThinkPad X1 Carbon Gen 5 packages"
			list_suffix="_nc"
		elif [[ $family_name =~ "X1" ]]; then
			echo "backup ThinkPad X1 Carbon Gen 9 packages"
			list_suffix=""
		else
			echo "backup packages"
			list_suffix="_desk"
		fi
		_backup_packages "$list_suffix"
		kacclean
	}

	test_pacman_mirror() {
		local log_file
		log_file="$(mktemp)" || return 1
		trap '[[ -n "$log_file" && -e "$log_file" ]] && rm -f "$log_file"' RETURN

		if (($+commands[milcheck])); then
			sudo milcheck 2>/dev/null || true
		fi

		if kacman -Syy >"$log_file" 2>&1; then
			return 0
		fi

		# Retry up to 3 times for transient DNS/network failures
		local _attempt _delay=3
		for _attempt in 1 2 3; do
			if grep -qE "Temporary failure in name resolution|could not resolve host|Name or service not known" "$log_file"; then
				echo "DNS error detected; retry $_attempt/3 after ${_delay}s..."
				sleep $_delay
				_delay=$((_delay * 2))
				if kacman -Syy >"$log_file" 2>&1; then
					return 0
				fi
			else
				break
			fi
		done

		echo "pacman -Syy failed; see log:"
		cat "$log_file"
		return 1
	}

	arch_update_mirrors() {
		local mirror="/etc/pacman.d/mirrorlist"
		local backup="/etc/pacman.d/mirrorlist.backup"
		local tmpfile

		tmpfile="$(mktemp)" || return 1
		trap '[[ -n "$tmpfile" && -e "$tmpfile" ]] && rm -f "$tmpfile"' RETURN

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
			--completion-percent 90 \
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

	arch_fix_db_conflicts() {
		local db_dir="/var/lib/pacman/local"

		sudo pacman -Dk &>/dev/null && return 0

		echo "==> Fixing pacman database file-ownership conflicts..."

		local fixed=0
		while IFS= read -r line; do
			local pkg1 pkg2 filepath
			pkg1=$(printf '%s' "$line" | sed "s/.*file owned by '\([^']*\)' and '\([^']*\)': '\([^']*\)'/\1/")
			pkg2=$(printf '%s' "$line" | sed "s/.*file owned by '\([^']*\)' and '\([^']*\)': '\([^']*\)'/\2/")
			filepath=$(printf '%s' "$line" | sed "s/.*file owned by '\([^']*\)' and '\([^']*\)': '\([^']*\)'/\3/")

			[[ "$pkg1" == "$line" || -z "$filepath" ]] && continue

			echo "  Conflict: '$pkg1' vs '$pkg2' → '$filepath'"

			# Prefer official repo package; AUR packages won't be found by pacman -Si
			local winner loser
			if sudo pacman -Si "$pkg2" &>/dev/null; then
				winner=$pkg2
				loser=$pkg1
			else
				winner=$pkg1
				loser=$pkg2
			fi

			echo "  Reinstalling '$winner' with --overwrite to claim '$filepath'..."
			sudo pacman -S --overwrite "$filepath" --noconfirm "$winner" &>/dev/null || true

			# Remove the stale ownership entry from the losing package's DB record
			local loser_entry
			loser_entry=$(ls "$db_dir" 2>/dev/null | grep "^${loser}-" | head -1)
			if [[ -n "$loser_entry" && -f "$db_dir/$loser_entry/files" ]]; then
				echo "  Removing '$filepath' from '$loser' local DB..."
				sudo sed -i "\|^${filepath}$|d" "$db_dir/$loser_entry/files"
			fi
			((fixed++))
		done < <(sudo pacman -Dk 2>&1 | grep "file owned by")

		if sudo pacman -Dk &>/dev/null; then
			echo "==> Resolved $fixed conflict(s)."
			return 0
		fi
		echo "WARNING: Remaining conflicts after fix attempt:"
		sudo pacman -Dk 2>&1
		return 1
	}

	arch_fix_missing_files() {
		local missing
		# stderr carries per-file warnings; stdout carries only package names
		missing=$(sudo pacman -Qqk 2>/dev/null | sort -u)

		[[ -z "$missing" ]] && return 0

		echo "==> Reinstalling packages with missing files: $(echo "$missing" | tr '\n' ' ')"
		while IFS= read -r pkg; do
			[[ -z "$pkg" ]] && continue
			sudo pacman -S --noconfirm "$pkg" &>/dev/null ||
				kacman -S --noconfirm "$pkg" &>/dev/null ||
				echo "  WARNING: could not reinstall '$pkg'"
		done <<<"$missing"
	}

	arch_update_packages() {
		# Pre-update maintenance (moved from start of old archup)
		sudo chown 0 "/etc/sudoers.d/$USER"
		# Set directory perms to 700 and file perms to 600 — chmod -R 600 would
		# break directory execute bits, so use find to target each type separately.
		sudo find "$HOME/.gnupg" -type d -exec chmod 700 {} \;
		sudo find "$HOME/.gnupg" -type f -exec chmod 600 {} \;

		run_command "sync and clear cache" sh -c "sync && sudo sysctl -w vm.drop_caches=3 && sudo swapoff -a && sudo swapon -a" &&
			printf '\n%s\n' 'RAM-cache and Swap were cleared.' &&
			free

		sudo su -c "chown 0 /etc/sudoers.d/$USER" 2>/dev/null || true

		run_command "cleaning package cache (pre-update)" kacclean

		if (($+commands[gpgconf])); then
			sudo gpgconf --kill all
		fi

		if (($+commands[pacman-key])); then
			# Always re-populate from the installed archlinux-keyring (fast, local) to
			# pick up any newly added or rotated keys before upgrading.
			run_command "populate archlinux keys" sudo pacman-key --populate archlinux

			if [ $# -ge 1 ]; then
				# Full key-refresh mode: archup keyref
				sudo chown -R "$USER" "$HOME/.gnupg"
				touch "$HOME/.gnupg/dirmngr_ldapservers.conf"
				sudo chmod 700 "$HOME/.gnupg/crls.d/" 2>/dev/null || true
				if (($+commands[dirmngr])); then
					sudo dirmngr </dev/null
				fi

				run_command "init pacman keys" sudo pacman-key --init
				run_command "populate archlinux keys" sudo pacman-key --populate archlinux

				# Retry --refresh-keys across multiple keyservers; warn but do not abort
				# if all fail — stale keys may still allow the upgrade to proceed.
				local -a _gpg_keyservers=(
					"hkps://keyserver.ubuntu.com"
					"hkps://keys.openpgp.org"
					"hkp://pool.sks-keyservers.net"
				)
				local _refreshed=false
				for _ks in "${_gpg_keyservers[@]}"; do
					echo "==> Refreshing pacman keys via $_ks ..."
					if sudo pacman-key --refresh-keys --keyserver "$_ks"; then
						_refreshed=true
						break
					fi
					echo "  $_ks failed, trying next keyserver..."
				done
				[[ "$_refreshed" == true ]] || echo "WARNING: Key refresh failed on all keyservers; continuing with existing keys"
			fi
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

		# Regenerate initramfs for every installed kernel preset instead of
		# hardcoding linux-zen — works correctly on any machine configuration.
		local _preset _preset_name
		for _preset in /etc/mkinitcpio.d/*.preset; do
			[[ -f "$_preset" ]] || continue
			_preset_name="${_preset##*/}"
			_preset_name="${_preset_name%.preset}"
			run_command "regenerate initramfs ($_preset_name)" sudo mkinitcpio -p "$_preset_name" || return $?
		done

		run_command "vacuum journal" sudo journalctl --vacuum-time=2weeks

		run_command "sync and clear cache" sh -c "sync && sudo sysctl -w vm.drop_caches=3" &&
			printf '\n%s\n' 'Page cache cleared.'
		# Swap reset can fail under memory pressure; warn but don't abort.
		sudo swapoff -a && sudo swapon -a && printf '\n%s\n' 'Swap cleared.' ||
			echo "WARNING: swap reset failed (possibly low memory)"
		# fsck on live filesystems is a no-op for most fs types; -p is safer than -a.
		sudo fsck -AR -p 2>/dev/null || true
		sudo journalctl --vacuum-time=2weeks
		systemd-analyze 2>/dev/null || true
		(($+commands[sensors])) && sensors 2>/dev/null || true
		free
	}

	alias archmain=arch_maintenance

	archup() {
		kpangoup

		# arch_update_mirrors || return $?
		arch_update_mirrors
		arch_fix_db_conflicts
		arch_fix_missing_files
		arch_update_packages "$@" || return $?
		arch_maintenance || return $?
		arch_fix_db_conflicts
		arch_fix_missing_files
	}
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
	fi
fi
