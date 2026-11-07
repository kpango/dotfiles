if (($+commands[php])); then
	[[ "$OSTYPE" == "darwin"* ]] && export PHP_BUILD_CONFIGURE_OPTS=${PHP_BUILD_CONFIGURE_OPTS:-"--with-openssl=/usr/local/opt/openssl"}
fi
if (($+commands[python3])); then
	export PYTHON_CONFIGURE_OPTS=${PYTHON_CONFIGURE_OPTS:-"--enable-shared"}
	export PYTHONIOENCODING=${PYTHONIOENCODING:-"utf-8"}
fi
if [ -z "$CARGO_HOME" ]; then
	if [ -d "/usr/local/lib/rust" ]; then
		export RUST_HOME="/usr/local/lib/rust"
		export CARGO_HOME=$RUST_HOME/cargo
		export RUSTUP_HOME=$RUST_HOME/rustup
	else
		export CARGO_HOME=$HOME/.cargo
		export RUSTUP_HOME=$HOME/.rustup
	fi
fi
export CARGO_REGISTRIES_CRATES_IO_PROTOCOL=${CARGO_REGISTRIES_CRATES_IO_PROTOCOL:-sparse}
export CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-${CPUCORES:-4}}
if (($+commands[go])); then
	#GO
	export GOPATH=${GOPATH:-$HOME/go}
	export GOROOT=${GOROOT:-${commands[go]:A:h:h}}
	export CGO_ENABLED=${CGO_ENABLED:-1}
	export GO111MODULE=${GO111MODULE:-on}
	export GOBIN=${GOBIN:-$GOPATH/bin}
	export GO15VENDOREXPERIMENT=${GO15VENDOREXPERIMENT:-1}
	export GOPRIVATE=${GOPRIVATE:-"*.yahoo.co.jp,github.com/vdaas/vald,github.com/vdaas/vald/apis,github.com/vdaas/vald-client-go"}
	export NVIM_GO_LOG_FILE=${NVIM_GO_LOG_FILE:-$XDG_DATA_HOME/go}
