if (($+commands[php])); then
	export PHP_BUILD_CONFIGURE_OPTS=${PHP_BUILD_CONFIGURE_OPTS:-"--with-openssl=/usr/local/opt/openssl"}
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
if (($+commands[go])); then
	#GO
	export GOPATH=${GOPATH:-$HOME/go}
	export GOROOT=${GOROOT:-${commands[go]%/*/*}}
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
	export LD=${LD:-/usr/bin/ldd}
	if [ -z "$_ZSH_CLANG_ENV_LOADED" ]; then
		export _ZSH_CLANG_ENV_LOADED=1
		if (($+commands[llvm-config])); then
			export LLVM_CONFIG_PATH=${commands[llvm-config]}
			if [[ -f "$ZCACHE_DIR/llvm_libdir.zsh" ]]; then
				if (($+functions[zsh-defer])); then zsh-defer -p -r source "$ZCACHE_DIR/llvm_libdir.zsh"; else source "$ZCACHE_DIR/llvm_libdir.zsh"; fi
			else
				_zcache_eval llvm_libdir 1 'echo "export LD_LIBRARY_PATH=\"$(llvm-config --libdir):\$LD_LIBRARY_PATH\""' "$LLVM_CONFIG_PATH"
			fi
		else
			export LD_LIBRARY_PATH=/usr/lib/clang/*/lib:$LD_LIBRARY_PATH
		fi
		# export LDFLAGS="-g -flto -march=native -fno-plt -Wl,-O3 -ffast-math,--sort-common,--as-needed,-z,relro,-z,now -fdata-sections -ffunction-sections -Wl,--gc-sections -fvisibility=hidden -L$LLVM_HOME/lib:-L$QT_HOME/lib:-L/usr/local/opt/openssl/lib:-L/usr/local/opt/bison/lib:$LDFLAGS"
		# export FFLAGS=$LDFLAGS
		#CLANG
		export CFLAGS=-I$LLVM_HOME/include:-I$QT_HOME/include:-I/usr/local/opt/openssl/include:$CFLAGS
		export CPPFLAGS=$CFLAGS
		export C_INCLUDE_PATH=$LLVM_HOME/include:$QT_HOME/include:$C_INCLUDE_PATH
		export CPLUS_INCLUDE_PATH=$LLVM_HOME/include:$QT_HOME/include:$CPLUS_INCLUDE_PATH
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
		sudo chmod -R u+rwX "$_ch" "$_rh"
		sudo chown -R "$USER" "$_ch" "$_rh"
	fi
	# Run one step; on failure restore tracked files to the pre-step snapshot and
	# drop any untracked files the step created, then swallow the error.
	_valdup_step() {
		local label=$1
		shift
		local snap untracked_before untracked_after f outfile ignored rc
		snap=$(git stash create 2>/dev/null)
		untracked_before=$(git ls-files --others --exclude-standard 2>/dev/null)
		outfile=$(mktemp)
		"$@" 2>&1 | tee "$outfile"
		rc=${pipestatus[1]}
		if (($rc == 0)); then
			# `make -k` targets (e.g. `update`, `format`) run their sub-targets with
			# a leading '-', so a failing sub-target is swallowed and this step
			# still reports success. Surface those here — they'd otherwise go
			# unnoticed indefinitely (this is how the rustfmt-component gap hid).
			ignored=$(grep -oE '\[[^]]+\] Error [0-9]+ \(ignored\)' "$outfile" 2>/dev/null)
			if [[ -n $ignored ]]; then
				print -u2 "valdup: step '$label' succeeded, but these sub-targets failed silently:"
				print -u2 -- "$ignored"
			fi
			rm -f "$outfile"
			return 0
		fi
		rm -f "$outfile"
		print -u2 "valdup: step '$label' failed — rolling back its file changes"
		if [[ -n $snap ]]; then
			git restore --source="$snap" --worktree --staged -- . 2>/dev/null ||
				git checkout --quiet "$snap" -- . 2>/dev/null
		else
			git restore --worktree --staged -- . 2>/dev/null ||
				git checkout --quiet -- . 2>/dev/null
		fi
		untracked_after=$(git ls-files --others --exclude-standard 2>/dev/null)
		comm -13 <(print -r -- "$untracked_before" | sort) <(print -r -- "$untracked_after" | sort) |
			while IFS= read -r f; do
				[[ -n $f ]] && rm -f -- "$f"
			done
		return 0
	}
	_valdup_step manifest valdmanifest
	_valdup_step update make -k update
	_valdup_step proto make proto/replace format/go format/go/test license format/rust workflow/fix
	_valdup_step perm make perm
	unset -f _valdup_step
	return 0
}
_vald_generate_mod() {
	local file=$1
	rm -rf "$file"
	head -n 5 hack/go.mod.default >"$file"
	awk '{printf "\t%s => %s upgrade\n", $1, $1}' go.sum | sort -n | uniq | sort -n >>"$file"
	echo ")" >>"$file"
}

valddep() {
	cd "$GOPATH/src/github.com/vdaas/vald" || return 1
	rm -rf go.mod go.sum
	cp hack/go.mod.default go.mod
	GOPRIVATE=github.com/vdaas/vald,github.com/vdaas/vald/apis go mod tidy

	_vald_generate_mod hack/go.mod.default2

	rm -rf hack/go.mod.default3
	head -n 5 hack/go.mod.default >hack/go.mod.default3
	rg 'k8s|opentelemetry|containerd' hack/go.mod.default >>hack/go.mod.default3
	echo ")" >>hack/go.mod.default3

	mv go.mod go.sum /tmp/
	cp hack/go.mod.default3 go.mod
	GOPRIVATE=github.com/vdaas/vald,github.com/vdaas/vald/apis go mod tidy

	_vald_generate_mod hack/go.mod.default3

	mv /tmp/go.mod /tmp/go.sum .
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
	export LD_LIBRARY_PATH=/lib:/usr/local/lib:${GCLOUD_PATH}/lib:/opt/containerd/lib:/opt/cuda/lib:${LD_LIBRARY_PATH}
	export LIBRARY_PATH=/lib:/usr/local/lib:${GCLOUD_PATH}/lib:/opt/containerd/lib:/opt/cuda/lib:${LD_LIBRARY_PATH}
fi

if (($+commands[rails])); then
	alias railskill='kill -9 $(pgrep rails)'
fi

if (($+commands[gemini])); then
	gemini() {
		local gemini="$commands[gemini]"
		local key
		if (($+commands[pass])); then
			local pass="$commands[pass]"
			key=$("$pass" show ai/gemini 2>/dev/null) || key=""
		fi
		if [[ -n "$key" ]]; then
			GEMINI_API_KEY="$key" "$gemini" "$@"
		else
			"$gemini" "$@"
		fi
	}
fi

# Devbox aliases
alias dbox="make -C \$rcpath devbox/shell" dbox-install="make -C \$rcpath devbox/install" dbox-setup="make -C \$rcpath devbox/setup" dbox-update="make -C \$rcpath devbox/update" dbox-clean="make -C \$rcpath devbox/clean"
