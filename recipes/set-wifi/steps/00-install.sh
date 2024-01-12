#!/bin/bash
set -e

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
