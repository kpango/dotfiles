if (($+commands[octant])); then
	export OCTANT_LISTENER_ADDR="0.0.0.0:8900"
fi
if (($+commands[kubectl])); then
	kubectl() {
		local kubectl="$commands[kubectl]"
		if (($+commands[kubecolor])); then
			local kubectl="$commands[kubecolor]"
		fi
		[ -z "$_lazy_kubectl_completion" ] && {
			source <("$kubectl" completion zsh)
			complete -o default -F __start_kubectl k
			_lazy_kubectl_completion=1
		}
		"$kubectl" "$@"
	}
	alias k=kubectl
	alias kpall="k get pods --all-namespaces -o wide"
	alias ksall="k get svc --all-namespaces -o wide"
	alias kiall="k get ingress --all-namespaces -o wide"
	alias knall="k get namespace -o wide"
	alias kdall="k get deployment --all-namespaces -o wide"

	if (($+commands[kind])); then
		kind() {
			local kind="$commands[kind]"
			[ -z "$_lazy_kind_completion" ] && {
				source <("$kind" completion zsh)
				_lazy_kind_completion=1
			}
			"$kind" "$@"
		}
		alias kind=kind
	fi

	if (($+commands[k3d])); then
		k3d() {
			local k3d="$commands[k3d]"
			[ -z "$_lazy_k3d_completion" ] && {
				source <("$k3d" completion zsh)
				_lazy_k3d_completion=1
			}
			"$k3d" "$@"
		}
		alias k3d=k3d
	fi

	if (($+commands[helm])); then
		helm() {
			local helm="$commands[helm]"
			[ -z "$_lazy_helm_completion" ] && {
				source <("$helm" completion zsh)
				_lazy_helm_completion=1
			}
			"$helm" "$@"
		}
		alias helm=helm
	fi

	if (($+commands[skaffold])); then
		skaffold() {
			local skaffold="$commands[skaffold]"
			[ -z "$_lazy_skaffold_completion" ] && {
				source <("$skaffold" completion zsh)
				_lazy_skaffold_completion=1
			}
			"$skaffold" "$@"
		}
		alias skaffold=skaffold
	fi

	if (($+commands[linkerd])); then
		linkerd() {
			local linkerd="$commands[linkerd]"
			[ -z "$_lazy_linkerd_completion" ] && {
				source <("$linkerd" completion zsh)
				_lazy_linkerd_completion=1
			}
			"$linkerd" "$@"
		}
		alias linkerd=linkerd
	fi

	if (($+commands[kustomize])); then
		kustomize() {
			local kustomize="$commands[kustomize]"
			[ -z "$_lazy_kustomize_completion" ] && {
				source <("$kustomize" completion zsh)
				_lazy_kustomize_completion=1
			}
			"$kustomize" "$@"
		}
		alias kustomize=kustomize
	fi
fi
