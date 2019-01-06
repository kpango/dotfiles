wget -q https://storage.googleapis.com/kubernetes-helm/helm-$(curl -s https://api.github.com/repos/helm/helm/releases/latest | jq -r '.tag_name')-linux-amd64.tar.gz -O - | tar -xzO linux-amd64/helm > /usr/local/bin/helm ;chmod +x /usr/local/bin/helm \

wget -q https://storage.googleapis.com/kubernetes-helm/helm-$(curl -s https://api.github.com/repos/helm/helm/releases/latest | jq -r '.tag_name')-linux-amd64.tar.gz

