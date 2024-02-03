#!/bin/bash
set -e
echo "Creating Software Bill Of Materials"

# Rebuild the layer if the environment changes.
echo ".env" >> "${LAYER_REBUILD_IF_CHANGED}"

ENV_FILE="$RUGPI_PROJECT_DIR/.env"

if [ -f "$ENV_FILE" ]; then
    echo "Loading .env file" >&2
    # shellcheck disable=SC1090
    . "$ENV_FILE"
fi

if [ -n "$RUGPI_PROJECT_DIR" ]; then
    SBOM_FILENAME="$RUGPI_PROJECT_DIR/${IMAGE_NAME:-image}.sbom.txt"
    echo "Writing sbom to $SBOM_FILENAME" >&2
    dpkg --list > "$SBOM_FILENAME"
else
    dpkg --list >&2
fi
