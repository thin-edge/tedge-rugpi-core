#!/bin/bash
set -euxo pipefail

BOOT_DIR="${RUGIX_LAYER_DIR}/roots/boot"
mkdir -p "${BOOT_DIR}"
cat <<EOT >> "${BOOT_DIR}/config.txt"
dtparam=spi=on
dtoverlay=tpm-slb9670
EOT