fi
if (($+commands[clang])); then
	export CC=${CC:-${commands[clang]}}
	export CXX=${CXX:-${commands[clang++]}}
	export CPP=${CPP:-"$CXX -E"}
	export LD=${LD:-/usr/bin/ld}
	if [ -z "$_ZSH_CLANG_ENV_LOADED" ]; then
		export _ZSH_CLANG_ENV_LOADED=1
		if (($+commands[llvm-config])); then
			export LLVM_CONFIG_PATH=${commands[llvm-config]}
			if [[ -f "$ZCACHE_DIR/llvm_libdir.zsh" && ! "$LLVM_CONFIG_PATH" -nt "$ZCACHE_DIR/llvm_libdir.zsh" ]]; then
				source "$ZCACHE_DIR/llvm_libdir.zsh"
			else
				_zcache_eval llvm_libdir 0 'echo "export LD_LIBRARY_PATH=\"$(llvm-config --libdir)\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\""' "$LLVM_CONFIG_PATH"
			fi
		else
			for _clang_lib in /usr/lib/clang/*/lib; do
				[[ -d "$_clang_lib" ]] && export LD_LIBRARY_PATH="${_clang_lib}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
			done
			unset _clang_lib
		fi
		# export LDFLAGS="-g -flto -march=native -fno-plt -Wl,-O3 -ffast-math,--sort-common,--as-needed,-z,relro,-z,now -fdata-sections -ffunction-sections -Wl,--gc-sections -fvisibility=hidden -L$LLVM_HOME/lib:-L$QT_HOME/lib:-L/usr/local/opt/openssl/lib:-L/usr/local/opt/bison/lib:$LDFLAGS"
		# export FFLAGS=$LDFLAGS
		#CLANG
		_cflags_extra="${LLVM_HOME:+-I$LLVM_HOME/include }${QT_HOME:+-I$QT_HOME/include }"
		[[ "$OSTYPE" == "darwin"* && -d "/usr/local/opt/openssl/include" ]] && _cflags_extra+="-I/usr/local/opt/openssl/include "
		[[ -n "$_cflags_extra" ]] && export CFLAGS="${_cflags_extra}${CFLAGS}"
		unset _cflags_extra
		export CPPFLAGS="$CFLAGS"
		export C_INCLUDE_PATH="${LLVM_HOME:+$LLVM_HOME/include:}${QT_HOME:+$QT_HOME/include:}${C_INCLUDE_PATH}"
		export CPLUS_INCLUDE_PATH="${LLVM_HOME:+$LLVM_HOME/include:}${QT_HOME:+$QT_HOME/include:}${CPLUS_INCLUDE_PATH}"
	fi
fi
valdmanifest() {
	make files helm/schema/all helm/schema/crd/all k8s/manifest/update k8s/manifest/operator/helm/update k8s/manifest/operator/benchmark/update k8s/manifest/operator/vald/update helm/docs/vald helm/docs/operator/helm helm/docs/operator/benchmark helm/docs/operator/vald clean/yaml files
}
valdup() {
	# Always succeeds. Each step is sandboxed: if a step fails, the repo file
	# changes it made are rolled back and the run continues with the next step.
	if ! cd "$GOPATH/src/github.com/vdaas/vald"; then
		print -u2 "valdup: vald repo not found at \$GOPATH/src/github.com/vdaas/vald — nothing to do"
		return 0
	fi
	# Grant write access to Cargo/Rustup when they live under a system-wide prefix
	# (e.g. /usr/local/lib/rust). No-op when the directories are already writable.
	local _ch="${CARGO_HOME:-$HOME/.cargo}" _rh="${RUSTUP_HOME:-$HOME/.rustup}"
	if [[ -d "$_ch" && ! -w "$_ch" ]]; then
		# chmod and chown run as separate statements, not `a && b`: $_rh may not
		# exist even when $_ch does, which would make chmod exit non-zero on
		# that one bad argument (while still applying to $_ch) -- chaining
		# would then let that skip the chown entirely, including for $_ch.
		# stderr is left unredirected (not 2>/dev/null): sudo/chmod/chown's own
		# error text (e.g. "No such file or directory" for a missing $_rh, or a
		# sudo prompt/permission failure) is the only place the *reason* for a
		# failure shows up -- the check below only reports that $_ch is still
		# unwritable, not why.
		sudo chmod -R u+rwX "$_ch" "$_rh"
		sudo chown -R "$USER" "$_ch" "$_rh"
		[[ -w "$_ch" ]] || print -u2 "valdup: failed to grant write access to $_ch — later cargo steps may fail"
	fi
	# Run one step; on failure restore tracked files to the pre-step snapshot and
	# drop any untracked files the step created, then swallow the error.
	_valdup_step() {
		local label=$1
		shift
		local snap untracked_before untracked_after f outfile ignored rc
		snap=$(git stash create 2>/dev/null)
		untracked_before=$(git ls-files --others --exclude-standard 2>/dev/null)
		outfile=$(mktemp) || { print -u2 "_valdup_step: mktemp failed, cannot capture output for '$label'"; return 1; }
		"$@" 2>&1 | tee "$outfile"
		rc=${pipestatus[1]}
		if (($rc == 0)); then
			# `make -k` targets (e.g. `update`, `format`) run their sub-targets with
			# a leading '-', so a failing sub-target is swallowed and this step
			# still reports success. Surface those here — they'd otherwise go
			# unnoticed indefinitely (this is how the rustfmt-component gap hid).
			ignored=$(rg -o '\[[^]]+\] Error [0-9]+ \(ignored\)' "$outfile" 2>/dev/null)
			if [[ -n $ignored ]]; then
				print -u2 "valdup: step '$label' succeeded, but these sub-targets failed silently:"
				print -u2 -- "$ignored"
			fi
			"${_rm[@]}" "$outfile"
			return 0
		fi
		"${_rm[@]}" "$outfile"
		print -u2 "valdup: step '$label' failed — rolling back its file changes"
		if [[ -n $snap ]]; then
			# $snap is the worktree state; its 2nd parent is the pre-step index.
			# Restoring --staged from $snap itself would leave every pre-step
			# worktree change staged.
			git restore --source="$snap" --worktree -- . 2>/dev/null ||
				git checkout --quiet "$snap" -- . 2>/dev/null
			git restore --source="${snap}^2" --staged -- . 2>/dev/null
		else
			git restore --worktree --staged -- . 2>/dev/null ||
				git checkout --quiet -- . 2>/dev/null
		fi
		untracked_after=$(git ls-files --others --exclude-standard 2>/dev/null)
		comm -13 <(print -r -- "$untracked_before" | sort) <(print -r -- "$untracked_after" | sort) |
			while IFS= read -r f; do
				[[ -n $f ]] && "${_rm[@]}" -- "$f"
			done
		return 0
	}
	# vm.overcommit_memory=2 (strict) makes the 128-way parallel formatters and
	# `go fix ./...` hit "fork: Cannot allocate memory" / "runtime: out of
	# memory" once CommitLimit fills. Relax to 0 for the run and restore it
	# afterwards (also on Ctrl-C), same as _dkms_install_safe.
	local _oc
	# `make update` resolves ~30 latest versions via api.github.com; anonymous
	# calls hit the 60/h rate limit (403) and silently keep stale versions.
	local -x GITHUB_TOKEN=${GITHUB_TOKEN:-$(gh auth token 2>/dev/null)}
	[[ -n $GITHUB_TOKEN ]] || print -u2 "valdup: no GITHUB_TOKEN (gh auth login?) — version bumps may be rate-limited"
	_oc=$(sysctl -n vm.overcommit_memory 2>/dev/null)
	[[ $_oc == 2 ]] && { sudo sysctl -q -w vm.overcommit_memory=0 ||
		print -u2 "valdup: failed to relax vm.overcommit_memory — parallel steps may OOM"; }
	# `make ngt/install` is keyed only on Capi.h existing, so a bumped
	# versions/NGT_VERSION never reinstalls NGT and cgo (`go fix ./...` in
	# format/go) fails on fields the old headers lack. Reinstall on mismatch.
	_valdup_ngt_sync() {
		local want have
		local -a libs
		want=$(<versions/NGT_VERSION)
		libs=(/usr/local/lib/libngt.so.*.*.*(Nn))
		have=${libs[-1]##*/libngt.so.}
		[[ -z $have || $have == "$want" ]] && return 0
		print -u2 "valdup: NGT $have installed but versions/NGT_VERSION is $want — reinstalling"
		# SUDO is unset by default (Docker builds run as root), so pass it for
		# the /usr/local installs of NGT and its libomp prerequisite.
		sudo "${_rm[@]}" /usr/local/include/NGT/Capi.h && make SUDO=sudo ngt/install
	}
	# Every make invocation (~40 sub-makes per run) creates its own
	# TEMP_DIR via `mktemp -d` and never removes it. Point TMPDIR at a per-run
	# dir so all of those (and _valdup_step's output captures) are dropped at
	# the end.
	local _tmp
	_tmp=$(mktemp -d -t valdup.XXXXXXXX) && local -x TMPDIR=$_tmp
	{
		_valdup_step manifest valdmanifest
		_valdup_step ngt _valdup_ngt_sync
		_valdup_step update make -k update
		_valdup_step ngt _valdup_ngt_sync
		_valdup_step proto make proto/replace format/go format/go/test license format/rust workflow/fix
		_valdup_step perm make perm
	} always {
		[[ $_oc == 2 ]] && sudo sysctl -q -w vm.overcommit_memory=2
		[[ -n $_tmp ]] && "${_rm[@]}" -- "$_tmp"
		unset -f _valdup_step _valdup_ngt_sync
	}
	return 0
}
_vald_generate_mod() {
	local file=$1
	"${_rm[@]}" "$file"
	head -n 5 hack/go.mod.default >"$file"
	awk '{printf "\t%s => %s upgrade\n", $1, $1}' go.sum | sort -n | uniq | sort -n >>"$file"
	echo ")" >>"$file"
}

