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

	# Lazy-load k8s completions on first Tab invocation to decouple 53.7KB
	# combined_completion.zsh and 7 stat checks from interactive startup.
	if [[ -z "$ZSH_EXECUTION_STRING" ]]; then
		_lazy_k8s_completion() {
			local _s="$service"
			[[ -z "$_s" ]] && _s="$words[1]"
			local _cf="$ZCACHE_DIR/combined_completion.zsh"
			if [[ ! -f "$_cf" ]]; then
				local -a _cmds
				for _cmd in kubectl kind k3d helm skaffold linkerd kustomize k9s; do
					(($+commands[$_cmd])) && _cmds+=("$_cmd")
				done
				if ((${#_cmds[@]} > 0)); then
					for _cmd in "${_cmds[@]}"; do
						timeout 10 "$_cmd" completion zsh 2>/dev/null
						print -r -- ""
					done >"${_cf}.tmp.$$" &&
						command mv -f "${_cf}.tmp.$$" "$_cf" &&
						zcompile -U -R "$_cf" 2>/dev/null
					command rm -f "${_cf}.tmp.$$" 2>/dev/null
				fi
			fi
			if [[ -f "$_cf" ]]; then
				source "$_cf"
				compdef _kubectl kubecolor k 2>/dev/null
			fi
			if [[ "$_s" == "k" || "$_s" == "kubecolor" ]]; then
				_s="kubectl"
			fi
			if [[ -n "$_comps[$_s]" && "$_comps[$_s]" != "_lazy_k8s_completion" ]]; then
				"$_comps[$_s]" "$@"
			fi
		}
		compdef _lazy_k8s_completion kubectl kind k3d helm skaffold linkerd kustomize k9s kubecolor k 2>/dev/null
	fi
fi
