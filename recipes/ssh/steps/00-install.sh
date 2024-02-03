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

add_ssh_key() {
    key="$1"
    echo "$key" >> /root/.ssh/authorized_keys
}

SSH_KEYS=$(env | grep -E '^SSH_KEYS_[0-9a-zA-Z_]+=' | cut -d= -f1)

if [ -n "${RECIPE_PARAM_ROOT_AUTHORIZED_KEYS}" ] || [ -n "$SSH_KEYS" ]; then
    mkdir -p /root/.ssh

    if [ -n "${RECIPE_PARAM_ROOT_AUTHORIZED_KEYS}" ]; then
        add_ssh_key "${RECIPE_PARAM_ROOT_AUTHORIZED_KEYS}"
    fi

    if [ -n "$SSH_KEYS" ]; then
        # Add keys from any env variables which start with SSH_KEYS_[0-9a-zA-Z_]+
        while read -r name; do
            echo "Adding key from env $name" >&2
            value=$(eval "echo \$$name")
            add_ssh_key "$value"
        done < <(echo "$SSH_KEYS")
    fi

    chmod -R 600 /root/.ssh
    cat /root/.ssh/authorized_keys >&2
fi
