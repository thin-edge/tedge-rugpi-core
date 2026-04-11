#!/bin/sh
set -eu
# NetworkManager default config
install -D -m 644 "${RECIPE_DIR}/files/NetworkManager.conf" -T /etc/NetworkManager/NetworkManager.conf
install -D -m 644 "${RECIPE_DIR}/files/globals.conf" -t /etc/NetworkManager/conf.d/

apt-get install -y systemd-resolved

# systemd-resolved settings
# Install as a drop-in (not the main resolved.conf) so it overrides any vendor
# drop-ins shipped by the OS (e.g. RaspiOS Trixie disables mDNS globally).
install -D -m 644 "${RECIPE_DIR}/files/resolved.conf" -T /etc/systemd/resolved.conf.d/99-tedge.conf
systemctl enable systemd-resolved

# Try to disable avahi-daemon (but don't fail if not present)
systemctl disable avahi-daemon ||:
systemctl mask avahi-daemon ||:

# Add mdns definitions
mkdir -p /usr/lib/systemd/dnssd

# systemd-resolved service definitions
install -D -m 644 "${RECIPE_DIR}/files/dns-sd/tedge.dnssd" -t /usr/lib/systemd/dnssd/
install -D -m 644 "${RECIPE_DIR}/files/dns-sd/ssh.dnssd" -t /usr/lib/systemd/dnssd/
install -D -m 644 "${RECIPE_DIR}/files/dns-sd/sftp-ssh.dnssd" -t /usr/lib/systemd/dnssd/
