#!/bin/sh
set -eu
install -D -m 644 "${RECIPE_DIR}/files/step-ca.toml" -t /etc/rugix/state/
