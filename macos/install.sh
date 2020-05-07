#!/bin/sh

/usr/bin/ruby -e $(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)

brew install wget

curl -fsSLO https://raw.githubusercontent.com/kpango/dotfiles/master/macos/Brewfile
brew bundle --file Brewfile
rm -rf Brewfile

brew autoupdate --start --upgrade --cleanup

cat <<EOF >$HOME/.docker/config.json
{
   "auths":{ },
   "credsStore":"desktop",
   "credSstore":"osxkeychain",
   "experimental": "enabled",
   "stackOrchestrator":"swarm"
}
EOF
cat <<EOF >$HOME/.docker/daemon.json
{
   "debug":false,
   "log-opts":{
      "max-file":"3",
      "max-size":"10m"
   },
   "experimental":true,
   "log-driver":"json-file",
   "features":{
      "buildkit":true
   },
   "live-restore":true,
   "dns-opts":[
      "timeout:1"
   ]
}
EOF

curl -fsSLO https://raw.githubusercontent.com/kpango/dotfiles/master/macos/monokai.terminal
open monokai.terminal
rm -rf monokai.terminal
