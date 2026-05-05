if (($+commands[octant])); then
	export OCTANT_LISTENER_ADDR="0.0.0.0:8900"
fi

if (($+commands[kubectl])); then
	if (($+commands[kubecolor])); then
		alias kubectl=kubecolor
		alias k=kubecolor
	else
		alias k=kubectl
	fi

	alias kpall="k get pods --all-namespaces -o wide"
	alias ksall="k get svc --all-namespaces -o wide"
	alias kiall="k get ingress --all-namespaces -o wide"
	alias knall="k get namespace -o wide"
	alias kdall="k get deployment --all-namespaces -o wide"

	local deps=()
	local cmds=()
	for cmd in kubectl kind k3d helm skaffold linkerd kustomize; do
		if (($+commands[$cmd])); then
			deps+=("$commands[$cmd]")
			cmds+=("$cmd")
		fi
	done

	if ((${#cmds[@]} > 0)); then
		local cache_file="$ZCACHE_DIR/combined_completion.zsh"
		local need_eval=0
		if [[ ! -f "$cache_file" ]]; then need_eval=1; fi
		for cmd in ${deps[@]}; do if [[ "$cmd" -nt "$cache_file" ]]; then need_eval=1; fi; done

		if ((need_eval)); then
			(for cmd in ${cmds[*]}; do "$cmd" completion zsh 2>/dev/null; done) >"$cache_file"
			zcompile "$cache_file" 2>/dev/null &|
		fi

		if [[ -z "$ZSH_EXECUTION_STRING" ]] && (($+functions[zsh-defer])); then
			zsh-defer -p -r -c "autoload -Uz compinit && compinit -C && source \"$cache_file\""
		fi
	fi
fi
