#!/bin/bash
set -euxo pipefail

BOOT_DIR="${RUGIX_LAYER_DIR}/roots/boot"
mkdir -p "${BOOT_DIR}"

DTPARAM="dtparam=i2c_arm=on"
if [ -n "${RECIPE_PARAM_BAUDRATE:-}" ]; then
    DTPARAM="${DTPARAM},i2c_arm_baudrate=${RECIPE_PARAM_BAUDRATE}"
fi

cat <<EOT >> "${BOOT_DIR}/config.txt"
${DTPARAM}
EOT

# Load i2c-dev on boot so that /dev/i2c-* is available without a manual modprobe
install -D -m 644 "${RECIPE_DIR}/files/i2c.conf" -t /etc/modules-load.d/

# Ensure the i2c group exists (Raspberry Pi OS ships it, other bases might not)
# and that the device nodes are owned by it
getent group i2c >/dev/null || groupadd -r i2c
install -D -m 644 "${RECIPE_DIR}/files/99-i2c.rules" -t /etc/udev/rules.d/

# Allow the tedge user to access the i2c bus
usermod -a -G i2c tedge
