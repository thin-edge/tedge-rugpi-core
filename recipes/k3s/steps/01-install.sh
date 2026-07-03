#!/bin/bash -e

# Install k3s in the server role and use secrets encryption by default
curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true INSTALL_K3S_SKIP_ENABLE=true sh -s - server --secrets-encryption

# Enable the service by default
systemctl enable k3s.service ||:

# Copy podman persist file
install -D -m 0644 "${RECIPE_DIR}/files/k3s.toml" -t /etc/rugix/state

# Add sudoers rules
install -D -m 0644 "${RECIPE_DIR}/files/suoders.k3s" -T /etc/sudoers.d/k3s

# Install helm cli (the helm controller is included in k3s by default)
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh
rm -f ./get_helm.sh

# Set default (warning, this is only for the root user)
# Add default local but there is not guarantee that any user will reference it
echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /etc/environment
echo "[ -f /etc/environment ] && . /etc/environment" >> "$HOME/.zshrc"
