#!/bin/bash
set -euxo pipefail

BOOT_DIR="${RUGIX_LAYER_DIR}/roots/boot"
mkdir -p "${BOOT_DIR}"
cat <<EOT >> "${BOOT_DIR}/config.txt"
dtparam=spi=on
dtoverlay=tpm-slb9670
dtoverlay=tpm-slb9673
EOT

# Allow tedge user to access the tpm
usermod -a -G tss tedge

# Used fixed uid/gid to avoid permission issues across A/B updates
groupmod -g "$RECIPE_PARAM_TSS_GROUP_ID" tss
usermod -u "$RECIPE_PARAM_TSS_USER_ID" tss

# Add helper scripts
install -m 0755 -d /usr/share/tedge-hsm/bin

# NOTE: disable the service as if the user does not have a TPM installed
# it results in systemd being marked as degraded due to this service failing
# Device with a TPM can just enable this service if they need it
systemctl disable tcsd.service ||:
