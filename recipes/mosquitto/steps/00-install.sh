#!/bin/bash -e
# Install more recent version of mosquitto >= 2.0.18 from debian sid to avoid mosquitto following bugs:
# The mosquitto repo can't be used as it does not included builds for arm64/aarch64 (only amd64 and armhf)
# * https://github.com/eclipse/mosquitto/issues/2604 (2.0.11)
# * https://github.com/eclipse/mosquitto/issues/2634 (2.0.15)

DPKG_ARCH=$(dpkg --print-architecture)

case "$DPKG_ARCH" in
    armhf)
        # armhf is not supported as the public debian repo refers to arm64 as armv7l and not armv6l.
        # This causes an incompatible bin fmt type to be installed for the target CPU.
        echo "Skipping mosquitto update as it is only supported on arm64 images" >&2
        exit 0
        ;;
esac

if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
fi
if [ "${VERSION_ID:-0}" -eq 12 ]; then
    # bookworm: install mosquitto from backports
    echo 'deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm-backports main' > /etc/apt/sources.list.d/debian-bookworm-backports.list
    apt-get update

    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Options::=--force-confold -y --no-install-recommends install -t bookworm-backports \
        mosquitto \
        mosquitto-clients
else
    # trixie includes the required mosquitto version
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Options::=--force-confold -y --no-install-recommends install \
        mosquitto \
        mosquitto-clients
fi

# Enable mosquitto by default (don't rely on the systemd )
systemctl enable mosquitto


patch_mosquitto_2011() {
    #
    # Prevent problems where mosquitto service fails to start due to binding to a
    # non-existent IP address due to the network not being ready
    # The same patch is also included in the yocto open-embedded recipe for mosquitto
    # See https://github.com/eclipse/mosquitto/issues/2878
    #
    # Slow down the restart rate of mosquitto so it does not trip the systemd restart rate limit
    # and stop mosquitto from starting altogether
    #
    mkdir -p /etc/systemd/system/mosquitto.service.d
    cat << EOT > /etc/systemd/system/mosquitto.service.d/override.conf
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
RestartSec = 5
EOT
    chmod 644 /etc/systemd/system/mosquitto.service.d/override.conf
}

patch_mosquitto_2018() {
    #
    # Slow down the restart rate of mosquitto so it does not trip the systemd restart rate limit
    # and stop mosquitto from starting altogether
    #
    mkdir -p /etc/systemd/system/mosquitto.service.d
    cat << EOT > /etc/systemd/system/mosquitto.service.d/override.conf
[Service]
RestartSec = 5
EOT
    chmod 644 /etc/systemd/system/mosquitto.service.d/override.conf
}

MOSQUITTO_VERSION=$(dpkg -l mosquitto | grep '^.i' | awk -F' ' '{print $3}')
echo "Mosquitto version: $MOSQUITTO_VERSION"
case "$MOSQUITTO_VERSION" in
    2.0.11* | 2.0.14* | 2.0.15*)
        echo "Patching mosquitto service (network-online and restart rate limit)"
        patch_mosquitto_2011
        ;;
    2.0.18* | 2.0.2* | 2.1*)
        echo "Patching mosquitto service (restart rate limit)"
        patch_mosquitto_2018
        ;;
esac
