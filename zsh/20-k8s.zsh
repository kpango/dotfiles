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

	if (( ${#cmds[@]} > 0 )); then
		if [[ -f "$ZCACHE_DIR/combined_completion.zsh" ]]; then
			zsh-defer -p -r source "$ZCACHE_DIR/combined_completion.zsh"
		else
			_zcache_eval combined_completion 1 "for cmd in ${cmds[*]}; do \"\$cmd\" completion zsh 2>/dev/null; done" "${deps[@]}"
		fi
	fi
fi
