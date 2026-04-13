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

# Check if the desired tedge group id is already being used by another group
# if so, reassign it.
# On Debian trixie, the 'render' group is already to gid 992 causing the conflict
EXISTING_GROUP_GID=$(getent group 992 ||:)
if [ -n "$EXISTING_GROUP_GID" ]; then
    case "$EXISTING_GROUP_GID" in
        tedge:x:992:)
            # nothing to do
            ;;
        *)
            group_name=$(echo "$EXISTING_GROUP_GID" | cut -d: -f1)
            echo "Reassigning ${group_name} gid to 892 (from ${EXISTING_GROUP_GID})" >&2
            groupmod -g 892 "$group_name"
            ;;
    esac
fi

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

# Enable services by default to have sensible default settings once tedge is configured
systemctl enable tedge-agent
systemctl enable tedge-mapper-c8y
systemctl enable tedge-mapper-collectd
systemctl enable collectd
systemctl disable c8y-firmware-plugin

# Persist tedge configuration and related components (e.g. mosquitto)
install -D -m 644 "${RECIPE_DIR}/files/tedge-config.toml" -t /etc/rugix/state

# Add default plugin configurations
install -D -m 644 -g tedge -o tedge "${RECIPE_DIR}/files/tedge-configuration-plugin.toml" -t /etc/tedge/plugins/
install -D -m 644 -g tedge -o tedge "${RECIPE_DIR}/files/tedge-log-plugin.toml" -t /etc/tedge/plugins/

# disable tedge management of the mosquitto listener
tedge config set mqtt.bind.enabled false

# Remove the include directive added by tedge from mosquitto.conf (if present)
# since tedge users the built-in bridge now, there is no-need to add mosquitto configuration
if [ -f /etc/mosquitto/mosquitto.conf ]; then
    sed -i '/^include \/etc\/tedge\/mosquitto-conf/d' /etc/mosquitto/mosquitto.conf
fi
