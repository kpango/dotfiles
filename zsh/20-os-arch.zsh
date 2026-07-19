if (($+commands[pacman])); then
	GCC=${commands[gcc]}
	GXX=${commands[g++]}
	GCPP="$GCC -E"
	run_command() {
		local desc="$1"
		shift
		local rc
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
			# pakku passes --config /tmp/pakku-$USER/makepkg.conf to makepkg; seed the
			# file from /etc/makepkg.conf if the directory was cleaned or never created.
			if [[ "$manager" == "pakku" ]]; then
				local _pakku_dir="/tmp/pakku-${USER}"
				if [[ ! -f "$_pakku_dir/makepkg.conf" ]]; then
					mkdir -p "$_pakku_dir"
					# Merge base config and conf.d overrides so PKGDEST and custom
					# flags set in makepkg.conf.d/ are visible to pakku's --config.
					cat /etc/makepkg.conf >"$_pakku_dir/makepkg.conf"
					for _c in /etc/makepkg.conf.d/*.conf; do
						[[ -f "$_c" ]] && cat "$_c" >>"$_pakku_dir/makepkg.conf"
					done
				fi
			fi
			$manager "$@" && return 0
			$manager "$@" --ignore mozc-ut-full-common --ignore fcitx5-mozc-ut-full && return 0
			CC=$GCC CXX=$GXX CPP=$GCPP $manager "$@" && return 0
			CC=$GCC CXX=$GXX CPP=$GCPP $manager "$@" --ignore mozc-ut-full-common --ignore fcitx5-mozc-ut-full && return 0
			echo "ERROR: $manager failed all strategies."
		fi
		return 1
	}

	kacman() {
		if try_package_manager paru "$@"; then return 0; fi
		if try_package_manager pakku "$@"; then return 0; fi
		if try_package_manager yay "$@"; then return 0; fi
		if (($+commands[pacman])); then
			echo "Trying with sudo pacman..."
			if run_command "executing sudo pacman" sudo pacman "$@"; then return 0; fi
		fi
		echo "Failed to execute the command with option '$@' with all package managers."
		return 1
	}
	kacclean() {
		setopt localoptions nullglob
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
		sudo pacman -Scc --noconfirm
		local _orphans
		_orphans=$(sudo pacman -Qtdq 2>/dev/null)
		[[ -n "$_orphans" ]] && kacman -Rsucnd --noconfirm ${(f)_orphans} || true
		(($+commands[paccache])) && sudo paccache -ruk0 || true
	}
	_backup_packages() {
		local suffix=$1
		local pkg_list="$DOTFILES_DIR/arch/pkg${suffix}.list"
		local aur_list="$DOTFILES_DIR/arch/aur${suffix}.list"
		sudo chmod -R 777 "$pkg_list" 2>/dev/null || true
		sudo chmod -R 777 "$aur_list" 2>/dev/null || true
		pacman -Qqen | sort >"$pkg_list"
		pacman -Qqem | sort >"$aur_list"
	}

	archback() {
		local family_name
		family_name=$(cat /sys/devices/virtual/dmi/id/product_family 2>/dev/null || echo "unknown")
		echo "$family_name"

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

		if (($+commands[milcheck])); then
			sudo milcheck 2>/dev/null || true
		fi

		if kacman -Syy --noconfirm >"$log_file" 2>&1; then
			rm -f "$log_file"
			return 0
		fi

		# Retry up to 3 times for transient DNS/network failures
		local _attempt _delay=3
		for _attempt in 1 2 3; do
			if grep -qE "Temporary failure in name resolution|could not resolve host|Name or service not known" "$log_file"; then
				echo "DNS error detected; retry $_attempt/3 after ${_delay}s..."
				sleep $_delay
				_delay=$((_delay * 2))
				if kacman -Syy --noconfirm >"$log_file" 2>&1; then
					rm -f "$log_file"
					return 0
				fi
			else
				break
			fi
		done

		echo "pacman -Syy failed; see log:"
		cat "$log_file"
		rm -f "$log_file"
		return 1
	}

	arch_update_mirrors() {
		(($+commands[reflector])) || { echo "reflector not found; skipping mirror update"; return 0; }
		local mirror="/etc/pacman.d/mirrorlist"
		local backup="/etc/pacman.d/mirrorlist.backup"
		local tmpfile

		tmpfile="$(mktemp)" || return 1

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
			rm -f "$tmpfile"
			return 1
		fi

		# Minimal sanity check
		if [[ ! -s "$tmpfile" || $(wc -l <"$tmpfile") -lt 5 ]]; then
			echo "Reflector produced an unexpectedly small mirrorlist; aborting."
			rm -f "$tmpfile"
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
				local escaped_filepath
				escaped_filepath=$(printf '%s\n' "$filepath" | sed 's/[|[\.*^$]/\\&/g')
				sudo sed -i "\|^${escaped_filepath}$|d" "$db_dir/$loser_entry/files"
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
		# pacman -Qqk outputs "pkg /path/to/missing/file" per line on stdout; extract pkg name only
		missing=$(sudo pacman -Qqk 2>/dev/null | awk '{print $1}' | sort -u)

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
		[[ -f "/etc/sudoers.d/$USER" ]] && sudo chown 0 "/etc/sudoers.d/$USER" || true
		# Set directory perms to 700 and file perms to 600 — chmod -R 600 would
		# break directory execute bits, so use find to target each type separately.
		sudo find "$HOME/.gnupg" -type d -exec chmod 700 {} \;
		sudo find "$HOME/.gnupg" -type f -exec chmod 600 {} \;

		run_command "sync and clear cache" sh -c "sync && sudo sysctl -w vm.drop_caches=3" &&
			printf '\n%s\n' 'Page cache cleared.'
		sudo swapoff -a && sudo swapon -a && printf '\n%s\n' 'Swap cleared.' ||
			echo "WARNING: swap reset skipped (no valid swap device on this machine)"
		free

		[[ -f "/etc/sudoers.d/$USER" ]] && sudo su -c "chown 0 /etc/sudoers.d/$USER" 2>/dev/null || true

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
		# On partial failure, retry each remaining outdated package individually
		# so a single broken AUR package does not block the rest of the system.
		if ! run_command "pacman full upgrade" kacman -Syyu --noconfirm; then
			echo "==> Full upgrade incomplete; retrying remaining packages individually..."
			local _outdated _failed=()
			_outdated=$(kacman -Qu 2>/dev/null | awk '{print $1}')
			if [[ -n "$_outdated" ]]; then
				while IFS= read -r _pkg; do
					[[ -z "$_pkg" ]] && continue
					run_command "upgrading $_pkg" kacman -S --noconfirm "$_pkg" ||
						_failed+=("$_pkg")
				done <<<"$_outdated"
			fi
			[[ ${#_failed[@]} -gt 0 ]] &&
				echo "WARNING: could not upgrade: ${_failed[*]}" ||
				true
		fi
	}

	alias archpkgs=arch_update_packages

	# Update AUR packages that try_package_manager skips via --ignore on fallback.
	# Called after the main upgrade so they don't block the rest of the system update.
	arch_update_aur_ignored() {
		local -a _pkgs _need_update
		for _p in mozc-ut-full-common fcitx5-mozc-ut-full google-chrome-beta; do
			pacman -Q "$_p" &>/dev/null && _pkgs+=("$_p")
		done
		[[ ${#_pkgs[@]} -eq 0 ]] && return 0

		local _inst _avail
		for _p in "${_pkgs[@]}"; do
			_inst=$(pacman -Q "$_p" 2>/dev/null | awk '{print $2}')
			_avail=$(paru -Si "$_p" 2>/dev/null | awk '/^Version/{print $3; exit}')
			# Only queue when AUR info was fetched successfully and versions differ.
			# If paru -Si fails (_avail empty), skip rather than trigger a needless rebuild.
			if [[ -n "$_avail" && "$_inst" != "$_avail" ]]; then
				_need_update+=("$_p")
			fi
		done

		if [[ ${#_need_update[@]} -eq 0 ]]; then
			echo "==> AUR ignored packages already up to date: ${_pkgs[*]}"
			return 0
		fi
		echo "==> Updating AUR packages skipped during main upgrade: ${_need_update[*]}"
		# Build each package individually so one failure does not block the others.
		for _p in "${_need_update[@]}"; do
			case "$_p" in
				mozc-ut-full-common|fcitx5-mozc-ut-full)
					# --nocheck skips the lengthy test suite that dominates build time
					kacman -S --noconfirm --nocheck "$_p" ||
						echo "WARNING: could not update $_p (skipping)"
					;;
				*)
					kacman -S --noconfirm "$_p" ||
						echo "WARNING: could not update $_p (skipping)"
					;;
			esac
		done
	}

	# paru-bin ships a pre-built binary; when libalpm API changes (e.g. the
	# _disable_sandbox symbol split in pacman 7.x dev), the binary breaks.
	# This rebuilds paru from source so it links against the current libalpm.
	_fix_paru_if_broken() {
		paru --version &>/dev/null && return 0
		echo "==> paru broken (symbol mismatch); rebuilding from AUR source..."
		local _dir
		_dir=$(mktemp -d) || return 1
		(
			cd "$_dir" || exit 1
			git clone --depth=1 https://aur.archlinux.org/paru.git . || exit 1
			makepkg -si --noconfirm || exit 1
		)
		local _rc=$?
		rm -rf "$_dir"
		if [[ $_rc -eq 0 ]]; then
			echo "==> paru rebuilt successfully"
		else
			echo "WARNING: paru rebuild failed; update will fall back to pakku/pacman"
		fi
		return $_rc
	}

	# Detect a corrupted /etc/makepkg.conf (essential vars missing) and restore
	# from /etc/makepkg.conf.pacnew if available, preserving the PKGDEST
	# override that try_package_manager seeds for pakku. Guards against the
	# failure mode where makepkg refuses to start because SRCEXT/PKGEXT/BUILDENV
	# are undefined — which makes every AUR build silently fail.
	_fix_makepkg_conf_if_broken() {
		local conf=/etc/makepkg.conf
		local pacnew="${conf}.pacnew"

		if grep -qE '^[[:space:]]*PKGEXT=' "$conf" 2>/dev/null &&
			grep -qE '^[[:space:]]*SRCEXT=' "$conf" 2>/dev/null &&
			grep -qE '^[[:space:]]*BUILDENV=' "$conf" 2>/dev/null; then
			return 0
		fi

		echo "==> $conf is missing essential variables (PKGEXT/SRCEXT/BUILDENV)"

		if [[ ! -f "$pacnew" ]]; then
			echo "WARNING: no $pacnew available; AUR builds will fail."
			echo "         Reinstall pacman with 'sudo pacman -S pacman' to restore."
			return 1
		fi

		local backup="${conf}.broken.bak.$(date +%Y%m%d-%H%M%S)"
		echo "==> Restoring from $pacnew (backup: $backup)"
		sudo cp "$conf" "$backup" || return 1
		sudo install -m 644 "$pacnew" "$conf" || return 1

		# Ensure PKGDEST is in conf.d (new architecture) rather than /etc/makepkg.conf.
		local _custom_conf="/etc/makepkg.conf.d/zen2-custom.conf"
		if [[ ! -f "$_custom_conf" ]] || ! grep -q 'PKGDEST' "$_custom_conf"; then
			printf '\nPKGDEST=/tmp/pakku-%s\n' "$USER" | sudo tee -a "$_custom_conf" >/dev/null
		fi

		sudo rm -f "$pacnew"
		rm -f "/tmp/pakku-${USER}/makepkg.conf"
		echo "==> $conf restored ($(wc -l <"$conf") lines)"
	}

	# Auto-merge makepkg.conf.d/*.pacnew when the live file is fully default
	# (every non-blank line is a comment). Anything customized is left alone
	# with a warning. Customizations under makepkg.conf.d break AUR builds
	# the same way a broken makepkg.conf does, so we keep these aligned.
	_merge_safe_makepkg_conf_d_pacnew() {
		setopt localoptions nullglob
		local pacnew_file live_file
		for pacnew_file in /etc/makepkg.conf.d/*.pacnew; do
			live_file="${pacnew_file%.pacnew}"
			[[ -f "$live_file" ]] || continue

			if grep -qvE '^[[:space:]]*(#|$)' "$live_file"; then
				echo "WARNING: $pacnew_file has live customizations; run 'sudo pacdiff' to merge"
			else
				echo "==> Auto-merging unchanged ${live_file##*/}.pacnew"
				sudo install -m 644 "$pacnew_file" "$live_file" && sudo rm -f "$pacnew_file"
			fi
		done
	}

	# Surface unmerged .pacnew files anywhere under /etc. Some (sudoers,
	# passwd, mkinitcpio.conf) require manual review, so we only warn.
	_warn_pending_pacnew() {
		local pacnew_list
		pacnew_list=$(sudo find /etc -name '*.pacnew' 2>/dev/null)
		[[ -z "$pacnew_list" ]] && return 0

		echo "==> Pending .pacnew files (resolve with 'sudo pacdiff'):"
		echo "$pacnew_list" | sed 's/^/    /'
	}

	# Kernel 7.0+ replaced scripts/pahole-flags.sh with scripts/gen-btf.sh.
	# nvidia-beta-dkms checks only for the old file; without this patch the
	# DKMS build fails with an awk curly-quote error during BTF generation.
	# vm.overcommit_memory=2 (strict) prevents mmap of zero-fill pages when
	# CommitLimit is tight during parallel DKMS conftest builds. Temporarily
	# relax to mode 0 for the duration of any dkms install call.
	_dkms_install_safe() {
		local _oc _ret
		_oc=$(sysctl -n vm.overcommit_memory 2>/dev/null || echo 0)
		[[ "$_oc" == "2" ]] && sudo sysctl -q -w vm.overcommit_memory=0
		sudo dkms install "$@"
		_ret=$?
		[[ "$_oc" == "2" ]] && sudo sysctl -q -w vm.overcommit_memory=2
		return $_ret
	}

	nvidia_dkms_fix() {
		local ver mk
		ver=$(pacman -Q nvidia-beta-dkms 2>/dev/null | awk '{print $2}' | cut -d- -f1)
		[[ -z "$ver" ]] && return 0

		mk="/var/lib/dkms/nvidia/${ver}/source/Makefile"
		[[ -f "$mk" ]] || return 0

		# Already patched if gen-btf.sh is in the condition.
		grep -q "gen-btf.sh" "$mk" && return 0

		# Only needed when the running kernel uses gen-btf.sh (kernel 7.0+).
		[[ -f "/usr/lib/modules/$(uname -r)/build/scripts/gen-btf.sh" ]] || return 0

		echo "==> Patching nvidia DKMS Makefile for kernel 7.x BTF generation (${ver})"
		sudo sed -i \
			's|PAHOLE_VARIABLES=\$(if \$(wildcard \$(KERNEL_SOURCES)/scripts/pahole-flags\.sh),,|PAHOLE_VARIABLES=$(if $(or $(wildcard $(KERNEL_SOURCES)/scripts/pahole-flags.sh),$(wildcard $(KERNEL_SOURCES)/scripts/gen-btf.sh)),,|' \
			"$mk"

		# Rebuild the module for the current kernel.
		_dkms_install_safe "nvidia/${ver}" -k "$(uname -r)"
	}

	arch_maintenance() {
		run_command "pacman db upgrade" sudo pacman-db-upgrade || return $?
		run_command "cleaning package cache (post-update)" kacclean

		# bootctl update exits 1 when already current — treat as success
		sudo bootctl update || true

		nvidia_dkms_fix

		(($+commands[rustup])) && run_command "update rust toolchain" rustup update --no-self-update || true

		# Regenerate initramfs for every installed kernel preset instead of
		# hardcoding linux-zen — works correctly on any machine configuration.
		local _preset _preset_name
		for _preset in /etc/mkinitcpio.d/*.preset; do
			[[ -f "$_preset" ]] || continue
			_preset_name="${_preset##*/}"
			_preset_name="${_preset_name%.preset}"
			run_command "regenerate initramfs ($_preset_name)" sudo mkinitcpio -p "$_preset_name" || return $?
		done

		# Verify DKMS modules are fully installed; auto-rebuild any that are not.
		if (($+commands[dkms])); then
			local _dkms_broken _mod _ver _kern _line
			_dkms_broken=$(dkms status 2>/dev/null | grep -v ": installed$")
			if [[ -n "$_dkms_broken" ]]; then
				echo "WARNING: DKMS modules not fully installed — rebuilding:"
				echo "$_dkms_broken" | sed 's/^/    /'
				while IFS= read -r _line; do
					[[ -z "$_line" ]] && continue
					# Format: "module/ver, kernel, arch: status"  or  "module/ver: added"
					_mod=$(echo "$_line" | awk -F'[/,]' '{print $1}')
					_ver=$(echo "$_line" | awk -F'[/,]' '{print $2}' | tr -d ' ')
					_kern=$(echo "$_line" | awk -F'[,:]' '{print $2}' | tr -d ' ')
					# Validate: must look like a kernel version (starts with digit).
					# "added" / "built" / other status words would otherwise be used as-is.
					[[ "$_kern" =~ ^[0-9]+\. ]] || _kern=$(uname -r)
					# Skip if kernel headers directory is absent — build will fail anyway.
					if [[ ! -d "/usr/lib/modules/${_kern}/build" ]]; then
						echo "  WARNING: headers for ${_kern} not found; skipping ${_mod}/${_ver} (install linux-*-headers)"
						continue
					fi
					echo "==> Rebuilding ${_mod}/${_ver} for ${_kern}"
					if _dkms_install_safe "${_mod}/${_ver}" -k "${_kern}"; then
						echo "    OK"
					else
						echo "    FAILED"
						local _log="/var/lib/dkms/${_mod}/${_ver}/build/make.log"
						if [[ -f "$_log" ]]; then
							echo "    --- last 30 lines of make.log ---"
							tail -30 "$_log" | sed 's/^/    /'
						fi
					fi
				done <<<"$_dkms_broken"
			else
				echo "==> DKMS: all modules OK"
				dkms status 2>/dev/null | sed 's/^/    /'
			fi
		fi

		# Regenerate CDI spec after potential NVIDIA driver update.
		if (($+commands[nvidia-ctk])); then
			sudo mkdir -p /etc/cdi
			run_command "regenerate NVIDIA CDI spec" \
				sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml || true
		fi

		run_command "vacuum journal" sudo journalctl --vacuum-time=2weeks

		run_command "sync and clear cache" sh -c "sync && sudo sysctl -w vm.drop_caches=3" &&
			printf '\n%s\n' 'Page cache cleared.'
		# Swap reset can fail under memory pressure; warn but don't abort.
		sudo swapoff -a && sudo swapon -a && printf '\n%s\n' 'Swap cleared.' ||
			echo "WARNING: swap reset failed (possibly low memory)"
		# fsck on live filesystems is a no-op for most fs types; -p is safer than -a.
		sudo fsck -AR -p 2>/dev/null || true
		systemd-analyze 2>/dev/null || true
		(($+commands[sensors])) && sensors 2>/dev/null || true
		free
	}

	alias archmain=arch_maintenance

	archup() {
		kpangoup
		# Pre-flight: keep build toolchain healthy before any AUR rebuild
		# can be attempted. _fix_paru_if_broken depends on a working
		# /etc/makepkg.conf, so the conf fix runs first.
		_fix_makepkg_conf_if_broken || true
		_merge_safe_makepkg_conf_d_pacnew
		_fix_paru_if_broken || true

		# arch_update_mirrors || return $?
		arch_update_mirrors
		arch_fix_db_conflicts
		arch_fix_missing_files
		arch_update_packages "$@" || true
		arch_update_aur_ignored
		arch_maintenance || return $?
		arch_fix_db_conflicts
		arch_fix_missing_files
		_warn_pending_pacnew
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
