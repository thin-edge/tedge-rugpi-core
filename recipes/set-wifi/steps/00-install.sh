#!/bin/bash
set -e

# Rebuild the layer if the environment changes.
echo ".env" >> "${LAYER_REBUILD_IF_CHANGED}"

if [ -f "$RUGIX_PROJECT_DIR/.env" ]; then
    # shellcheck disable=SC1091
    . "$RUGIX_PROJECT_DIR/.env"
fi

# Remove software kill switches which would otherwise prevent the wifi from being enabled by default on rpi 3 and 4's
# Related to https://github.com/thin-edge/tedge-rugix-image/issues/69
# On RaspberryPiOS the image disables the wifi by default on 5Ghz devices if the country code is not set
# but since we are building generic images the wifi will be enabled by default.
#
# For background checkout the following links
# * https://github.com/RPi-Distro/pi-gen/issues/414
# * https://github.com/RPi-Distro/pi-gen/blob/master/stage2/02-net-tweaks/01-run.sh#L28
if [ "$RECIPE_PARAM_DISABLE_RFKILL" = "true" ] && [ -d /var/lib/systemd/rfkill ]; then
    echo "Enabling wifi on 5GHz enabled devices by default" >&2
    for filename in /var/lib/systemd/rfkill/*:wlan; do
        echo 0 > "$filename"
    done
fi

# Set country code otherwise the wifi can be disabled by default
RECIPE_PARAM_COUNTRY_CODE=${RECIPE_PARAM_COUNTRY_CODE:-$SECRETS_WIFI_COUNTRY_CODE}
if command -V raspi-config >/dev/null 2>&1; then
    raspi-config nonint do_wifi_country "${RECIPE_PARAM_COUNTRY_CODE:-DE}"
fi

# Use secret values if the user has not give default values in the [parameters]
RECIPE_PARAM_ID=${RECIPE_PARAM_ID:-$SECRETS_WIFI_ID}
RECIPE_PARAM_SSID=${RECIPE_PARAM_SSID:-$SECRETS_WIFI_SSID}
RECIPE_PARAM_PASSWORD=${RECIPE_PARAM_PASSWORD:-$SECRETS_WIFI_PASSWORD}

if [ -z "$RECIPE_PARAM_SSID" ]; then
    echo "Skipping wifi configuration as ssid is empty" >&2
    exit 0
fi

if [ -z "$RECIPE_PARAM_ID" ]; then
    RECIPE_PARAM_ID=wifi
fi

echo "Configuring wifi (using NetworkManager). id=$RECIPE_PARAM_ID, ssid=$RECIPE_PARAM_SSID" >&2

cat << EOT > /etc/NetworkManager/system-connections/wifi.nmconnection
[connection]
id=${RECIPE_PARAM_ID}
uuid=354ca6a0-bc96-4a29-82f4-c7cbc6e43fac
type=wifi

[wifi]
mode=infrastructure
ssid=${RECIPE_PARAM_SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${RECIPE_PARAM_PASSWORD}

[ipv4]
method=auto

[ipv6]
addr-gen-mode=default
method=auto

[proxy]
EOT

chmod 600 /etc/NetworkManager/system-connections/wifi.nmconnection
