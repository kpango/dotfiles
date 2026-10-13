# Corporate (Jamf-managed) environment.
#
# These exports used to be injected directly into ~/.zshrc by Jamf. Once
# home-manager's programs.zsh is enabled it owns ~/.zshrc, so that file gets
# replaced and the settings would silently stop applying — breaking npm/node TLS
# and letting pip/uv bypass the sanctioned package proxy. They live here instead,
# reached through the same zshrc that home-manager sources.
#
# Everything is gated on the Netskope agent's CA bundle existing, which is the
# marker for "this is a corporate-managed machine". On any other host — kpango's
# Linux boxes included — the whole file is a no-op.
#
# If Jamf ever rewrites ~/.zshrc, home-manager's generated file is replaced and
# the dotfiles' zsh setup stops loading entirely. Re-run `nix-update` to restore
# it; the exports below keep working either way.

_corp_netskope_ca="/Library/Application Support/Netskope/STAgent/data/nscacert.pem"

if [[ -f "$_corp_netskope_ca" ]]; then
	# Netskope terminates TLS, so Node must trust its CA or every HTTPS request
	# from node and npm fails certificate verification.
	export NODE_EXTRA_CA_CERTS="$_corp_netskope_ca"

	# Takumi Guard PyPI proxy — pip and uv resolve through it, not pypi.org.
	export PIP_INDEX_URL="https://pypi.flatt.tech/simple/"
	export UV_INDEX_URL="https://pypi.flatt.tech/simple/"
fi

unset _corp_netskope_ca
