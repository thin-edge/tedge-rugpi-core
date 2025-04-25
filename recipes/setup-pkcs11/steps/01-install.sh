#!/bin/sh
set -e

# Persist tokens
install -D -m 644 "${RECIPE_DIR}/files/softhsm2-tokens.toml" -t /etc/rugix/state

usermod -a -G softhsm tedge

# Add helper scripts
install -m 0755 -d /usr/share/tedge-hsm/bin
install -D -m 0755 "${RECIPE_DIR}/files/init-pkcs11.sh" -t /usr/share/tedge-hsm/bin/
