if (($+commands[apt-get])); then
	_apt_clean_cache() {
		sudo du -sh /var/cache/apt/archives 2>/dev/null || true
		sudo rm -rf /var/cache/apt /var/lib/apt/lists/*
		sudo mkdir -p /var/cache/apt/archives/partial
	}

	aptup() {
		kpangoup
		_apt_clean_cache
		sudo apt-key adv --refresh-keys --keyserver keyserver.ubuntu.com
		sudo apt-key list | awk -F"/" '/expired:/{print $2}' | xargs -I {} sudo apt-key del {}
		echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' | sudo tee /etc/apt/apt.conf.d/keep-cache >/dev/null
		echo 'APT::Install-Recommends "false";' | sudo tee /etc/apt/apt.conf.d/no-install-recommends >/dev/null

		for cmd in clean autoremove update upgrade full-upgrade clean; do
			sudo DEBIAN_FRONTEND=noninteractive apt-get -y $cmd
		done

		sudo dpkg-reconfigure -f noninteractive tzdata
		sudo DEBIAN_FRONTEND=noninteractive apt-get -y autoremove --purge
		sudo DEBIAN_FRONTEND=noninteractive apt-get -y autoclean --purge
		_apt_clean_cache
		sudo update-alternatives --set cc $CC
		sudo update-alternatives --set c++ $CXX
		sudo systemctl daemon-reload
	}
	alias up=aptup
fi
