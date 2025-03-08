#!/bin/sh
set -e

install -D -m 644 "${RECIPE_DIR}/files/parsec-init.sh" -t /usr/bin/

# provider config
install -D -m 644 "${RECIPE_DIR}/files/tpm-provider.toml" -t /usr/share/parsec/

# Note: The pkcs11-provider is created by the parsec-init.sh script as the configure requires
# some machine specific config (e.g. the path to the .so file which usually is different per CPU architecture)

# Use symlink so that the workflow file can be updated within the image
ln -s /usr/share/parsec/tpm-provider.toml /etc/parsec/config.tpm-provider.toml