valddep() {
	cd "$GOPATH/src/github.com/vdaas/vald" || return 1
	"${_rm[@]}" go.mod go.sum
	"${_cp[@]}" hack/go.mod.default go.mod
	GOPRIVATE=github.com/vdaas/vald,github.com/vdaas/vald/apis go mod tidy

	_vald_generate_mod hack/go.mod.default2

	"${_rm[@]}" hack/go.mod.default3
	head -n 5 hack/go.mod.default >hack/go.mod.default3
	rg 'k8s|opentelemetry|containerd' hack/go.mod.default >>hack/go.mod.default3
	echo ")" >>hack/go.mod.default3

	command mv go.mod go.sum /tmp/
	"${_cp[@]}" hack/go.mod.default3 go.mod
	GOPRIVATE=github.com/vdaas/vald,github.com/vdaas/vald/apis go mod tidy

	_vald_generate_mod hack/go.mod.default3

	command mv /tmp/go.mod /tmp/go.sum .
	$EDITOR -d hack/go.mod.default hack/go.mod.default2
	$EDITOR -d hack/go.mod.default hack/go.mod.default3
	cd -
}

if (($+commands[gcloud])); then
	if [ -d /usr/local/lib/google-cloud-sdk ]; then
		export GCLOUD_PATH=${GCLOUD_PATH:-"/usr/lib/google-cloud-sdk"}
	fi
	export USE_GKE_GCLOUD_AUTH_PLUGIN=${USE_GKE_GCLOUD_AUTH_PLUGIN:-True}
