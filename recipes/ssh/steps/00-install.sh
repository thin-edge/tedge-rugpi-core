#!/bin/bash
set -e

# Rebuild the layer if the environment changes.
echo ".env" >> "${LAYER_REBUILD_IF_CHANGED}"

ENV_FILE="$RUGIX_PROJECT_DIR/.env"

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

#
# Retrieve public ssh keys from GitHub
#
download_keys_from_github() {
    for gh_username in $(echo "$1" | tr ',' '\n' | xargs -n1); do
        if [ -n "$gh_username" ]; then
            gh_url="https://github.com/${gh_username}.keys"
            public_ssh_key=$(curl -fsSL "$gh_url" ||:)
            if [ -n "$public_ssh_key" ]; then
                echo "Adding key/s from Github User ${gh_username}. url=${gh_url}" >&2
                public_ssh_key=$(printf '\n# %s\n%s\n' "$gh_username" "$public_ssh_key")
                echo "  $public_ssh_key" >&2
                add_ssh_key "$public_ssh_key"
            else
                echo "WARNING: Could not find a public ssh key. url=$gh_url" >&2
            fi
        fi
    done
}

# From recipe parameters
if [ -n "${RECIPE_PARAM_ROOT_AUTHORIZED_KEYS_GITHUB_USERS:-}" ]; then
    download_keys_from_github "$RECIPE_PARAM_ROOT_AUTHORIZED_KEYS_GITHUB_USERS"
fi

# From .env file
if [ -n "${SSH_GITHUB_USERS:-}" ]; then
    download_keys_from_github "$SSH_GITHUB_USERS"
fi

# Additional Github user list to make it easier the forked repo to add the owner without
# having to splice in with the SSH_GITHUB_USERS list
if [ -n "${SSH_GITHUB_OWNER:-}" ]; then
    download_keys_from_github "$SSH_GITHUB_OWNER"
fi
