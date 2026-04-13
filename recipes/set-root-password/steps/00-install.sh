#!/bin/bash
set -e

# Rebuild the layer if the environment changes.
echo ".env" >> "${LAYER_REBUILD_IF_CHANGED}"

if [ -f "$RUGIX_PROJECT_DIR/.env" ]; then
    # shellcheck disable=SC1091
    set -a
    . "$RUGIX_PROJECT_DIR/.env"
    set +a
fi

# Support both SECRETS_ROOT_PASSWORD (preferred) and ROOT_PASSWORD
ROOT_PASSWORD="${SECRETS_ROOT_PASSWORD:-$ROOT_PASSWORD}"

if [ -z "$ROOT_PASSWORD" ]; then
    echo "Skipping root password configuration: SECRETS_ROOT_PASSWORD is not set" >&2
    exit 0
fi

echo "Setting root password" >&2
echo "root:${ROOT_PASSWORD}" | chpasswd
