#!/bin/sh
set -eu
install -D -m 644 "${RECIPE_DIR}/files/etc-step-ca.toml" -t /etc/rugpi/state
