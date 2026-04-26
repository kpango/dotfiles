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
		if (($+commands["llvm-config"])); then
			export LD_LIBRARY_PATH=$(llvm-config --libdir):$LD_LIBRARY_PATH
			export LLVM_CONFIG_PATH=${commands["llvm-config"]}
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
if [ -d "$GOPATH/src/github.com/vdaas/vald" ]; then
	valdmanifest() {
		make files
		make helm/schema/all
		make helm/schema/crd/all
		make k8s/manifest/update
		make k8s/manifest/helm-operator/update
		make helm/docs/vald
		make helm/docs/vald-helm-operator
		make clean/yaml
		make files
	}
	alias valdmanifest=valdmanifest
	valdup() {
		cd "$GOPATH/src/github.com/vdaas/vald"
		sudo chmod -R 777 $CARGO_HOME
		sudo chmod -R 777 $RUSTUP_HOME
		sudo chown -R $USER $CARGO_HOME
		sudo chown -R $USER $RUSTUP_HOME
		valdmanifest
		make -k update
		make format
		chword $GOPATH/src/github.com/vdaas/vald "interface\{\}" "any"
		make proto/replace format/go format/go/test workflow/fix
	}
	alias valdup=valdup
	valddep() {
		cd "$GOPATH/src/github.com/vdaas/vald"
		rm -rf go.mod go.sum &&
			cp hack/go.mod.default go.mod &&
			GOPRIVATE=github.com/vdaas/vald,github.com/vdaas/vald/apis go mod tidy
		rm -rf hack/go.mod.default2 &&
			cat hack/go.mod.default | head -n 5 >>hack/go.mod.default2 &&
			cat go.sum | awk '{printf "\t%s => %s upgrade\n", $1, $1}' |
			sort -n | uniq | sort -n >>hack/go.mod.default2 &&
			echo ")" >>hack/go.mod.default2
		rm -rf hack/go.mod.default3
		cat hack/go.mod.default | head -n 5 >>hack/go.mod.default3
		cat hack/go.mod.default | rg k8s >>hack/go.mod.default3
		cat hack/go.mod.default | rg opentelemetry >>hack/go.mod.default3
		cat hack/go.mod.default | rg containerd >>hack/go.mod.default3
		echo ")" >>hack/go.mod.default3
		rm -rf /tmp/go.mod /tmp/go.sum &&
			mv go.mod go.sum /tmp &&
			cp hack/go.mod.default3 go.mod &&
			GOPRIVATE=github.com/vdaas/vald,github.com/vdaas/vald/apis go mod tidy &&
			rm -rf hack/go.mod.default3 &&
			cat hack/go.mod.default | head -n 5 >>hack/go.mod.default3 &&
			cat go.sum | awk '{printf "\t%s => %s upgrade\n", $1, $1}' |
			sort -n | uniq | sort -n >>hack/go.mod.default3 &&
			echo ")" >>hack/go.mod.default3 &&
			rm -rf go.mod go.sum &&
			mv /tmp/go.mod /tmp/go.sum .
		$EDITOR -d hack/go.mod.default hack/go.mod.default2
		$EDITOR -d hack/go.mod.default hack/go.mod.default3
		cd -
	}
	alias valddep=valddep
fi

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
	alias railskill="kill -9 $(pgrep rails)"
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
	alias gemini=gemini
fi

# Devbox aliases
alias dbox="make -C \$rcpath devbox/shell"
alias dbox-install="make -C \$rcpath devbox/install"
alias dbox-setup="make -C \$rcpath devbox/setup"
alias dbox-update="make -C \$rcpath devbox/update"
alias dbox-clean="make -C \$rcpath devbox/clean"
