#!/bin/sh
set -e
install -D -m 644 "${RECIPE_DIR}/files/tedge-firmware" -t /etc/sudoers.d/
install -D -m 644 "${RECIPE_DIR}/files/system.toml" -t /etc/tedge/
install -D -m 644 "${RECIPE_DIR}/files/firmware_update.rugix.toml" -t /usr/share/tedge-workflows/
install -D -m 755 "${RECIPE_DIR}/files/rugix_workflow.sh" -t /usr/bin/
install -D -m 755 "${RECIPE_DIR}/files/firmware-version" /usr/share/tedge-inventory/scripts.d/80_firmware
install -D -m 755 "${RECIPE_DIR}/files/rugix-system" /usr/share/tedge-inventory/scripts.d/85_rugix_System

# auto rollback service incase if new agent is corrupt (only rely on tooling which is definitely there)
install -D -m 755 "${RECIPE_DIR}/files/firmware-auto-rollback" /usr/bin/firmware-auto-rollback
install -D -m 644 "${RECIPE_DIR}/files/firmware-auto-rollback.service" -t /usr/lib/systemd/system/
install -D -m 644 "${RECIPE_DIR}/files/firmware-auto-rollback.timer" -t /usr/lib/systemd/system/

if [ "${RECIPE_PARAM_AUTOROLLBACK}" = "true" ]; then
    systemctl enable firmware-auto-rollback.timer
fi

# Use symlink so that the workflow file can be updated within the image
ln -s /usr/share/tedge-workflows/firmware_update.rugix.toml /etc/tedge/operations/firmware_update.toml

# Support upgrading from older versions where it still has a persisted symlink
# from /etc/tedge/operations/firmware_update.toml to firmware_update.rugpi.toml
ln -s /usr/share/tedge-workflows/firmware_update.rugix.toml /usr/share/tedge-workflows/firmware_update.rugpi.toml
# Note: system.toml will still have a symlink to the older rugpi file, and the system.toml
# is persisted across updates
ln -s /usr/bin/rugix_workflow.sh /usr/bin/rugpi_workflow.sh

# Add system-hooks
# https://oss.silitics.com/rugix/docs/ctrl/hooks#system-update-hooks
install -m 0755 -d /etc/rugix/hooks/system-commit/pre-commit
install -D -m 0755 "${RECIPE_DIR}/files/hooks/pre-commit/"* /etc/rugix/hooks/system-commit/pre-commit/
