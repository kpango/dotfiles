#!/bin/sh

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

brew install wget

curl -fsSLO https://raw.githubusercontent.com/kpango/dotfiles/main/macos/Brewfile
brew bundle --file Brewfile
rm -rf Brewfile
brew autoupdate --start --upgrade --cleanup

curl -fsSLO https://raw.githubusercontent.com/kpango/dotfiles/main/macos/monokai.terminal
open monokai.terminal
rm -rf monokai.terminal

mas install 1475387142

echo "please input Cisco AnyConnect VPN password"
security add-generic-password -a $(whoami) -s mac_login_pass -w
