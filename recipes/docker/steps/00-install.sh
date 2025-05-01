#!/bin/bash -e

# Check if Debian trixie is being sued and silently skip it as docker isn't available for trixie yet
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
fi

if [ "$VERSION_CODENAME" = "trixie" ]; then
  echo "WARNING: Skipping docker installation as it is not supported on trixie" >&2
  exit 0
fi

# Add Docker's official GPG key:

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources:
DOCKER_REPO=https://download.docker.com/linux/debian
DPKG_ARCH=$(dpkg --print-architecture)
case "$DPKG_ARCH" in
    armhf)
        # For armhf, raspbian requires armv6 compiled binaries, not armv7
        # therefore the raspbian source is required instead of the standard debian repo
        DOCKER_REPO=https://download.docker.com/linux/raspbian
        ;;
esac

echo \
  "deb [arch=$DPKG_ARCH signed-by=/etc/apt/keyrings/docker.gpg] $DOCKER_REPO \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
   tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update

apt-get install -y --no-install-recommends \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    tedge-container-plugin-ng

usermod -aG docker tedge

# Copy Docker persist file
install -D -m 644 "${RECIPE_DIR}/files/docker.toml" -t /etc/rugix/state

# Add mosquitto listener which allows other containers access to the thin-edge.io MQTT broker
install -D -m 0644 "${RECIPE_DIR}/files/tedge-networkcontainer.conf" -t /etc/tedge/mosquitto-conf/

# Add sudoers rules
install -D -m 0644 "${RECIPE_DIR}/files/suoders.tedge-container-plugin" -T /etc/sudoers.d/tedge-container-plugin

# Enable the service by default
systemctl enable docker.service
