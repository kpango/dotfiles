#!/bin/bash

sudo apt-get update
sudo apt-get -y install apt-transport-https ca-certificates curl gnupg2 software-properties-common wget jq make
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get install docker-ce
sudo systemctl enable docker
# wget https://storage.googleapis.com/gvisor/releases/nightly/latest/runsc
# wget https://storage.googleapis.com/gvisor/releases/nightly/latest/runsc.sha512
# sha512sum -c runsc.sha512
# chmod a+x runsc
# sudo mv runsc /usr/local/bin
sudo systemctl enable docker
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<EOF >/dev/null
{
  "dns": [
    "1.1.1.1",
    "8.8.8.8",
    "8.8.4.4"
  ],
  "dns-opts": [
    "timeout:1"
  ],
  "runtimes": {
    "runsc": {
      "path": "/usr/local/bin/runsc"
    }
  },
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "debug": false,
  "live-restore": true,
  "experimental": true,
  "features": {
    "buildkit": true
  }
}
EOF

docker pull kpango/dev:latest
