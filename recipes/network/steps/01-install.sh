#!/bin/sh
set -eu
# NetworkManager default config
install -D -m 644 "${RECIPE_DIR}/files/NetworkManager.conf" -T /etc/NetworkManager/NetworkManager.conf
install -D -m 644 "${RECIPE_DIR}/files/globals.conf" -t /etc/NetworkManager/conf.d/

install -D -m 644 "${RECIPE_DIR}/files/resolved.conf" -T /etc/systemd/resolved.conf

systemctl enable systemd-resolved

# Add mdns definitions
mkdir -p /usr/lib/systemd/dnssd

