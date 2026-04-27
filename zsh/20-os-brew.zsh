if (($+commands[brew])); then
	brewup() {
		if (($+commands[kpangoup])); then kpangoup; fi
		cd $(brew --prefix)/Homebrew
		if (($+commands[gfr])); then gfr; fi
		git config --local pull.ff only
		git fetch origin
		git reset --hard origin/master
		cd -
		brew cleanup
		brew update
		brew upgrade
		brew cleanup
		brew doctor
		case ${OSTYPE} in
		darwin*)
			softwareupdate --all --install --force
			sudo pmset -a hibernatemode 0
			sudo rm -rf /private/var/vm/sleepimage \
				/System/Library/Speech/Voices/* \
				/private/var/log/* \
				/private/var/folders/ \
				/usr/share/emacs/ \
				/private/var/tmp/TM* \
				$HOME/Library/Caches/* \
				/private/tmp/junk
			sudo touch /private/var/vm/sleepimage
			sudo chmod 000 /private/var/vm/sleepimage
			# sudo pmset -a hibernatemode 3
			# sudo rm /private/var/vm/sleepimage
			purge
			;;
		esac
	}
	alias up=brewup
fi
