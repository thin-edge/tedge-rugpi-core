#!/bin/bash
set -e
echo "Creating Software Bill Of Materials"

if [ -n "$RUGIX_ARTIFACTS_DIR" ]; then
    mkdir -p "$RUGIX_ARTIFACTS_DIR"
    SBOM_FILENAME="$RUGIX_ARTIFACTS_DIR/sbom.txt"
    echo "Writing sbom to $SBOM_FILENAME" >&2
    dpkg --list > "$SBOM_FILENAME"
else
    dpkg --list >&2
fi
