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

echo 'deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm-backports main' > /etc/apt/sources.list.d/debian-bookworm-backports.list
apt-get update

DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Options::=--force-confold -y --no-install-recommends install -t bookworm-backports \
    mosquitto \
    mosquitto-clients
