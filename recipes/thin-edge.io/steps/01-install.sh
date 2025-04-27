#!/bin/bash
set -e
echo "----------------------------------------------------------------------------------"
echo "Executing $0"
echo "----------------------------------------------------------------------------------"
echo

# Rebuild the layer if the environment changes.
echo ".env" >> "${LAYER_REBUILD_IF_CHANGED}"
if [ -f "$RUGIX_PROJECT_DIR/.env" ]; then
    # shellcheck disable=SC1091
    . "$RUGIX_PROJECT_DIR/.env"
fi

RECIPE_PARAM_CHANNEL="${RECIPE_PARAM_CHANNEL:-release}"

# Used fixed uid/gid to avoid permission issues across A/B updates
groupadd --system --gid 992 tedge || groupmod -g 992 tedge
useradd --system --no-create-home --shell "/bin/false" --uid 999 --gid 992 tedge || usermod -u 999 tedge

# WORKAROUND: Parameters defined in the layer.toml don't seem to be passed to the recipe
# so use an additional env variable to set some parameters until the root cause is found
if [ -n "${TEDGE_INSTALL_CHANNEL:-}" ]; then
    echo "Using thin-edge.io install channel defined from env: TEDGE_INSTALL_CHANNEL=$TEDGE_INSTALL_CHANNEL" >&2
    RECIPE_PARAM_CHANNEL="$TEDGE_INSTALL_CHANNEL"
fi

# install thin-edge.io
arch=$(uname -m)
INSTALL_OPTS=()
case "$arch" in
    *armv7*)
        # Due to differences between the build process and the target device, the arch
        # used for installation needs to be forced to armv6.
        echo "Using armv6 workaround" >&2
        INSTALL_OPTS+=(
            --arch
            armv6
        )
        ;;
esac

download_file_with_retries() {
    max_attempts="$1"
    retries="$max_attempts"
    url="$2"
    tmp_file=$(mktemp)
    while ! wget -O "$tmp_file" "$url"; do
        retries=$((retries - 1))
        if [ "$retries" -lt 0 ]; then
            echo "ERROR: Failed to download url after $max_attempts attempts. url=$url" >&2
            return 1
        fi
        echo "WARNING: Failed to download url (attempts_remaining=$((retries+1)). Retrying in 5 seconds" >&2
        sleep 5
    done

    # cat file to stdout
    cat "$tmp_file"
    rm -f "$tmp_file"
}

# NOTE: For some reason this can fail to download from cloudsmith
download_file_with_retries 3 thin-edge.io/install.sh | sh -s -- --channel "$RECIPE_PARAM_CHANNEL" "${INSTALL_OPTS[@]}"

# Install collectd
apt-get install -y -o DPkg::Options::=--force-confnew --no-install-recommends \
    mosquitto-clients \
    tedge-command-plugin \
    tedge-collectd-setup \
    tedge-monit-setup \
    tedge-inventory-plugin

# custom tedge configuration
# reduce number of packages shown (supported only from >= 1.1.0)
tedge config set software.plugin.exclude "^(glibc|lib|kernel-|iptables-module).*"
tedge config set c8y.enable.firmware_update "true"

# Enable network manager by default
systemctl enable NetworkManager || true

# Remove software kill switches which would otherwise prevent the wifi from being enabled by default on rpi 3 and 4's
# Related to https://github.com/thin-edge/tedge-rugix-image/issues/69
# On RaspberryPiOS the image disables the wifi by default on 5Ghz devices if the country code is not set
# but since we are building generic images the wifi will be enabled by default.
#
# For background checkout the following links
# * https://github.com/RPi-Distro/pi-gen/issues/414
# * https://github.com/RPi-Distro/pi-gen/blob/master/stage2/02-net-tweaks/01-run.sh#L28
REMOVE_RFKILL=0
if [ "$REMOVE_RFKILL" = 1 ] && [ -d /var/lib/systemd/rfkill ]; then
    echo "Enabling wifi on 5GHz enabled devices by default" >&2
    for filename in /var/lib/systemd/rfkill/*:wlan; do
        echo 0 > "$filename"
    done
    rfkill unblock all ||:
    nmcli radio wifi on 2>/dev/null ||:
fi

# Enable services by default to have sensible default settings once tedge is configured
systemctl enable tedge-agent
systemctl enable tedge-mapper-c8y
systemctl enable tedge-mapper-collectd
systemctl enable collectd
systemctl disable c8y-firmware-plugin

# Custom mosquitto configuration
if ! grep -q '^pid_file' /etc/mosquitto/mosquitto.conf; then
    install -D -m 644 "${RECIPE_DIR}/files/custom.conf" -t /etc/tedge/mosquitto-conf/
fi

# Use default tedge mosquitto settings so mosquitto is functional before connecting to a cloud
# Note: These settings will be overridden on `tedge connect`
install -D -m 644 -g tedge -o tedge "${RECIPE_DIR}/files/tedge-mosquitto.conf" -t /etc/tedge/mosquitto-conf/

# Persist tedge configuration and related components (e.g. mosquitto)
install -D -m 644 "${RECIPE_DIR}/files/tedge-config.toml" -t /etc/rugix/state

# Add default plugin configurations
install -D -m 644 -g tedge -o tedge "${RECIPE_DIR}/files/tedge-configuration-plugin.toml" -t /etc/tedge/plugins/
install -D -m 644 -g tedge -o tedge "${RECIPE_DIR}/files/tedge-log-plugin.toml" -t /etc/tedge/plugins/
