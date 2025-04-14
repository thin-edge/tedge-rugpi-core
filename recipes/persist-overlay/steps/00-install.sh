#!/bin/sh
set -eu
install -D -m 644 "${RECIPE_DIR}/files/state.toml" -t /etc/rugix/
