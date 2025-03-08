#!/bin/bash
set -euxo pipefail

BOOT_DIR="${RUGIX_LAYER_DIR}/roots/boot"
mkdir -p "${BOOT_DIR}"
cat <<EOT >> "${BOOT_DIR}/config.txt"
dtparam=spi=on
dtoverlay=tpm-slb9670
dtoverlay=tpm-slb9673
EOT

# Add helper scripts
install -m 0755 -d /usr/share/tedge-hsm/bin
install -D -m 0755 "${RECIPE_DIR}/files/init-tpm.sh" -t /usr/share/tedge-hsm/bin/