fi

if [ -z "$_ZSH_LD_ENV_LOADED" ]; then
	export _ZSH_LD_ENV_LOADED=1
	_ld_extra=""
	for _ld_d in ${GCLOUD_PATH:+"$GCLOUD_PATH/lib"} /opt/containerd/lib /opt/cuda/lib; do
		[[ -d "$_ld_d" ]] && _ld_extra="${_ld_extra:+$_ld_extra:}$_ld_d"
	done
	if [[ -n "$_ld_extra" ]]; then
		export LD_LIBRARY_PATH="${_ld_extra}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
		export LIBRARY_PATH="${_ld_extra}${LIBRARY_PATH:+:$LIBRARY_PATH}"
	fi
	unset _ld_extra _ld_d
fi

if (($+commands[rails])); then
	alias railskill='kill -9 $(pgrep rails)'
fi

if (($+commands[agy])); then
	agy() {
		local agy="$commands[agy]"
		local key
		if (($+commands[pass])); then
			local pass="$commands[pass]"
			key=$("$pass" show ai/agy 2>/dev/null) || key=""
		fi
		if [[ -n "$key" ]]; then
			AGY_API_KEY="$key" "$agy" "$@"
		else
			"$agy" "$@"
		fi
	}
fi

# Devbox aliases
alias dbox="make -C \$rcpath devbox/shell" dbox-install="make -C \$rcpath devbox/install" dbox-setup="make -C \$rcpath devbox/setup" dbox-update="make -C \$rcpath devbox/update" dbox-clean="make -C \$rcpath devbox/clean"

# prime-agent: route every kernel bash command through the shell guard.
# Only when the installer has put the guard in place, so shells without a
# prime-agent install are unaffected. Single-quoted on purpose: the kernel
# expands $HOME itself when it sources the prefix.
if [[ -f "$HOME/.prime/agent/bin/prime-shell-guard.sh" ]]; then
	export PRIME_AGENT_BASH_COMMAND_PREFIX='. "$HOME/.prime/agent/bin/prime-shell-guard.sh"'
	# pa-sandbox cannot mount a private /proc on this machine; accept the host /proc
	# (pa-sandbox still warns on every run). The script's own default stays fail-closed.
	export PA_SANDBOX_ALLOW_HOST_PROC=1
fi
