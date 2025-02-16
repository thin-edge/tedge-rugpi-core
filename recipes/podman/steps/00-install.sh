#!/bin/bash -e

apt-get update
apt-get install -y --no-install-recommends \
    podman \
    podman-compose \
    tedge-container-plugin-ng

# Copy podman persist file
install -D -m 644 "${RECIPE_DIR}/files/podman.toml" -t /etc/rugix/state

# Add mosquitto listener which allows other containers access to the thin-edge.io MQTT broker
install -D -m 0644 "${RECIPE_DIR}/files/tedge-networkcontainer.conf" -t /etc/tedge/mosquitto-conf/

# Add sudoers rules
install -D -m 0644 "${RECIPE_DIR}/files/suoders.tedge-container-plugin" -T /etc/sudoers.d/tedge-container-plugin
