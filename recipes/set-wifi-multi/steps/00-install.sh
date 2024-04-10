#!/bin/bash
set -e

# Rebuild the layer if the environment changes.
echo ".env" >> "${LAYER_REBUILD_IF_CHANGED}"

ENV_FILE="$RUGPI_PROJECT_DIR/.env"

if [ -f "$ENV_FILE" ]; then
    echo "Loading .env file" >&2
    # Export all variables included in the file so that env can read them as well
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
fi

gen_uuid() {
    uuid=$(openssl rand -hex 16)
    echo "${uuid:0:8}-${uuid:8:4}-${uuid:12:4}-${uuid:16:4}-${uuid:20:12}"
}

add_wifi_connection() {
    conn_id="$1"
    conn_ssid="$2"
    conn_psk="$3"
    echo "Configuring wifi (using NetworkManager). id=$conn_id, ssid=$conn_ssid" >&2

    conn_file="/etc/NetworkManager/system-connections/${conn_id}.nmconnection"

    cat << EOT > "$conn_file"
[connection]
id=${RECIPE_PARAM_ID}
uuid=$(gen_uuid)
type=wifi

[wifi]
mode=infrastructure
ssid=${conn_ssid}

[wifi-security]
key-mgmt=wpa-psk
psk=${conn_psk}

[ipv4]
method=auto

[ipv6]
addr-gen-mode=default
method=auto

[proxy]
EOT

chmod 600 "$conn_file"
}

WIFI_SSIDS=$(env | grep -E '^SECRETS_WIFI_[0-9a-zA-Z-]+_SSID=' | cut -d= -f1)

if [ -n "$WIFI_SSIDS" ]; then
    while read -r WIFI_SSID_ENV; do
        WIFI_ID=$(echo "$WIFI_SSID_ENV" | cut -d_ -f3)
        WIFI_SSID=$(eval "echo \$$WIFI_SSID_ENV")
        WIFI_PASSWORD=$(eval "echo \$SECRETS_WIFI_${WIFI_ID}_PASSWORD")
        if [ -n "$WIFI_SSID" ] && [ -n "$WIFI_PASSWORD" ]; then
            echo add_wifi_connection "$WIFI_ID" "$WIFI_SSID" "$WIFI_PASSWORD"
        fi
    done < <(echo "$WIFI_SSIDS")
fi
