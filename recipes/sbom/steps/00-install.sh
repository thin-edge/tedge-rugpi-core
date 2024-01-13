#!/bin/bash
set -e
echo "Creating Software Bill Of Materials"

ENV_FILE="$RUGPI_PROJECT_DIR/.env"

if [ -f "$ENV_FILE" ]; then
    echo "Loading .env file" >&2
    # shellcheck disable=SC1090
    . "$ENV_FILE"
fi

if [ -n "$RUGPI_PROJECT_DIR" ]; then
    SBOM_FILENAME=${IMAGE_FULLNAME:-debian-packages.list}
    dpkg --list > "$RUGPI_PROJECT_DIR/$SBOM_FILENAME"
else
    dpkg --list >&2
fi
