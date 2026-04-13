#!/bin/bash -e

apt-get update
apt-get install -y --no-install-recommends \
    podman \
    passt \
    uidmap \
    netavark \
    aardvark-dns \
    podman-compose \
    tedge-container-plugin-ng

# Copy podman persist file
install -D -m 644 "${RECIPE_DIR}/files/podman.toml" -t /etc/rugix/state

# Add sudoers rules
install -D -m 0644 "${RECIPE_DIR}/files/suoders.tedge-container-plugin" -T /etc/sudoers.d/tedge-container-plugin
